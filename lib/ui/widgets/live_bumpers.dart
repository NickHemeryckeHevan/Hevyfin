// The app's own idents, channel idents, the feature intro and the break screens of
// the cinema and the TV's channels. All are drawn with plain transforms and opacity (no blur,
// no shadows) so the Chromecast keeps up, and all start at an offset: joining halfway
// through a bumper shows it halfway through.
import 'dart:math';

import 'package:flutter/material.dart';

import '../../theme.dart';

/// Runs a 0..1 animation over [length], starting at [offset].
class _Clock extends StatefulWidget {
  final Duration length, offset;
  final Widget Function(BuildContext, double t) builder;
  const _Clock({super.key, required this.length, required this.offset, required this.builder});
  @override
  State<_Clock> createState() => _ClockState();
}

class _ClockState extends State<_Clock> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.length)
    ..value = widget.length.inMilliseconds == 0 ? 1 : (widget.offset.inMilliseconds / widget.length.inMilliseconds).clamp(0, 1)
    ..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (context, _) => widget.builder(context, _c.value));
}

/// 0..1 progress of [t] inside the window [a, b], eased.
double _seg(double t, double a, double b, [Curve curve = Curves.easeOutCubic]) => curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));

/// In and out fades at the ends of a bumper.
double _fade(double t, Duration len) {
  final edge = 400 / max(len.inMilliseconds, 1);
  return min(_seg(t, 0, edge, Curves.linear), 1 - _seg(t, 1 - edge, 1, Curves.linear));
}

TextStyle _display(double size, {Color color = Colors.white, double spacing = 0, FontStyle style = FontStyle.normal}) =>
    TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: color, letterSpacing: spacing, height: 1, fontStyle: style);

/// The live screens are drawn on a 1440-wide stage, the TV's layout. Elsewhere the stage is
/// scaled to the screen's width (its height follows the screen's shape), so a phone shows
/// the same picture, smaller, instead of words running off the edges.
class LiveStage extends StatelessWidget {
  final Widget child;
  const LiveStage({super.key, required this.child});
  static const width = 1440.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final scale = c.maxWidth / width;
      if ((scale - 1).abs() < .01 || !c.hasBoundedHeight) return child;
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.fill,
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, height: c.maxHeight / scale, child: child),
        ),
      );
    },
  );
}

/// Fades [child] in at [at] while it rises into place.
Widget _rise(double t, double at, Widget child) => Opacity(
  opacity: _seg(t, at, at + .12),
  child: Transform.translate(offset: Offset(0, 28 * (1 - _seg(t, at, at + .2))), child: child),
);

TextStyle _head(double size) => TextStyle(fontSize: size, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -size * .025, height: 1.04);
TextStyle _light(double size, {double spacing = 0}) =>
    TextStyle(fontSize: size, fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: spacing, height: 1.1);
const _eyebrow = TextStyle(color: Hy.orange, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 5);
const _body = TextStyle(color: Hy.textDim, fontSize: 24, height: 1.4);

/// One of the app's bumpers by kind ("ident", "phone", "feature",
/// "ch1".."ch3", "ch3n", "next"). The cinema's own are quiet and typographic: a warm glow
/// that drifts, a line or two that rise into place.
class Bumper extends StatelessWidget {
  final String kind;
  final Duration length, offset;

