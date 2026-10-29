import 'dart:async';
import 'dart:math' show max, min;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../host.dart';
import '../../api/seerr.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../theme.dart';
import 'billboard.dart' show prewarmPlay;
import 'spotlight.dart';

JellyfinClient jf(BuildContext context) => context.read<AppState>().client!;

/// Network image that fades in and falls back to a warm gradient with the title.
class NetImage extends StatelessWidget {
  final String? url;
  final BoxFit fit;
  final String? fallbackText;
  final Alignment alignment;
  const NetImage(this.url, {super.key, this.fit = BoxFit.cover, this.fallbackText, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      decoration: BoxDecoration(gradient: fallbackText == null ? null : Hy.gradientFor(fallbackText!), color: Hy.surfaceHigh),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(10),
      child: fallbackText == null
          ? null
          : Text(
              fallbackText!,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
    );
    if (url == null || url!.isEmpty) return fallback;
    return Image.network(
      url!,
      fit: fit,
      alignment: alignment,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (_, child, frame, sync) {
        if (sync) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: frame == null ? ColoredBox(color: Hy.surface, child: child) : child,
        );
      },
    );
  }
}

/// Grows a little under the mouse and sinks a little under a finger, like Netflix's tiles.
/// It can also be reached with the arrow keys (TV remote, keyboard): the focused tile
/// grows and gets an orange outline, and OK/Enter opens it.
class HoverScale extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final bool autofocus;

  /// Corner radius of the focus outline (use a large one for round things).
  final double radius;
  final FocusNode? focusNode;

  /// Told when the remote lands on it or leaves (TV Home's spotlight follows it).
  final ValueChanged<bool>? onFocus;
  const HoverScale({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 1.06,
    this.autofocus = false,
    this.radius = Hy.radius,
    this.focusNode,
    this.onFocus,
  });
  @override
  State<HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<HoverScale> {
  bool _hover = false;
  bool _down = false;
  bool _focus = false;
  Timer? _hold;
  bool _held = false;

  /// OK went down here (not on the page before: its release lands here after Back or OK
  /// opened this page, and must not play the first poster).
  bool _pressed = false;

  static final _ok = {LogicalKeyboardKey.select, LogicalKeyboardKey.enter, LogicalKeyboardKey.numpadEnter, LogicalKeyboardKey.gameButtonA};

  /// TV: OK opens on release, and held down it gives the long-press menu instead.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (!_ok.contains(e.logicalKey)) return KeyEventResult.ignored;
    if (e is KeyDownEvent) {
      _pressed = true;
      _held = false;
      _hold?.cancel();
      setState(() => _down = true);
      _hold = Timer(const Duration(milliseconds: 550), () {
        _held = true;
        if (mounted) setState(() => _down = false);
        widget.onLongPress?.call();
      });
    } else if (e is KeyUpEvent) {
      _hold?.cancel();
      if (mounted) setState(() => _down = false);
      if (_pressed && !_held) widget.onTap?.call();
      _pressed = false;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final grow = _focus ? (Device.isTv ? 1.1 : (widget.scale > 1.08 ? widget.scale : 1.08)) : (_hover ? widget.scale : 1.0);
    final detector = _detector(grow);
    if (!Device.isTv || widget.onLongPress == null || widget.onTap == null) return detector;
    return Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onKey, child: detector);
  }

  Widget _detector(double grow) {
    return FocusableActionDetector(
      enabled: widget.onTap != null,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      onFocusChange: widget.onFocus,
      actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap?.call())},
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? .95 : grow,
          duration: Duration(milliseconds: _down ? 90 : 220),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              // TV: a bold white frame you can see from the sofa; elsewhere orange.
              border: Border.all(color: _focus ? (Device.isTv ? Colors.white : Hy.orange) : Colors.transparent, width: Device.isTv ? 4 : 3),
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              // Blurred shadows are expensive on TV chips: the outline alone marks focus there.
              boxShadow: _focus && !Device.isTv ? const [BoxShadow(color: Color(0x40FF7A1A), blurRadius: 18)] : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Fades and slides its child in once, after [delay]: used to stagger rows and sections.
class FadeIn extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Offset from;
  const FadeIn({super.key, required this.child, this.delay = Duration.zero, this.from = const Offset(0, .06)});
  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
  late final _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () => mounted ? _c.forward() : null);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: SlideTransition(
      position: Tween(begin: widget.from, end: Offset.zero).animate(_a),
      child: widget.child,
    ),
  );
}

