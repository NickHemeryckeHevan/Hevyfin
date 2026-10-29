import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../theme.dart';
import '../shell.dart';
import 'common.dart';

/// The big billboard at the top of Home/Shows/Movies.
class Billboard extends StatelessWidget {
  final Item item;
  final String? eyebrow;
  const Billboard(this.item, {super.key, this.eyebrow});

  @override
  Widget build(BuildContext context) {
    if (isNarrow(context)) return _MobileBillboard(item);
    final c = jf(context);
    final size = MediaQuery.sizeOf(context);
    final narrow = isNarrow(context);
    final height = narrow ? size.height * .62 : (size.width * .5).clamp(420.0, (size.height * .85).clamp(420.0, double.infinity));
    final pad = pagePadding(context);
    final logo = c.logo(item);
    final art = narrow ? (c.poster(item, width: 900) ?? c.backdrop(item)) : c.backdrop(item);

    // Its own layer, so moving the remote through rows below doesn't repaint the art.
    return ScrollTopOnFocus(
      child: RepaintBoundary(
        child: SizedBox(
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(art, alignment: narrow ? Alignment.topCenter : Alignment.topCenter),
              // Fade left (desktop) and into the page at the bottom, like Netflix.
              if (!narrow)
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment(.3, 0), colors: [Color(0xE6000000), Colors.transparent]),
                  ),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, .55, 1],
                    colors: [Colors.transparent, Hy.bg.withValues(alpha: .25), Hy.bg],
                  ),
                ),
              ),
              Positioned(
                left: pad,
                right: narrow ? pad : null,
                bottom: narrow ? 20 : height * .16,
                child: FadeIn(
                  from: const Offset(-.04, 0),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: narrow ? double.infinity : (size.width * .42).clamp(380, 620)),
                    child: Column(
                      crossAxisAlignment: narrow ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (eyebrow != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Wordmark(size: 13),
                                const SizedBox(width: 8),
                                Text(
                                  eyebrow!.toUpperCase(),
                                  style: const TextStyle(letterSpacing: 3, fontWeight: FontWeight.w700, fontSize: 12, color: Hy.textDim),
                                ),
                              ],
                            ),
                          ),
                        if (logo != null)
                          ConstrainedBox(
                            constraints: BoxConstraints(maxHeight: narrow ? 90 : 150, maxWidth: narrow ? 260 : 460),
                            child: Image.network(
                              logo,
                              alignment: narrow ? Alignment.center : Alignment.bottomLeft,
                              errorBuilder: (_, _, _) => _Title(item.displayTitle, narrow),
                            ),
                          )
                        else
                          _Title(item.displayTitle, narrow),
                        const SizedBox(height: 14),
                        if (!narrow) ...[
                          MetaLine(item),
                          const SizedBox(height: 12),
                          if ((item.overview ?? '').isNotEmpty)
                            Text(
                              item.overview!,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, height: 1.4, shadows: [Shadow(blurRadius: 8)]),
                            ),
                          const SizedBox(height: 20),
                        ] else ...[
                          Text(item.genres.take(3).join('  •  '), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 14),
                        ],
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PlayButton(item, autofocus: Device.isTv),
                            const SizedBox(width: 10),
                            FilledButton.icon(
                              onPressed: () => openItem(context, item),
                              style: FilledButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: .22), foregroundColor: Colors.white),
                              icon: const Icon(Icons.info_outline_rounded),
                              label: const Text('More info'),
                            ),
                            const SizedBox(width: 10),
                            _MyListRound(item),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Round My List toggle whose icon spins between + and ✓.
