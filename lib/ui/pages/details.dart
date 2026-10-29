import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/jellyfin.dart';
import '../../api/seerr.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../theme.dart';
import '../widgets/billboard.dart';
import '../widgets/common.dart';
import '../widgets/together.dart';
import 'collection.dart';
import 'downloads.dart';
import 'live_player.dart';
import 'person.dart';
import '../../host.dart';

/// A movie or a show: art, actions, episodes, cast and more like this.
class DetailsPage extends StatelessWidget {
  final String id;

  /// Opened from this universe's path: a season it makes a mini series opens as one.
  final String? universe;
  const DetailsPage({super.key, required this.id, this.universe});

  @override
  Widget build(BuildContext context) {
    final rev = context.select<AppState, int>((a) => a.revision);
    return Loader<Item>(
      key: ValueKey('$id$rev'),
      load: () async {
        final i = await jf(context).item(id);
        if (universe != null && context.mounted) {
          final onPath = await jf(context).onPath(i, universe!);
          if (onPath != null) return onPath;
        }
        // An episode or season opens its show, on that season.
        if ((i.isEpisode || i.isSeason) && i.seriesId != null && context.mounted) {
          final show = await jf(context).item(i.seriesId!);
          show.raw['OpenSeasonId'] = i.isSeason ? i.id : i.seasonId;
          return show;
        }
        return i;
      },
      // A collection gets its own page; one with a custom design (HevyfinPage) gets that design.
      builder: (context, item) => switch ((item.isCollection, item.isCollection ? pageDesign(item) : null)) {
        (true, final page?) => UniverseView(item, page),
        (true, null) => CollectionView(item),
        _ => _Details(item),
      },
    );
  }
}

class _Details extends StatelessWidget {
  final Item item;
  const _Details(this.item);

  @override
  Widget build(BuildContext context) {
    if (isNarrow(context)) return _MobileDetails(item);
    final c = jf(context);
    final size = MediaQuery.sizeOf(context);
    final narrow = isNarrow(context);
    final pad = pagePadding(context);
    final logo = c.logo(item);
    final heroH = (narrow ? size.width * .62 + 60 : (size.width * .45).clamp(380.0, (size.height * .72).clamp(380.0, double.infinity))).floorToDouble();

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: heroH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(c.backdrop(item), alignment: Alignment.topCenter),
                if (!narrow)
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment(.2, 0), colors: [Color(0xE6000000), Colors.transparent]),
                    ),
                  ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .5, 1],
                      colors: [Colors.transparent, Hy.bg.withValues(alpha: .3), Hy.bg],
                    ),
                  ),
                ),
                Positioned(
                  left: pad,
                  right: pad,
                  bottom: 8,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        logo != null
                            ? ConstrainedBox(
                                constraints: BoxConstraints(maxHeight: narrow ? 80 : 140, maxWidth: narrow ? 240 : 440),
                                child: Image.network(logo, alignment: Alignment.bottomLeft, errorBuilder: (_, _, _) => _BigTitle(item.name)),
                              )
                            : _BigTitle(item.name),
                        _MiniLabel(item),
                      ],
                    ),
                  ),
                ),
                if (!narrow && item.miniStop?.season != null)
                  Positioned(right: pad, bottom: 8, child: _SeasonPoster(item, width: (heroH * .3).clamp(120.0, 230.0))),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 14, pad, 0),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Actions(item),
                const SizedBox(height: 22),
                narrow
                    ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_About(item), const SizedBox(height: 16), _Credits(item)])
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 3, child: _About(item)),
                          const SizedBox(width: 48),
                          Expanded(flex: 2, child: _Credits(item)),
                        ],
                      ),
                const SizedBox(height: 30),
                FadeIn(delay: const Duration(milliseconds: 120), child: _DetailTabs(item)),
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BigTitle extends StatelessWidget {
  final String text;
  const _BigTitle(this.text);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      fontSize: isNarrow(context) ? 32 : 52,
      fontWeight: FontWeight.w900,
      height: 1.02,
      letterSpacing: -1,
      shadows: const [Shadow(blurRadius: 16)],
    ),
  );
}

/// Under a mini series' title: which season (or cut) of its show it is.
class _MiniLabel extends StatelessWidget {
  final Item item;
  const _MiniLabel(this.item);
  @override
  Widget build(BuildContext context) {
    final m = item.miniStop;
    if (m == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        (m.title != m.item.name ? '${m.title} · ${m.code}' : m.code ?? '').toUpperCase(),
        style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w800, letterSpacing: 2.5, fontSize: 15),
      ),
    );
  }
}

/// Opened from a universe's path: what to remember from the stops before this one.
class _Previously extends StatelessWidget {
  final Item item;
  const _Previously(this.item);
  @override
  Widget build(BuildContext context) {
    final text = item.pathStop?.previously;
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      decoration: BoxDecoration(
        color: Hy.surfaceHigh,
        borderRadius: BorderRadius.circular(Hy.radius),
        border: const Border(left: BorderSide(color: Hy.orange, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PREVIOUSLY',
            style: TextStyle(color: Hy.orange, fontWeight: FontWeight.w800, letterSpacing: 2.2, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(color: Hy.textDim, fontSize: 14.5, height: 1.45)),
        ],
      ),
    );
  }
}