  /// For "next": what's coming up and when.
  final String title, sub;
  const Bumper({super.key, required this.kind, required this.length, required this.offset, this.title = '', this.sub = ''});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: _Clock(
      key: ValueKey('$kind$title'),
      length: length,
      offset: offset,
      builder: (context, t) => Opacity(
        opacity: _fade(t, length),
        child: switch (kind) {
          'ident' => _ident(t),
          'phone' => _phone(t),
          'feature' => _feature(t),
          'next' => _next(t),
          'theme' => _theme(t),
          'ch3n' => _afterHours(t),
          _ when kind.startsWith('ch') => ChannelIdent(number: int.tryParse(kind.substring(2)) ?? 1, t: t),
          _ => const SizedBox.shrink(),
        },
      ),
    ),
  );

  /// "Hevyfin presents".
  Widget _ident(double t) => _Room(
    t: t,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rise(
          t,
          .08,
          // A light passing over the name.
          ShaderMask(
            shaderCallback: (r) => LinearGradient(
              colors: const [Hy.orangeDeep, Hy.orangeBright, Colors.white, Hy.orangeBright, Hy.orangeDeep],
              stops: <double>[0, .3 + .5 * t - .1, .35 + .5 * t, .4 + .5 * t, 1].map((s) => s.clamp(0.0, 1.0)).toList(),
            ).createShader(r),
            child: Text('HEVYFIN', style: _display(150, spacing: -2)),
          ),
        ),
        const SizedBox(height: 22),
        // A hairline drawn out from the middle.
        Container(width: 560 * _seg(t, .02, .4), height: 2, color: Hy.orange),
        const SizedBox(height: 26),
        _rise(
          t,
          .3,
          // Letter spacing also trails the last letter; pad the front to keep it centred.
          Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Text('PRESENTS', style: _light(34, spacing: 26)),
          ),
        ),
      ],
    ),
  );

  Widget _phone(double t) => _Room(
    t: t,
    mark: true,
    glow: const Alignment(-.45, 0),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rise(t, .02, CustomPaint(size: const Size(150, 270), painter: _Handset(_seg(t, .2, .45, Curves.easeInOut)))),
        const SizedBox(width: 90),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _rise(t, .1, const Text('BEFORE WE BEGIN', style: _eyebrow)),
            const SizedBox(height: 18),
            _rise(t, .16, Text('Phones on silent,\nscreens down.', style: _head(76))),
            const SizedBox(height: 22),
            _rise(t, .5, const Text('Thanks for keeping the room dark.', style: _body)),
          ],
        ),
      ],
    ),
  );

  Widget _feature(double t) {
    // Two hairlines open out like a widescreen frame around the words.
    final open = _seg(t, 0, .4, Curves.easeInOutCubic);
    final line = Container(width: 900 * open, height: 1, color: Colors.white30);
    return _Room(
      t: t,
      glow: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          line,
          const SizedBox(height: 56),
          _rise(t, .2, const Text('AND NOW', style: _eyebrow)),
          const SizedBox(height: 22),
          _rise(
            t,
            .28,
            Transform.scale(
              scale: 1 + .03 * t,
              child: Text('Feature Presentation', style: _light(84, spacing: 1)),
            ),
          ),
          const SizedBox(height: 56),
          line,
        ],
      ),
    );
  }

  Widget _next(double t) => _Room(
    t: t,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _rise(t, 0, const Text('UP NEXT', style: _eyebrow)),
        const SizedBox(height: 22),
        _rise(t, .06, Text(title, textAlign: TextAlign.center, maxLines: 2, style: _head(80))),
        if (sub.isNotEmpty) ...[const SizedBox(height: 18), _rise(t, .12, Text(sub, style: _body))],
      ],
    ),
  );

  /// Tonight's theme ("Horror Friday"): the room takes on the theme's colour.
  Widget _theme(double t) {
    final look = themeLook(title);
    // Horror's lights stutter now and then.
    final flicker = look.flicker && (t * 37).floor() % 9 == 0 && t > .25 ? .55 : 1.0;
    return Opacity(
      opacity: flicker,
      child: _Room(
        t: t,
        glowColor: look.color,
        mark: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rise(t, 0, Text("TONIGHT'S THEME", style: _eyebrow.copyWith(color: look.color))),
            const SizedBox(height: 24),
            _rise(t, .06, Icon(look.icon, color: look.color, size: 64)),
            const SizedBox(height: 20),
            _rise(t, .1, Text(title, textAlign: TextAlign.center, style: _head(120))),
            const SizedBox(height: 18),
            _rise(t, .18, Text(sub, style: _light(32).copyWith(color: Hy.textDim))),
          ],
        ),
      ),
    );
  }

  /// After hours on channel 3: a few quiet words on black, nothing else.
  Widget _afterHours(double t) {
    const lines = ['after hours', 'it\'s late.', 'grown-up cartoons from here on.', 'after hours'];
    final i = min((t * lines.length).floor(), lines.length - 1);
    return Center(
      child: Text(
        lines[i],
        style: const TextStyle(fontSize: 64, fontWeight: FontWeight.w300, fontStyle: FontStyle.italic, color: Hy.orangeBright, letterSpacing: 1),
      ),
    );
  }
}

