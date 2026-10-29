import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../api/seerr.dart';
import 'app_state.dart' show defaultFallback, defaultServer, seerrPort;
import 'device.dart';
import '../host.dart';

const _task = 'hevyfin-requests';
final _notes = FlutterLocalNotificationsPlugin();

/// Where a tapped notification should go (a route), wired up by the app.
void Function(String route)? onAlertTap;

/// Android runs this in the background every half hour, even with the app closed.
@pragma('vm:entry-point')
void alertsDispatcher() {
  Workmanager().executeTask((task, _) async {
    try {
      await _init(background: true);
      await checkRequests();
    } catch (e) {
      debugPrint('alerts: $e');
    }
    return true;
  });
}

Future<void> _init({bool background = false}) => _notes.initialize(
  settings: const InitializationSettings(
    android: AndroidInitializationSettings('ic_stat_hevyfin'),
    linux: LinuxInitializationSettings(defaultActionName: 'Open'),
  ),
  onDidReceiveNotificationResponse: background ? null : (r) => r.payload == null ? null : onAlertTap?.call(r.payload!),
);

/// "Your request is ready to watch": set up at launch. Phones check in the background;
/// the computer checks while Hevyfin is open. The TV doesn't (nobody requests from it).
Future<void> initAlerts() async {
  if (Device.isTv || !(Host.isAndroid || Host.isLinux)) return;
  try {
    await _init();
    if (Host.isAndroid) {
      await _notes.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.requestNotificationsPermission();
      await Workmanager().initialize(alertsDispatcher);
      await Workmanager().registerPeriodicTask(
        _task,
        _task,
        frequency: const Duration(minutes: 30),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    }
    // While open: now, and every 15 minutes.
    unawaited(checkRequests());
    Timer.periodic(const Duration(minutes: 15), (_) => checkRequests());
  } catch (e) {
    debugPrint('alerts: $e');
  }
}

/// Looks at the signed-in profile's Seerr requests and announces each one that has become
/// available since the last look (once per request). The first look only takes note.
Future<int> checkRequests() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final cookie = prefs.getString('seerrCookie');
  final user = prefs.getString('userId');
  if (cookie == null || user == null) return 0;
  final override = (prefs.getString('seerrUrl') ?? '').trim();
  final hosts = override.isNotEmpty
      ? [override]
      : [
          for (final s in [prefs.getString('server') ?? defaultServer, prefs.getString('fallback') ?? defaultFallback])
            if (Uri.tryParse(s)?.host case final h? when h.isNotEmpty) '${Uri.parse(s).scheme}://$h:$seerrPort',
        ];
  for (final url in hosts) {
    final seerr = SeerrClient(url, cookie: cookie);
    final List<SeerrRequest> reqs;
    try {
      reqs = await seerr.myRequests(take: 40).timeout(const Duration(seconds: 15));
    } catch (_) {
      continue;
    }
    final key = 'alerted:$user';
    final seen = prefs.getStringList(key);
    final ready = reqs.where((r) => r.statusLabel == 'Available').toList();
    if (seen == null) {
      await prefs.setStringList(key, [for (final r in ready) '${r.id}']);
      return 0;
    }
    var n = 0;
    for (final r in ready.where((r) => !seen.contains('${r.id}'))) {
      String title;
      try {
        title = (await seerr.details(r.type, r.tmdbId)).title;
      } catch (_) {
        title = r.type == 'tv' ? 'Your show' : 'Your movie';
      }
      await _notes.show(
        id: r.id,
        title: 'Ready to watch: $title',
        body: 'Your request is in the library now.',
        payload: '/request/${r.type}/${r.tmdbId}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails('requests', 'Requests', channelDescription: 'When something you asked for is ready', importance: Importance.high),
          linux: LinuxNotificationDetails(),
        ),
      );
      seen.add('${r.id}');
      n++;
    }
    await prefs.setStringList(key, seen);
    return n;
  }
  return 0;
}