class _MyListRound extends StatelessWidget {
  final Item item;
  const _MyListRound(this.item);
  @override
  Widget build(BuildContext context) {
    final inList = context.select<AppState, bool>((a) => a.myList.contains(item.id));
    return Tooltip(
      message: inList ? 'Remove from My List' : 'Add to My List',
      child: HoverScale(
        scale: 1.1,
        onTap: () => context.read<AppState>().toggleMyList(item.id).catchError((_) {}),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.black38,
            border: Border.all(color: inList ? Hy.orange : Colors.white70, width: 2),
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (c, a) => RotationTransition(
              turns: Tween(begin: .75, end: 1.0).animate(a),
              child: FadeTransition(opacity: a, child: c),
            ),
            child: Icon(inList ? Icons.check_rounded : Icons.add_rounded, key: ValueKey(inList), color: inList ? Hy.orange : Colors.white),
          ),
        ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  final bool narrow;
  const _Title(this.text, this.narrow);
  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: narrow ? TextAlign.center : TextAlign.start,
    style: TextStyle(fontSize: narrow ? 34 : 54, fontWeight: FontWeight.w900, height: 1.02, letterSpacing: -1, shadows: const [Shadow(blurRadius: 16)]),
  );
}

/// White Netflix "Play" (or "Resume"), which opens the player.
class PlayButton extends StatefulWidget {
  final Item item;
  final String? label;

  /// On a TV the remote starts here.
  final bool autofocus;
  const PlayButton(this.item, {super.key, this.label, this.autofocus = false});

  @override
  State<PlayButton> createState() => _PlayButtonState();
}

class _PlayButtonState extends State<PlayButton> {
  late final _node = FocusNode(debugLabel: 'play')..addListener(_onFocus);

  @override
  void initState() {
    super.initState();
    // TV: parts of a page load at different speeds, and the shell puts the remote on whatever
    // came first (a row further down, say). The page's Play takes it when it appears, unless
    // the remote has been used since the page opened.
    if (widget.autofocus && Device.isTv) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_node.hasFocus && TvRemote.untouchedSincePageOpened) _node.requestFocus();
      });
    }
  }

  /// TV: resting on Play gets the stream ready, so OK starts it sooner.
  void _onFocus() {
    if (!_node.hasFocus || !Device.isTv) return;
    prewarmPlay(context, widget.item);
  }

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item, label = widget.label;
    final resume = item.resumePosition > Duration.zero && !item.isSeries;
    return FilledButton.icon(
      focusNode: _node,
      autofocus: widget.autofocus,
      onPressed: () => playItem(context, item),
      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
      icon: const Icon(Icons.play_arrow_rounded, size: 28),
      label: Text(label ?? (resume ? 'Resume' : 'Play')),
    );
  }
}

final _targets = <String, (DateTime, Future<Item?>)>{};

/// What Play on [item] will start, worked out once for a little while.
Future<Item?> _target(BuildContext context, Item item) {
  final key = '${item.id}${item.miniStop?.code ?? ''}'; // a mini series isn't its whole show
  final had = _targets[key];
  if (had != null && DateTime.now().difference(had.$1) < const Duration(seconds: 45)) return had.$2;
  final f = playTarget(jf(context), item, story: context.read<AppState>().storyOrder.contains(item.id));
  f.ignore();
  _targets[key] = (DateTime.now(), f);
  return f;
}

Timer? _warmSoon;

/// Gets [item]'s stream ready ahead of a press on Play (a show: its next episode's), once
/// the remote has stayed on it a moment (flicking along a row asks for nothing).
void prewarmPlay(BuildContext context, Item item) {
  _warmSoon?.cancel();
  _warmSoon = Timer(const Duration(milliseconds: 350), () => context.mounted ? _prewarm(context, item) : null);
}

Future<void> _prewarm(BuildContext context, Item item) async {
  final c = jf(context), mbps = context.read<AppState>().maxMbps;
  try {
    final target = (item.isSeries || item.isCollection) ? await _target(context, item) : item;
    if (target != null) c.prewarm(target.id, maxBitrate: mbps > 0 ? mbps * 1000000 : null);
  } catch (_) {}
}