/// The cinema's bumpers share a room: black, a warm glow drifting across it, and in the
/// the cards the cinema's name in the corner.
class _Room extends StatelessWidget {
  final double t;
  final Widget child;
  final Widget? footer;
  final bool mark;
  final Alignment glow;
  final Color glowColor;
  const _Room({
    required this.t,
    required this.child,
    this.footer,
    this.mark = false,
    this.glow = const Alignment(0, -.1),
    this.glowColor = const Color(0xFFFF7A1A),
  });

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(glow.x + .3 * (t - .5), glow.y),
            radius: 1.1,
            colors: [glowColor.withValues(alpha: .25), glowColor.withValues(alpha: .05), Colors.transparent],
            stops: const [0, .45, 1],
          ),
        ),
      ),
      if (mark)
        Positioned(
          left: 64,
          top: 52,
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: Hy.orange, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(width: 12),
              const Text(
                'HEVYFIN CINEMA',
                style: TextStyle(color: Hy.textDim, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 5),
              ),
            ],
          ),
        ),
      Center(child: child),
      if (footer != null) Positioned(left: 0, right: 0, bottom: 56, child: Center(child: footer)),
    ],
  );
}

/// A phone whose screen goes dark ([dim] 0..1), then shows a moon.
class _Handset extends CustomPainter {
  final double dim;
  _Handset(this.dim);
  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(26));
    canvas.drawRRect(
      body.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Colors.white70,
    );
    final screen = RRect.fromRectAndRadius((Offset.zero & size).deflate(12), const Radius.circular(17));
    canvas.drawRRect(screen, Paint()..color = Color.lerp(const Color(0xFFFFC08A), const Color(0xFF141414), dim)!);
    // The camera pill.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(size.width / 2, 26), width: 36, height: 8), const Radius.circular(4)),
      Paint()..color = Colors.black,
    );
    final c = size.center(Offset.zero);
    final moon = Path.combine(
      PathOperation.difference,
      Path()..addOval(Rect.fromCircle(center: c, radius: 26)),
      Path()..addOval(Rect.fromCircle(center: c + const Offset(13, -9), radius: 22)),
    );
    canvas.drawPath(moon, Paint()..color = Hy.orange.withValues(alpha: _seg(dim, .6, 1, Curves.linear)));
  }

  @override
  bool shouldRepaint(_Handset old) => old.dim != dim;
}

/// A channel's logo, big for idents ([t] animates it) or small for the guide and the
/// corner of the screen.
class ChannelIdent extends StatelessWidget {
  final int number;
  final double? t;
  final double size;

  /// Channel 3 after 20:00.
  final bool night;
  const ChannelIdent({super.key, required this.number, this.t, this.size = 1, this.night = false});

  @override
  Widget build(BuildContext context) {
    final t = this.t;
    final logo = _logo();
    if (t == null) return logo;
    return Center(
      child: Transform.scale(scale: .8 + .2 * _seg(t, 0, .6, Curves.easeOutBack), child: logo),
    );
  }

  Widget _logo() {
    final s = size * (t == null ? 1 : 3);
    switch (number) {
      case 1:
        // Movie Night: a film-strip box with the name.
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 6 * s),
          decoration: BoxDecoration(gradient: Hy.orangeGradient, borderRadius: BorderRadius.circular(6 * s)),
          child: Text(
            'MOVIE NIGHT',
            style: _display(22 * s, color: Colors.black, spacing: 2 * s),
          ),
        );
      case 2:
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'HEVYFIN',
              style: _display(16 * s, color: Hy.textDim, spacing: 2 * s),
            ),
            SizedBox(width: 6 * s),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [Color(0xFF4FC3F7), Color(0xFF7C4DFF)]).createShader(r),
              child: Text('MIX', style: _display(38 * s, spacing: -1 * s)),
            ),
          ],
        );
      case 4:
        // LOL TV: a yellow speech bubble.
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12 * s, vertical: 5 * s),
          decoration: BoxDecoration(
            color: const Color(0xFFFFD23F),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14 * s),
              topRight: Radius.circular(14 * s),
              bottomRight: Radius.circular(14 * s),
              bottomLeft: Radius.circular(3 * s),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'LOL',
                style: _display(30 * s, color: Colors.black, spacing: 1 * s),
              ),
              SizedBox(width: 3 * s),
              Padding(
                padding: EdgeInsets.only(bottom: 3 * s),
                child: Text(
                  'TV',
                  style: _display(13 * s, color: const Color(0xFF7A5A00), spacing: 1 * s),
                ),
              ),
            ],
          ),
        );
      default:
        if (night) {
          return Text(
            'after hours',
            style: TextStyle(fontSize: 22 * s, fontWeight: FontWeight.w300, fontStyle: FontStyle.italic, color: Hy.orangeBright, letterSpacing: .5 * s),
          );
        }
        // Cartoons: a round orange badge.
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: 5 * s),
          decoration: BoxDecoration(color: Hy.orange, borderRadius: BorderRadius.circular(40 * s)),
          child: Text('TOONS', style: _display(24 * s, color: Colors.black, spacing: 1 * s)),
        );
    }
  }
}

