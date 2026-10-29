import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../api/jellyfin.dart';
import '../../api/seerr.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../theme.dart';
import 'common.dart';

/// TV Home, after Google TV: while the remote moves through the rows, the screen behind them
/// shows the title it's on (its art, logo and a few words), and after resting there a moment
/// its trailer plays silently in the background, once.
class Spotlight extends StatefulWidget {
  final Widget child;
  const Spotlight({super.key, required this.child});

  /// Puts [item] in the spotlight (null: the page's own banner is showing).
  static void show(BuildContext context, Item? item) => context.findAncestorStateOfType<_SpotlightState>()?._show(item == null ? null : _Lit.item(item));

  /// A title that isn't in the library yet (the rows of things to request).
  static void showSeerr(BuildContext context, SeerrMedia m) => context.findAncestorStateOfType<_SpotlightState>()?._show(_Lit.seerr(m));

  @override
  State<Spotlight> createState() => _SpotlightState();
}

class _SpotlightState extends State<Spotlight> {
  final _page = GlobalKey();
  _Lit? _item;
  Timer? _settle, _rest;
  Player? _player;
  VideoController? _video;
  String? _playing;
  bool _showVideo = false;
  StreamSubscription<bool>? _done;

  void _show(_Lit? item) {
    // Rows rebuild as they load: only a real change of title counts.
    if (item?.id == _item?.id) return;
    _settle?.cancel();
    _rest?.cancel();
    _stopTrailer();
    // Flicking along a row doesn't fetch art for every tile passed.
    _settle = Timer(Duration(milliseconds: item == null || _item == null ? 0 : 140), () {
      if (!mounted) return;
      setState(() => _item = item);
      final lib = item?.item;
      if (lib != null) _rest = Timer(const Duration(seconds: 2), () => _trailer(lib));
    });
  }

  Future<void> _trailer(Item item) async {
    if (_atTop || !context.read<AppState>().trailerPreviews || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final c = jf(context);
    final id = await c.libraryTrailer(item).catchError((_) => null);
    if (id == null || !mounted || _item?.id != item.id) return;
    final p = _player ??= Player();
    // Decoded on the TV's video chip like the main player: in software the Chromecast can't
    // keep up and skips frames, which looks like fast-forward.
    _video ??= VideoController(
      p,
      configuration: Device.isTv ? const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec') : const VideoControllerConfiguration(),
    );
    await p.setVolume(0);
    _playing = item.id;
    await _done?.cancel();
    _done = p.stream.completed.listen((d) => d ? _stopTrailer() : null);
    // Shown once the first frames are in, so it never flashes black.
    StreamSubscription<bool>? first;
    first = p.stream.playing.listen((on) {
      if (on && mounted && _playing == item.id) {
        Future.delayed(const Duration(milliseconds: 400), () {
          if (mounted && _playing == item.id) setState(() => _showVideo = true);
        });
        first?.cancel();
      }
    });
    try {
      final info = await c.playbackInfo(id);
      if (!mounted || _playing != item.id) return;
      await p.open(Media(c.streamUrl(id, info)));
    } catch (_) {}
  }

  void _stopTrailer() {
    _playing = null;
    _player?.stop();
    if (_showVideo && mounted) setState(() => _showVideo = false);
  }

  /// A page opened over this one (a title, the player): nothing plays or shows underneath.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!(ModalRoute.of(context)?.isCurrent ?? true) && _item != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => mounted ? _show(null) : null);
    }
  }

  /// Back at the top of the page the banner shows itself, so the spotlight steps aside (also
  /// when coming back to the page with the remote somewhere else).
  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final top = n.metrics.pixels < 160;
    if (top != _atTop) {
      setState(() => _atTop = top);
      if (top) _stopTrailer();
    }
    return false;
  }

  bool _atTop = true;

  @override
  void dispose() {
    _settle?.cancel();
    _rest?.cancel();
    _done?.cancel();
    _player?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final item = _atTop ? null : _item;
    final on = item != null;
    final size = MediaQuery.sizeOf(context);
    final pad = pagePadding(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        // The title's art across the top, then the trailer over it.
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: on ? 1 : 0,
            duration: const Duration(milliseconds: 350),
            child: Align(
              alignment: Alignment.topRight,
              child: SizedBox(
                width: size.width * .78,
                height: size.height * .72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 450),
                      layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, ?cur]),
                      child: item == null ? const SizedBox.shrink() : NetImage(item.backdrop(c), key: ValueKey(item.id), alignment: Alignment.topCenter),
                    ),
                    if (_video != null)
                      AnimatedOpacity(
                        opacity: _showVideo ? 1 : 0,
                        duration: const Duration(milliseconds: 700),
                        child: Video(controller: _video!, controls: NoVideoControls, fill: Colors.transparent, fit: BoxFit.cover),
                      ),
                    // Melts into the page on the left and at the bottom, with soft top and right edges.
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Hy.bg, Color(0x99070707), Colors.transparent, Colors.transparent, Color(0x99070707)],
                          stops: [0, .3, .6, .93, 1],
                        ),
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x99070707), Colors.transparent],
                          stops: [0, .1],
                        ),
                      ),
                    ),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Color(0x66070707), Hy.bg],
                          stops: [.35, .65, 1],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Rows above the one in use fade out under the title (only then: the mask costs a
        // layer every frame, and the key keeps the page's state when it comes and goes).
        if (on)
          ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.transparent, Colors.white],
              stops: [0, .28, .312],
            ).createShader(r),
            child: KeyedSubtree(
              key: _page,
              child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
            ),
          )
        else
          KeyedSubtree(
            key: _page,
            child: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
          ),
        Positioned(
          left: pad,
          top: 36,
          width: (size.width * .44).clamp(380, 640),
          child: IgnorePointer(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topLeft, children: [...prev, ?cur]),
              transitionBuilder: (child, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, .04), end: Offset.zero).animate(a),
                  child: child,
                ),
              ),
              child: item == null ? const SizedBox.shrink(key: ValueKey('none')) : _Info(item, key: ValueKey(item.id)),
            ),
          ),
        ),
      ],
    );
  }
}