/// A mini series' own season poster, standing beside its title.
class _SeasonPoster extends StatelessWidget {
  final Item item;
  final double width;
  const _SeasonPoster(this.item, {required this.width});
  @override
  Widget build(BuildContext context) {
    final season = item.miniStop?.season;
    if (season == null) return const SizedBox.shrink();
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Hy.radius),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Hy.radius),
        child: AspectRatio(
          aspectRatio: 2 / 3,
          child: NetImage(jf(context).poster(season, width: (width * 2).round()), fallbackText: season.name),
        ),
      ),
    );
  }
}

/// Watched: a mini series is its own episodes, not the whole show.
bool _watched(Item item) => item.miniStop?.played ?? item.played;

Future<void> _setWatched(BuildContext context, Item item) async {
  final c = jf(context), on = !_watched(item);
  await Future.wait([for (final p in item.miniStop?.parts ?? [item]) c.setPlayed(p.id, on)]);
}

class _Actions extends StatelessWidget {
  final Item item;
  const _Actions(this.item);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final inList = app.myList.contains(item.id);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PlayButton(item, autofocus: Device.isTv),
        // A private showing with trailers, a countdown and an intermission.
        if (item.isMovie) _CinemaMode(item),
        _Trailer(
          item,
          builder: (onTap) => _RoundAction(icon: Icons.movie_filter_rounded, label: 'Trailer', onTap: onTap),
        ),
        _RoundAction(
          icon: inList ? Icons.check_rounded : Icons.add_rounded,
          label: 'My List',
          active: inList,
          onTap: () async {
            try {
              await app.toggleMyList(item.id);
            } catch (e) {
              if (context.mounted) toast(context, 'Could not update My List: $e');
            }
          },
        ),
        _RoundAction(
          icon: _watched(item) ? Icons.visibility_rounded : Icons.visibility_outlined,
          label: _watched(item) ? 'Watched' : 'Mark watched',
          active: _watched(item),
          onTap: () async {
            await _setWatched(context, item);
            app.bump();
          },
        ),
        if (!Device.isTv && !Host.isWeb && item.isMovie)
          _RoundAction(icon: Icons.download_rounded, label: 'Download', onTap: () => downloadItem(context, item)),
        if (!Device.isTv)
          _RoundAction(
            icon: Icons.cast_rounded,
            label: 'Play on…',
            onTap: () => showPlayOn(context, item: item),
          ),
        _RoundAction(
          icon: Icons.groups_rounded,
          label: 'Watch together',
          onTap: () => showWatchTogether(context, item: item),
        ),
        if (item.isSeries && item.miniStop == null && app.seerrReady && item.tmdbId != null) _MissingSeasons(item),
      ],
    );
  }
}

/// A Trailer button, shown once there's a trailer: the copy saved on the server plays in
/// Hevyfin (server/library-trailers.py); without one, YouTube opens.
class _Trailer extends StatefulWidget {
  final Item item;
  final Widget Function(VoidCallback onTap) builder;
  const _Trailer(this.item, {required this.builder});
  @override
  State<_Trailer> createState() => _TrailerState();
}

class _TrailerState extends State<_Trailer> {
  late final Future<String?> _local = jf(context).libraryTrailer(widget.item).catchError((_) => null);

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _local,
    builder: (context, snap) {
      final local = snap.data, remote = widget.item.remoteTrailer;
      if (snap.connectionState != ConnectionState.done || (local == null && remote == null)) return const SizedBox.shrink();
      return widget.builder(
        () => local != null
            ? context.push('/play/$local?trailer=1&name=${Uri.encodeQueryComponent(widget.item.name)}')
            : launchUrl(Uri.parse(remote!), mode: LaunchMode.externalApplication),
      );
    },
  );
}

class _RoundAction extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _RoundAction({required this.icon, required this.label, required this.onTap, this.active = false});
  @override
  State<_RoundAction> createState() => _RoundActionState();
}

class _RoundActionState extends State<_RoundAction> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final circle = InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) => setState(() => _focused = v),
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _focused && Device.isTv ? Colors.white : (active ? Hy.orange.withValues(alpha: .15) : Colors.black26),
          border: Border.all(color: _focused && Device.isTv ? Colors.white : (active ? Hy.orange : Colors.white60), width: 2),
        ),
        child: Icon(widget.icon, color: _focused && Device.isTv ? Colors.black : (active ? Hy.orange : Colors.white)),
      ),
    );
    // A remote can't hover for a tooltip: the selected button says what it does underneath.
    if (!Device.isTv) return Tooltip(message: widget.label, child: circle);
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        circle,
        Positioned(
          top: 54,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: _focused ? 1 : 0,
              duration: const Duration(milliseconds: 150),
              child: Text(
                widget.label,
                softWrap: false,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, shadows: [Shadow(blurRadius: 6)]),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "Request season 3" when Seerr knows about seasons the library is missing.
class _MissingSeasons extends StatelessWidget {
  final Item item;
  const _MissingSeasons(this.item);
  @override
  Widget build(BuildContext context) {
    final seerr = context.read<AppState>().seerr!;
    return FutureBuilder<SeerrMedia>(
      future: seerr.details('tv', item.tmdbId!),
      builder: (context, snap) {
        final m = snap.data;
        if (m == null) return const SizedBox.shrink();
        final status = m.seasonStatus;
        final missing = m.seasonNumbers.where((n) => (status[n] ?? MediaStatus.unknown).requestable && status[n] != MediaStatus.partial).toList();
        final pending = m.seasonNumbers.where((n) => status[n] == MediaStatus.pending || status[n] == MediaStatus.processing).toList();
        if (missing.isEmpty && pending.isEmpty) return const SizedBox.shrink();
        final label = missing.isEmpty
            ? 'Season${pending.length > 1 ? 's' : ''} ${pending.join(', ')} on the way'
            : 'Request season${missing.length > 1 ? 's' : ''} ${missing.length > 4 ? '${missing.first}–${missing.last}' : missing.join(', ')}';
        return OutlinedButton.icon(
          onPressed: () => context.push('/request/tv/${item.tmdbId}'),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Hy.orange),
            foregroundColor: Hy.orange,
          ),
          icon: Icon(missing.isEmpty ? Icons.downloading_rounded : Icons.add_to_queue_rounded),
          label: Text(label),
        );
      },
    );
  }
}

