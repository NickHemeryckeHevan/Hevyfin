import 'dart:math';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../theme.dart';
import '../shell.dart';
import '../widgets/billboard.dart';
import '../widgets/common.dart';
import '../widgets/spotlight.dart';
import 'home.dart';

/// Shows or Movies: billboard, a genre picker, then a row per genre.
class BrowsePage extends StatelessWidget {
  final String type; // 'Series' or 'Movie'
  const BrowsePage({super.key, required this.type});

  String get _label => type == 'Series' ? 'Shows' : 'Movies';

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final rev = context.select<AppState, int>((a) => a.revision);
    final pw = posterWidth(context);
    final posterH = pw * 1.5 + 14;
    final page = CustomScrollView(
      key: PageStorageKey('browse$type'),
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (v) => v ? Spotlight.show(context, null) : null,
                child: Loader<Item?>(
                  key: ValueKey('bb$type$rev'),
                  loading: SizedBox(height: MediaQuery.sizeOf(context).height * .6),
                  load: () async {
                    final pool = (await c.items(types: [type], sortBy: 'Random', limit: 20)).where((i) => i.backdropTags.isNotEmpty).toList();
                    return pool.isEmpty ? null : pool[Random().nextInt(pool.length)];
                  },
                  builder: (context, item) =>
                      item == null ? SizedBox(height: topInset(context) + 60) : Billboard(item, eyebrow: type == 'Series' ? 'Series' : 'Film'),
                ),
              ),
              // Phones pick genres from the header chips instead.
              // (and TVs, where the remote should land on Play first)
              if (!isNarrow(context) && !Device.isTv)
                Positioned(
                  left: pagePadding(context),
                  top: topInset(context) + 4,
                  child: _GenrePicker(type: type, label: _label),
                ),
            ],
          ),
        ),
        SliverToBoxAdapter(
          child: Loader<List<Genre>>(
            key: ValueKey('rows$type$rev'),
            load: () => c.genres(types: [type]),
            builder: (context, genres) => Column(
              children: [
                LazyRow<Item>(
                  title: 'New $_label',
                  height: posterH,
                  load: () => c.latest(type, limit: 24),
                  card: (i) => PosterCard(i, width: pw),
                ),
                LazyRow<Item>(
                  title: 'Top 10 $_label',
                  height: 222,
                  load: () => c.items(types: [type], sortBy: 'CommunityRating', sortOrder: 'Descending', limit: 10),
                  cards: (items) => [for (var i = 0; i < items.length; i++) Top10Card(i + 1, items[i])],
                ),
                if (type == 'Series')
                  LazyRow<Item>(
                    title: 'Shows You Haven\'t Started',
                    height: posterH,
                    load: () async => (await c.items(
                      types: [type],
                      filters: 'IsUnplayed',
                      sortBy: 'Random',
                      limit: 40,
                    )).where((i) => i.playedPercentage == null || i.playedPercentage == 0).take(20).toList(),
                    card: (i) => PosterCard(i, width: pw),
                  )
                else
                  LazyRow<Item>(
                    title: 'Movies You Haven\'t Seen',
                    height: posterH,
                    load: () => c.items(types: [type], filters: 'IsUnplayed', sortBy: 'Random', limit: 20),
                    card: (i) => PosterCard(i, width: pw),
                  ),
                for (final g in genres)
                  LazyRow<Item>(
                    title: g.name,
                    height: posterH,
                    minItems: 3,
                    load: () => c.items(types: [type], genre: g.name, sortBy: 'Random', limit: 24),
                    card: (i) => PosterCard(i, width: pw),
                    onMore: () => context.push('/genre/${Uri.encodeComponent(g.name)}?type=$type'),
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
    // TV: like Home, the selected title fills the top of the screen.
    return Device.isTv ? Spotlight(child: TvRowAnchor(at: .5, child: page)) : page;
  }
}

class _GenrePicker extends StatelessWidget {
  final String type, label;
  const _GenrePicker({required this.type, required this.label});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(
        label,
        style: TextStyle(fontSize: isNarrow(context) ? 22 : 34, fontWeight: FontWeight.w900, shadows: const [Shadow(blurRadius: 12)]),
      ),
      const SizedBox(width: 20),
      FutureBuilder<List<Genre>>(
        future: jf(context).genres(types: [type]),
        builder: (context, snap) => PopupMenuButton<String>(
          tooltip: 'Genres',
          offset: const Offset(0, 40),
          constraints: const BoxConstraints(maxHeight: 460),
          onSelected: (g) => context.push('/genre/${Uri.encodeComponent(g)}?type=$type'),
          itemBuilder: (_) => [for (final g in snap.data ?? const <Genre>[]) PopupMenuItem(value: g.name, child: Text(g.name))],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: .6),
              border: Border.all(color: Colors.white70),
            ),
            child: const Row(
              children: [
                Text('Genres', style: TextStyle(fontWeight: FontWeight.w600)),
                SizedBox(width: 18),
                Icon(Icons.arrow_drop_down_rounded, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

/// Everything in one genre, as a grid.
class GenrePage extends StatefulWidget {
  final String name;
  final String? type;
  const GenrePage({super.key, required this.name, this.type});
  @override
  State<GenrePage> createState() => _GenrePageState();
}

class _GenrePageState extends State<GenrePage> {
  String _sort = 'Random';
  static const _sorts = {
    'Random': 'Surprise me',
    'DateCreated': 'Recently added',
    'PremiereDate': 'Release date',
    'CommunityRating': 'Rating',
    'SortName': 'A–Z',
  };

  @override
  Widget build(BuildContext context) {
    final types = widget.type == null ? ['Movie', 'Series'] : [widget.type!];
    final pad = pagePadding(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, topInset(context) + 12, pad, 12),
            child: Wrap(
              spacing: 16,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  widget.type == null ? widget.name : '${widget.name} ${widget.type == 'Series' ? 'Shows' : 'Movies'}',
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
                ),
                DropdownButton<String>(
                  value: _sort,
                  underline: const SizedBox.shrink(),
                  dropdownColor: Hy.surfaceHigh,
                  items: [for (final e in _sorts.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                  onChanged: (v) => setState(() => _sort = v!),
                ),
              ],
            ),
          ),
        ),
        Loader<List<Item>>(
          key: ValueKey(_sort),
          sliver: true,
          load: () => jf(context).items(types: types, genre: widget.name, sortBy: _sort, sortOrder: _sort == 'SortName' ? 'Ascending' : 'Descending'),
          builder: (context, items) => PosterGrid(children: [for (final i in items) PosterCard(i)]),
        ),
      ],
    );
  }
}

/// The user's Jellyfin favourites.
class MyListPage extends StatelessWidget {
  const MyListPage({super.key});
  @override
  Widget build(BuildContext context) {
    final rev = context.select<AppState, int>((a) => a.revision);
    final pad = pagePadding(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, topInset(context) + 12, pad, 12),
            child: const Text('My List', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
          ),
        ),
        Loader<List<Item>>(
          key: ValueKey(rev),
          sliver: true,
          loading: const SizedBox.shrink(),
          load: () => jf(context).items(filters: 'IsFavorite', sortBy: 'DateCreated', sortOrder: 'Descending'),
          builder: (context, items) => items.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(60),
                    child: Column(
                      children: [
                        Icon(Icons.bookmark_add_outlined, size: 56, color: Hy.textMute),
                        SizedBox(height: 12),
                        Text(
                          'Nothing here yet. Tap "My List" on any movie or show to save it.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Hy.textDim),
                        ),
                      ],
                    ),
                  ),
                )
              : PosterGrid(children: [for (final i in items) PosterCard(i)]),
        ),
      ],
    );
  }
}
