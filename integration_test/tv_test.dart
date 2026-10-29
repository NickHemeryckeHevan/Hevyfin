// Drives the TV interface with remote keys only (arrows, OK, Back) against the real
// server and saves a screenshot after each step. Needs a signed-in session.
//   flutter test integration_test/tv_test.dart -d linux --dart-define=SHOTS=/some/dir
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:hevyfin/state/device.dart';
import 'package:integration_test/integration_test.dart';

const shots = String.fromEnvironment('SHOTS');
const shotCmd = String.fromEnvironment('SHOT_CMD', defaultValue: 'spectacle -b -n -a -o');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tv remote tour', (tester) async {
    Future<void> wait(double seconds) async {
      final end = DateTime.now().add(Duration(milliseconds: (seconds * 1000).round()));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      if (shots.isEmpty) return;
      // SHOT_CMD takes the file name last, e.g. 'spectacle -b -n -a -o' (KDE) or 'gnome-screenshot -w -f'.
      // Inside a distrobox it runs on the host.
      final inBox = File('/run/.containerenv').existsSync();
      final cmd = [...shotCmd.split(' '), '$shots/$name.png'];
      await Process.run(inBox ? 'distrobox-host-exec' : cmd.first, inBox ? cmd : cmd.sublist(1));
    }

    Future<void> press(LogicalKeyboardKey key, {int times = 1, double settle = .6}) async {
      for (var i = 0; i < times; i++) {
        await tester.sendKeyEvent(key);
        await wait(settle);
      }
    }

    String focused() {
      final ctx = FocusManager.instance.primaryFocus?.context;
      if (ctx == null) return 'nothing';
      final texts = <String>[];
      void visit(Element e) {
        final w = e.widget;
        if (w is Text && w.data != null) texts.add(w.data!);
        if (texts.length < 2) e.visitChildElements(visit);
      }

      (ctx as Element).visitChildElements(visit);
      return '${FocusManager.instance.primaryFocus!.debugLabel ?? ''} ${texts.join(' / ')}';
    }

    Future<void> back() async {
      await tester.binding.handlePopRoute();
      await wait(1.5);
    }

    Device.isTv = true;
    app.main();
    await wait(9);

    // Home: the remote starts on the billboard's Play.
    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.arrowLeft);
    debugPrint('home focus: ${focused()}');
    await shot('tv-01-home');

    // Down into the rows; right along one.
    await press(LogicalKeyboardKey.arrowDown, times: 2, settle: 1);
    await press(LogicalKeyboardKey.arrowRight, times: 2);
    debugPrint('row focus: ${focused()}');
    await shot('tv-02-row');

    // Left to the edge opens the menu.
    await press(LogicalKeyboardKey.arrowLeft, times: 4);
    debugPrint('menu focus: ${focused()}');
    await shot('tv-03-menu');

    // Menu: down to Shows, OK.
    await press(LogicalKeyboardKey.arrowUp, times: 6, settle: .3);
    await press(LogicalKeyboardKey.arrowDown, times: 2);
    await press(LogicalKeyboardKey.enter, settle: 5);
    debugPrint('shows focus: ${focused()}');
    await shot('tv-04-shows');

    // A row tile, OK opens the title.
    await press(LogicalKeyboardKey.arrowDown, times: 2, settle: 1);
    debugPrint('shows row focus: ${focused()}');
    await press(LogicalKeyboardKey.enter, settle: 5);
    debugPrint('details focus: ${focused()}');
    await shot('tv-05-details');
    await press(LogicalKeyboardKey.arrowDown, times: 3, settle: 1);
    debugPrint('details lower focus: ${focused()}');
    await shot('tv-06-details-lower');

    // Back up to Play and start it; drive the player with the remote.
    await press(LogicalKeyboardKey.arrowUp, times: 6, settle: .5);
    debugPrint('details top focus: ${focused()}');
    await press(LogicalKeyboardKey.enter, settle: 8);
    debugPrint('player focus: ${focused()}');
    await shot('tv-06b-player');
    await press(LogicalKeyboardKey.arrowRight, settle: 1);
    await shot('tv-06c-player-seek');
    await press(LogicalKeyboardKey.arrowUp, settle: 1);
    await press(LogicalKeyboardKey.arrowRight, times: 2, settle: .6);
    debugPrint('player buttons focus: ${focused()}');
    await shot('tv-06d-player-buttons');
    await press(LogicalKeyboardKey.arrowDown, settle: 1);
    debugPrint('player after down: ${focused()}');
    await back(); // hides the controls
    await back(); // leaves the player
    await wait(2);
    debugPrint('after player: ${focused()}');

    // Back from a top-level page opens the menu (pressing it again there leaves the app).
    await back();
    debugPrint('after back: ${focused()}');
    await shot('tv-07-back-menu');

    // Search page from the menu.
    await press(LogicalKeyboardKey.arrowUp, times: 6, settle: .3);
    await press(LogicalKeyboardKey.enter, settle: 3);
    debugPrint('search focus: ${focused()}');
    await shot('tv-08-search');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
