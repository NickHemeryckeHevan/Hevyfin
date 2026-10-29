import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../api/seerr.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../state/row_cache.dart';
import '../../state/seasons.dart';
import '../../theme.dart';
import '../widgets/billboard.dart';
import '../widgets/common.dart';
import '../widgets/spotlight.dart';

/// Netflix-style home: billboard, then personal rows, top 10s, genres and things to request.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final rev = context.select<AppState, int>((a) => a.revision);
    final seerrReady = context.select<AppState, bool>((a) => a.seerrReady);
    final page = RefreshIndicator(
      color: Hy.orange,
      onRefresh: () async => context.read<AppState>().bump(),
      child: CustomScrollView(
        key: const PageStorageKey('home'),
        slivers: [
          SliverToBoxAdapter(
            // Back on the banner: it shows itself again.
            child: Focus(
              canRequestFocus: false,
              skipTraversal: true,
              onFocusChange: (v) => v ? Spotlight.show(context, null) : null,
              child: _HomeBillboard(key: ValueKey('hero$rev')),
            ),
          ),
          SliverToBoxAdapter(
            child: _HomeRows(key: ValueKey('rows$rev'), seerr: seerrReady),
          ),
        ],
      ),
    );
    if (!Device.isTv) return page;
    // TV: the selected title fills the top of the screen, its row sits under it.
    return Spotlight(child: TvRowAnchor(at: .5, child: page));
  }
}

class _HomeBillboard extends StatelessWidget {
  const _HomeBillboard({super.key});
  @override
  Widget build(BuildContext context) => Loader<Item?>(
    load: () async {
      final c = jf(context);
      // A pick from the last pool shows at once; the pool itself is refreshed for next time.
      final cached = RowCache.get('billboard', c.userId)?.where((i) => i.backdropTags.isNotEmpty).toList();
      final fresh = Future(() async {
        final pool = [...await c.latest('Movie', limit: 12), ...await c.latest('Series', limit: 12)].where((i) => i.backdropTags.isNotEmpty).toList();
        RowCache.put('billboard', c.userId, pool);
        return pool;
      });
      final usable = cached != null && cached.isNotEmpty;
      if (usable) fresh.ignore();
      final pool = usable ? cached : await fresh;
      return pool.isEmpty ? null : pool[Random().nextInt(pool.length)];
    },
    loading: SizedBox(height: MediaQuery.sizeOf(context).height * .6),
    builder: (context, item) =>
        item == null ? SizedBox(height: MediaQuery.sizeOf(context).height * .2) : Billboard(item, eyebrow: item.isSeries ? 'Series' : 'Film'),
  );
}

class _HomeRows extends StatelessWidget {
  final bool seerr;
  const _HomeRows({super.key, required this.seerr});

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final pw = posterWidth(context);
    final posterH = pw * 1.5 + 14;
    final landW = isNarrow(context) ? 230.0 : 300.0;
    final landH = landW * 9 / 16 + 62;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LazyRow<Item>(
          title: 'Continue Watching',
          height: landH,
          load: () => c.resume(),
          card: (i) => LandscapeCard(i, width: landW),
        ),
        LazyRow<Item>(
          title: 'Next Up',
          height: landH,
          load: () => c.nextUp(),
          card: (i) => LandscapeCard(i, width: landW),
        ),
        LazyRow<Item>(
          title: 'New on Hevyfin',
          height: posterH,
          load: () async {
            final all = [...await c.latest('Movie', limit: 20), ...await c.latest('Series', limit: 20)];
            all.sort((a, b) => ('${b.raw['DateCreated']}').compareTo('${a.raw['DateCreated']}'));
            return all;
          },
          card: (i) => PosterCard(i, width: pw),
        ),
        // Halloween in October, Christmas in December and so on.
        for (final r in seasonalRows(DateTime.now()))
          LazyRow<Item>(
            title: r.title,
            subtitle: r.subtitle,
            height: posterH,
            minItems: 3,
            load: () async => (await c.everything()).where(r.pick).toList()..shuffle(),
            card: (i) => PosterCard(i, width: pw),
          ),
        LazyRow<Item>(
          title: 'Collections',
          height: posterH,
          load: () => c.collections(),
          card: (i) => PosterCard(i, width: pw),
          onMore: () => context.go('/collections'),
        ),
        _BecauseYouWatched(posterWidth: pw, posterHeight: posterH, seerr: seerr),
        LazyRow<Item>(
          title: 'Top 10 Movies in Your Library',
          height: 222,
          load: () => c.items(types: ['Movie'], sortBy: 'CommunityRating', sortOrder: 'Descending', limit: 10),
          cards: (items) => [for (var i = 0; i < items.length; i++) Top10Card(i + 1, items[i])],
        ),
        _GenreRows(posterWidth: pw, posterHeight: posterH, offset: 0),
        LazyRow<Item>(
          title: 'Top 10 Shows in Your Library',
          height: 222,
          load: () => c.items(types: ['Series'], sortBy: 'CommunityRating', sortOrder: 'Descending', limit: 10),
          cards: (items) => [for (var i = 0; i < items.length; i++) Top10Card(i + 1, items[i])],
        ),
        LazyRow<Item>(
          title: 'Back on the Shelf',
          subtitle: 'Watch it again:',
          height: posterH,
          load: () async {
            final watched = await c.items(types: ['Movie'], filters: 'IsPlayed', sortBy: 'Random', limit: 20);
            return watched;
          },
          card: (i) => PosterCard(i, width: pw),
        ),
        _GenreRows(posterWidth: pw, posterHeight: posterH, offset: 3),
        if (seerr)
          LazyRow<SeerrMedia>(
            title: 'Trending Now – Not on Hevyfin Yet',
            height: posterH,
            load: () async {
              final s = context.read<AppState>().seerr!;
              final r = await s.trending();
              return r.where((m) => m.status != MediaStatus.available).toList();
            },
            card: (m) => SeerrCard(m, width: pw),
            onMore: () => context.go('/new'),
          ),
        const SizedBox(height: 40),
      ],
    );
  }
}

