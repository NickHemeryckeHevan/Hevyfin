import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/jellyfin.dart';
import 'app_state.dart';
import 'live.dart';

/// A marathon the user planned (on any of their devices; the TV plays it).
class Marathon {
  final String id;
  final String name;
  final DateTime start;
  final List<String> movieIds;
  final List<int> breaks;

  /// Minutes of intermission halfway through each movie (0 = none).
  final List<int> intermissions;

  /// Built when saved, so the order of trailers stays put.
  final Timeline show;
  const Marathon(this.id, this.name, this.start, this.movieIds, this.breaks, this.show, {this.intermissions = const []});

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'start': start.millisecondsSinceEpoch,
    'movies': movieIds,
    'breaks': breaks,
    'inter': intermissions,
    'show': show.toJson(),
  };

  factory Marathon.fromJson(Map<String, dynamic> j) => Marathon(
    j['id'] as String,
    j['name'] as String,
    DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
    (j['movies'] as List).cast<String>(),
    (j['breaks'] as List).cast<int>(),
    Timeline.fromJson((j['show'] as Map).cast<String, dynamic>()),
    intermissions: ((j['inter'] as List?) ?? const []).cast<int>(),
  );
}

/// The cinema's screenings, the channels' schedules and the user's marathons.
/// Schedules are built once per day and saved, so a library scan never reshuffles a day
/// that is already on the air.
class LiveStore extends ChangeNotifier {
  final AppState app;
  LiveStore(this.app) {
    _loadMarathons();
  }

  Pool? pool;
  String? error;
  bool loading = false;
  DateTime? _fetched;
  Future<void>? _busy;

  final Map<String, List<Timeline>> _screenings = {};
  final Map<String, List<Timeline>> _channels = {};
  List<Marathon> marathons = [];

  /// Marathons the start prompt has already been shown for.
  final Set<String> prompted = {};

  JellyfinClient get _c => app.client!;

  /// Fetches the library (at most every few hours) and makes sure today's and tomorrow's
  /// schedules exist.
  Future<void> ensure() => _busy ??= _ensure().whenComplete(() => _busy = null);

  Future<void> _ensure() async {
    // Pages call this from initState: don't notify in the middle of a build.
    await Future<void>.delayed(Duration.zero);
    final now = DateTime.now();
    try {
      if (pool == null || _fetched == null || now.difference(_fetched!) > const Duration(hours: 3)) {
        loading = true;
        notifyListeners();
        pool = await _fetchPool();
        _fetched = now;
      }
      error = null;
      final today = DateTime(now.year, now.month, now.day);
      for (final d in [today, DateTime(today.year, today.month, today.day + 1)]) {
        _screeningsFor(d);
      }
      final cd = channelDay(now);
      for (final d in [cd, DateTime(cd.year, cd.month, cd.day + 1, 6)]) {
        _channelsFor(d);
      }
      _prune(today);
      await syncMarathons();
    } catch (e) {
      error = '$e';
    }
    loading = false;
    notifyListeners();
  }

  Future<Pool> _fetchPool() async {
    final (movies, series, episodes) = await _c.schedulable();
    final clips = await _c.cinemaClips();
    bool animated(Item i) => i.genres.any((g) => g == 'Animation' || g == 'Anime');
    // LOL TV's line-up: the series tagged "lol-tv" on the server (docs/tv-channels.md).
    bool sitcom(Item s) => s.tags.contains('lol-tv');
    final byId = {for (final s in series) s.id: s};
    final eps = <String, List<Title>>{};
    for (final e in episodes) {
      final s = byId[e.seriesId];
      final r = e.runtime;
      if (s == null || r == null || r < const Duration(minutes: 5) || (e.parentIndexNumber ?? 1) == 0) continue;
      eps
          .putIfAbsent(s.id, () => [])
          .add(
            Title(
              id: e.id,
              name: e.name,
              runtime: r,
              age: ageOf(s.officialRating),
              animated: animated(s),
              played: e.played,
              seriesId: s.id,
              seriesName: s.name,
              code: e.episodeCode,
            ),
          );
    }

    return Pool(
      [
        for (final m in movies)
          if (m.runtime != null)
            Title(
              id: m.id,
              name: m.name,
              runtime: m.runtime!,
              critic: m.criticRating,
              community: m.communityRating,
              age: ageOf(m.officialRating),
              animated: animated(m),
              played: m.played,
              genres: m.genres,
            ),
      ],
      [
        for (final s in series)
          if (eps[s.id] != null) Series(s.id, s.name, ageOf(s.officialRating), animated(s), eps[s.id]!, sitcom: sitcom(s)),
      ],
      [
        for (final c in clips)
          if (c.runtime != null && c.runtime! > const Duration(seconds: 3)) Clip(c.id, c.name.replaceAll(RegExp(r'\s*\(\d{4}\)$'), ''), c.runtime!),
      ],
    );
  }