class _About extends StatelessWidget {
  final Item item;
  const _About(this.item);
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      MetaLine(item),
      const SizedBox(height: 10),
      Ratings(item),
      if (item.tagline != null) ...[
        const SizedBox(height: 14),
        Text(
          item.tagline!,
          style: const TextStyle(fontStyle: FontStyle.italic, color: Hy.textDim, fontSize: 15),
        ),
      ],
      _Previously(item),
      const SizedBox(height: 12),
      Text(item.overview ?? '', style: const TextStyle(fontSize: 16, height: 1.5)),
      if (!item.isCollection) PartOf(item),
    ],
  );
}

/// Who's in it and what kind of thing it is: text to read, not links (people open from
/// the Cast tab).
class _Credits extends StatelessWidget {
  final Item item;
  const _Credits(this.item);
  @override
  Widget build(BuildContext context) {
    final cast = item.people.where((p) => p.type == 'Actor').take(5).map((p) => p.name).toList();
    final directors = item.people.where((p) => p.type == 'Director').map((p) => p.name).toList();
    final creators = item.people.where((p) => p.type == 'Writer' || p.type == 'Creator').take(3).map((p) => p.name).toList();
    Widget line(String k, List<String> v) => v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$k: ',
                    style: const TextStyle(color: Hy.textMute),
                  ),
                  TextSpan(text: v.join(', ')),
                ],
              ),
            ),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line('Cast', cast),
        line('Genres', item.genres),
        line(item.isSeries ? 'Creators' : 'Director', item.isSeries ? creators : directors),
        if (item.status != null && item.isSeries) line('Status', [item.status == 'Continuing' ? 'Still airing' : 'Ended']),
      ],
    );
  }
}

class _Episodes extends StatefulWidget {
  final Item series;
  const _Episodes(this.series);
  @override
  State<_Episodes> createState() => _EpisodesState();
}

class _EpisodesState extends State<_Episodes> {
  List<Item>? _seasons;
  Item? _season;
  Future<List<Item>>? _episodes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // A mini series is just its own episodes: no other seasons to pick.
    if (widget.series.miniStop case final m?) {
      setState(() {
        _seasons = const [];
        _episodes = Future.value(m.parts);
      });
      return;
    }
    final c = jf(context);
    final seasons = await c.seasons(widget.series.id);
    if (!mounted || seasons.isEmpty) return;
    // Open on the season asked for (a universe's season or cut), else the one with the next
    // thing to watch.
    final open = seasons.where((s) => s.id == widget.series.raw['OpenSeasonId']).firstOrNull;
    final next = open != null ? null : (await c.nextUp(seriesId: widget.series.id, limit: 1)).firstOrNull;
    final regular = seasons.where((s) => (s.indexNumber ?? 0) > 0).toList();
    final start = open ?? seasons.where((s) => s.id == next?.seasonId).firstOrNull ?? regular.firstOrNull ?? seasons.first;
    setState(() {
      _seasons = seasons;
      _pick(start);
    });
  }

  /// From the episode row on into the next or previous season (TV).
  int _land = 0;
  bool _cross(int dir) {
    final seasons = _seasons;
    if (seasons == null || _season == null) return false;
    final i = seasons.indexOf(_season!) + dir;
    if (i < 0 || i >= seasons.length) return false;
    setState(() {
      _land = dir;
      _pick(seasons[i]);
    });
    return true;
  }

  void _pick(Item s) {
    _season = s;
    _episodes = jf(context).episodes(widget.series.id, seasonId: s.id);
  }

  @override
  Widget build(BuildContext context) {
    final seasons = _seasons;
    if (seasons == null) return const SizedBox(height: 80);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Wide screens: the Episodes tab is the heading and the seasons are pills below.
        if (isNarrow(context))
          Row(
            children: [
              const Text('Episodes', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (widget.series.miniStop case final m?)
                Text(
                  m.code ?? '',
                  style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w700),
                )
              else if (seasons.length > 1 && isNarrow(context))
                HoverScale(
                  scale: 1,
                  onTap: () async {
                    final i = await showBlurPicker(context, [for (final s in seasons) s.name], selected: seasons.indexOf(_season!));
                    if (i != null && mounted) setState(() => _pick(seasons[i]));
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    decoration: BoxDecoration(color: Hy.surfaceHigh, borderRadius: BorderRadius.circular(4)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_season!.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white),
                      ],
                    ),
                  ),
                )
              else if (seasons.length > 1)
                const SizedBox.shrink()
              else
                Text(
                  _season!.name,
                  style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w700),
                ),
            ],
          ),
        if (seasons.length > 1 && !isNarrow(context)) ...[
          const SizedBox(height: 4),
          _SeasonPills(
            seasons: seasons,
            selected: _season!,
            onPick: (s) => setState(() {
              _land = 0;
              _pick(s);
            }),
          ),
        ],
        const SizedBox(height: 10),
        // Not keyed by season: the last season's episodes stay up while the next one loads,
        // so the page keeps its height and doesn't jump back to the top.
        FutureBuilder<List<Item>>(
          future: _episodes,
          builder: (context, snap) {
            if (!snap.hasData) {
              return const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator(color: Hy.orange)),
              );
            }
            // TV: a sideways row of big stills, like the rest of the TV app.
            if (Device.isTv) return _EpisodeStrip(snap.data!, onEdge: _cross, land: _land);
            return Column(children: [for (final e in snap.data!) _EpisodeTile(e, key: ValueKey(e.id))]);
          },
        ),
      ],
    );
  }
}