/// A softly pulsing placeholder block shown while something loads.
class Skeleton extends StatefulWidget {
  final double? width, height;
  final double radius;
  const Skeleton({super.key, this.width, this.height, this.radius = Hy.radius});
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(widget.radius),
        gradient: LinearGradient(
          begin: Alignment(-1 + 3 * _c.value - 1, -.3),
          end: Alignment(1 + 3 * _c.value - 1, .3),
          colors: const [Hy.surface, Hy.surfaceHigh, Hy.surface],
          stops: const [.3, .5, .7],
        ),
      ),
    ),
  );
}

void openItem(BuildContext context, Item i) => context.push('/item/${i.id}');
void openSeerr(BuildContext context, SeerrMedia m) {
  if (m.status == MediaStatus.available && m.jellyfinId != null) {
    context.push('/item/${m.jellyfinId}');
  } else {
    context.push('/request/${m.mediaType}/${m.tmdbId}');
  }
}

/// Portrait poster tile.
class PosterCard extends StatelessWidget {
  final Item item;
  final double width;

  /// Where a tap goes, if not the title's own page (a universe's stop: its page on the path).
  final String? route;
  const PosterCard(this.item, {super.key, this.width = 150, this.route});

  @override
  Widget build(BuildContext context) {
    final inList = context.select<AppState, bool>((a) => a.myList.contains(item.id));
    return SizedBox(
      width: width,
      child: HoverScale(
        onTap: () => route != null ? context.push(route!) : openItem(context, item),
        onLongPress: () => showItemMenu(context, item),
        onFocus: (v) => v ? Spotlight.show(context, item) : null,
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Hy.radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(jf(context).poster(item, width: (width * 2).round()), fallbackText: item.displayTitle),
                if (item.played) const Positioned(top: 6, right: 6, child: _CornerBadge(icon: Icons.check_rounded)),
                if (!item.played && (item.unplayedCount ?? 0) > 0 && item.isSeries)
                  Positioned(top: 6, right: 6, child: _CornerBadge(text: '${item.unplayedCount}')),
                if (inList) const Positioned(top: 6, left: 6, child: _CornerBadge(icon: Icons.bookmark_rounded, orange: true)),
                if (item.progress != null) Positioned(left: 0, right: 0, bottom: 0, child: ProgressStrip(item.progress!)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CornerBadge extends StatelessWidget {
  final IconData? icon;
  final String? text;
  final bool orange;
  const _CornerBadge({this.icon, this.text, this.orange = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: text == null ? 3 : 7, vertical: 3),
    decoration: BoxDecoration(color: orange ? Hy.orange : Colors.black.withValues(alpha: .75), borderRadius: BorderRadius.circular(20)),
    child: text != null
        ? Text(text!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))
        : Icon(icon, size: 15, color: orange ? Colors.black : Hy.orange),
  );
}

class ProgressStrip extends StatelessWidget {
  final double value;
  final double height;
  const ProgressStrip(this.value, {super.key, this.height = 4});
  @override
  Widget build(BuildContext context) => Container(
    height: height,
    color: Colors.white.withValues(alpha: .25),
    alignment: Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: value,
      child: Container(color: Hy.orange),
    ),
  );
}

/// 16:9 tile with title underneath: continue watching, next up, episodes.
class LandscapeCard extends StatelessWidget {
  final Item item;
  final double width;
  final VoidCallback? onTap;
  const LandscapeCard(this.item, {super.key, this.width = 280, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final sub = item.isEpisode ? '${item.episodeCode}  ${item.name}' : (item.year?.toString() ?? '');
    return SizedBox(
      width: width,
      child: HoverScale(
        scale: 1.04,
        onTap: onTap ?? () => context.push('/play/${item.id}'),
        onLongPress: () => showItemMenu(context, item),
        onFocus: (v) {
          if (!v) return;
          Spotlight.show(context, item);
          // Continue watching plays straight away: get it ready.
          if (Device.isTv && onTap == null) prewarmPlay(context, item);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Hy.radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(c.thumb(item, width: (width * 2).round()), fallbackText: item.displayTitle),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(begin: Alignment.center, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0x99000000)]),
                      ),
                    ),
                    Center(
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: .45),
                          border: Border.all(color: Colors.white70, width: 1.5),
                        ),
                        padding: const EdgeInsets.all(8),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
                      ),
                    ),
                    if (item.progress != null) Positioned(left: 0, right: 0, bottom: 0, child: ProgressStrip(item.progress!)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.displayTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            if (sub.isNotEmpty)
              Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Hy.textDim, fontSize: 12.5),
              ),
          ],
        ),
      ),
    );
  }
}

