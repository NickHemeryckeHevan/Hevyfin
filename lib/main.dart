import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'router.dart';
import 'state/alerts.dart';
import 'state/app_state.dart';
import 'state/device.dart';
import 'state/downloads.dart';
import 'state/link.dart';
import 'state/row_cache.dart';
import 'state/tv_home.dart';
import 'state/live_store.dart';
import 'theme.dart';
import 'ui/pages/login.dart';
import 'ui/pages/profiles.dart';
import 'ui/pages/tv_login.dart';
import 'ui/widgets/intro.dart';
import 'ui/widgets/screensaver.dart';
import 'host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PaintingBinding.instance.imageCache.maximumSizeBytes = 500 << 20;
  await Device.init();
  // Remotes are keys, not touch: always show what is selected (Android starts in touch mode).
  if (Device.isTv) FocusManager.instance.highlightStrategy = FocusHighlightStrategy.alwaysTraditional;
  // TVs have little memory: keep fewer decoded images around.
  if (Device.isTv) PaintingBinding.instance.imageCache.maximumSizeBytes = 120 << 20;
  if (const bool.fromEnvironment('PERF')) {
    _logFrameTimes();
    FocusManager.instance.addListener(() {
      final n = FocusManager.instance.primaryFocus;
      String label = '';
      void visit(Element e) {
        if (label.isNotEmpty) return;
        final w = e.widget;
        if (w is Text && (w.data ?? '').isNotEmpty) label = w.data!;
        if (w is Image && label.isEmpty && w.image is NetworkImage) label = 'img:${(w.image as NetworkImage).url.split('/Items/').last.split('/').first}';
        e.visitChildElements(visit);
      }

      (n?.context as Element?)?.visitChildElements(visit);
      final r = n?.rect;
      debugPrint('FOCUS "$label" at x=${r?.left.round()} y=${r?.top.round()}');
    });
    HardwareKeyboard.instance.addHandler((e) {
      if (e is KeyDownEvent) debugPrint('KEY ${e.logicalKey.debugName}');
      return false;
    });
  }
  final prefs = await SharedPreferences.getInstance();
  final app = AppState(prefs);
  await app.load();
  // Home opens onto the last rows while fresh ones load.
  final uid = app.client?.userId;
  if (uid != null && uid.isNotEmpty) await RowCache.load(uid);
  unawaited(initAlerts());
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: app),
        // Films and episodes saved for offline viewing (phones and computers).
        ChangeNotifierProvider(create: (_) => Downloads(app), lazy: false),
        // Remote commands from other devices and watch parties.
        ChangeNotifierProvider(create: (_) => Link(app), lazy: false),
        // The TV's cinema and channels.
        ChangeNotifierProvider(create: (_) => LiveStore(app), lazy: true),
      ],
      child: const HevyfinApp(),
    ),
  );
}

class HevyfinApp extends StatefulWidget {
  const HevyfinApp({super.key});
  @override
  State<HevyfinApp> createState() => _HevyfinAppState();
}

class _HevyfinAppState extends State<HevyfinApp> {
  final _router = buildRouter(initial: Host.env('HEVYFIN_ROUTE'));

  bool get _playing {
    final path = _router.routerDelegate.currentConfiguration.uri.path;
    return path.startsWith('/play') || path.startsWith('/live');
  }

  @override
  void initState() {
    super.initState();
    // A tapped "ready to watch" notification opens the title.
    onAlertTap = _router.push;
    // Google TV's Continue watching row: keep it filled, and open what's picked there.
    unawaited(TvHome.listen(_router.push));
    final c = context.read<AppState>().client;
    if (c != null) unawaited(TvHome.sync(c, force: true));
    // Another device (or the watch party) asks for something to play here.
    context.read<Link>().openPlayer = (id, start, {sync = false}) async {
      final link = context.read<Link>();
      if (link.target != null) {
        link.target!.remoteStop();
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      final q = [if (start > Duration.zero) 't=${start.inMilliseconds}', if (sync) 'sync=1'];
      _router.push('/play/$id${q.isEmpty ? '' : '?${q.join('&')}'}');
    };
  }

  @override
  Widget build(BuildContext context) {
    final (loggedIn, choosing, adding, known) = context.select<AppState, (bool, bool, bool, bool)>(
      (a) => (a.loggedIn, a.choosing, a.adding, a.profiles.isNotEmpty),
    );
    final theme = Hy.theme(tv: Device.isTv);
    // "Who's watching?" at launch (more than one profile here), on request, and after a sign-out.
    if (!adding && (choosing || (!loggedIn && known))) {
      return MaterialApp(title: 'Hevyfin', debugShowCheckedModeBanner: false, theme: theme, builder: _tvScale, home: const ProfilesPage());
    }
    if (!loggedIn || adding) {
      return MaterialApp(
        title: 'Hevyfin',
        debugShowCheckedModeBanner: false,
        theme: theme,
        builder: _tvScale,
        home: Device.isTv ? const TvLoginPage() : const LoginPage(),
      );
    }
    return MaterialApp.router(
      title: 'Hevyfin',
      debugShowCheckedModeBanner: false,
      theme: theme,
      // The TV's screensaver sits over every page, but never over something playing.
      builder: (context, child) => _tvScale(
        context,
        Device.isTv && child != null
            ? Intro(
                child: Screensaver(allowed: () => !_playing, child: child),
              )
            : child,
      ),
      routerConfig: _router,
    );
  }
}

/// Profiling aid (--dart-define=PERF=true): every 5 s, log how many frames were slow.
void _logFrameTimes() {
  final build = <int>[], raster = <int>[];
  SchedulerBinding.instance.addTimingsCallback((ts) {
    for (final t in ts) {
      build.add(t.buildDuration.inMicroseconds);
      raster.add(t.rasterDuration.inMicroseconds);
    }
  });
  Timer.periodic(const Duration(seconds: 5), (_) {
    if (build.isEmpty) return;
    int p(List<int> l, double q) => (l..sort())[((l.length - 1) * q).round()] ~/ 1000;
    final slow = [
      for (var i = 0; i < build.length; i++)
        if (build[i] + raster[i] > 16667) 1,
    ].length;
    debugPrint('PERF frames=${build.length} slow=$slow build p50=${p(build, .5)}ms p90=${p(build, .9)}ms raster p50=${p(raster, .5)}ms p90=${p(raster, .9)}ms');
    build.clear();
    raster.clear();
  });
}

/// TVs report a 960×540 layout, which makes everything look zoomed in from the sofa.
/// Lay the app out at 1440×810 instead and scale it to fit the screen.
Widget _tvScale(BuildContext context, Widget? child) {
  if (!Device.isTv || child == null) return child ?? const SizedBox.shrink();
  final mq = MediaQuery.of(context);
  const width = 1440.0;
  final scale = mq.size.width / width;
  if (scale >= 1) return child;
  final size = Size(width, mq.size.height / scale);
  return ClipRect(
    child: FittedBox(
      fit: BoxFit.fill,
      alignment: Alignment.topLeft,
      child: SizedBox.fromSize(
        size: size,
        child: MediaQuery(
          data: mq.copyWith(size: size, devicePixelRatio: mq.devicePixelRatio * scale),
          child: child,
        ),
      ),
    ),
  );
}