/// The show's seasons as a line of pills: the one showing is filled orange, the one under
/// the remote or mouse lifts and turns white. On TV, resting on a season shows it.
class _SeasonPills extends StatefulWidget {
  final List<Item> seasons;
  final Item selected;
  final ValueChanged<Item> onPick;
  const _SeasonPills({required this.seasons, required this.selected, required this.onPick});
  @override
  State<_SeasonPills> createState() => _SeasonPillsState();
}

class _SeasonPillsState extends State<_SeasonPills> {
  Timer? _rest;
  late final _nodes = {for (final s in widget.seasons) s.id: FocusNode(debugLabel: 'season ${s.name}')};
  bool _inside = false;

  @override
  void dispose() {
    _rest?.cancel();
    for (final n in _nodes.values) {
      n.dispose();
    }
    super.dispose();
  }

  /// Coming onto the line from the episodes or the tabs lands on the season showing.
  void _focused(Item s) {
    if (!_inside && s.id != widget.selected.id) {
      _inside = true;
      _nodes[widget.selected.id]?.requestFocus();
      return;
    }
    _inside = true;
    if (!Device.isTv) return;
    _rest?.cancel();
    _rest = Timer(const Duration(milliseconds: 450), () {
      if (mounted && s.id != widget.selected.id) widget.onPick(s);
    });
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onFocusChange: (v) => v ? null : _inside = false,
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final s in widget.seasons)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Pill(
                focusNode: _nodes[s.id],
                label: s.name,
                selected: s.id == widget.selected.id,
                onTap: () => widget.onPick(s),
                onFocus: () => _focused(s),
              ),
            ),
        ],
      ),
    ),
  );
}

class _EpisodeStrip extends StatefulWidget {
  final List<Item> episodes;

  /// Right past the last episode (1) or left past the first (-1): on into the next or
  /// previous season. False when there is none.
  final bool Function(int dir)? onEdge;

  /// After a season change made from here: land on its first (1) or last (-1) episode.
  final int land;
  const _EpisodeStrip(this.episodes, {this.onEdge, this.land = 0});
  @override
  State<_EpisodeStrip> createState() => _EpisodeStripState();
}

class _EpisodeStripState extends State<_EpisodeStrip> {
  static const _w = 400.0, _gap = 22.0;

  // Opens on the episode to watch next: the first one not finished.
  late final _scroll = ScrollController(initialScrollOffset: _offset(_nextUp));
  late List<FocusNode> _nodes = _makeNodes();
  int _at = -1;

  int get _nextUp => widget.episodes.indexWhere((e) => !e.played);

  List<FocusNode> _makeNodes() => [for (final e in widget.episodes) FocusNode(debugLabel: 'episode ${e.indexNumber}')];

  double _offset(int i) => i <= 0 ? 0 : i * (_w + _gap);