  String get _p => 'live.${app.client?.userId ?? ''}';

  /// Bumped when the channel rules change, so saved days are rebuilt with the new ones.
  static const _chKey = 'ch3';

  /// Same for the cinema's screenings.
  static const _screenKey = 'screen3';

  List<Timeline> _read(String key) {
    final raw = app.prefs.getString(key);
    if (raw == null) return const [];
    try {
      return [for (final t in jsonDecode(raw) as List) Timeline.fromJson((t as Map).cast<String, dynamic>())];
    } catch (_) {
      return const [];
    }
  }

  void _write(String key, List<Timeline> t) => app.prefs.setString(key, jsonEncode([for (final x in t) x.toJson()]));

  List<Timeline> _screeningsFor(DateTime day) {
    final k = dayKey(day);
    final cached = _screenings[k] ?? _read('$_p.$_screenKey.$k');
    final pool = this.pool;
    // Rebuild a day that was made before the trailers arrived, as long as nothing has started.
    final stale =
        cached.isNotEmpty &&
        pool != null &&
        pool.clips.isNotEmpty &&
        !cached.any((t) => t.steps.any((s) => s.kind == StepKind.clip)) &&
        cached.every((t) => t.start.isAfter(DateTime.now()));
    if ((cached.isEmpty || stale) && pool != null) {
      final built = screenings(day, pool);
      _write('$_p.$_screenKey.$k', built);
      return _screenings[k] = built;
    }
    return _screenings[k] = cached;
  }

  List<Timeline> _channelsFor(DateTime day) {
    final k = dayKey(day);
    final cached = _channels[k] ?? _read('$_p.$_chKey.$k');
    final pool = this.pool;
    if (cached.isEmpty && pool != null) {
      final cursors = <String, int>{...((jsonDecode(app.prefs.getString('$_p.cursors') ?? '{}') as Map).cast<String, int>())};
      final built = channelDays(day, pool, cursors);
      _write('$_p.$_chKey.$k', built);
      app.prefs.setString('$_p.cursors', jsonEncode(cursors));
      return _channels[k] = built;
    }
    return _channels[k] = cached;
  }

  /// Forget schedules from before yesterday.
  void _prune(DateTime today) {
    final keep = {for (var i = -1; i <= 1; i++) dayKey(DateTime(today.year, today.month, today.day + i))};
    for (final key in app.prefs.getKeys().toList()) {
      final m = RegExp(r'\.(screen\d*|ch\d*)\.(\d{8})$').firstMatch(key);
      final stale = m != null && m.group(1) != _chKey && m.group(1) != _screenKey;
      if (m != null && key.startsWith(_p) && (stale || !keep.contains(m.group(2)))) app.prefs.remove(key);
    }
    _screenings.removeWhere((k, _) => !keep.contains(k));
    _channels.removeWhere((k, _) => !keep.contains(k));
    bool old(Marathon m) => m.show.end.isBefore(today.subtract(const Duration(days: 1)));
    if (marathons.any(old)) _updateRemote((list) => list.where((m) => !old(m)).toList());
  }

  List<Timeline> screeningsOn(DateTime day) => _screeningsFor(DateTime(day.year, day.month, day.day));

