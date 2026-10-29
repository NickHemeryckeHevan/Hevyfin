// The collection page (art, progress, numbers, familiar faces, trivia, the films in order)
// and the Collections wall, on a computer and a phone (real server).
//   flutter test integration_test/collection_page_test.dart -d linux --dart-define=SHOTS=/some/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:hevyfin/router.dart';
import 'package:hevyfin/state/app_state.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

const shots = String.fromEnvironment('SHOTS');

/// Which collection (by name); the first one if not given.
const only = String.fromEnvironment('COL');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('collection page', (tester) async {
    Future<void> wait(double s) async {
      final end = DateTime.now().add(Duration(milliseconds: (s * 1000).round()));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      if (shots.isEmpty) return;
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      final image = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    app.main();
    await wait(8);
    final ctx = rootNavigatorKey.currentContext!;
    final router = GoRouter.of(ctx);
    final cols = await ctx.read<AppState>().client!.collections();
    final col = cols.firstWhere((c) => c.name == only, orElse: () => cols.first);
    for (final (label, size, dpr) in [('pc', const Size(1600, 1000), 1.0), ('phone', const Size(1080, 2400), 2.75)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      router.go('/');
      await wait(1);
      router.push('/item/${col.id}');
      // Wait for it to load (slow over Tailscale), then for the art.
      for (var i = 0; i < 80 && find.text(col.name).evaluate().isEmpty; i++) {
        await wait(.5);
      }
      await wait(6);
      await shot('$label-col-1');
      for (var i = 2; i <= 4; i++) {
        await tester.drag(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first, Offset(0, label == 'pc' ? -800 : -1500));
        await wait(4);
        await shot('$label-col-$i');
      }
      router.pop();
      router.push('/collections');
      await wait(4);
      await shot('$label-collections');
      router.pop();
    }
  }, timeout: const Timeout(Duration(minutes: 4)));
}