  /// Only sideways: the page itself stays where the remote put it.
  void _show(int i) {
    _at = i;
    if (!_scroll.hasClients) return;
    _scroll.animateTo(_offset(i).clamp(0, _scroll.position.maxScrollExtent), duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(_EpisodeStrip old) {
    super.didUpdateWidget(old);
    if (old.episodes.firstOrNull?.id == widget.episodes.firstOrNull?.id) return;
    // Another season: new cards, and the remote goes where it was heading.
    final hadFocus = _nodes.any((n) => n.hasFocus);
    final old0 = _nodes;
    _nodes = _makeNodes();
    final target = widget.land > 0 ? 0 : (widget.land < 0 ? widget.episodes.length - 1 : _nextUp.clamp(0, widget.episodes.length - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final n in old0) {
        n.dispose();
      }
      if (!mounted || widget.episodes.isEmpty) return;
      if (_scroll.hasClients) _scroll.jumpTo(_offset(target).clamp(0, _scroll.position.maxScrollExtent));
      if (hadFocus || widget.land != 0) _nodes[target].requestFocus();
      _at = target;
    });
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent || widget.onEdge == null) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowRight && _at == widget.episodes.length - 1 && widget.onEdge!(1)) return KeyEventResult.handled;
    if (k == LogicalKeyboardKey.arrowLeft && _at == 0 && widget.onEdge!(-1)) return KeyEventResult.handled;
    return KeyEventResult.ignored;
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final n in _nodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    canRequestFocus: false,
    skipTraversal: true,
    onKeyEvent: _onKey,
    child: SizedBox(
      height: _w * 9 / 16 + 112,
      child: ListView.separated(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.only(right: 400),
        itemCount: widget.episodes.length,
        separatorBuilder: (_, _) => const SizedBox(width: _gap),
        itemBuilder: (context, i) =>
            _EpisodeCard(widget.episodes[i], width: _w, focusNode: _nodes[i], onFocus: () => _show(i), key: ValueKey(widget.episodes[i].id)),
      ),
    ),
  );
}

class _EpisodeCard extends StatelessWidget {
  final Item ep;
  final double width;

  final VoidCallback onFocus;
  final FocusNode? focusNode;
  const _EpisodeCard(this.ep, {super.key, required this.width, required this.onFocus, this.focusNode});

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final mins = ep.runtime?.inMinutes;
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Only the still lifts and takes the frame; the words under it stay readable.
          HoverScale(
            focusNode: focusNode,
            scale: 1.04,
            onTap: () => context.push('/play/${ep.id}'),
            onLongPress: () => showItemMenu(context, ep),
            onFocus: (v) {
              if (!v) return;
              onFocus();
              prewarmPlay(context, ep);
            },
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Hy.radius),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(c.thumb(ep, width: 800), fallbackText: ep.name),
                    if (ep.played)
                      const Positioned(
                        top: 8,
                        right: 8,
                        child: Icon(Icons.check_circle_rounded, color: Hy.orange, size: 26, shadows: [Shadow(blurRadius: 8)]),
                      ),
                    if (ep.progress != null && !ep.played) Positioned(left: 0, right: 0, bottom: 0, child: ProgressStrip(ep.progress!, height: 5)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${ep.indexNumber ?? ''}.  ${ep.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            [if (mins != null) '$mins min', if (ep.premiereDate != null) '${ep.premiereDate!.year}'].join('  ·  '),
            style: const TextStyle(color: Hy.textDim, fontSize: 13.5, fontWeight: FontWeight.w600),
          ),
          if ((ep.overview ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              ep.overview!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Hy.textDim, fontSize: 13.5, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _EpisodeTile extends StatefulWidget {
  final Item ep;
  const _EpisodeTile(this.ep, {super.key});
  @override
  State<_EpisodeTile> createState() => _EpisodeTileState();
}

class _EpisodeTileState extends State<_EpisodeTile> {
  late bool _played = widget.ep.played;

  @override
  Widget build(BuildContext context) {
    final e = widget.ep;
    final narrow = isNarrow(context);
    final thumbW = narrow ? 130.0 : 190.0;
    return InkWell(
      onTap: () => context.push('/play/${e.id}'),
      borderRadius: BorderRadius.circular(Hy.radius),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: 14, horizontal: narrow ? 0 : 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Hy.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!narrow)
              SizedBox(
                width: 40,
                child: Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: Text('${e.indexNumber ?? ''}', style: const TextStyle(fontSize: 22, color: Hy.textDim)),
                ),
              ),
            SizedBox(
              width: thumbW,
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NetImage(jf(context).thumb(e, width: 400), fallbackText: e.name),
                      const Center(child: Icon(Icons.play_circle_outline_rounded, size: 36, color: Colors.white70)),
                      if (e.progress != null && !_played) Positioned(left: 0, right: 0, bottom: 0, child: ProgressStrip(e.progress!)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          narrow ? '${e.indexNumber ?? ''}. ${e.name}' : e.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                        ),
                      ),
                      Text(formatRuntime(e.runtime), style: const TextStyle(color: Hy.textDim)),
                      if (!Device.isTv && !Host.isWeb) DownloadIcon(e),
                      IconButton(
                        tooltip: _played ? 'Mark unwatched' : 'Mark watched',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          setState(() => _played = !_played);
                          await jf(context).setPlayed(e.id, _played);
                        },
                        icon: Icon(
                          _played ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
                          color: _played ? Hy.orange : Hy.textMute,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.overview ?? '',
                    maxLines: narrow ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Hy.textDim, height: 1.4, fontSize: 13.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Ratings extends StatelessWidget {
  final Item item;
  const Ratings(this.item, {super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    if (!app.seerrReady || item.tmdbId == null) return const SizedBox.shrink();
    return FutureBuilder<SeerrRatings>(
      future: app.seerr!.ratings(item.isSeries ? 'tv' : 'movie', item.tmdbId!),
      builder: (context, snap) {
        final r = snap.data;
        return AnimatedSize(
          duration: const Duration(milliseconds: 250),
          child: r == null || r.isEmpty
              ? const SizedBox(width: double.infinity)
              : FadeIn(
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (r.imdb != null)
                        _Score(
                          badge: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: const Color(0xFFF5C518), borderRadius: BorderRadius.circular(3)),
                            child: const Text(
                              'IMDb',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 12, letterSpacing: -.3),
                            ),
                          ),
                          value: r.imdb!.toStringAsFixed(1),
                          extra: r.imdbVotes == null ? null : _votes(r.imdbVotes!),
                        ),
                      if (r.critics != null)
                        _Score(
                          badge: Icon(
                            (r.criticsRating ?? '').contains('Rotten') ? Icons.sentiment_dissatisfied_rounded : Icons.local_florist_rounded,
                            size: 18,
                            color: (r.criticsRating ?? '').contains('Rotten') ? const Color(0xFF7BC043) : const Color(0xFFFA320A),
                          ),
                          value: '${r.critics}%',
                          extra: 'critics',
                        ),
                      if (r.audience != null)
                        _Score(
                          badge: const Icon(Icons.people_alt_rounded, size: 17, color: Color(0xFFFFB400)),
                          value: '${r.audience}%',
                          extra: 'audience',
                        ),
                    ],
                  ),
                ),
        );
      },
    );
  }

  static String _votes(int n) => n >= 1000000 ? '${(n / 1000000).toStringAsFixed(1)}M' : (n >= 1000 ? '${(n / 1000).round()}K' : '$n');
}

class _Score extends StatelessWidget {
  final Widget badge;
  final String value;
  final String? extra;
  const _Score({required this.badge, required this.value, this.extra});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      badge,
      const SizedBox(width: 6),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      if (extra != null) ...[const SizedBox(width: 4), Text(extra!, style: const TextStyle(color: Hy.textMute, fontSize: 12))],
    ],
  );
}

