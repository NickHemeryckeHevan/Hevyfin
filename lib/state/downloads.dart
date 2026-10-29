import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../api/jellyfin.dart';
import 'app_state.dart';

/// How big a download is: the original file, or a smaller copy the server makes.
enum DlQuality {
  original('Original', 'Best picture, biggest file', null, null),
  high('1080p', 'About 1.8 GB an hour', 4000000, 1920),
  standard('720p', 'About 700 MB an hour', 1500000, 1280);

  final String label, hint;
  final int? bitrate, maxWidth;
  const DlQuality(this.label, this.hint, this.bitrate, this.maxWidth);
}

/// One film or episode kept on this device.
class Download {
  final String id, name, type;
  final String? seriesName, episodeCode, overview;
  final DlQuality quality;
  final DateTime added;
  int bytes, total;
  String status; // queued, downloading, done, failed
  String? error;
  Duration resume;

  Download({
    required this.id,
    required this.name,
    required this.type,
    this.seriesName,
    this.episodeCode,
    this.overview,
    required this.quality,
    required this.added,
    this.bytes = 0,
    this.total = 0,
    this.status = 'queued',
    this.error,
    this.resume = Duration.zero,
  });

  bool get done => status == 'done';
  String get title => seriesName ?? name;
  String get subtitle => episodeCode == null ? '' : '$episodeCode  $name';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'type': type,
    'series': ?seriesName,
    'code': ?episodeCode,
    'overview': ?overview,
    'q': quality.name,
    'added': added.toIso8601String(),
    'bytes': bytes,
    'total': total,
    'status': status == 'downloading' ? 'queued' : status,
    'error': ?error,
    'resume': resume.inSeconds,
  };

  factory Download.fromJson(Map j) => Download(
    id: j['id'] as String,
    name: j['name'] as String,
    type: j['type'] as String,
    seriesName: j['series'] as String?,
    episodeCode: j['code'] as String?,
    overview: j['overview'] as String?,
    quality: DlQuality.values.byName(j['q'] as String),
    added: DateTime.parse(j['added'] as String),
    bytes: j['bytes'] as int? ?? 0,
    total: j['total'] as int? ?? 0,
    status: j['status'] as String? ?? 'queued',
    error: j['error'] as String?,
    resume: Duration(seconds: j['resume'] as int? ?? 0),
  );
}

/// Films and episodes saved on this device to watch offline, one at a time, never more
/// than [limit] in all. Phones and computers only.
class Downloads extends ChangeNotifier {
  final AppState app;
  Downloads(this.app) {
    // Nothing is kept in a browser.
    if (kIsWeb) return;
    _load();
    app.addListener(_onApp);
  }

  bool _wasOnline = false;

  /// Back online (or signed in): carry on downloading and report offline viewing.
  void _onApp() {
    final online = app.client != null && !app.offline;
    if (online && !_wasOnline) syncProgress();
    _wasOnline = online;
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _http?.close();
    super.dispose();
  }

  static const limit = 10 * 1000 * 1000 * 1000; // 10 GB

  final List<Download> items = [];
  Directory? _dir;
  http.Client? _http;
  String? _active;

  int get used => items.fold(0, (s, d) => s + (d.done ? d.total : d.bytes));

  /// Space taken plus space promised to downloads still waiting.
  int get reserved => items.fold(0, (s, d) => s + (d.done ? d.total : (d.bytes > d.total ? d.bytes : d.total)));