/// Play a movie/episode, or for a show: the next-up episode (else the first one).
Future<void> playItem(BuildContext context, Item item) async {
  // A mini series: its next episode, then on along its universe's path.
  if (item.miniStop case final m?) {
    context.push('/play/${m.nextPart.id}?in=${m.box}');
    return;
  }
  // Opened from a universe's path: playback carries on along it.
  final box = item.pathStop?.box, path = box == null ? '' : '?in=$box';
  if (!item.isSeries && !item.isCollection) {
    context.push('/play/${item.id}$path');
    return;
  }
  try {
    final target = await _target(context, item);
    _targets.remove(item.id);
    if (target != null && context.mounted) context.push('/play/${target.id}$path');
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}

/// What "Play" starts: a movie itself; for a show a half-watched episode first, then the
/// next unwatched one, then the very first.
Future<Item?> playTarget(JellyfinClient c, Item item, {bool story = false}) async {
  if (item.miniStop case final m?) return m.nextPart;
  // A franchise: the first stop in order not watched yet (a half-watched one counts); a
  // season or cut of a show starts on its first episode still to watch, a whole show below.
  if (item.isCollection) {
    final films = await c.collectionItems(item.id, story: story, name: item.name);
    final stops = await c.universeStops(item, films, story: story);
    final stop = stops.where((s) => !s.played).firstOrNull ?? stops.firstOrNull;
    if (stop == null) return null;
    if (stop.isPart) return stop.nextPart;
    return stop.item.isSeries ? playTarget(c, stop.item) : stop.item;
  }
  if (!item.isSeries) return item;
  var target = (await c.resume(limit: 50)).where((e) => e.seriesId == item.id).firstOrNull;
  target ??= (await c.nextUp(seriesId: item.id, limit: 1)).firstOrNull;
  target ??= (await c.episodes(item.id)).where((e) => (e.parentIndexNumber ?? 0) > 0).firstOrNull;
  return target;
}

/// Netflix mobile's billboard: a rounded poster card floating on a blurred glow of itself.
class _MobileBillboard extends StatelessWidget {
  final Item item;
  const _MobileBillboard(this.item);

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final width = MediaQuery.sizeOf(context).width;
    final posterArt = c.poster(item, width: 900);
    final poster = posterArt ?? c.backdrop(item);
    // Posters already carry the title, so only bare backdrops get the logo.
    final logo = posterArt == null ? c.logo(item) : null;
    final cardW = width - 40;
    final cardH = (cardW * 1.32).clamp(300.0, (MediaQuery.sizeOf(context).height * .62).clamp(300.0, double.infinity));
    final inList = context.select<AppState, bool>((a) => a.myList.contains(item.id));

    return Stack(
      children: [
        Positioned.fill(
          child: ShaderMask(
            shaderCallback: (r) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white, Colors.white, Colors.transparent],
              stops: [0, .55, 1],
            ).createShader(r),
            blendMode: BlendMode.dstIn,
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60, tileMode: TileMode.decal),
              child: Opacity(opacity: .7, child: NetImage(poster)),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, topInset(context) + 6, 20, 26),
          child: FadeIn(
            from: const Offset(0, .04),
            child: HoverScale(
              scale: 1,
              onTap: () => openItem(context, item),
              child: Container(
                height: cardH,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: .14)),
                  boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 40, offset: Offset(0, 18))],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetImage(poster, fallbackText: item.displayTitle, alignment: Alignment.topCenter),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            stops: [.45, 1],
                            colors: [Colors.transparent, Color(0xF2000000)],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 16,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (logo != null)
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 84, maxWidth: 250),
                                child: Image.network(logo, errorBuilder: (_, _, _) => _Title(item.displayTitle, true)),
                              )
                            else if (posterArt == null)
                              _Title(item.displayTitle, true),
                            const SizedBox(height: 10),
                            Text(
                              item.genres.take(3).join('  •  '),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => playItem(context, item),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white,
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    icon: const Icon(Icons.play_arrow_rounded, size: 28),
                                    label: const Text('Play'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => context.read<AppState>().toggleMyList(item.id).catchError((_) {}),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: Colors.white.withValues(alpha: .22),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    icon: AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 250),
                                      transitionBuilder: (c, a) => RotationTransition(
                                        turns: Tween(begin: .75, end: 1.0).animate(a),
                                        child: FadeTransition(opacity: a, child: c),
                                      ),
                                      child: Icon(inList ? Icons.check_rounded : Icons.add_rounded, key: ValueKey(inList)),
                                    ),
                                    label: const Text('My List'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