/// The phone layout, after Netflix's app: art on top, big Play, tabs for episodes and the rest.
class _MobileDetails extends StatefulWidget {
  final Item item;
  const _MobileDetails(this.item);
  @override
  State<_MobileDetails> createState() => _MobileDetailsState();
}

class _MobileDetailsState extends State<_MobileDetails> {
  bool _overviewOpen = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final c = jf(context);
    final app = context.watch<AppState>();
    final inList = app.myList.contains(item.id);
    final width = MediaQuery.sizeOf(context).width;
    final logo = c.logo(item);
    final cast = item.people.where((p) => p.type == 'Actor').take(4).toList();
    final makers = item.people.where((p) => item.isSeries ? (p.type == 'Writer' || p.type == 'Creator') : p.type == 'Director').take(2).toList();
    const pad = 16.0;

    Widget names(String label, List<String> v) => v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(color: Hy.textMute),
                  ),
                  TextSpan(
                    text: v.join(', '),
                    style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              style: const TextStyle(fontSize: 13),
            ),
          );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: width * 9 / 16 + MediaQuery.paddingOf(context).top + 20,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(c.backdrop(item, width: 1280), alignment: Alignment.topCenter),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, .25, .7, 1],
                      colors: [Color(0x99000000), Colors.transparent, Colors.transparent, Hy.bg],
                    ),
                  ),
                ),
                Center(
                  child: FadeIn(
                    delay: const Duration(milliseconds: 150),
                    from: Offset.zero,
                    child: HoverScale(
                      onTap: () => playItem(context, item),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: .45),
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 38),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: pad),
          sliver: SliverToBoxAdapter(
            child: FadeIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A mini series: its season's poster beside the title.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (item.miniStop?.season != null) ...[_SeasonPoster(item, width: 72), const SizedBox(width: 14)],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (logo != null)
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 70, maxWidth: 240),
                                child: Image.network(logo, alignment: Alignment.centerLeft, errorBuilder: (_, _, _) => _BigTitle(item.name)),
                              )
                            else
                              _BigTitle(item.name),
                            _MiniLabel(item),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  MetaLine(item),
                  const SizedBox(height: 8),
                  Ratings(item),
                  const SizedBox(height: 14),
                  SizedBox(width: double.infinity, child: _ResumeAwarePlay(item)),
                  if (item.isMovie) ...[const SizedBox(height: 8), SizedBox(width: double.infinity, child: _CinemaMode(item, tall: true))],
                  if (item.isSeries && item.miniStop == null && app.seerrReady && item.tmdbId != null) ...[
                    const SizedBox(height: 8),
                    SizedBox(width: double.infinity, child: _MissingSeasons(item)),
                  ],
                  const SizedBox(height: 14),
                  if (item.tagline != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        item.tagline!,
                        style: const TextStyle(fontStyle: FontStyle.italic, color: Hy.textDim),
                      ),
                    ),
                  if (item.pathStop?.previously != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: _Previously(item)),
                  GestureDetector(
                    onTap: () => setState(() => _overviewOpen = !_overviewOpen),
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 250),
                      alignment: Alignment.topCenter,
                      child: Text(
                        item.overview ?? '',
                        maxLines: _overviewOpen ? null : 4,
                        overflow: _overviewOpen ? null : TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, height: 1.45),
                      ),
                    ),
                  ),
                  names('Starring', [for (final p in cast) p.name]),
                  names(item.isSeries ? 'Creators' : 'Director', [for (final p in makers) p.name]),
                  names('Genres', item.genres),
                  PartOf(item),
                  const SizedBox(height: 18),
                  // One even row across the screen (it used to wrap, leaving one on its own).
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final a in <Widget>[
                        _IconAction(
                          icon: inList ? Icons.check_rounded : Icons.add_rounded,
                          label: 'My List',
                          active: inList,
                          onTap: () => app.toggleMyList(item.id).catchError((e) {
                            if (context.mounted) toast(context, 'Could not update My List: $e');
                          }),
                        ),
                        _IconAction(
                          icon: _watched(item) ? Icons.visibility_rounded : Icons.visibility_outlined,
                          label: 'Watched',
                          active: _watched(item),
                          onTap: () async {
                            await _setWatched(context, item);
                            app.bump();
                          },
                        ),
                        _Trailer(
                          item,
                          builder: (onTap) => _IconAction(icon: Icons.movie_filter_rounded, label: 'Trailer', onTap: onTap),
                        ),
                        if (item.isMovie && !Host.isWeb) _IconAction(icon: Icons.download_rounded, label: 'Download', onTap: () => downloadItem(context, item)),
                        _IconAction(
                          icon: Icons.cast_rounded,
                          label: 'On TV',
                          onTap: () => showPlayOn(context, item: item),
                        ),
                        _IconAction(
                          icon: Icons.groups_rounded,
                          label: 'Together',
                          onTap: () => showWatchTogether(context, item: item),
                        ),
                        if (item.isSeries && app.seerrReady && item.tmdbId != null)
                          _IconAction(icon: Icons.travel_explore_rounded, label: 'All seasons', onTap: () => context.push('/request/tv/${item.tmdbId}')),
                      ])
                        Expanded(child: a),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(pad, 0, pad, 50),
          sliver: SliverToBoxAdapter(child: _DetailTabs(item)),
        ),
      ],
    );
  }
}

