import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import '../theme.dart';
import 'widgets/common.dart';

/// Netflix-style controls drawn over the video. On phones: tap to show or hide,
/// double-tap the sides to skip 10 seconds, lock the screen. On the desktop: move the
/// mouse to show them, click to play/pause, double-click for fullscreen. Both: scrub the
/// bar, pick speed, episodes and tracks, and jump to the next episode.
class PlayerControls extends StatefulWidget {
  final Player player;
  final String title;
  final String? subtitle;
  final VoidCallback onBack;
  final VoidCallback onTracks;
  final VoidCallback? onEpisodes;
  final VoidCallback? onNext;

  /// Hidden while the video is in the floating mini player.
  final bool enabled;

  /// Mouse-and-keyboard layout.
  final bool desktop;

  /// Remote-control layout (Android TV): no touch gestures, keys drive everything.
  final bool tv;

  /// What OK does on a TV while the controls are hidden and a "Skip Intro" or
  /// "Next Episode" button is on screen.
  final VoidCallback? onOverlayAction;
  final bool fullscreen;
  final VoidCallback? onFullscreen;

  /// A frame from the video at a position, shown above the bar while seeking.
  final Widget? Function(Duration)? preview;

  /// In a watch party play/pause and seeking go through the group instead of the player.
  final VoidCallback? onTogglePlay;
  final ValueChanged<Duration>? onSeekTo;

  /// Sleep timer: opens its picker; [sleep] is what's set ("23 min", "End of episode") or null.
  final VoidCallback? onSleep;
  final String? sleep;
  const PlayerControls({
    super.key,
    required this.player,
    required this.title,
    this.subtitle,
    required this.onBack,
    required this.onTracks,
    this.onEpisodes,
    this.onNext,
    this.enabled = true,
    this.desktop = false,
    this.tv = false,
    this.onOverlayAction,
    this.fullscreen = false,
    this.onFullscreen,
    this.preview,
    this.onTogglePlay,
    this.onSeekTo,
    this.onSleep,
    this.sleep,
  });

  @override
  State<PlayerControls> createState() => PlayerControlsState();
}

