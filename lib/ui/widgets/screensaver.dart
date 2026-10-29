import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../router.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../shell.dart' show Wordmark;
import 'common.dart';

/// TV only: after a few minutes without a key press (and nothing playing), the library's
/// backdrops drift by slowly, with each title and the time, like Google TV's ambient mode.
/// A library with no movies or shows yet gets the Hevyfin logo and the time instead.
/// Any key brings the app back (that key does nothing else). After an hour the screen may
/// sleep again, so the TV's own screen-off still happens.
class Screensaver extends StatefulWidget {
  final Widget child;

  /// False while something plays: no screensaver over a film.
  final bool Function() allowed;
  const Screensaver({super.key, required this.child, required this.allowed});

  /// Idle time before it starts (SAVER_SECONDS overrides it for testing).
  static const idle = Duration(seconds: int.fromEnvironment('SAVER_SECONDS', defaultValue: 300));
  static const _device = MethodChannel('hevyfin/device');

  /// How many players are open. Players count themselves in and out, so the screensaver never
  /// starts over a video, whatever the route looks like.
  static final players = ValueNotifier(0);

  @override
  State<Screensaver> createState() => _ScreensaverState();
}

/// How long each title stays up.
const _slide = Duration(seconds: 14);

class _ScreensaverState extends State<Screensaver> {
  Timer? _idle, _next, _off;
  List<Item> _pool = const [];
  int _i = 0;
  bool _on = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
    Screensaver.players.addListener(_onPlayers);
    _arm();
  }

  bool get _allowed => Screensaver.players.value == 0 && widget.allowed();

  void _onPlayers() {
    // Players count themselves in from initState, mid-build: change nothing until it's done.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (Screensaver.players.value > 0 && _on) return _stop();
      _arm();
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    Screensaver.players.removeListener(_onPlayers);
    _idle?.cancel();
    _next?.cancel();
    _off?.cancel();
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (_on) {
      if (e is KeyDownEvent) {
        final shown = _pool.isEmpty ? null : _pool[_i % _pool.length];
        _stop();
        // OK opens the title on screen; any other key just wakes the app.
        final k = e.logicalKey;
        if (shown != null && (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.gameButtonA)) {
          final ctx = rootNavigatorKey.currentContext;
          if (ctx != null) openItem(ctx, shown);
        }
      }
      return true;
    }
    _arm();
    return false;
  }

  void _arm() {
    _idle?.cancel();
    _idle = Timer(Screensaver.idle, _start);
  }

  Future<void> _start() async {
    final c = context.read<AppState>().client;
    if (!_allowed || c == null) return _arm();
    try {
      // Titles with their own logo look best: those first, the rest after.
      final all = (await c.everything()).where((i) => i.backdropTags.isNotEmpty).toList()..shuffle();
      _pool = [...all.where((i) => c.logo(i) != null), ...all.where((i) => c.logo(i) == null)];
    } catch (_) {
      _pool = const [];
    }
    // No art yet (an empty library): the logo screensaver.
    if (!mounted || !_allowed) return _arm();
    setState(() {
      _on = true;
      _i = 0;
    });
    _keepOn(true);
    _next = Timer.periodic(_slide, (_) {
      if (!mounted) return;
      setState(() => _i++);
      _precache();
    });
    _precache();
    // An hour is plenty: let the TV turn its screen off as it normally would.
    _off = Timer(const Duration(hours: 1), () => _keepOn(false));
  }

  void _precache() {
    if (_pool.isEmpty) return;
    final c = context.read<AppState>().client;
    final url = c?.backdrop(_pool[(_i + 1) % _pool.length], width: 1920);
    if (url != null) precacheImage(NetworkImage(url), context).catchError((_) {});
  }

  void _stop() {
    _next?.cancel();
    _off?.cancel();
    _keepOn(false);
    setState(() => _on = false);
    _arm();
  }

  void _keepOn(bool on) => Screensaver._device.invokeMethod('keepScreenOn', on).catchError((_) => null);

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (_on)
        _pool.isEmpty
            ? LogoSaver(index: _i, key: const ValueKey('screensaver'))
            : _Ambient(item: _pool[_i % _pool.length], index: _i, key: const ValueKey('screensaver')),
    ],
  );
}