/// Episodes / More Like This / Cast, switched by Netflix's sliding-bar tabs.
class _DetailTabs extends StatefulWidget {
  final Item item;
  const _DetailTabs(this.item);
  @override
  State<_DetailTabs> createState() => _DetailTabsState();
}

class _DetailTabsState extends State<_DetailTabs> {
  late List<String> _tabs = [
    if (widget.item.isCollection) 'In order',
    if (widget.item.isSeries) 'Episodes',
    if (!widget.item.isCollection) 'More Like This',
    if (widget.item.people.any((p) => p.type == 'Actor')) 'Cast',
  ];
  int _tab = 0;
  Item? _franchise;

  @override
  void initState() {
    super.initState();
    // A film from a franchise gets a tab with the whole series, in order.
    if (widget.item.isMovie) {
      jf(context)
          .collectionOf(widget.item.id)
          .then((b) {
            if (b == null || !mounted) return;
            setState(() {
              _franchise = b;
              _tabs = [..._tabs]..insert(1, 'Collection');
            });
          })
          .catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _TabStrip(tabs: _tabs, index: _tab, onTap: (i) => setState(() => _tab = i)),
      const SizedBox(height: 14),
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, .03), end: Offset.zero).animate(a),
            child: child,
          ),
        ),
        layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?cur]),
        child: KeyedSubtree(
          key: ValueKey(_tabs[_tab]),
          child: switch (_tabs[_tab]) {
            'Episodes' => _Episodes(widget.item),
            'Cast' => _CastGrid(widget.item),
            'In order' => CollectionList(widget.item),
            'Collection' => CollectionList(_franchise!, current: widget.item.id),
            _ => _MoreLikeThis(widget.item),
          },
        ),
      ),
    ],
  );
}

/// Full-width white Play / Resume, with the episode it will start for shows.
class _ResumeAwarePlay extends StatelessWidget {
  final Item item;
  const _ResumeAwarePlay(this.item);
  @override
  Widget build(BuildContext context) {
    final resume = item.resumePosition > Duration.zero && !item.isSeries;
    return FilledButton.icon(
      onPressed: () => playItem(context, item),
      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 13)),
      icon: const Icon(Icons.play_arrow_rounded, size: 28),
      label: Text(resume ? 'Resume' : 'Play'),
    );
  }
}