/// Ten seconds to the feature when there's no movie to show: a ring that empties around the
/// seconds left.
class Countdown extends StatelessWidget {
  final Duration offset;
  const Countdown({super.key, required this.offset});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: _Clock(
      length: const Duration(seconds: 10),
      offset: offset,
      builder: (context, t) => _Room(
        t: t,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('THE FEATURE BEGINS', style: _eyebrow),
            const SizedBox(height: 36),
            SizedBox(
              width: 280,
              height: 280,
              child: CustomPaint(
                painter: _Ring(1 - t, width: 3),
                child: Center(
                  child: Text('${(10 - t * 10).ceil().clamp(1, 10)}', style: _light(130).copyWith(fontFeatures: _tab)),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

const _tab = [FontFeature.tabularFigures()];

/// Right before a feature: the movie's wide art drifting closer behind its title, who's in
/// it, and the seconds left; a hairline along the bottom fills up to the start.
class FeatureIntro extends StatelessWidget {
  final String title, meta;
  final String? backdrop;
  final Future<List<String>> actors;
  final Duration length, offset;
  const FeatureIntro({super.key, required this.title, required this.meta, required this.actors, required this.length, required this.offset, this.backdrop});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: _Clock(
      length: length,
      offset: offset,
      builder: (context, t) {
        final left = ((1 - t) * length.inMilliseconds / 1000).ceil();
        return Opacity(
          opacity: _seg(t, 0, .06, Curves.linear),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (backdrop != null)
                Opacity(
                  opacity: .6 * _seg(t, 0, .15, Curves.linear),
                  child: Transform.scale(
                    scale: 1.02 + .08 * t,
                    child: Image.network(backdrop!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
                  ),
                ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xF0000000), Color(0x80000000), Color(0x10000000)], stops: [0, .5, 1]),
                ),
              ),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.center, colors: [Colors.black, Colors.transparent]),
                ),
              ),
              Positioned(
                left: 96,
                right: 420,
                bottom: 120,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _rise(t, .02, const Text('FEATURE PRESENTATION', style: _eyebrow)),
                    const SizedBox(height: 22),
                    _rise(t, .05, Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _head(96))),
                    if (meta.isNotEmpty) ...[const SizedBox(height: 20), _rise(t, .09, Text(meta, style: _body))],
                    FutureBuilder<List<String>>(
                      future: actors,
                      builder: (context, snap) {
                        final names = snap.data ?? const [];
                        if (names.isEmpty) return const SizedBox();
                        final who = names.length == 1 ? names.first : '${names.take(names.length - 1).join(', ')} and ${names.last}';
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _rise(t, .13, Text('With $who', style: _light(24).copyWith(color: Hy.textDim))),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                right: 96,
                bottom: 120,
                child: _rise(
                  t,
                  .16,
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'STARTS IN',
                        style: TextStyle(color: Hy.textMute, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 5),
                      ),
                      const SizedBox(height: 4),
                      Text('$left', style: _light(120).copyWith(fontFeatures: _tab, height: 1)),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: t,
                    child: Container(height: 3, color: Hy.orange),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _Ring extends CustomPainter {
  final double left, width;
  _Ring(this.left, {this.width = 6});
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - width);
    canvas.drawArc(
      r,
      0,
      2 * pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = Colors.white12,
    );
    canvas.drawArc(
      r,
      -pi / 2,
      2 * pi * left,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..color = Hy.orange,
    );
  }

  @override
  bool shouldRepaint(_Ring old) => old.left != left;
}

/// A slow back-and-forth for screens without a clock of their own (0..1).
double _drift(DateTime now) => .5 + .5 * sin(now.millisecondsSinceEpoch / 9000);

/// The cinema's intermission or a marathon's break: posters from the library turning over
/// on the left; on the right the minutes left, a hairline that fills up, and when it's back.
class BreakScreen extends StatelessWidget {
  final String heading;
  final String title;
  final DateTime ends;
  final Duration? length;
  final String? hint;

  /// Poster images to cycle through.
  final List<String> posters;
  const BreakScreen({super.key, required this.heading, required this.title, required this.ends, this.length, this.posters = const [], this.hint});

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Colors.black,
    child: StreamBuilder(
      stream: Stream.periodic(const Duration(milliseconds: 250)),
      builder: (context, _) {
        final now = DateTime.now();
        final secs = max(ends.difference(now).inSeconds, 0);
        final mins = (secs / 60).ceil();
        final done = length == null || length!.inSeconds == 0 ? 0.0 : (1 - secs / length!.inSeconds).clamp(0.0, 1.0);
        // A new poster every 6 seconds.
        final slot = now.millisecondsSinceEpoch ~/ 6000;
        final poster = posters.isEmpty ? null : posters[slot % posters.length];
        return _Room(
          t: _drift(now),
          glow: const Alignment(-.5, 0),
          child: Row(
            children: [
              Expanded(
                flex: 5,
                child: Center(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 900),
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(
                        scale: Tween(begin: .96, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
                        child: child,
                      ),
                    ),
                    child: poster == null
                        ? const SizedBox()
                        : Container(
                            key: ValueKey(slot),
                            width: 340,
                            height: 510,
                            foregroundDecoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Image.network(
                                poster,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const ColoredBox(color: Hy.surface),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              Expanded(
                flex: 6,
                child: Padding(
                  padding: const EdgeInsets.only(right: 96),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(heading, style: _eyebrow),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('$mins', style: _light(200, spacing: -6).copyWith(fontFeatures: _tab, height: .95)),
                          const SizedBox(width: 16),
                          Text(mins == 1 ? 'minute' : 'minutes', style: _light(44).copyWith(color: Hy.textDim)),
                        ],
                      ),
                      const SizedBox(height: 26),
                      SizedBox(
                        width: 520,
                        child: Stack(
                          children: [
                            Container(height: 2, color: Colors.white12),
                            FractionallySizedBox(
                              widthFactor: done,
                              child: Container(height: 2, color: Hy.orange),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Back at ${ends.hour.toString().padLeft(2, '0')}:${ends.minute.toString().padLeft(2, '0')}  ·  ${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')} left',
                        style: const TextStyle(color: Hy.textDim, fontSize: 20, fontFeatures: _tab),
                      ),
                      const SizedBox(height: 44),
                      Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: _head(44)),
                      const SizedBox(height: 10),
                      const Text('Stretch your legs, grab a snack.', style: _body),
                      if (hint != null) ...[const SizedBox(height: 28), Text(hint!, style: const TextStyle(color: Hy.textMute, fontSize: 18))],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Before a screening: the movie's art, faint, behind its title and the time to the doors.
class WaitingRoom extends StatelessWidget {
  final String title;
  final DateTime start;
  final String? art;
  const WaitingRoom({super.key, required this.title, required this.start, this.art});

  @override
  Widget build(BuildContext context) => StreamBuilder(
    stream: Stream.periodic(const Duration(milliseconds: 500)),
    builder: (context, _) {
      final now = DateTime.now();
      final s = start.difference(now).inSeconds.clamp(0, 1 << 30);
      final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
      final clock = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}' : '$m:${sec.toString().padLeft(2, '0')}';
      return Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (art != null)
            Opacity(
              opacity: .3,
              child: Image.network(art!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black, Color(0x66000000)]),
            ),
          ),
          _Room(
            t: _drift(now),
            mark: true,
            footer: Text(
              'Trailers at ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Hy.textMute, fontSize: 18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('TONIGHT', style: _eyebrow),
                const SizedBox(height: 22),
                SizedBox(
                  width: 1100,
                  child: Text(title, textAlign: TextAlign.center, maxLines: 2, style: _head(84)),
                ),
                const SizedBox(height: 48),
                const Text(
                  'DOORS OPEN IN',
                  style: TextStyle(color: Hy.textMute, fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 5),
                ),
                const SizedBox(height: 6),
                Text(clock, style: _light(150, spacing: -4).copyWith(fontFeatures: _tab)),
              ],
            ),
          ),
        ],
      );
    },
  );
}

/// Each theme's colour and sign.
({Color color, IconData icon, bool flicker}) themeLook(String name) {
  final n = name.toLowerCase();
  if (n.startsWith('horror')) return (color: const Color(0xFFE5383B), icon: Icons.nightlight_round, flicker: true);
  if (n.startsWith('family')) return (color: const Color(0xFFFFC145), icon: Icons.family_restroom_rounded, flicker: false);
  if (n.startsWith('sci-fi')) return (color: const Color(0xFF4FC3F7), icon: Icons.rocket_launch_rounded, flicker: false);
  if (n.startsWith('comedy')) return (color: const Color(0xFF7CDB6A), icon: Icons.sentiment_very_satisfied_rounded, flicker: false);
  if (n.startsWith('action')) return (color: const Color(0xFFFF6A1A), icon: Icons.local_fire_department_rounded, flicker: false);
  return (color: Hy.orange, icon: Icons.theaters_rounded, flicker: false);
}

/// A seat for a showing: the same one every time for that show.
String seatFor(String showId) {
  final h = showId.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0x3fffffff);
  return '${String.fromCharCode(65 + h % 12)}${1 + (h ~/ 12) % 18}';
}

/// After a showing: a ticket stub to keep. A torn-off ticket with the film, the date and
/// time, and the seat.
class TicketStub extends StatelessWidget {
  final String title, seat;
  final DateTime when;
  final String? art;
  final double scale;
  const TicketStub({super.key, required this.title, required this.when, required this.seat, this.art, this.scale = 1});

  @override
  Widget build(BuildContext context) {
    const months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];
    final date = '${when.day} ${months[when.month - 1]} ${when.year}';
    final time = '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
    Widget field(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: const Color(0x99000000), fontSize: 11 * scale, fontWeight: FontWeight.w700, letterSpacing: 2 * scale),
        ),
        SizedBox(height: 2 * scale),
        Text(
          value,
          style: TextStyle(color: Colors.black, fontSize: 20 * scale, fontWeight: FontWeight.w800),
        ),
      ],
    );
    return SizedBox(
      width: 620 * scale,
      height: 250 * scale,
      child: ClipPath(
        clipper: _Notches(14 * scale, 440 * scale),
        child: Row(
          children: [
            // The ticket.
            Container(
              width: 440 * scale,
              padding: EdgeInsets.fromLTRB(28 * scale, 22 * scale, 22 * scale, 20 * scale),
              decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFFFE9CF), Color(0xFFFFD6A6)])),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'HEVYFIN CINEMA',
                        style: TextStyle(color: const Color(0xFFB34700), fontSize: 13 * scale, fontWeight: FontWeight.w800, letterSpacing: 4 * scale),
                      ),
                      const Spacer(),
                      Text(
                        'ADMIT ONE',
                        style: TextStyle(color: const Color(0x99000000), fontSize: 11 * scale, fontWeight: FontWeight.w700, letterSpacing: 2 * scale),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Colors.black, fontSize: 30 * scale, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -.5 * scale),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      field('DATE', date),
                      SizedBox(width: 22 * scale),
                      field('TIME', time),
                      SizedBox(width: 22 * scale),
                      field('SCREEN', '1'),
                      SizedBox(width: 22 * scale),
                      field('SEAT', seat),
                    ],
                  ),
                ],
              ),
            ),
            // The stub: dashed tear line, a barcode and the seat again.
            Expanded(
              child: Container(
                color: const Color(0xFFFF9A3C),
                padding: EdgeInsets.all(16 * scale),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      seat,
                      style: TextStyle(color: Colors.black, fontSize: 44 * scale, fontWeight: FontWeight.w900),
                    ),
                    Text(
                      'SEAT',
                      style: TextStyle(color: const Color(0x99000000), fontSize: 11 * scale, fontWeight: FontWeight.w700, letterSpacing: 2 * scale),
                    ),
                    SizedBox(height: 16 * scale),
                    SizedBox(
                      width: 120 * scale,
                      height: 42 * scale,
                      child: CustomPaint(painter: _Barcode('$title$date$seat')),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Round bites out of the edges where the stub tears off.
class _Notches extends CustomClipper<Path> {
  final double r, at;
  _Notches(this.r, this.at);
  @override
  Path getClip(Size size) => Path.combine(
    PathOperation.difference,
    Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r))),
    Path()
      ..addOval(Rect.fromCircle(center: Offset(at, 0), radius: r))
      ..addOval(Rect.fromCircle(center: Offset(at, size.height), radius: r)),
  );
  @override
  bool shouldReclip(_Notches old) => old.r != r || old.at != at;
}

class _Barcode extends CustomPainter {
  final String seed;
  _Barcode(this.seed);
  @override
  void paint(Canvas canvas, Size size) {
    final rng = Random(seed.hashCode);
    final p = Paint()..color = Colors.black;
    var x = 0.0;
    while (x < size.width) {
      final w = 1.0 + rng.nextInt(3);
      if (rng.nextBool()) canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), p);
      x += w + 1;
    }
  }

  @override
  bool shouldRepaint(_Barcode old) => old.seed != seed;
}