class PlayerControlsState extends State<PlayerControls> with TickerProviderStateMixin {
  Player get _p => widget.player;
  final _subs = <StreamSubscription>[];
  late final _playIcon = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: _p.state.playing ? 1 : 0);

  bool _visible = true;
  bool _locked = false;
  Timer? _hide;

  Duration _pos = Duration.zero, _dur = Duration.zero, _buf = Duration.zero;
  bool _buffering = true;
  double? _scrub; // 0..1 while dragging

  // Remote and keyboard seeks: where the last skip landed, shown as a preview for a moment.
  Duration? _peek;
  Timer? _peekTimer;

  // Double-tap seeking: which side, how far so far, and a ripple to show it.
  int _seekDir = 0;
  int _seekSecs = 0;
  Timer? _seekReset;
  Offset? _tapAt;

  // Desktop: the play/pause icon that pops in the middle after a click or key press.
  IconData? _flash;

  // TV: the video area takes the remote's keys; Up moves onto the buttons.
  final _keys = FocusNode(debugLabel: 'player-keys');
  final _firstAction = FocusNode(debugLabel: 'first-action');
  int _flashId = 0;
  double _volume = 100;
  bool _hoverBar = false;

  @override
  void initState() {
    super.initState();
    _pos = _p.state.position;
    _dur = _p.state.duration;
    _buffering = _p.state.buffering;
    _volume = _p.state.volume;
    _subs
      // Position updates arrive many times a second: only redraw while the controls show
      // (and then at most once per displayed second).
      ..add(
        _p.stream.position.listen((v) {
          final changed = v.inSeconds != _pos.inSeconds;
          _pos = v;
          if (_scrub == null && mounted && _visible && changed) setState(() {});
        }),
      )
      ..add(_p.stream.duration.listen((v) => mounted ? setState(() => _dur = v) : null))
      ..add(
        _p.stream.buffer.listen((v) {
          final changed = (v - _buf).inSeconds.abs() >= 2;
          _buf = v;
          if (mounted && _visible && changed) setState(() {});
        }),
      )
      ..add(_p.stream.buffering.listen((v) => mounted ? setState(() => _buffering = v) : null))
      ..add(_p.stream.volume.listen((v) => mounted ? setState(() => _volume = v) : null))
      ..add(
        _p.stream.playing.listen((v) {
          v ? _playIcon.forward() : _playIcon.reverse();
          if (v) {
            _scheduleHide();
          } else {
            _hide?.cancel();
          }
        }),
      );
    _scheduleHide();
    // TV: the remote drives the player from the moment it opens.
    if (widget.tv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mayTakeFocus(FocusManager.instance.primaryFocus)) _keys.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _hide?.cancel();
    _seekReset?.cancel();
    _peekTimer?.cancel();
    _keys.dispose();
    _firstAction.dispose();
    _playIcon.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(Duration(seconds: widget.tv ? 7 : (widget.desktop ? 3 : 4)), () {
      if (mounted && _p.state.playing && _scrub == null && !_hoverBar) hide();
    });
  }

  /// Shows the controls for a few seconds (also used by keyboard shortcuts).
  void show() {
    if (!_visible) setState(() => _visible = true);
    _scheduleHide();
  }

  void _show() => show();

  bool get visible => _visible;

  void hide() {
    _hide?.cancel();
    setState(() => _visible = false);
    // On a TV the remote goes back to the video when the buttons disappear.
    // Only take the remote back from our own buttons: never from an episode list or
    // track menu open on top, or presses there would land on the video behind it.
    final p = FocusManager.instance.primaryFocus;
    if (widget.tv && _mayTakeFocus(p)) _keys.requestFocus();
  }

  /// Puts the remote on the first button: right away if the buttons are built, else once
  /// they are (and make sure that frame comes: playback alone no longer redraws).
  void _focusButtons() {
    if (_firstAction.context != null) {
      _firstAction.requestFocus();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _firstAction.requestFocus());
    WidgetsBinding.instance.scheduleFrame();
  }

  /// True unless the focus is somewhere else on top (an episode list, a track menu):
  /// nothing focused, the player itself, one of its buttons, or just its page.
  bool _mayTakeFocus(FocusNode? p) => p == null || p == _keys || p.ancestors.contains(_keys) || _keys.ancestors.contains(p);

  /// Remote keys while the video (not a button) has focus.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    // Keys from a focused button bubble up here too: leave those to normal navigation.
    if (e is KeyUpEvent || !node.hasPrimaryFocus) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.gameButtonA) {
      if (e is KeyRepeatEvent) return KeyEventResult.handled;
      if (!_visible && widget.onOverlayAction != null) {
        widget.onOverlayAction!();
      } else {
        togglePlay();
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.mediaPlay || k == LogicalKeyboardKey.mediaPause || k == LogicalKeyboardKey.space) {
      if (e is! KeyRepeatEvent) togglePlay();
      return KeyEventResult.handled;
    }
    // A remote steps 30 seconds a press, Netflix style; a keyboard 10.
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.mediaRewind) {
      seekBy(widget.tv ? -30 : -10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.mediaFastForward) {
      seekBy(widget.tv ? 30 : 10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.arrowDown) {
      show();
      _focusButtons();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Keys while a button has focus: Down (or Back, handled by the page) returns to the video.
  KeyEventResult _onButtonKey(FocusNode _, KeyEvent e) {
    if (e is! KeyUpEvent) show();
    if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.arrowDown) {
      hide();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Play/pause with the centre icon popping, Netflix-desktop style.
  void togglePlay() {
    _playPause();
    setState(() {
      _flash = _p.state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded;
      _flashId++;
    });
    show();
  }

  /// Skip and show where we are.
  void seekBy(int s) {
    _seekBy(s);
    show();
    if (widget.preview == null) return;
    _peekTimer?.cancel();
    setState(() => _peek = _pos);
    _peekTimer = Timer(const Duration(milliseconds: 1400), () => mounted ? setState(() => _peek = null) : null);
  }

  void _toggle() {
    if (_visible) {
      _hide?.cancel();
      setState(() => _visible = false);
    } else {
      _show();
    }
  }

  void _seekBy(int s) {
    var p = _p.state.position + Duration(seconds: s);
    if (p < Duration.zero) p = Duration.zero;
    if (_dur > Duration.zero && p > _dur) p = _dur;
    _seekTo(p);
    setState(() => _pos = p);
  }

  void _seekTo(Duration p) => widget.onSeekTo != null ? widget.onSeekTo!(p) : _p.seek(p);
  void _playPause() => widget.onTogglePlay != null ? widget.onTogglePlay!() : _p.playOrPause();

  void _doubleTap() {
    final at = _tapAt;
    if (at == null || _locked) return;
    final w = context.size?.width ?? 1;
    final dir = at.dx < w * .4 ? -1 : (at.dx > w * .6 ? 1 : 0);
    if (dir == 0) {
      _playPause();
      return;
    }
    setState(() {
      _seekSecs = _seekDir == dir ? _seekSecs + 10 : 10;
      _seekDir = dir;
    });
    _seekBy(dir * 10);
    _seekReset?.cancel();
    _seekReset = Timer(const Duration(milliseconds: 750), () => mounted ? setState(() => _seekDir = 0) : null);
  }

  static String _fmt(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
    String two(int n) => n.toString().padLeft(2, '0');
    return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
  }

  Future<void> _speed() async {
    const rates = [.5, .75, 1.0, 1.25, 1.5, 2.0];
    _hide?.cancel();
    final i = await showBlurPicker(context, [for (final r in rates) r == 1 ? '1x (Normal)' : '${r}x'], selected: rates.indexOf(_p.state.rate));
    if (i != null) await _p.setRate(rates[i]);
    _scheduleHide();
  }

  /// Speed, lock and the sleep timer, in one list.
  Future<void> _more() async {
    _hide?.cancel();
    final rate = _p.state.rate;
    final options = <(String, VoidCallback)>[
      ('Speed: ${rate == 1 ? 'Normal' : '${rate}x'}', _speed),
      if (!widget.tv)
        (
          'Lock the screen',
          () {
            setState(() => _locked = true);
            _scheduleHide();
          },
        ),
      if (widget.onSleep != null) (widget.sleep == null ? 'Sleep timer' : 'Sleep timer: ${widget.sleep}', widget.onSleep!),
    ];
    final i = await showBlurPicker(context, [for (final o in options) o.$1]);
    if (i != null) {
      options[i].$2();
    } else {
      _scheduleHide();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return const SizedBox.shrink();
    final pad = MediaQuery.paddingOf(context);
    final progress = _scrub ?? (_dur.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0));
    final shown = _dur * progress;
    final buffered = _dur.inMilliseconds == 0 ? 0.0 : (_buf.inMilliseconds / _dur.inMilliseconds).clamp(0.0, 1.0);

    final desktop = widget.desktop;
    final tv = widget.tv;
    final layer = MouseRegion(
      cursor: desktop && !_visible ? SystemMouseCursors.none : MouseCursor.defer,
      onHover: desktop ? (_) => show() : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tv ? null : (desktop ? togglePlay : _toggle),
        onDoubleTapDown: desktop || tv ? null : (d) => _tapAt = d.localPosition,
        onDoubleTap: tv ? null : (desktop ? widget.onFullscreen : _doubleTap),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if ((desktop || tv) && _flash != null) _Flash(key: ValueKey(_flashId), icon: _flash!),
            // Double-tap ripple on the side that was tapped.
            _SeekRipple(dir: _seekDir, seconds: _seekSecs),
            if (_buffering) const Center(child: _Spinner()),
            if (_locked)
              _Fade(
                visible: _visible,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.only(bottom: 24 + pad.bottom),
                    child: _Pill(
                      icon: Icons.lock_rounded,
                      label: 'Screen locked · tap to unlock',
                      onTap: () {
                        setState(() => _locked = false);
                        _show();
                      },
                    ),
                  ),
                ),
              )
            else
              _Fade(
                visible: _visible,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Darken the edges so the controls read on any picture.
                    const IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [0, .22, .6, 1],
                            colors: [Color(0xCC000000), Color(0x66000000), Color(0x66000000), Color(0xE6000000)],
                          ),
                        ),
                      ),
                    ),
                    // Top: back, title, tracks.
                    Positioned(
                      left: pad.left + 8,
                      right: pad.right + 8,
                      top: pad.top + 6,
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: widget.onBack,
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 28),
                          ),
                          const SizedBox(width: 4),
                          // The desktop shows the title in the bottom bar instead.
                          if (desktop)
                            const Spacer()
                          else
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.white),
                                  ),
                                  if (widget.subtitle != null)
                                    Text(
                                      widget.subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13, color: Hy.textDim),
                                    ),
                                  if (_dur > Duration.zero)
                                    Text(
                                      'Ends at ${clockTime(DateTime.now().add((_dur - shown) * (1 / _p.state.rate)))}',
                                      style: const TextStyle(fontSize: 12.5, color: Hy.textDim, fontWeight: FontWeight.w600),
                                    ),
                                ],
                              ),
                            ),
                          const SizedBox(width: 52),
                        ],
                      ),
                    ),
                    // Centre: -10, play/pause, +10 (phones; the desktop has them in the bar).
                    if (!desktop && !tv)
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _SpinButton(
                              icon: Icons.replay_10_rounded,
                              turns: -1,
                              onTap: () {
                                _seekBy(-10);
                                _scheduleHide();
                              },
                            ),
                            const SizedBox(width: 56),
                            HoverScale(
                              scale: 1,
                              onTap: () {
                                _playPause();
                                _scheduleHide();
                              },
                              child: AnimatedOpacity(
                                opacity: _buffering ? 0 : 1,
                                duration: const Duration(milliseconds: 150),
                                child: AnimatedIcon(icon: AnimatedIcons.play_pause, progress: _playIcon, size: 64, color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 56),
                            _SpinButton(
                              icon: Icons.forward_10_rounded,
                              turns: 1,
                              onTap: () {
                                _seekBy(10);
                                _scheduleHide();
                              },
                            ),
                          ],
                        ),
                      ),
                    // Bottom: scrubber with remaining time, then the action row.
                    Positioned(
                      left: pad.left + 20,
                      right: pad.right + 20,
                      bottom: pad.bottom + 6,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: _Scrubber(
                                  value: progress,
                                  buffered: buffered,
                                  label: _scrub == null ? (_peek == null ? null : _fmt(_peek!)) : _fmt(shown),
                                  preview: switch (_scrub != null ? shown : _peek) {
                                    final at? => widget.preview?.call(at),
                                    null => null,
                                  },
                                  onStart: (v) {
                                    _hide?.cancel();
                                    setState(() => _scrub = v);
                                  },
                                  onChanged: (v) => setState(() => _scrub = v),
                                  onEnd: (v) {
                                    _seekTo(_dur * v);
                                    setState(() {
                                      _pos = _dur * v;
                                      _scrub = null;
                                    });
                                    _scheduleHide();
                                  },
                                ),
                              ),
                              const SizedBox(width: 14),
                              SizedBox(
                                width: 64,
                                child: Text(
                                  _dur == Duration.zero ? '' : _fmt(_dur - shown),
                                  textAlign: TextAlign.right,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          if (desktop)
                            MouseRegion(
                              onEnter: (_) => _hoverBar = true,
                              onExit: (_) => _hoverBar = false,
                              child: Row(
                                children: [
                                  _IconBtn(
                                    icon: _p.state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                    tip: _p.state.playing ? 'Pause (Space)' : 'Play (Space)',
                                    onTap: togglePlay,
                                    big: true,
                                  ),
                                  _IconBtn(icon: Icons.replay_10_rounded, tip: 'Back 10 seconds (←)', onTap: () => seekBy(-10)),
                                  _IconBtn(icon: Icons.forward_10_rounded, tip: 'Forward 10 seconds (→)', onTap: () => seekBy(10)),
                                  _IconBtn(
                                    icon: _volume == 0 ? Icons.volume_off_rounded : (_volume < 50 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                                    tip: 'Mute (M)',
                                    onTap: () => _p.setVolume(_volume > 0 ? 0 : 100),
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: Slider(value: _volume.clamp(0, 100), max: 100, onChanged: (v) => _p.setVolume(v)),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      [
                                        widget.title,
                                        ?widget.subtitle,
                                        if (_dur > Duration.zero) '·  ends at ${clockTime(DateTime.now().add((_dur - shown) * (1 / _p.state.rate)))}',
                                      ].join('   '),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  if (widget.onNext != null)
                                    _IconBtn(icon: Icons.skip_next_rounded, tip: 'Next episode (Shift+N)', onTap: widget.onNext!, accent: true),
                                  if (widget.onEpisodes != null) _IconBtn(icon: Icons.video_library_outlined, tip: 'Episodes', onTap: widget.onEpisodes!),
                                  _IconBtn(icon: Icons.subtitles_outlined, tip: 'Audio & Subtitles', onTap: widget.onTracks),
                                  _IconBtn(icon: Icons.speed_rounded, tip: 'Speed', onTap: _speed),
                                  if (widget.onSleep != null)
                                    _IconBtn(
                                      icon: Icons.bedtime_rounded,
                                      tip: widget.sleep == null ? 'Sleep timer' : 'Sleep timer: ${widget.sleep}',
                                      onTap: widget.onSleep!,
                                      accent: widget.sleep != null,
                                    ),
                                  if (widget.onFullscreen != null)
                                    _IconBtn(
                                      icon: widget.fullscreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                                      tip: 'Fullscreen (F)',
                                      onTap: widget.onFullscreen!,
                                    ),
                                ],
                              ),
                            )
                          else
                            Focus(
                              canRequestFocus: false,
                              skipTraversal: true,
                              onKeyEvent: _onButtonKey,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                // The few things people reach for; the rest under More.
                                child: Row(
                                  children: [
                                    if (widget.onEpisodes != null)
                                      _Action(focusNode: _firstAction, icon: Icons.video_library_outlined, label: 'Episodes', onTap: widget.onEpisodes!),
                                    _Action(
                                      focusNode: widget.onEpisodes == null ? _firstAction : null,
                                      icon: Icons.subtitles_outlined,
                                      label: 'Audio & Subtitles',
                                      onTap: widget.onTracks,
                                    ),
                                    _Action(
                                      icon: Icons.more_horiz_rounded,
                                      label: 'More',
                                      onTap: _more,
                                      lit: widget.sleep != null || _p.state.rate != 1,
                                    ),
                                    if (widget.onNext != null) ...[
                                      const SizedBox(width: 24),
                                      _Action(icon: Icons.skip_next_rounded, label: 'Next Episode', onTap: widget.onNext!, strong: true),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (!tv) return layer;
    return Focus(focusNode: _keys, autofocus: true, onKeyEvent: _onKey, child: layer);
  }
}

class _Fade extends StatelessWidget {
  final bool visible;
  final Widget child;
  const _Fade({required this.visible, required this.child});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      child: AnimatedScale(scale: visible ? 1 : 1.02, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic, child: child),
    ),
  );
}

/// ±10 s button that gives a little spin when pressed.
class _SpinButton extends StatefulWidget {
  final IconData icon;
  final int turns;
  final VoidCallback onTap;
  const _SpinButton({required this.icon, required this.turns, required this.onTap});
  @override
  State<_SpinButton> createState() => _SpinButtonState();
}

class _SpinButtonState extends State<_SpinButton> {
  double _turns = 0;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: () {
      setState(() => _turns += widget.turns * .25);
      widget.onTap();
    },
    child: AnimatedRotation(
      turns: _turns,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      child: Icon(widget.icon, color: Colors.white, size: 44),
    ),
  );
}

class _Action extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool strong;

  /// A setting that's on: orange icon, normal weight.
  final bool lit;
  final FocusNode? focusNode;
  const _Action({required this.icon, required this.label, required this.onTap, this.strong = false, this.lit = false, this.focusNode});
  @override
  Widget build(BuildContext context) => TextButton.icon(
    focusNode: focusNode,
    onPressed: onTap,
    style: TextButton.styleFrom(foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
    icon: Icon(icon, size: 24, color: strong || lit ? Hy.orange : Colors.white),
    label: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, fontSize: 13.5)),
  );
}

class _Pill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Pill({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .7),
    shape: const StadiumBorder(side: BorderSide(color: Colors.white38)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    ),
  );
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(width: 56, height: 56, child: CircularProgressIndicator(color: Hy.orange, strokeWidth: 4));
}