/// "Cinema mode": a private showing with trailers, a countdown and an intermission.
class _CinemaMode extends StatelessWidget {
  final Item item;
  final bool tall;
  const _CinemaMode(this.item, {this.tall = false});
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () => goLive(context, LiveKind.movie, item.id),
    style: tall ? OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 13)) : null,
    icon: const Icon(Icons.theaters_rounded),
    label: const Text('Cinema mode'),
  );
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _IconAction({required this.icon, required this.label, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => HoverScale(
    scale: 1,
    onTap: onTap,
    child: SizedBox(
      width: double.infinity,
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
            child: Icon(icon, key: ValueKey(icon), size: 28, color: active ? Hy.orange : Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: active ? Hy.orange : Hy.textDim, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

/// Netflix's tabs: the active one gets an orange bar above it that slides across.
class _TabStrip extends StatelessWidget {
  final List<String> tabs;
  final int index;
  final ValueChanged<int> onTap;
  const _TabStrip({required this.tabs, required this.index, required this.onTap});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final painter = [
        for (final t in tabs)
          (TextPainter(
                text: TextSpan(
                  text: t,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                textDirection: TextDirection.ltr,
              )..layout()).width +
              28,
      ];
      final left = painter.take(index).fold(0.0, (a, b) => a + b);
      return Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Hy.border)),
        ),
        child: Stack(
          children: [
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              left: left,
              top: 0,
              width: painter[index],
              height: 4,
              child: Container(color: Hy.orange),
            ),
            Row(
              children: [
                for (final (i, t) in tabs.indexed)
                  InkWell(
                    onTap: () => onTap(i),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 8),
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: i == index ? Colors.white : Hy.textMute),
                        child: Text(t),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

/// A collection's films in order (release or story), numbered, with what's been watched.
class CollectionList extends StatelessWidget {
  final Item collection;
  final String? current;
  const CollectionList(this.collection, {super.key, this.current});
  @override
  Widget build(BuildContext context) {
    final story = context.select<AppState, bool>((a) => a.storyOrder.contains(collection.id));
    return Loader<List<Item>>(
      key: ValueKey('${collection.id}$story'),
      load: () => jf(context).collectionItems(collection.id, story: story, name: collection.name),
      builder: (context, films) {
        final next = films.where((m) => !m.played).firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // A universe with a story order (story: tags): as the films came out, or as the story goes.
            if (films.any((m) => m.storyPlace(collection.name) != null))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    ChoiceChip(
                      label: const Text('Release order'),
                      selected: !story,
                      onSelected: (_) => context.read<AppState>().setStoryOrder(collection.id, false),
                    ),
                    ChoiceChip(
                      label: const Text('Story order'),
                      selected: story,
                      onSelected: (_) => context.read<AppState>().setStoryOrder(collection.id, true),
                    ),
                    Text(
                      story ? '  In the order the story happens' : '  In the order they came out',
                      style: const TextStyle(color: Hy.textMute, fontSize: 12.5),
                    ),
                  ],
                ),
              ),
            if (current != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () => context.push('/item/${collection.id}'),
                  child: Text(
                    '${collection.name} →',
                    style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            for (final (n, m) in films.indexed)
              FadeIn(
                delay: Duration(milliseconds: 30 * n),
                child: HoverScale(
                  scale: 1.01,
                  onTap: () => context.push('/item/${m.id}'),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: m.id == current ? Hy.orange.withValues(alpha: .12) : Hy.surface,
                      borderRadius: BorderRadius.circular(Hy.radius + 2),
                      border: Border.all(color: m.id == current ? Hy.orange : Colors.transparent),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${n + 1}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w300, color: Hy.textDim),
                          ),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(Hy.radius),
                          child: SizedBox(width: 52, height: 78, child: NetImage(jf(context).poster(m, width: 160), fallbackText: m.name)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                m.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                [if (m.year != null) '${m.year}', if (m.runtime != null) formatRuntime(m.runtime)].join('  ·  '),
                                style: const TextStyle(color: Hy.textDim, fontSize: 13),
                              ),
                              if (m.progress != null && !m.played) ...[const SizedBox(height: 6), SizedBox(width: 160, child: ProgressStrip(m.progress!))],
                            ],
                          ),
                        ),
                        if (m.played)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Icon(Icons.check_circle_rounded, color: Hy.orange),
                          )
                        else if (m.id == next?.id)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              'UP NEXT',
                              style: TextStyle(color: Hy.orange, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 1.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MoreLikeThis extends StatelessWidget {
  final Item item;
  const _MoreLikeThis(this.item);
  @override
  Widget build(BuildContext context) => Loader<List<Item>>(
    load: () => jf(context).similar(item.id, limit: 18),
    builder: (context, items) => items.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(30),
            child: Text('Nothing similar in your library yet.', style: TextStyle(color: Hy.textMute)),
          )
        : GridView.extent(
            maxCrossAxisExtent: isNarrow(context) ? 140 : 190,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            childAspectRatio: 2 / 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final (n, i) in items.indexed)
                FadeIn(
                  delay: Duration(milliseconds: 30 * n),
                  child: PosterCard(i, width: 130),
                ),
            ],
          ),
  );
}

class _CastGrid extends StatelessWidget {
  final Item item;
  const _CastGrid(this.item);
  @override
  Widget build(BuildContext context) {
    final cast = item.people.where((p) => p.type == 'Actor').take(30).toList();
    return GridView.extent(
      maxCrossAxisExtent: isNarrow(context) ? 140 : 170,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      childAspectRatio: .68,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      children: [
        for (final (n, p) in cast.indexed)
          FadeIn(
            delay: Duration(milliseconds: 25 * n),
            child: HoverScale(
              scale: 1,
              onTap: () => openPerson(context, jellyfinId: p.id, name: p.name),
              child: Column(
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipOval(
                      child: NetImage(
                        jf(context).personImage(p, width: 300),
                        fallbackText: p.name.split(' ').map((s) => s.isEmpty ? '' : s[0]).join(),
                        alignment: Alignment.topCenter,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  Text(
                    p.role ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Hy.textDim, fontSize: 11.5),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