/// Netflix's "Top 10": a huge outlined rank next to the poster.
class Top10Card extends StatelessWidget {
  final int rank;
  final Item item;
  const Top10Card(this.rank, this.item, {super.key});

  @override
  Widget build(BuildContext context) {
    const h = 210.0;
    return SizedBox(
      width: rank == 10 ? 260 : 220,
      height: h,
      child: HoverScale(
        scale: 1.04,
        onTap: () => openItem(context, item),
        onLongPress: () => showItemMenu(context, item),
        onFocus: (v) => v ? Spotlight.show(context, item) : null,
        child: Stack(
          children: [
            Positioned(
              left: 0,
              bottom: -28,
              child: Stack(
                children: [
                  Text(
                    '$rank',
                    style: TextStyle(
                      fontSize: 200,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: -18,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 4
                        ..color = Hy.orange,
                    ),
                  ),
                  Text(
                    '$rank',
                    style: const TextStyle(fontSize: 200, fontWeight: FontWeight.w900, height: 1, letterSpacing: -18, color: Hy.bg),
                  ),
                ],
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Hy.radius),
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: NetImage(jf(context).poster(item), fallbackText: item.displayTitle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A TMDB poster from Seerr, with its library/request status.
class SeerrCard extends StatelessWidget {
  final SeerrMedia media;
  final double width;
  const SeerrCard(this.media, {super.key, this.width = 150});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: HoverScale(
      onTap: () => openSeerr(context, media),
      onFocus: (v) => v ? Spotlight.showSeerr(context, media) : null,
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Hy.radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(media.posterPath == null ? null : SeerrClient.image(media.posterPath), fallbackText: media.title),
              Positioned(top: 6, left: 6, child: _TypeTag(media.isTv ? 'SERIES' : 'FILM')),
              if (media.status != MediaStatus.unknown)
                Positioned(top: 6, right: 6, child: StatusPill(media.status, progress: media.downloadProgress, compact: true)),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TypeTag extends StatelessWidget {
  final String text;
  const _TypeTag(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .7), borderRadius: BorderRadius.circular(3)),
    child: Text(text, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 1)),
  );
}

class StatusPill extends StatelessWidget {
  final MediaStatus status;
  final double? progress;
  final bool compact;
  const StatusPill(this.status, {super.key, this.progress, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      MediaStatus.available => (const Color(0xFF2ECC71), Icons.check_circle_rounded),
      MediaStatus.partial => (const Color(0xFF2ECC71), Icons.remove_circle_rounded),
      MediaStatus.processing => (Hy.orange, Icons.downloading_rounded),
      _ => (const Color(0xFFB98CFF), Icons.schedule_rounded),
    };
    final pct = progress != null && status != MediaStatus.available ? '${(progress! * 100).round()}%' : null;
    final label = pct == null ? status.label : (compact ? pct : 'Downloading $pct');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 10, vertical: compact ? 3 : 5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 13 : 16, color: color),
          if (!compact || progress != null) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(fontSize: compact ? 10.5 : 12.5, fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ],
      ),
    );
  }
}

/// Horizontal row with a heading; arrow buttons appear on hover (desktop).
class MediaRow extends StatefulWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final double height;
  final VoidCallback? onMore;
  const MediaRow({super.key, required this.title, this.subtitle, required this.children, required this.height, this.onMore});

  @override
  State<MediaRow> createState() => _MediaRowState();
}

class _MediaRowState extends State<MediaRow> {
  final _scroll = ScrollController();
  bool _hover = false;

  // TV remote: one focus slot per tile, the tile the row is on, and whether the
  // remote is inside this row at all (to restore the position when coming back).
  List<FocusNode> _slots = const [];
  int _index = 0;
  bool _inside = false;

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in _slots) {
      n.dispose();
    }
    super.dispose();
  }

  /// On TV "See all" is the last tile of the row (a header link would be an extra stop
  /// between rows for the remote).
  List<Widget> get _tiles => [...widget.children, if (Device.isTv && widget.onMore != null) _SeeAllTile(height: widget.height - 12, onTap: widget.onMore!)];

  void _syncSlots() {
    if (_slots.length == _tiles.length) return;
    for (final n in _slots) {
      n.dispose();
    }
    _slots = [for (var i = 0; i < _tiles.length; i++) FocusNode(debugLabel: 'tile $i', canRequestFocus: false, skipTraversal: true)];
    _index = _index.clamp(0, (_slots.length - 1).clamp(0, 1 << 20));
  }

  /// Puts the remote on tile [i]; false if that tile isn't built yet.
  bool _focusTile(int i) {
    final node = _slots[i].descendants.where((d) => d.canRequestFocus && !d.skipTraversal).firstOrNull;
    node?.requestFocus();
    return node != null;
  }

  void _onTileFocus(int i, bool has) {
    if (!has) return;
    if (!_inside) {
      _inside = true;
      // Coming back into the row: return to where it was, like Netflix.
      if (i != _index && i < _slots.length && _slots[_index].descendants.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusTile(_index));
        return;
      }
      // Bring the row up to the upper part of the screen (TV Home: under the spotlight).
      final at = context.getInheritedWidgetOfExactType<TvRowAnchor>()?.at;
      Scrollable.ensureVisible(context, alignment: at == null ? .3 : at - .07, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
    }
    _index = i;
    final ctx = _slots[i].context;
    // TV: the selected tile sits at the page margin, like Google TV, so nothing is left
    // half-visible at the row's left edge.
    if (Device.isTv && ctx != null && _scroll.hasClients) {
      final tile = ctx.findRenderObject() as RenderBox?, row = context.findRenderObject() as RenderBox?;
      if (tile != null && row != null && tile.attached && row.attached) {
        final dx = tile.localToGlobal(Offset.zero, ancestor: row).dx;
        final target = (_scroll.offset + dx - pagePadding(context)).clamp(0.0, _scroll.position.maxScrollExtent);
        if ((target - _scroll.offset).abs() > 1) _scroll.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
        return;
      }
    }
    if (ctx != null) {
      // Keep the tile in the row's view with a little of the neighbour showing.
      Scrollable.ensureVisible(
        ctx,
        alignment: i == 0 ? 0 : .08,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
      );
    }
  }

  /// Left/Right move tile by tile inside the row and stop at its ends.
  KeyEventResult _onRowKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final dir = k == LogicalKeyboardKey.arrowRight ? 1 : (k == LogicalKeyboardKey.arrowLeft ? -1 : 0);
    if (dir == 0) return KeyEventResult.ignored;
    final next = _index + dir;
    if (next < 0) return KeyEventResult.ignored; // the menu is to the left
    if (next >= _slots.length) return KeyEventResult.handled; // end of the row
    if (!_focusTile(next) && _scroll.hasClients) {
      // Not built yet: scroll it in, then focus it.
      final w = _slots[_index].context?.size?.width ?? 200;
      _scroll.jumpTo((_scroll.offset + dir * (w + 10)).clamp(0, _scroll.position.maxScrollExtent));
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusTile(next));
    }
    return KeyEventResult.handled;
  }

  /// TV: tile [i] starts left of the page margin (scrolled past).
  bool _hidden(int i, double pad) {
    final row = context.findRenderObject() as RenderBox?;
    final box = _slots[i].context?.findRenderObject() as RenderBox?;
    if (row == null || box == null || !row.attached || !box.attached || !box.hasSize) return false;
    return box.localToGlobal(Offset.zero, ancestor: row).dx < pad - 12;
  }

  void _page(int dir) {
    final w = context.size?.width ?? 800;
    _scroll.animateTo(
      (_scroll.offset + dir * (w - 160)).clamp(0, _scroll.position.maxScrollExtent),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.children.isEmpty) return const SizedBox.shrink();
    final pad = pagePadding(context);
    if (Device.isTv) _syncSlots();
    final row = _row(pad);
    if (!Device.isTv) return row;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onRowKey,
      onFocusChange: (has) {
        if (!has) _inside = false;
      },
      child: row,
    );
  }

  Widget _row(double pad) {
    final tiles = _tiles;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        if (widget.subtitle != null)
                          TextSpan(
                            text: '${widget.subtitle} ',
                            style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w600),
                          ),
                        TextSpan(text: widget.title),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                if (widget.onMore != null && !Device.isTv)
                  TextButton(
                    onPressed: widget.onMore,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'See all',
                          style: TextStyle(color: Hy.orange, fontWeight: FontWeight.w700),
                        ),
                        Icon(Icons.chevron_right_rounded, color: Hy.orange),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: SizedBox(
              height: widget.height,
              // TV: tiles scrolled past disappear a little before the menu instead of running
              // into it (which looks like more tiles hiding behind it). Top and bottom stay
              // open so a focused tile can still grow.
              child: ClipRect(
                clipBehavior: Clip.none,
                child: Stack(
                  children: [
                    ListView.separated(
                      controller: _scroll,
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 6),
                      itemCount: tiles.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      // Each tile paints on its own: a focused tile growing doesn't repaint the row.
                      itemBuilder: (_, i) => Device.isTv && i < _slots.length
                          ? Focus(
                              focusNode: _slots[i],
                              onFocusChange: (has) => _onTileFocus(i, has),
                              // Tiles scrolled (even partly) past the page margin are hidden, so
                              // nothing looks tucked away behind the side menu.
                              child: AnimatedBuilder(
                                animation: _scroll,
                                builder: (_, child) => Opacity(opacity: _hidden(i, pad) ? 0 : 1, child: child),
                                child: RepaintBoundary(child: tiles[i]),
                              ),
                            )
                          : RepaintBoundary(child: tiles[i]),
                    ),
                    if (isDesktop(context)) ...[
                      _Arrow(left: true, visible: _hover, pad: pad, onTap: () => _page(-1), scroll: _scroll),
                      _Arrow(left: false, visible: _hover, pad: pad, onTap: () => _page(1), scroll: _scroll),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  final bool left, visible;
  final double pad;
  final VoidCallback onTap;
  final ScrollController scroll;
  const _Arrow({required this.left, required this.visible, required this.pad, required this.onTap, required this.scroll});

  @override
  Widget build(BuildContext context) => Positioned(
    left: left ? 0 : null,
    right: left ? null : 0,
    top: 0,
    bottom: 0,
    width: pad.clamp(36, 56),
    child: ListenableBuilder(
      listenable: scroll,
      builder: (_, _) {
        final has = scroll.hasClients && scroll.position.hasContentDimensions;
        final show = visible && has && (left ? scroll.offset > 4 : scroll.offset < scroll.position.maxScrollExtent - 4);
        return IgnorePointer(
          ignoring: !show,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: Material(
              color: Colors.black.withValues(alpha: .6),
              child: InkWell(
                onTap: onTap,
                child: Icon(left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, size: 40, color: Colors.white),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// TV: when the remote was last pressed and when the shell last opened a page.
abstract final class TvRemote {
  static DateTime lastKey = DateTime(0), pageOpened = DateTime(0);
  static bool _listening = false;

  static void listen() {
    if (_listening) return;
    _listening = true;
    HardwareKeyboard.instance.addHandler((e) {
      if (e is KeyDownEvent) lastKey = DateTime.now();
      return false;
    });
  }

  /// No key since the page opened (the press that opened it comes just before).
  static bool get untouchedSincePageOpened => !lastKey.isAfter(pageOpened);
}

/// Mouse-and-keyboard layout (hover arrows and so on); never in TV mode, which a desktop can run too.
/// The web version is for computers, whatever system the browser is on.
bool isDesktop(BuildContext context) =>
    !Device.isTv && (Host.isWeb || Theme.of(context).platform == TargetPlatform.linux || Theme.of(context).platform == TargetPlatform.windows);
bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 720;
double pagePadding(BuildContext context) => isNarrow(context) ? 16 : (Device.isTv ? 64 : 48);

double posterWidth(BuildContext context) => isNarrow(context) ? 112 : 160;

/// Outlined age rating, like "PG-13".
class OutlineTag extends StatelessWidget {
  final String text;
  const OutlineTag(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      border: Border.all(color: Hy.textDim),
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      text,
      style: const TextStyle(color: Hy.textDim, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

String formatRuntime(Duration? d) {
  if (d == null || d.inMinutes == 0) return '';
  final h = d.inHours, m = d.inMinutes % 60;
  return h > 0 ? '${h}h ${m}m' : '${m}m';
}

/// Netflix-style "97% match" from the community rating.
String? matchText(Item i) {
  final r = i.communityRating;
  if (r == null || r <= 0) return null;
  return '${(r * 10).round().clamp(1, 99)}% match';
}

/// Meta line: match, year, rating, runtime/seasons, quality.
class MetaLine extends StatelessWidget {
  final Item item;
  const MetaLine(this.item, {super.key});
  @override
  Widget build(BuildContext context) {
    final match = matchText(item);
    final mini = item.miniStop;
    final runtime = mini != null
        ? '${mini.parts.length} Episode${mini.parts.length == 1 ? '' : 's'} · ${formatRuntime(mini.runtime)}'
        : item.isSeries
        ? (item.childCount == null ? '' : '${item.childCount} Season${item.childCount == 1 ? '' : 's'}')
        : formatRuntime(item.runtime);
    return Wrap(
      spacing: 10,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (match != null)
          Text(
            match,
            style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w800),
          ),
        if (item.year != null)
          Text(
            '${item.year}',
            style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w600),
          ),
        if (item.officialRating != null) OutlineTag(item.officialRating!),
        if (runtime.isNotEmpty)
          Text(
            runtime,
            style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w600),
          ),
        if (item.quality != null) OutlineTag(item.quality!),
        if (ends != null)
          Text(
            'Ends at $ends',
            style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w600),
          ),
      ],
    );
  }

  /// When it would end if started now (from where it was left, if it was).
  String? get ends {
    final r = item.runtime;
    if (r == null || item.isSeries || item.isCollection || item.played) return null;
    final left = item.resumePosition > Duration.zero && item.resumePosition < r ? r - item.resumePosition : r;
    return clockTime(DateTime.now().add(left));
  }
}

/// 22:41
String clockTime(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// Loads once, shows a spinner, then the result (or a retry on error).
class Loader<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  final Object? reloadKey;
  final Widget? loading;

  /// Set when used directly inside a CustomScrollView, so the spinner and error get wrapped.
  final bool sliver;
  const Loader({super.key, required this.load, required this.builder, this.reloadKey, this.loading, this.sliver = false});
  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  late Future<T> _future = widget.load();

  @override
  void didUpdateWidget(covariant Loader<T> old) {
    super.didUpdateWidget(old);
    if (old.reloadKey != widget.reloadKey) _future = widget.load();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<T>(
    future: _future,
    builder: (context, snap) {
      Widget box(Widget w) => widget.sliver ? SliverToBoxAdapter(child: w) : w;
      if (snap.hasError) {
        return box(ErrorView('${snap.error}', onRetry: () => setState(() => _future = widget.load())));
      }
      if (snap.connectionState != ConnectionState.done) {
        return box(
          widget.loading ??
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: CircularProgressIndicator(color: Hy.orange),
                ),
              ),
        );
      }
      return widget.builder(context, snap.data as T);
    },
  );
}

class ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  const ErrorView(this.message, {super.key, this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: Hy.textMute),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Hy.textDim),
          ),
          if (onRetry != null) ...[const SizedBox(height: 16), OutlinedButton(onPressed: onRetry, child: const Text('Try again'))],
        ],
      ),
    ),
  );
}

void toast(BuildContext context, String msg) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));