/// Google TV / Apple TV style ambient screen: the title's art drifting slowly, the time large
/// and light at the top, the title quietly at the bottom, and a hairline counting down to
/// the next one. It sits above the app's pages, so it brings its own text style.
class _Ambient extends StatelessWidget {
  final Item item;
  final int index;
  const _Ambient({super.key, required this.item, required this.index});

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final logo = c.logo(item, width: 800);
    final runtime = item.runtime;
    final meta = [
      if (item.year != null) '${item.year}',
      if (item.genres.isNotEmpty) item.genres.take(2).join(', '),
      if (item.isSeries) 'Series' else if (runtime != null) '${runtime.inHours > 0 ? '${runtime.inHours}h ' : ''}${runtime.inMinutes % 60}m',
    ];
    final tagline = item.tagline ?? '';
    // Alternate the drift so consecutive titles don't all move the same way.
    final dir = index.isEven ? 1.0 : -1.0;
    return Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle(
        style: GoogleFonts.interTight(color: Colors.white, decoration: TextDecoration.none),
        child: ColoredBox(
          color: Colors.black,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 1600),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, ?cur]),
            child: Stack(
              key: ValueKey(item.id),
              fit: StackFit.expand,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: _slide + const Duration(seconds: 2),
                  builder: (_, t, child) => Transform.translate(
                    offset: Offset(dir * (t - .5) * 36, 0),
                    child: Transform.scale(scale: 1.06 + t * .06, child: child),
                  ),
                  child: NetImage(c.backdrop(item, width: 1920), alignment: Alignment.topCenter),
                ),
                // Shade where the words are, and nowhere else.
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x8C000000), Color(0x00000000), Color(0x00000000), Color(0xD9000000)],
                      stops: [0, .28, .5, 1],
                    ),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0x80000000), Color(0x00000000)], stops: [0, .55]),
                  ),
                ),
                const Positioned(left: 64, top: 44, child: _Clock()),
                Positioned(
                  left: 64,
                  bottom: 68,
                  right: 520,
                  child: _Rise(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(color: Hy.orange, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              item.isSeries ? 'SERIES IN YOUR LIBRARY' : 'FILM IN YOUR LIBRARY',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 2.6, color: Color(0xB3FFFFFF)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (logo != null)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 120, maxWidth: 440),
                            child: Image.network(logo, alignment: Alignment.bottomLeft, errorBuilder: (_, _, _) => _Title(item.name)),
                          )
                        else
                          _Title(item.name),
                        const SizedBox(height: 14),
                        Text(
                          meta.join('   ·   '),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xCCFFFFFF), letterSpacing: .2),
                        ),
                        if (tagline.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            tagline,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w400, color: Color(0x99FFFFFF), height: 1.35),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Positioned(right: 64, bottom: 72, child: _Hint()),
                // A hairline along the bottom counting down to the next title.
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 2,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: _slide,
                    builder: (_, t, _) => Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: t,
                        child: const ColoredBox(color: Color(0x59FFFFFF)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The screensaver for a library without art yet: the Hevyfin wordmark and the time on black.
/// Every slide ([index]) they move to another spot, so nothing burns into the screen.
class LogoSaver extends StatelessWidget {
  final int index;
  const LogoSaver({super.key, required this.index});

  static const _spots = [Alignment(-.5, -.4), Alignment(.45, .35), Alignment(.4, -.45), Alignment(-.45, .4), Alignment(0, 0), Alignment(.55, 0)];

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: DefaultTextStyle(
      style: GoogleFonts.interTight(color: Colors.white, decoration: TextDecoration.none),
      child: ColoredBox(
        color: Colors.black,
        child: AnimatedAlign(
          alignment: _spots[index % _spots.length],
          duration: const Duration(seconds: 3),
          curve: Curves.easeInOutCubic,
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wordmark(size: 96),
              SizedBox(height: 18),
              _Clock(),
            ],
          ),
        ),
      ),
    ),
  );
}

/// The title's words come up a moment after its picture.
class _Rise extends StatelessWidget {
  final Widget child;
  const _Rise({required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 1400),
    curve: const Interval(.4, 1, curve: Curves.easeOutCubic),
    builder: (_, t, child) => Opacity(
      opacity: t,
      child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: child),
    ),
    child: child,
  );
}

class _Hint extends StatelessWidget {
  const _Hint();
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0x66FFFFFF), width: 1.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'OK',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xCCFFFFFF), letterSpacing: .5),
        ),
      ),
      const SizedBox(width: 10),
      const Text(
        'to see it',
        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0x99FFFFFF)),
      ),
    ],
  );
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w800, height: 1.02, letterSpacing: -1),
  );
}

class _Clock extends StatefulWidget {
  const _Clock();
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> {
  late final Timer _t = Timer.periodic(const Duration(seconds: 10), (_) => setState(() {}));
  @override
  void dispose() {
    _t.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _t;
    final now = DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat.Hm().format(now),
          style: const TextStyle(fontSize: 104, fontWeight: FontWeight.w200, height: 1, letterSpacing: -4, fontFeatures: [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text(
            DateFormat('EEEE d MMMM').format(now).toUpperCase(),
            style: const TextStyle(fontSize: 13, color: Color(0xB3FFFFFF), fontWeight: FontWeight.w600, letterSpacing: 2.6),
          ),
        ),
      ],
    );
  }
}