  Future<Directory> _folder() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationSupportDirectory();
    return _dir = await Directory('${base.path}/downloads').create(recursive: true);
  }

  File _manifest(Directory d) => File('${d.path}/downloads.json');
  Future<File> video(String id) async => File('${(await _folder()).path}/$id.video');
  Future<File> poster(String id) async => File('${(await _folder()).path}/$id.jpg');
  Future<File> subtitle(String id) async => File('${(await _folder()).path}/$id.srt');

  Download? of(String id) => items.where((d) => d.id == id).firstOrNull;

  Future<void> _load() async {
    try {
      final f = _manifest(await _folder());
      if (await f.exists()) {
        items
          ..clear()
          ..addAll([for (final j in jsonDecode(await f.readAsString()) as List) Download.fromJson(j as Map)]);
      }
    } catch (e) {
      debugPrint('downloads: $e');
    }
    notifyListeners();
    _next();
  }

  Future<void> _save() async => _manifest(await _folder()).writeAsString(jsonEncode([for (final d in items) d.toJson()]));

  /// Roughly how big [item] will be at [q], in bytes.
  static int estimate(Item item, DlQuality q, {int? originalSize}) {
    final secs = item.runtime?.inSeconds ?? 0;
    if (q.bitrate == null) return originalSize ?? 0;
    return ((q.bitrate! + 192000) / 8 * secs * 1.05).round();
  }

  /// Queue [item] (a film or an episode). Fails if it wouldn't fit in the 10 GB.
  Future<void> add(Item item, DlQuality q) async {
    final c = app.client!;
    if (of(item.id) != null) return;
    final info = await c.playbackInfo(item.id);
    final size = estimate(item, q, originalSize: (info.source['Size'] as num?)?.toInt());
    if (reserved + size > limit) {
      throw 'Not enough room: ${gb(reserved)} of ${gb(limit)} used and this needs about ${gb(size)}. Delete something first.';
    }
    items.add(
      Download(
        id: item.id,
        name: item.name,
        type: item.type,
        seriesName: item.isEpisode ? item.seriesName : null,
        episodeCode: item.isEpisode ? item.episodeCode : null,
        overview: item.overview,
        quality: q,
        added: DateTime.now(),
        total: size,
      ),
    );
    await _save();
    notifyListeners();
    // The poster, for the list when offline.
    final url = item.isEpisode ? c.thumb(item, width: 600) : c.poster(item, width: 400);
    if (url != null) {
      unawaited(
        http.get(Uri.parse(url)).then((r) async => r.statusCode == 200 ? (await poster(item.id)).writeAsBytes(r.bodyBytes) : null).catchError((_) => null),
      );
    }
    _next();
  }

  Future<void> remove(String id) async {
    if (_active == id) {
      _http?.close();
      _http = null;
      _active = null;
    }
    items.removeWhere((d) => d.id == id);
    for (final f in [await video(id), await poster(id), await subtitle(id), File('${(await video(id)).path}.part')]) {
      if (await f.exists()) await f.delete();
    }
    await _save();
    notifyListeners();
    _next();
  }

  Future<void> retry(String id) async {
    final d = of(id);
    if (d == null) return;
    d
      ..status = 'queued'
      ..error = null;
    notifyListeners();
    _next();
  }

  /// Where an offline film was left off, for next time (and for the server once online).
  Future<void> saveResume(String id, Duration at) async {
    final d = of(id);
    if (d == null) return;
    d.resume = at;
    await _save();
  }

  void _next() {
    if (_active != null || app.client == null || app.offline) return;
    final d = items.where((d) => d.status == 'queued').firstOrNull;
    if (d == null) return;
    unawaited(_fetch(d));
  }

  Future<void> _fetch(Download d) async {
    final c = app.client!;
    _active = d.id;
    d.status = 'downloading';
    notifyListeners();
    final client = _http = http.Client();
    final part = File('${(await video(d.id)).path}.part');
    try {
      final info = await c.playbackInfo(d.id);
      final q = d.quality;
      final url = q.bitrate == null
          ? c.uri('/Videos/${d.id}/stream', {'static': true, 'mediaSourceId': info.mediaSourceId, 'api_key': c.token})
          : c.uri('/Videos/${d.id}/stream.mp4', {
              'mediaSourceId': info.mediaSourceId,
              'container': 'mp4',
              'videoCodec': 'h264',
              'audioCodec': 'aac',
              'maxAudioChannels': 2,
              'videoBitRate': q.bitrate,
              'audioBitRate': 192000,
              'maxWidth': q.maxWidth,
              'api_key': c.token,
              'deviceId': c.deviceId,
              'playSessionId': info.playSessionId,
            });
      // Smaller copies lose the subtitles inside the file: keep the preferred language beside it.
      if (q.bitrate != null) await _fetchSubtitle(c, d.id, info);
      final res = await client.send(http.Request('GET', url));
      if (res.statusCode >= 400) throw 'server said ${res.statusCode}';
      if (res.contentLength != null && res.contentLength! > 0) d.total = res.contentLength!;
      final sink = part.openWrite();
      d.bytes = 0;
      var lastNotify = DateTime.now();
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          d.bytes += chunk.length;
          if (used > limit) throw 'This would go over the 10 GB for downloads';
          if (DateTime.now().difference(lastNotify) > const Duration(milliseconds: 500)) {
            lastNotify = DateTime.now();
            notifyListeners();
          }
        }
      } finally {
        await sink.close();
      }
      if (_active != d.id) return; // removed meanwhile
      await part.rename((await video(d.id)).path);
      d
        ..total = d.bytes
        ..status = 'done';
    } catch (e) {
      if (_active != d.id) return;
      d
        ..status = 'failed'
        ..error = '$e';
      if (await part.exists()) await part.delete();
    } finally {
      client.close();
      if (_active == d.id) _active = null;
      await _save();
      notifyListeners();
      _next();
    }
  }

  Future<void> _fetchSubtitle(JellyfinClient c, String id, PlaybackInfo info) async {
    final want = app.subtitleLang.isEmpty ? 'eng' : app.subtitleLang;
    final subs = info.streams.where((s) => s.type == 'Subtitle' && s.isText).toList();
    final pick = subs.where((s) => (s.language ?? '').startsWith(want.substring(0, 2))).firstOrNull ?? subs.firstOrNull;
    if (pick == null) return;
    final url = c.uri('/Videos/$id/${info.mediaSourceId}/Subtitles/${pick.index}/0/Stream.srt', {'api_key': c.token});
    try {
      final r = await http.get(url);
      if (r.statusCode == 200) await (await subtitle(id)).writeAsBytes(r.bodyBytes);
    } catch (_) {}
  }

  /// Back online: start anything waiting, and tell the server how far offline viewing got.
  Future<void> syncProgress() async {
    final c = app.client;
    if (c == null || app.offline) return;
    _next();
    for (final d in items.where((d) => d.done && d.resume > Duration.zero)) {
      try {
        await c.post('/UserItems/${d.id}/UserData', query: {'userId': c.userId}, body: {'PlaybackPositionTicks': d.resume.inMicroseconds * 10});
      } catch (_) {}
    }
  }
}

String gb(int bytes) => bytes >= 1e9 ? '${(bytes / 1e9).toStringAsFixed(1)} GB' : '${(bytes / 1e6).round()} MB';