/// Grid of posters that adapts to the width.
class PosterGrid extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets? padding;
  const PosterGrid({super.key, required this.children, this.padding});
  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return SliverPadding(
      padding: padding ?? EdgeInsets.fromLTRB(pad, 8, pad, 40),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: posterWidth(context) + 20,
          childAspectRatio: 2 / 3,
          mainAxisSpacing: 14,
          crossAxisSpacing: 10,
        ),
        delegate: SliverChildListDelegate(children),
      ),
    );
  }
}

/// Netflix's full-screen picker (seasons, speeds…): a blurred overlay with a centred list.
Future<int?> showBlurPicker(BuildContext context, List<String> labels, {int? selected}) => showGeneralDialog<int>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close',
  barrierColor: Colors.transparent,
  transitionDuration: const Duration(milliseconds: 260),
  transitionBuilder: (_, a, _, child) => FadeTransition(
    opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
    child: child,
  ),
  pageBuilder: (ctx, _, _) => BackdropFilter(
    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
    // No blur on TV: too heavy for TV chips; the dark tint is enough.
    enabled: !Device.isTv,
    child: Material(
      color: Colors.black.withValues(alpha: Device.isTv ? .88 : .72),
      child: SafeArea(
        child: Stack(
          children: [
            Center(
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.fromLTRB(24, 40, 24, MediaQuery.sizeOf(ctx).height < 500 ? 40 : 120),
                itemCount: labels.length,
                itemBuilder: (ctx, i) => FadeIn(
                  delay: Duration(milliseconds: 18 * i.clamp(0, 20)),
                  from: const Offset(0, .3),
                  child: InkWell(
                    onTap: () => Navigator.pop(ctx, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      child: Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: i == selected ? 22 : 19,
                          fontWeight: i == selected ? FontWeight.w800 : FontWeight.w500,
                          color: i == selected ? Colors.white : Hy.textDim,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Bottom centre like Netflix; top right in landscape so it doesn't cover the list.
            Positioned(
              left: MediaQuery.sizeOf(ctx).height < 500 ? null : 0,
              right: MediaQuery.sizeOf(ctx).height < 500 ? 24 : 0,
              top: MediaQuery.sizeOf(ctx).height < 500 ? 16 : null,
              bottom: MediaQuery.sizeOf(ctx).height < 500 ? null : 28,
              child: Center(
                child: Material(
                  color: Colors.white,
                  shape: const CircleBorder(),
                  child: IconButton(
                    iconSize: 30,
                    padding: const EdgeInsets.all(14),
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: Colors.black),
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

/// When the remote moves onto something inside [child] (the banner's buttons), scroll the
/// page all the way to the top so the whole banner shows again, like Netflix.
class ScrollTopOnFocus extends StatelessWidget {
  final Widget child;
  const ScrollTopOnFocus({super.key, required this.child});
  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (has) {
      if (!has) return;
      // After the focus system's own "scroll into view" has run.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pos = Scrollable.maybeOf(context)?.position;
        if (pos != null && pos.pixels > 0) pos.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
      });
    },
    child: child,
  );
}

/// The end-of-row "See all" on TV.
class _SeeAllTile extends StatelessWidget {
  final double height;
  final VoidCallback onTap;
  const _SeeAllTile({required this.height, required this.onTap});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: height * .62,
    height: height,
    child: HoverScale(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Hy.surfaceHigh,
          borderRadius: BorderRadius.circular(Hy.radius),
          border: Border.all(color: Hy.border),
        ),
        alignment: Alignment.center,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_forward_rounded, color: Hy.orange, size: 36),
            SizedBox(height: 10),
            Text('See all', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ],
        ),
      ),
    ),
  );
}

/// TV: up/down on a long page of mixed sections (rows, grids, text) moves to the nearest line
/// of focusable things above or below, wherever it is on the page, and brings it to the upper
/// middle of the screen. Left/right stay with the rows. Give the page a [ScrollController] from
/// [builder]; elsewhere this is just the page.
class TvPageNav extends StatefulWidget {
  final Widget Function(ScrollController controller) builder;
  const TvPageNav({super.key, required this.builder});
  @override
  State<TvPageNav> createState() => _TvPageNavState();
}

class _TvPageNavState extends State<TvPageNav> {
  final _scroll = ScrollController();
  final _node = FocusNode(canRequestFocus: false, skipTraversal: true);

  @override
  void dispose() {
    _scroll.dispose();
    _node.dispose();
    super.dispose();
  }

  Rect? _rect(FocusNode n, RenderBox page) {
    final box = n.context?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: page) & box.size;
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final down = e.logicalKey == LogicalKeyboardKey.arrowDown;
    if (!down && e.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    final page = context.findRenderObject() as RenderBox?, cur = FocusManager.instance.primaryFocus;
    final at = page == null || cur == null ? null : _rect(cur, page);
    if (at == null) return KeyEventResult.ignored;
    final width = page!.size.width;
    // Everything focusable on the page that lies wholly above or below the focused thing.
    final lines = <(FocusNode, Rect)>[];
    for (final n in _node.traversalDescendants) {
      if (identical(n, cur) || n.ancestors.contains(cur) || cur!.ancestors.contains(n)) continue;
      final r = _rect(n, page);
      if (r == null || r.right < 0 || r.left > width) continue; // scrolled away in a row
      if (down ? r.top >= at.center.dy : r.bottom <= at.center.dy) lines.add((n, r));
    }
    if (lines.isEmpty) {
      if (!down || !_scroll.hasClients) return KeyEventResult.ignored; // the top: up goes nowhere
      // Nothing more to land on: show the rest of the page.
      final p = _scroll.position;
      _scroll.animateTo(
        (p.pixels + p.viewportDimension * .6).clamp(0, p.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
      return KeyEventResult.handled;
    }
    // The nearest line, then the thing in it closest to straight above or below.
    final edge = down ? lines.map((l) => l.$2.top).reduce(min) : lines.map((l) => l.$2.bottom).reduce(max);
    // From something page-wide (text, a banner), a row is entered at its start.
    final x = at.width > width * .6 ? 0.0 : at.center.dx;
    final line = lines.where((l) => down ? l.$2.top < edge + 40 : l.$2.bottom > edge - 40).toList()
      ..sort((a, b) => (a.$2.center.dx - x).abs().compareTo((b.$2.center.dx - x).abs()));
    final (next, r) = line.first;
    next.requestFocus();
    if (_scroll.hasClients) {
      final p = _scroll.position;
      // Its top a third of the way down, or as much of a tall one as fits.
      final target = (p.pixels + r.top - p.viewportDimension * (r.height > p.viewportDimension * .6 ? .08 : .3)).clamp(0.0, p.maxScrollExtent);
      _scroll.animateTo(target, duration: const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => Device.isTv ? Focus(focusNode: _node, onKeyEvent: _onKey, child: widget.builder(_scroll)) : widget.builder(_scroll);
}

/// TV: a section with nothing to press (text, a quote) still gets a stop when moving down
/// the page, so it scrolls into view to be read. A soft frame shows where you are.
class TvReadStop extends StatefulWidget {
  final Widget child;
  const TvReadStop({super.key, required this.child});
  @override
  State<TvReadStop> createState() => _TvReadStopState();
}

class _TvReadStopState extends State<TvReadStop> {
  bool _on = false;
  @override
  Widget build(BuildContext context) {
    if (!Device.isTv) return widget.child;
    return Focus(
      onFocusChange: (v) => setState(() => _on = v),
      // The frame sits around the section, outside its own layout, so nothing moves.
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.passthrough,
        children: [
          Positioned(
            left: -16,
            right: -16,
            top: -12,
            bottom: -12,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: _on ? const Color(0x14FFFFFF) : Colors.transparent,
                border: Border.all(color: _on ? const Color(0x55FFFFFF) : Colors.transparent, width: 2),
              ),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

/// A rounded choice (a season, a page section): the current one filled orange, the one
/// under the remote or mouse lifts and turns white.
class Pill extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onFocus;
  final FocusNode? focusNode;
  const Pill({super.key, this.focusNode, required this.label, required this.selected, required this.onTap, this.onFocus});
  @override
  State<Pill> createState() => _PillState();
}

class _PillState extends State<Pill> {
  bool _focus = false, _hover = false;

  @override
  Widget build(BuildContext context) {
    final lit = _focus || _hover;
    final bg = lit ? Colors.white : (widget.selected ? Hy.orange : Hy.surfaceHigh);
    final fg = lit ? Colors.black : (widget.selected ? Colors.white : Hy.textDim);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      mouseCursor: SystemMouseCursors.click,
      onShowHoverHighlight: (v) => setState(() => _hover = v),
      onFocusChange: (v) {
        setState(() => _focus = v);
        if (v) {
          widget.onFocus?.call();
          // Only along its own line: scrolling the page from here made it jump between the
          // seasons and the episodes.
          final row = Scrollable.maybeOf(context);
          final box = context.findRenderObject();
          if (row != null && row.position.axis == Axis.horizontal && box != null) {
            row.position.ensureVisible(box, alignment: .5, duration: const Duration(milliseconds: 250));
          }
        }
      },
      actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap())},
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _focus ? 1.1 : 1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            padding: EdgeInsets.symmetric(horizontal: Device.isTv ? 22 : 18, vertical: Device.isTv ? 11 : 9),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(40),
              boxShadow: _focus ? const [BoxShadow(color: Color(0x66000000), blurRadius: 16, offset: Offset(0, 6))] : const [],
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: Device.isTv ? 17 : 14),
              child: Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where on screen the remote's line steps bring the selected row (a share of the page's
/// height from the top); TV Home puts rows lower, under the title spotlight.
class TvRowAnchor extends InheritedWidget {
  final double at;
  const TvRowAnchor({super.key, required this.at, required super.child});
  static double of(BuildContext context) => context.getInheritedWidgetOfExactType<TvRowAnchor>()?.at ?? .3;
  @override
  bool updateShouldNotify(TvRowAnchor old) => old.at != at;
}

/// The long-press menu for a title (holding OK on the remote, or a long tap).
Future<void> showItemMenu(BuildContext context, Item item) async {
  final app = context.read<AppState>();
  final c = jf(context);
  final router = GoRouter.of(context);
  final resume = item.resumePosition > const Duration(seconds: 30) && !item.played;
  final playable = item.isMovie || item.isEpisode;
  final inList = app.myList.contains(item.id);
  String fmt(Duration d) => d.inHours > 0 ? '${d.inHours} h ${d.inMinutes % 60} min' : '${d.inMinutes} min';
  final options = <(String, Future<void> Function())>[
    if (playable && resume) ('Resume from ${fmt(item.resumePosition)}', () async => router.push('/play/${item.id}')),
    if (playable) (resume ? 'Play from the start' : 'Play', () async => router.push('/play/${item.id}${resume ? '?t=1' : ''}')),
    if (!playable) ('Open', () async => openItem(context, item)),
    (inList ? 'Remove from My List' : 'Add to My List', () => app.toggleMyList(item.id)),
    if (!item.isCollection)
      (
        item.played ? 'Mark as not watched' : 'Mark as watched',
        () async {
          await c.setPlayed(item.id, !item.played);
          app.bump();
        },
      ),
    if (item.isEpisode && item.seriesId != null) ('Go to ${item.seriesName ?? 'the show'}', () async => router.push('/item/${item.seriesId}')),
    if (playable) ('More info', () async => router.push('/item/${item.isEpisode ? (item.seriesId ?? item.id) : item.id}')),
  ];
  final i = await showBlurPicker(context, [for (final o in options) o.$1]);
  if (i == null) return;
  try {
    await options[i].$2();
  } catch (e) {
    if (context.mounted) toast(context, "Couldn't do that: $e");
  }
}