/// The bar: a thin track that thickens while dragging, with a time bubble above the thumb.
const _previewW = 240.0;

class _Scrubber extends StatelessWidget {
  final double value, buffered;
  final String? label;
  final Widget? preview;
  final ValueChanged<double> onStart, onChanged, onEnd;
  const _Scrubber({required this.value, required this.buffered, this.label, this.preview, required this.onStart, required this.onChanged, required this.onEnd});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final w = box.maxWidth;
      double at(double dx) => (dx / w).clamp(0.0, 1.0);
      final dragging = label != null;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (d) => onStart(at(d.localPosition.dx)),
        onHorizontalDragUpdate: (d) => onChanged(at(d.localPosition.dx)),
        onHorizontalDragEnd: (_) => onEnd(value),
        onTapUp: (d) => onEnd(at(d.localPosition.dx)),
        child: SizedBox(
          height: 44,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.centerLeft,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: dragging ? 7 : 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
              ),
              FractionallySizedBox(
                widthFactor: buffered,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: dragging ? 7 : 4,
                  decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              FractionallySizedBox(
                widthFactor: value,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: dragging ? 7 : 4,
                  decoration: BoxDecoration(color: Hy.orange, borderRadius: BorderRadius.circular(4)),
                ),
              ),
              Positioned(
                left: value * w - (dragging ? 11 : 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: dragging ? 22 : 16,
                  height: dragging ? 22 : 16,
                  decoration: const BoxDecoration(
                    color: Hy.orange,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 6)],
                  ),
                ),
              ),
              if (dragging && preview != null)
                Positioned(
                  left: (value * w - _previewW / 2).clamp(0, max(0, w - _previewW)),
                  bottom: 70,
                  child: Container(
                    width: _previewW,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white70, width: 2),
                    ),
                    child: ClipRRect(borderRadius: BorderRadius.circular(6), child: preview),
                  ),
                ),
              if (dragging)
                Positioned(
                  left: (value * w - 36).clamp(0, w - 72),
                  bottom: 36,
                  child: Container(
                    width: 72,
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .8), borderRadius: BorderRadius.circular(6)),
                    child: Text(
                      label!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontFeatures: [FontFeature.tabularFigures()]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// The half-moon glow and "+20s" that appear while double-tapping a side.
class _SeekRipple extends StatelessWidget {
  final int dir, seconds;
  const _SeekRipple({required this.dir, required this.seconds});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: AnimatedOpacity(
      opacity: dir == 0 ? 0 : 1,
      duration: Duration(milliseconds: dir == 0 ? 400 : 80),
      child: Align(
        alignment: dir < 0 ? Alignment.centerLeft : Alignment.centerRight,
        child: FractionallySizedBox(
          widthFactor: .38,
          heightFactor: 1,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: dir < 0 ? const BorderRadius.horizontal(right: Radius.circular(400)) : const BorderRadius.horizontal(left: Radius.circular(400)),
            ),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(dir < 0 ? Icons.fast_rewind_rounded : Icons.fast_forward_rounded, color: Colors.white, size: 36),
                const SizedBox(height: 4),
                Text('${dir < 0 ? '-' : '+'}${seconds}s', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tip;
  final VoidCallback onTap;
  final bool big, accent;
  const _IconBtn({required this.icon, required this.tip, required this.onTap, this.big = false, this.accent = false});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: tip,
    child: HoverScale(
      scale: 1.2,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Icon(icon, size: big ? 40 : 30, color: accent ? Hy.orange : Colors.white),
      ),
    ),
  );
}

/// The big icon that pops and fades in the middle when you click to play or pause.
class _Flash extends StatefulWidget {
  final IconData icon;
  const _Flash({super.key, required this.icon});
  @override
  State<_Flash> createState() => _FlashState();
}

class _FlashState extends State<_Flash> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Center(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Opacity(
          opacity: (1 - _c.value).clamp(0, 1),
          child: Transform.scale(
            scale: 1 + _c.value * .6,
            child: Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .45), shape: BoxShape.circle),
              child: Icon(widget.icon, size: 56, color: Colors.white),
            ),
          ),
        ),
      ),
    ),
  );
}
