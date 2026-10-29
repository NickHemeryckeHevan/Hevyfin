// Clicks through the main screens against the real server and saves a screenshot of each.
// Needs a signed-in session (sign in once in the app) and, for the shots, a screenshot tool
// (SHOT_CMD, KDE's spectacle by default).
//   flutter test integration_test/tour_test.dart -d linux --dart-define=SHOTS=/some/dir
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:hevyfin/ui/widgets/common.dart';
import 'package:integration_test/integration_test.dart';

const shots = String.fromEnvironment('SHOTS');
const shotCmd = String.fromEnvironment('SHOT_CMD', defaultValue: 'spectacle -b -n -a -o');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tour', (tester) async {
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

    Future<void> scrollDown(double px) async {
      await tester.drag(find.byType(CustomScrollView).last, Offset(0, -px), warnIfMissed: false);
      await wait(2.5);
    }

    Future<void> tapText(String text) async {
      // Prefer the top-bar link over chips with the same label.
      final nav = find.widgetWithText(TextButton, text);
      await tester.tap(nav.evaluate().isNotEmpty ? nav.first : find.text(text).first, warnIfMissed: false);
      await wait(4);
    }

    app.main();
    await wait(8);
    expect(find.text('HEVYFIN'), findsWidgets, reason: 'should be signed in and on Home');
    await shot('01-home');
    await scrollDown(700);
    await shot('02-home-rows');
    await scrollDown(800);
    await shot('03-home-rows');
    await scrollDown(800);
    await shot('04-home-rows');
    await scrollDown(900);
    await shot('05-home-rows');

    await tapText('Shows');
    await shot('06-shows');
    await scrollDown(700);
    await shot('07-shows-rows');

    await tapText('Movies');
    await shot('08-movies');

    await tapText('New & Popular');
    await wait(2);
    await shot('09-new');
    await tapText('My Requests');
    await wait(3);
    await shot('10-requests');

    // Open a show from the Shows page.
    await tapText('Shows');
    await scrollDown(500);
    await tester.tap(find.byType(PosterCard).first, warnIfMissed: false);
    await wait(5);
    await shot('11-details');
    await scrollDown(600);
    await shot('12-details-episodes');

    // Search: library + Seerr results.
    await tester.tap(find.byIcon(Icons.search_rounded).first, warnIfMissed: false);
    await wait(2);
    await tester.enterText(find.byType(TextField).first, 'star');
    await wait(5);
    await shot('13-search');

    // A request page from the search results.
    await scrollDown(500);
    final seerrCard = find.byType(SeerrCard);
    if (seerrCard.evaluate().isNotEmpty) {
      await tester.tap(seerrCard.first, warnIfMissed: false);
      await wait(5);
      await shot('14-request');
    }

    // Play something from Continue Watching.
    await tapText('Home');
    await wait(3);
    await tester.tap(find.byType(LandscapeCard).first, warnIfMissed: false);
    await wait(10);
    await shot('15-player');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await wait(3);
    await shot('16-after-player');
  }, timeout: const Timeout(Duration(minutes: 5)));
}
