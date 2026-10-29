import 'package:flutter/material.dart';

import '../../theme.dart';
import '../shell.dart';

/// TV launch: the wordmark settles in with a light passing over it, then fades into the
/// app (which has been loading Home underneath all along).
class Intro extends StatefulWidget {
  final Widget child;
  const Intro({super.key, required this.child});
  @override
  State<Intro> createState() => _IntroState();
}

class _IntroState extends State<Intro> with SingleTickerProviderStateMixin {
  late final _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..forward();
  bool _gone = false;

  @override
  void initState() {
    super.initState();
    _a.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) setState(() => _gone = true);
    });
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      if (!_gone)
        IgnorePointer(
          child: AnimatedBuilder(
            animation: _a,
            builder: (context, _) {
              final t = _a.value;
              // In over the first 40%, the light sweeps 25–70%, out over the last 25%.
              final settle = Curves.easeOutBack.transform((t / .4).clamp(0, 1));
              final sweep = ((t - .25) / .45).clamp(0.0, 1.0);
              final out = ((t - .75) / .25).clamp(0.0, 1.0);
              return Opacity(
                opacity: 1 - Curves.easeIn.transform(out),
                child: ColoredBox(
                  color: Hy.bg,
                  child: Center(
                    child: Opacity(
                      opacity: (t / .25).clamp(0, 1),
                      child: Transform.scale(
                        scale: .9 + .1 * settle,
                        child: ShaderMask(
                          blendMode: BlendMode.srcATop,
                          shaderCallback: (r) => LinearGradient(
                            begin: Alignment(-1.6 + 3.2 * sweep, -.3),
                            end: Alignment(-1.0 + 3.2 * sweep, .3),
                            colors: const [Colors.transparent, Color(0xCCFFFFFF), Colors.transparent],
                          ).createShader(r),
                          child: const Wordmark(size: 72),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
    ],
  );
}