/// What the spotlight shows: a library title, or one that can be requested.
class _Lit {
  final String id;
  final Item? item;
  final SeerrMedia? media;
  _Lit.item(Item this.item) : id = item.id, media = null;
  _Lit.seerr(SeerrMedia this.media) : id = 'tmdb${media.tmdbId}', item = null;

  String? backdrop(JellyfinClient c) => item != null ? c.backdrop(item!, width: 1280) : SeerrClient.image(media!.backdropPath, size: 'w1280');
}

class _Info extends StatelessWidget {
  final _Lit lit;
  const _Info(this.lit, {super.key});

  @override
  Widget build(BuildContext context) {
    final m = lit.media;
    if (m != null) {
      final meta = [?m.year?.toString(), m.isTv ? 'Series' : 'Film', ...m.genres.take(2)].join('  ·  ');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _title(m.title),
          const SizedBox(height: 12),
          Text(meta, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (m.status.requestable)
            const Text(
              'Not on Hevyfin yet: open it to request',
              style: TextStyle(color: Hy.orange, fontWeight: FontWeight.w700),
            )
          else
            StatusPill(m.status, progress: m.downloadProgress),
          ?_overview(m.overview),
        ],
      );
    }
    final item = lit.item!;
    final c = jf(context);
    final show = item.isEpisode && item.seriesId != null;
    final logo = c.logo(item);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logo != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96, maxWidth: 380),
            child: Image.network(logo, alignment: Alignment.bottomLeft, errorBuilder: (_, _, _) => _title(item.displayTitle)),
          )
        else
          _title(item.displayTitle),
        const SizedBox(height: 12),
        if (show) Text('${item.episodeCode}  ${item.name}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)) else MetaLine(item),
        ?_overview(item.overview),
      ],
    );
  }

  static Widget _title(String t) => Text(
    t,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, height: 1.05, letterSpacing: -1),
  );

  static Widget? _overview(String? t) => (t ?? '').isEmpty
      ? null
      : Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(
            t!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15.5, height: 1.4, color: Color(0xFFDDDDDD), shadows: [Shadow(blurRadius: 8)]),
          ),
        );
}
