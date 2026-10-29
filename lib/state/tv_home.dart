import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/jellyfin.dart';
import 'device.dart';

/// Hevyfin on Google TV's home screen: what's started and what's next go into the system's
/// "Continue watching" row, and picking one there opens it straight in the player.
abstract final class TvHome {
  static const _channel = MethodChannel('hevyfin/link');
  static DateTime _last = DateTime(2000);

  /// Opens `hevyfin://play/<id>` links: the one the app started with, and later ones.
  static Future<void> listen(void Function(String route) open) async {
    if (!Device.isTv) return;
    void handle(String? link) {
      final u = Uri.tryParse(link ?? '');
      if (u == null || u.scheme != 'hevyfin' || u.host != 'play' || u.pathSegments.isEmpty) return;
      open('/play/${u.pathSegments.first}');
    }

    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') handle(call.arguments as String?);
    });
    try {
      handle(await _channel.invokeMethod<String>('initial'));
    } catch (_) {}
  }

  /// Refreshes the row (at most every half minute unless [force]).
  static Future<void> sync(JellyfinClient c, {bool force = false}) async {
    if (!Device.isTv) return;
    if (!force && DateTime.now().difference(_last) < const Duration(seconds: 30)) return;
    _last = DateTime.now();
    try {
      final started = await c.resume(limit: 8);
      final next = await c.nextUp(limit: 8);
      final seen = <String>{};
      final items = [
        for (final (i, s) in [for (final i in started) (i, true), for (final i in next) (i, false)])
          if (seen.add(i.isEpisode ? (i.seriesId ?? i.id) : i.id))
            {
              'id': i.id,
              'episode': i.isEpisode,
              'started': s,
              'title': i.isEpisode ? (i.seriesName ?? i.name) : i.name,
              if (i.isEpisode) 'episodeTitle': i.name,
              'season': ?i.parentIndexNumber,
              'number': ?i.indexNumber,
              'description': ?i.overview,
              'image': ?c.thumb(i, width: 640),
              'durationMs': ?i.runtime?.inMilliseconds,
              if (s) 'positionMs': i.resumePosition.inMilliseconds,
              'lastPlayed': ?i.lastPlayed?.millisecondsSinceEpoch,
            },
      ];
      await _channel.invokeMethod('watchNext', items);
    } catch (e) {
      debugPrint('watch next: $e');
    }
  }
}
