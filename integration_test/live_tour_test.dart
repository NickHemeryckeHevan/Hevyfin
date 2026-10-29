// Walks the TV's Cinema and TV tabs and the live player with remote keys, and saves an
// in-app screenshot of each screen (no window focus needed).
//   HEVYFIN_TV=1 flutter test integration_test/live_tour_test.dart -d linux --dart-define=SHOTS=/some/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:hevyfin/router.dart';
import 'package:hevyfin/state/live.dart';
import 'package:hevyfin/state/live_store.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live tour', (tester) async {
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
    }

    Future<void> key(LogicalKeyboardKey k, {double after = .6}) async {
      await tester.sendKeyEvent(k);
      await wait(after);
    }

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    app.main();
    await wait(8);
    final router = GoRouter.of(rootNavigatorKey.currentContext!);
    final store = rootNavigatorKey.currentContext!.read<LiveStore>();

    router.go('/cinema');
    await wait(8);
    expect(store.pool, isNotNull, reason: 'schedule should load: ${store.error}');
    debugPrint('POOL ${store.pool!.movies.length} movies, ${store.pool!.series.length} series, '
        '${store.pool!.trailers.length} trailers');
    for (final t in store.screeningsOn(DateTime.now())) {
      debugPrint('SCREENING ${t.start} ${t.title} until ${t.end}');
    }
    await shot('01-cinema');

    router.go('/tv');
    await wait(5);
    await shot('02-tv-guide');
    for (final (i, t) in store.channelsAt(DateTime.now()).indexed) {
      final now = t.listingAt(DateTime.now());
      debugPrint('CHANNEL ${i + 1}: now ${now?.title} ${now?.sub} (${now?.start}-${now?.end}); ${t.listings().length} programs today');
    }

    // Tune in to channel 1, zap up twice.
    router.push('/live/channel/1');
    await wait(6);
    await shot('03-channel-1');
    await key(LogicalKeyboardKey.arrowUp, after: 4);
    await shot('04-channel-2');
    await key(LogicalKeyboardKey.arrowUp, after: 4);
    await shot('05-channel-3');
    await key(LogicalKeyboardKey.enter, after: 1);
    await shot('06-banner');
    router.pop();
    await wait(2);

    // A private viewing: skip through the pre-show with OK and snap each step.
    // It starts from the movie's page, next to Play.
    final movie = store.pool!.movies.first;
    router.push('/item/${movie.id}');
    await wait(5);
    await key(LogicalKeyboardKey.arrowRight);
    await shot('09-details-cinema-mode');
    await key(LogicalKeyboardKey.enter, after: 2.5);
    await shot('10-preshow-ident');
    for (var i = 0; i < 14; i++) {
      await key(LogicalKeyboardKey.enter, after: 2.5);
      await shot('1${(i + 1).toString().padLeft(2, '0')}-preshow');
    }
    router.pop();
    await wait(2);

    // Each bumper on its own, halfway in, for the record.
    for (final kind in ['ident', 'phone', 'feature', 'ch1', 'ch2', 'ch3', 'ch3n', 'next']) {
      final id = 'test-$kind';
      store.marathons.removeWhere((m) => m.id == id);
      store.prompted.add(id);
      store.marathons.add(
        Marathon(id, 'Test', DateTime.now(), const [], const [], Timeline('marathon-$id', 'Test', DateTime.now().subtract(const Duration(seconds: 3)), [bumper(kind, dur: const Duration(seconds: 20), title: 'Shrek 2', sub: 'at 21:30')])),
      );
      router.push('/live/marathon/$id');
      await wait(2);
      await shot('3-bumper-$kind');
      router.pop();
      await wait(1);
      store.marathons.removeWhere((m) => m.id == id);
    }

    router.push('/cinema/marathon/new');
    await wait(3);
    await shot('40-marathon-editor');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