/// "Because you watched X" from the library, and from Seerr: things like it you could request.
class _BecauseYouWatched extends StatelessWidget {
  final double posterWidth, posterHeight;
  final bool seerr;
  const _BecauseYouWatched({required this.posterWidth, required this.posterHeight, required this.seerr});

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    return Loader<List<Item>>(
      loading: const SizedBox.shrink(),
      load: () async {
        // The last few distinct things watched: a movie, or the show an episode belongs to.
        final recent = [...await c.resume(limit: 10), ...await c.recentlyWatched(limit: 40)];
        final seen = <String>{};
        final sources = <Item>[];
        for (final i in recent) {
          final key = i.isEpisode ? i.seriesId : i.id;
          if (key == null || !seen.add(key)) continue;
          sources.add(i.isEpisode ? await c.item(key) : i);
          if (sources.length == 3) break;
        }
        return sources;
      },
      builder: (context, sources) => Column(
        children: [
          for (final (n, src) in sources.indexed) ...[
            LazyRow<Item>(
              subtitle: 'Because you watched',
              title: src.name,
              height: posterHeight,
              minItems: 3,
              load: () async => (await c.similar(src.id, limit: 24)).where((i) => !i.played).toList(),
              card: (i) => PosterCard(i, width: posterWidth),
            ),
            if (seerr && src.tmdbId != null && n < 2)
              LazyRow<SeerrMedia>(
                subtitle: 'More like ${src.name}',
                title: '– request it',
                height: posterHeight,
                load: () async {
                  final s = context.read<AppState>().seerr!;
                  final r = await s.recommendations(src.isSeries ? 'tv' : 'movie', src.tmdbId!);
                  return r.where((m) => m.status.requestable && m.posterPath != null).take(20).toList();
                },
                card: (m) => SeerrCard(m, width: posterWidth),
              ),
          ],
        ],
      ),
    );
  }
}

/// A few random genre rows; [offset] picks a different slice so they spread down the page.
class _GenreRows extends StatelessWidget {
  final double posterWidth, posterHeight;
  final int offset;
  const _GenreRows({required this.posterWidth, required this.posterHeight, required this.offset});

  static List<Genre>? _shuffled;

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    return Loader<List<Genre>>(
      loading: const SizedBox.shrink(),
      load: () async {
        if (offset == 0 || _shuffled == null) _shuffled = (await c.genres())..shuffle();
        return _shuffled!.skip(offset).take(3).toList();
      },
      builder: (context, genres) => Column(
        children: [
          for (final g in genres)
            LazyRow<Item>(
              title: g.name,
              height: posterHeight,
              load: () => c.items(genre: g.name, sortBy: 'Random', limit: 24),
              minItems: 4,
              card: (i) => PosterCard(i, width: posterWidth),
              onMore: () => context.push('/genre/${Uri.encodeComponent(g.name)}'),
            ),
        ],
      ),
    );
  }
}

/// A [MediaRow] that loads its own items once and hides itself when empty or failing.
class LazyRow<T> extends StatefulWidget {
  final String title;
  final String? subtitle;
  final double height;
  final Future<List<T>> Function() load;
  final Widget Function(T)? card;
  final List<Widget> Function(List<T>)? cards;
  final VoidCallback? onMore;
  final int minItems;
  const LazyRow({
    super.key,
    required this.title,
    this.subtitle,
    required this.height,
    required this.load,
    this.card,
    this.cards,
    this.onMore,
    this.minItems = 1,
  });

  @override
  State<LazyRow<T>> createState() => _LazyRowState<T>();
}

class _LazyRowState<T> extends State<LazyRow<T>> {
  late final Future<List<T>> _future = _load();

  /// Library rows show their last contents at once, then the fresh ones.
  late final List<T>? _cached = T == Item ? RowCache.get(widget.title, jf(context).userId) as List<T>? : null;

  Future<List<T>> _load() async {
    final items = await widget.load();
    if (T == Item && mounted) RowCache.put(widget.title, jf(context).userId, items.cast<Item>());
    return items;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<T>>(
    future: _future,
    builder: (context, snap) {
      final ready = snap.connectionState == ConnectionState.done;
      if (!ready && _cached == null) return _SkeletonRow(height: widget.height);
      final items = (ready ? snap.data : _cached) ?? const [];
      if (items.length < widget.minItems) return const SizedBox.shrink();
      return FadeIn(
        child: MediaRow(
          title: widget.title,
          subtitle: widget.subtitle,
          height: widget.height,
          onMore: widget.onMore,
          children: widget.cards?.call(items) ?? items.map(widget.card!).toList(),
        ),
      );
    },
  );
}

/// What a row looks like while it loads.
class _SkeletonRow extends StatelessWidget {
  final double height;
  const _SkeletonRow({required this.height});
  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final tileH = height - 12;
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, 0, 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Skeleton(width: 160, height: 18),
          const SizedBox(height: 16),
          SizedBox(
            height: tileH,
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              scrollDirection: Axis.horizontal,
              itemCount: 6,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, _) => Skeleton(width: tileH * 2 / 3, height: tileH),
            ),
          ),
        ],
      ),
    );
  }
}
