// Measures desktop frame times while scrolling Home, hovering a row and opening a title.
//   flutter drive --profile -d linux --driver=test_driver/integration_test.dart --target=integration_test/perf_test.dart
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('perf', (tester) async {
    final timings = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(timings.addAll);
    Future<void> wait(double s) => tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: (s * 1000).round())));

    void report(String name) {
      if (timings.isEmpty) return debugPrint('PERF $name: no frames');
      List<double> ms(Iterable<Duration> d) => (d.map((x) => x.inMicroseconds / 1000).toList()..sort());
      String s(List<double> v) => 'p50 ${v[v.length ~/ 2].toStringAsFixed(1)} p90 ${v[(v.length * .9).floor()].toStringAsFixed(1)} max ${v.last.toStringAsFixed(1)}';
      final b = ms(timings.map((t) => t.buildDuration)), r = ms(timings.map((t) => t.rasterDuration));
      final slow = timings.where((t) => t.totalSpan.inMicroseconds > 16700).length;
      final span = timings.last.timestampInMicroseconds(FramePhase.vsyncStart) - timings.first.timestampInMicroseconds(FramePhase.vsyncStart);
      final hz = (timings.length - 1) / (span / 1e6);
      debugPrint('PERF $name: ${timings.length} frames at ${hz.toStringAsFixed(0)} fps, window on a ${tester.view.display.refreshRate.round()}Hz display, ${tester.view.physicalSize.width.round()}x${tester.view.physicalSize.height.round()}, $slow over 16.7ms | build ${s(b)} | raster ${s(r)}');
      timings.clear();
    }

    app.main();
    await wait(8);
    timings.clear();
    await wait(3);
    report('idle home');

    final scroll = find.byType(CustomScrollView).last;
    final center = tester.getCenter(scroll);
    for (var i = 0; i < 6; i++) {
      final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await g.addPointer(location: center);
      tester.binding.handlePointerEvent(PointerScrollEvent(position: center, scrollDelta: const Offset(0, 300)));
      await wait(.35);
      await g.removePointer();
    }
    await wait(1);
    report('wheel scroll down');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset(40, center.dy));
    final w = tester.getSize(scroll).width;
    for (var x = 40.0; x < w - 40; x += 25) {
      await mouse.moveTo(Offset(x, center.dy));
      await wait(.03);
    }
    await wait(1);
    report('hover along a row');

    for (var i = 0; i < 6; i++) {
      tester.binding.handlePointerEvent(PointerScrollEvent(position: center, scrollDelta: const Offset(0, -400)));
      await wait(.35);
    }
    await wait(1);
    report('wheel scroll up');

    await tester.tap(find.text('Play').first, warnIfMissed: false);
    await wait(10);
    timings.clear();
    await wait(4);
    report('playing, controls hidden');
    final np = tester.widget<Video>(find.byType(Video).first).controller.player.platform as NativePlayer;
    for (final k in ['hwdec-current', 'video-codec', 'width', 'height', 'video-params/pixelformat', 'container-fps', 'display-fps', 'frame-drop-count', 'scale', 'sub-codec', 'video-sync', 'vo']) {
      debugPrint('MPV $k = ${await np.getProperty(k)}');
    }
    for (var i = 0; i < 40; i++) {
      await mouse.moveTo(Offset(300.0 + i * 10, 400));
      await wait(.05);
    }
    report('playing, moving the mouse');
    await mouse.removePointer();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
