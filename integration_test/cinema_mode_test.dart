// Cinema mode on the computer (and phone): from a movie's page into a private showing,
// tapping through the pre-show, and back out; channels stay TV-only.
//   flutter test integration_test/cinema_mode_test.dart -d linux --dart-define=SHOTS=/some/dir
// Add --dart-define=PHONE=true for a phone-sized (20:9 landscape) window.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:hevyfin/router.dart';
import 'package:hevyfin/state/live_store.dart';
import 'package:hevyfin/ui/pages/live_player.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const shots = String.fromEnvironment('SHOTS');
const phone = bool.fromEnvironment('PHONE');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cinema mode', (tester) async {
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
      // The root layer is in physical pixels.
      final image = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    tester.view.physicalSize = phone ? const Size(2400, 1080) : const Size(1920, 1080);
    tester.view.devicePixelRatio = phone ? 2.75 : 1;
    final mid = tester.view.physicalSize.center(Offset.zero) / tester.view.devicePixelRatio;
    app.main();
    await wait(8);
    final router = GoRouter.of(rootNavigatorKey.currentContext!);
    final store = rootNavigatorKey.currentContext!.read<LiveStore>();
    await store.ensure();
    final movie = store.pool!.movies.first;

    // Channels are the TV's: the computer is sent home.
    router.push('/live/channel/1');
    await wait(2);
    expect(find.byType(LivePlayerPage), findsNothing);

    router.push('/item/${movie.id}');
    await wait(5);
    await shot('cm-01-details');
    // A desktop window this short keeps the button below the fold: open the showing directly.
    if (phone) {
      router.push('/live/movie/${movie.id}');
    } else {
      await tester.tap(find.text('Cinema mode'));
    }
    await wait(3);
    expect(find.byType(LivePlayerPage), findsOneWidget);
    await shot('cm-02-preshow');
    // A tap shows the banner and the close button; ads, trailers and breaks have a skip button.
    await tester.tapAt(mid);
    await wait(.5);
    await shot('cm-03-banner');
    await tester.tapAt(mid);
    await wait(.5);
    for (var i = 0; i < 4; i++) {
      final skip = find.byWidgetPredicate((w) => w is Text && RegExp(r'^(Skip|Start now)').hasMatch(w.data ?? ''));
      if (skip.evaluate().isEmpty) break;
      await tester.tap(skip.first);
      await wait(3);
      await shot('cm-04-skip-$i');
    }
    // Leave with the close button.
    await tester.tapAt(mid);
    await wait(.3);
    await shot('cm-05-close');
    await tester.tap(find.byTooltip('Leave'));
    await wait(2);
    expect(find.byType(LivePlayerPage), findsNothing);
    if (!phone) expect(find.text('Cinema mode'), findsOneWidget);
  });
}
