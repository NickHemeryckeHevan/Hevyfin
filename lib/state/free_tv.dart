import 'package:http/http.dart' as http;

import '../api/jellyfin.dart';

/// The free channels (5 and up: broadcasters' own streams, through Jellyfin Live TV) and
/// their schedule, kept for a few minutes so the guide and the player share one load.
abstract final class FreeTv {
  static List<Item> channels = const [];
  static List<Item> programs = const [];
  static DateTime _at = DateTime(2000);
  static Future<void>? _loading;

  static Future<void> load(JellyfinClient c, {bool force = false}) {
    if (!force && DateTime.now().difference(_at) < const Duration(minutes: 10)) return Future.value();
    return _loading ??= () async {
      try {
        final now = DateTime.now();
        final ch = await c.tvChannels();
        final pr = await c.tvPrograms(now.subtract(const Duration(hours: 1)), now.add(const Duration(hours: 14)));
        channels = ch;
        programs = pr;
        _at = DateTime.now();
      } finally {
        _loading = null;
      }
    }();
  }

  static final _streams = <String, (DateTime, String)>{};

  /// The stream to hand the player: the best quality up to 1080p (about 8 Mb/s) picked from
  /// the channel's list, so the player doesn't first sample every quality on offer (that was
  /// 6-8 seconds of black on some channels; one picked here starts in about one).
  static Future<String?> stream(JellyfinClient c, String channelId) async {
    final had = _streams[channelId];
    if (had != null && DateTime.now().difference(had.$1) < const Duration(minutes: 30)) return had.$2;
    final master = await c.channelStream(channelId);
    if (master == null) return null;
    var url = master;
    try {
      final res = await http.get(Uri.parse(master)).timeout(const Duration(seconds: 6));
      url = bestVariant(master, res.body) ?? master;
    } catch (_) {}
    _streams[channelId] = (DateTime.now(), url);
    return url;
  }

  /// From an HLS master playlist, the highest-bandwidth variant at or under [cap].
  static String? bestVariant(String masterUrl, String body, {int cap = 8000000}) {
    final lines = body.split('\n');
    final variants = <(int, String)>[];
    for (var i = 0; i < lines.length - 1; i++) {
      if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
      final bw = int.tryParse(RegExp(r'BANDWIDTH=(\d+)').firstMatch(lines[i])?.group(1) ?? '');
      final uri = lines[i + 1].trim();
      if (bw == null || uri.isEmpty || uri.startsWith('#')) continue;
      variants.add((bw, Uri.parse(masterUrl).resolve(uri).toString()));
    }
    if (variants.isEmpty) return null;
    final fits = variants.where((v) => v.$1 <= cap).toList();
    final pool = fits.isEmpty ? variants : fits;
    pool.sort((a, b) => b.$1.compareTo(a.$1));
    return fits.isEmpty ? pool.last.$2 : pool.first.$2;
  }

  static List<Item> on(String channelId) => programs.where((p) => p.channelId == channelId).toList();

  static Item? now(String channelId, [DateTime? at]) {
    final t = at ?? DateTime.now();
    return programs.where((p) => p.channelId == channelId && !(p.startDate?.isAfter(t) ?? true) && (p.endDate?.isAfter(t) ?? false)).firstOrNull;
  }
}
