// Which rows the computer's Home shows, top to bottom (real server).
//   flutter test integration_test/home_rows_test.dart -d linux --dart-define=SHOTS=/some/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:integration_test/integration_test.dart';

const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('home rows', (tester) async {
    Future<void> wait(double s) async {
      final end = DateTime.now().add(Duration(milliseconds: (s * 1000).round()));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    app.main();
    await wait(10);
    final seen = <String>[];
    for (var i = 0; i < 14; i++) {
      for (final e in find.byType(Text).evaluate()) {
        final t = (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '';
        if (t.isNotEmpty && !seen.contains(t) && RegExp(r'^(Continue|Next Up|New on|Top 10|Collections|Back on|Trending|Because|More like|[A-Z][a-z]+ & |Comedy|Drama|Action|Animation|Fantasy|Sci)').hasMatch(t)) seen.add(t);
      }
      if (shots.isNotEmpty) {
        final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
        final image = await layer.toImage(Offset.zero & tester.view.physicalSize, pixelRatio: 1);
        File('$shots/home-$i.png').writeAsBytesSync((await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List());
      }
      await tester.drag(find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).first, const Offset(0, -500));
      await wait(1.5);
    }
    debugPrint('ROWS ${seen.join(' | ')}');
  });
}
