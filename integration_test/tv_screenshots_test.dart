// The README's TV screenshots: signs in to Jellyfin's public demo server (public-domain
// films, no personal library) in the TV interface and saves an in-app screenshot of each
// screen (no window focus needed, so it also runs on a virtual display like Xvfb).
//   HEVYFIN_TV=1 flutter test integration_test/tv_screenshots_test.dart -d linux \
//     --dart-define=SHOTS=/some/dir --dart-define=SAVER_SECONDS=60
// Use a build whose app id has no sign-in of your own: it signs in as the demo user.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:hevyfin/router.dart';
import 'package:hevyfin/state/app_state.dart';
import 'package:hevyfin/state/live_store.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const shots = String.fromEnvironment('SHOTS');
const demo = String.fromEnvironment('DEMO_SERVER', defaultValue: 'https://demo.jellyfin.org/stable');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tv screenshots', (tester) async {
    Future<void> wait(double s) async {
      final end = DateTime.now().add(Duration(milliseconds: (s * 1000).round()));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      if (shots.isEmpty) return;
      final rv = tester.binding.renderViews.first;
      final layer = rv.debugLayer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & rv.size, pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      debugPrint('SHOT $name');
    }

    Future<void> key(LogicalKeyboardKey k, {double after = .8}) async {
      await tester.sendKeyEvent(k);
      await wait(after);
    }

    // A key that does nothing else keeps the screensaver away (any key resets its timer).
    Future<void> awake() => key(LogicalKeyboardKey.shiftLeft, after: .3);

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    app.main();
    await wait(6);
    // Before sign-in there's no router yet: find the app state through the widget tree.
    final state = tester.element(find.byType(MaterialApp).first).read<AppState>();

    if (!state.loggedIn) {
      await shot('tv-00-sign-in');
      await state.login(server: demo, fallback: '', username: 'demo', password: '');
      await wait(8);
    }
    final router = GoRouter.of(rootNavigatorKey.currentContext!);
    final store = rootNavigatorKey.currentContext!.read<LiveStore>();

    router.go('/');
    await wait(10);
    await awake();
    await shot('tv-01-home');

    router.go('/cinema');
    await wait(10);
    await awake();
    await shot('tv-02-cinema');

    router.go('/tv');
    await wait(6);
    await awake();
    await shot('tv-03-channels');

    // A movie's page, then its private screening ("Cinema mode"): the pre-show step by step.
    final movie = store.pool!.movies.firstWhere((m) => m.runtime > const Duration(minutes: 60));
    router.push('/item/${movie.id}');
    await wait(8);
    await awake();
    await shot('tv-04-details');
    router.push('/live/movie/${movie.id}');
    await wait(3);
    await shot('tv-05-presents');
    await key(LogicalKeyboardKey.enter, after: 3);
    await shot('tv-06-phones');
    await key(LogicalKeyboardKey.enter, after: 4);
    await shot('tv-07-countdown');
    router.pop();
    await wait(2);
    router.pop();
    await wait(2);

    // Leave it alone until the screensaver starts (SAVER_SECONDS).
    router.go('/');
    await awake();
    await wait(const int.fromEnvironment('SAVER_SECONDS', defaultValue: 300) + 6);
    await shot('tv-09-screensaver');
  }, timeout: const Timeout(Duration(minutes: 15)));
}
