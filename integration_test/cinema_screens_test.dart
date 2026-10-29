// Screenshots of the cinema's full-screen pages on their own (intro, countdown, break,
// waiting room), on a TV-sized and a phone-sized screen.
//   flutter test integration_test/cinema_screens_test.dart -d linux --dart-define=SHOTS=/some/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/theme.dart';
import 'package:hevyfin/ui/widgets/live_bumpers.dart';
import 'package:integration_test/integration_test.dart';

const shots = String.fromEnvironment('SHOTS');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('cinema screens', (tester) async {
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

    final now = DateTime.now();
    final screens = <String, Widget>{
      'intro': FeatureIntro(
        title: 'The Lighthouse Keeper',
        meta: '2014  ·  1h 40m  ·  R  ·  Comedy  ·  Drama',
        actors: Future.value(['Ada Example', 'Ben Sample', 'Cleo Placeholder']),
        length: const Duration(seconds: 15),
        offset: const Duration(seconds: 5),
      ),
      'countdown': const Countdown(offset: Duration(seconds: 4)),
      'break': BreakScreen(
        heading: 'INTERMISSION',
        title: 'The Lighthouse Keeper',
        ends: now.add(const Duration(minutes: 6, seconds: 12)),
        length: const Duration(minutes: 10),
        hint: 'Press OK to carry on now',
      ),
      'waiting': WaitingRoom(title: 'The Lighthouse Keeper', start: now.add(const Duration(minutes: 12, seconds: 40))),
      'bumper-ident': const Bumper(kind: 'ident', length: Duration(seconds: 6), offset: Duration(seconds: 4)),
      'theme-horror': const Bumper(kind: 'theme', title: 'Horror Friday', sub: 'Lights off. Doors locked.', length: Duration(seconds: 8), offset: Duration(seconds: 5)),
      'theme-family': const Bumper(kind: 'theme', title: 'Family Saturday', sub: 'Popcorn for everyone.', length: Duration(seconds: 8), offset: Duration(seconds: 5)),
      'ident-lol': const Bumper(kind: 'ch4', length: Duration(seconds: 5), offset: Duration(seconds: 3)),
      'ticket': Center(child: TicketStub(title: 'The Lighthouse Keeper', when: DateTime(2026, 10, 19, 20, 30), seat: seatFor('screen-x'))),
    };
    for (final (label, size, dpr) in [('tv', const Size(1920, 1080), 1.0), ('phone', const Size(2400, 1080), 2.75)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = dpr;
      for (final e in screens.entries) {
        await tester.pumpWidget(MaterialApp(theme: Hy.theme(), home: Scaffold(body: LiveStage(child: e.value))));
        await wait(1.5);
        await shot('$label-${e.key}');
      }
    }
  });
}