  /// The three channels' schedules for the channel day containing [now].
  List<Timeline> channelsAt(DateTime now) => _channelsFor(channelDay(now));

  /// The channel's schedule at [now] and, near 06:00, the next day's too.
  Timeline? channel(int number, DateTime now) {
    final day = channelsAt(now);
    return day.length >= number ? day[number - 1] : null;
  }

  Timeline? screening(String id) {
    for (final list in _screenings.values) {
      for (final t in list) {
        if (t.id == id) return t;
      }
    }
    return null;
  }

  Title? movie(String id) => pool?.movies.where((m) => m.id == id).firstOrNull;

  // ---- marathons ----

  static List<Marathon> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      return [for (final m in jsonDecode(raw) as List) Marathon.fromJson((m as Map).cast<String, dynamic>())];
    } catch (_) {
      return [];
    }
  }

  static String _encode(List<Marathon> list) => jsonEncode([for (final m in list) m.toJson()]);

  /// The local copy, so the TV knows its marathons even when the server is briefly away.
  void _loadMarathons() => marathons = _decode(app.prefs.getString('live.marathons'));

  void _saveMarathons() => app.prefs.setString('live.marathons', _encode(marathons));

  DateTime? _synced;

  /// Marathons live on the Jellyfin server under the user, so one planned on the phone or
  /// the computer shows up on the TV. Fetches at most once a minute unless [force].
  Future<void> syncMarathons({bool force = false}) async {
    final c = app.client;
    if (c == null || (!force && _synced != null && DateTime.now().difference(_synced!) < const Duration(minutes: 1))) return;
    try {
      final raw = await c.sharedPref('marathons');
      _synced = DateTime.now();
      final remote = _decode(raw);
      // First run after the update: marathons planned on this TV move to the server.
      if (raw == null && marathons.isNotEmpty) {
        await c.setSharedPref('marathons', _encode(marathons));
        return;
      }
      if (_encode(remote) != _encode(marathons)) {
        marathons = remote..sort((a, b) => a.start.compareTo(b.start));
        _saveMarathons();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('marathon sync failed: $e');
    }
  }

  /// Read the server's list, change it, write it back (another device may have edited it).
  Future<void> _updateRemote(List<Marathon> Function(List<Marathon>) change) async {
    marathons = change(marathons)..sort((a, b) => a.start.compareTo(b.start));
    _saveMarathons();
    notifyListeners();
    final c = app.client;
    if (c == null) return;
    try {
      final remote = _decode(await c.sharedPref('marathons'));
      final updated = change(remote)..sort((a, b) => a.start.compareTo(b.start));
      await c.setSharedPref('marathons', _encode(updated));
      marathons = updated;
      _saveMarathons();
      _synced = DateTime.now();
      notifyListeners();
    } catch (e) {
      error = "Couldn't save the marathon on the server: $e";
      notifyListeners();
    }
  }

  Future<void> saveMarathon({
    String? id,
    required String name,
    required DateTime start,
    required List<String> movieIds,
    required List<int> breaks,
    List<int> intermissions = const [],
  }) {
    final pool = this.pool;
    if (pool == null) return Future.value();
    final mid = id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final movies = [for (final i in movieIds) ?movie(i)];
    final show = marathonShow(mid, name, start, movies, breaks, pool, intermissions: intermissions);
    final m = Marathon(mid, name, start, movieIds, breaks, show, intermissions: intermissions);
    prompted.remove(mid);
    return _updateRemote(
      (list) => [
        for (final x in list)
          if (x.id != mid) x,
        m,
      ],
    );
  }

  Future<void> deleteMarathon(String id) => _updateRemote((list) => list.where((m) => m.id != id).toList());

  Marathon? marathon(String id) => marathons.where((m) => m.id == id).firstOrNull;

  /// A marathon whose start time has just come (for the "starts now" prompt).
  Marathon? due(DateTime now) =>
      marathons.where((m) => !prompted.contains(m.id) && !now.isBefore(m.start) && now.difference(m.start) < const Duration(minutes: 2)).firstOrNull;
}
