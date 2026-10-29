// Cinema mode, channels and marathons leave Jellyfin's "where was I" alone: watch part of
// a film in Cinema mode, leave, and its saved spot, watched state and last-played date
// are what they were.
//   flutter test integration_test/live_untracked_test.dart -d linux
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hevyfin/main.dart' as app;
import 'package:hevyfin/router.dart';
import 'package:hevyfin/state/app_state.dart';
import 'package:hevyfin/state/live_store.dart';
import 'package:hevyfin/ui/pages/live_player.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('live viewing is not tracked', (tester) async {
    Future<void> wait(double s) async {
      final end = DateTime.now().add(Duration(milliseconds: (s * 1000).round()));
      while (DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    app.main();
    await wait(8);
    final ctx = rootNavigatorKey.currentContext!;
    final c = ctx.read<AppState>().client!;
    final store = ctx.read<LiveStore>();
    await store.ensure();
    final movie = store.pool!.movies.first;
    Map<String, dynamic> data(Map j) => {for (final k in ['PlaybackPositionTicks', 'Played', 'PlayCount', 'LastPlayedDate']) k: (j['UserData'] as Map?)?[k]};
    final before = data(await c.get('/Items/${movie.id}', {'userId': c.userId}) as Map);

    GoRouter.of(ctx).push('/live/movie/${movie.id}');
    await wait(4);
    // Skip the pre-show until the film itself plays.
    for (var i = 0; i < 20; i++) {
      final skip = find.byWidgetPredicate((w) => w is Text && RegExp(r'^(Skip|Start now)').hasMatch(w.data ?? ''));
      if (skip.evaluate().isEmpty) {
        await tester.tapAt(const Offset(960, 540));
        await wait(.5);
        if (skip.evaluate().isEmpty) break;
      }
      await tester.tap(skip.first);
      await wait(2);
    }
    await wait(20);
    expect(find.byType(LivePlayerPage), findsOneWidget);
    GoRouter.of(ctx).pop();
    await wait(4);
    final after = data(await c.get('/Items/${movie.id}', {'userId': c.userId}) as Map);
    debugPrint('UNTRACKED before=$before after=$after');
    expect(after, before);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
