import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../api/seerr.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../theme.dart';
import '../widgets/billboard.dart' show playTarget;
import '../widgets/common.dart';
import '../widgets/together.dart';
import 'details.dart' show CollectionList;
import 'person.dart' show openPerson;

part 'universe.dart';

/// Everything a collection's page shows, fetched once.
class _Data {
  final Item box;
  final List<Item> films;

  /// A universe's path: a stop per title, or a show spread over seasons and cuts.
  final List<Stop> stops;
  _Data(this.box, this.films, [List<Stop>? stops]) : stops = stops ?? [for (final f in films) Stop(f)];

  bool get spread => stops.any((s) => s.isPart);
  List<Stop> get stopsWatched => stops.where((s) => s.played).toList();
  Duration get stopsLeft => stops.fold(Duration.zero, (s, x) => s + x.left);
  Duration get stopsTotal => stops.fold(Duration.zero, (s, x) => s + x.runtime);

  Duration get total => films.fold(Duration.zero, (s, f) => s + (f.runtime ?? Duration.zero));
  List<Item> get watched => films.where((f) => f.played).toList();
  Duration get left =>
      films.where((f) => !f.played).fold(Duration.zero, (s, f) => s + (f.runtime ?? Duration.zero) - (f.played ? Duration.zero : f.resumePosition));
  List<int> get years => [for (final f in films) ?f.year]..sort();

  /// Average score out of 100: critics where known, else the audience (out of 10).
  int? get score {
    final s = [for (final f in films) f.criticRating?.toDouble() ?? (f.communityRating == null ? null : f.communityRating! * 10)].whereType<double>().toList();
    return s.isEmpty ? null : (s.reduce((a, b) => a + b) / s.length).round();
  }

  /// Actors in more than one film, the most frequent first.
  List<(Person, int)> get faces {
    final count = <String, int>{}, who = <String, Person>{};
    for (final f in films) {
      for (final p in f.people.where((p) => p.type == 'Actor').take(12)) {
        count[p.id] = (count[p.id] ?? 0) + 1;
        who.putIfAbsent(p.id, () => p);
      }
    }
    final list = [
      for (final e in count.entries)
        if (e.value > 1) (who[e.key]!, e.value),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return list.take(18).toList();
  }

  List<String> get genres {
    final c = <String, int>{};
    for (final f in films) {
      for (final g in f.genres) {
        c[g] = (c[g] ?? 0) + 1;
      }
    }
    return (c.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => e.key).take(6).toList();
  }
}

String _hours(Duration d) {
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  final h = d.inHours, m = d.inMinutes % 60;
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}

String _count(int n) => n < 13 ? const ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve'][n] : '$n';

/// A collection's own page: the art, what it is, how far you've got, numbers and trivia,
/// the faces that keep coming back, and the films in order.
class CollectionView extends StatelessWidget {
  final Item box;
  const CollectionView(this.box, {super.key});

  @override
  Widget build(BuildContext context) => Loader<_Data>(
    load: () async {
      final c = jf(context);
      final films = await c.collectionItems(box.id, name: box.name);
      // People, scores and genres for the numbers and the faces.
      final full = await c.get('/Items', {
        'userId': c.userId,
        'parentId': box.id,
        'includeItemTypes': 'Movie,Series',
        'fields': 'People,Genres,CommunityRating,CriticRating,RunTimeTicks,ProductionYear',
      }) as Map;
      final byId = {for (final i in (full['Items'] as List).cast<Map>()) i['Id']: i};
      for (final f in films) {
        final x = byId[f.id];
        if (x != null) f.raw['People'] = x['People'];
      }
      return _Data(box, films);
    },
    builder: (context, d) => _Page(d),
  );
}

class _Page extends StatelessWidget {
  final _Data d;
  const _Page(this.d);

  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final box = d.box;
    final size = MediaQuery.sizeOf(context);
    final narrow = isNarrow(context);
    final pad = pagePadding(context);
    final films = d.films;
    final first = films.firstOrNull, last = films.lastOrNull;
    final years = d.years;
    final span = years.isEmpty ? '' : (years.first == years.last ? '${years.first}' : '${years.first}–${years.last}');
    final backdrop = box.backdropTags.isNotEmpty ? c.backdrop(box) : (films.isEmpty ? null : c.backdrop(films[min(films.length - 1, films.length ~/ 2)]));
    final kind = box.isUniverse ? 'UNIVERSE' : 'COLLECTION';
    final watched = d.watched.length;
    final heroH = (narrow ? size.width * .75 + 40 : (size.height * .62).clamp(360.0, 640.0)).floorToDouble();
    final overview = (box.overview ?? '').trim().isNotEmpty
        ? box.overview!
        : '${_count(films.length)[0].toUpperCase()}${_count(films.length).substring(1)} ${films.length == 1 ? 'film' : 'films'}'
              '${span.isEmpty ? '' : ' from $span'}, about ${_hours(d.total)} of watching in all.';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: heroH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(backdrop, alignment: Alignment.topCenter),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment(.4, 0), colors: [Color(0xE6000000), Colors.transparent]),
                  ),
                ),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, .55, 1],
                      colors: [Colors.transparent, Color(0x660E0E0E), Hy.bg],
                    ),
                  ),
                ),
                Positioned(
                  left: pad,
                  right: pad,
                  bottom: 10,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        [kind, '${films.length} ${films.length == 1 ? 'TITLE' : 'TITLES'}', if (span.isNotEmpty) span].join('  ·  '),
                        style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w800, letterSpacing: 3, fontSize: 13),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        box.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: narrow ? 32 : 56, fontWeight: FontWeight.w900, height: 1.02, letterSpacing: narrow ? -.5 : -1.2),
                      ),
                      if (box.tagline != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          box.tagline!,
                          style: TextStyle(fontSize: narrow ? 15 : 19, fontStyle: FontStyle.italic, color: Hy.textDim),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 16, pad, 80),
          sliver: SliverList.list(
            children: [
              _Actions(d),
              const SizedBox(height: 18),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Text(overview, style: const TextStyle(fontSize: 15.5, height: 1.5)),
              ),
              if (d.genres.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final g in d.genres)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: Hy.surfaceHigh, borderRadius: BorderRadius.circular(20)),
                        child: Text(
                          g,
                          style: const TextStyle(color: Hy.textDim, fontSize: 12.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 26),
              // How far you've got.
              _Progress(watched: watched, total: films.length, left: d.left, next: films.where((f) => !f.played).firstOrNull),
              const SizedBox(height: 26),
              _Stats(
                tiles: [
                  ('${films.length}', films.length == 1 ? 'title' : 'titles'),
                  (_hours(d.total), 'to watch them all'),
                  if (years.length > 1) ('${years.last - years.first + 1}', 'years of releases'),
                  if (d.score != null) ('${d.score}%', 'average score'),
                ],
              ),
              const SizedBox(height: 30),
              const _Heading('In order'),
              const SizedBox(height: 10),
              CollectionList(box),
              if (d.faces.isNotEmpty) ...[
                const SizedBox(height: 30),
                const _Heading('Familiar faces'),
                const SizedBox(height: 4),
                const Text('Who keeps coming back', style: TextStyle(color: Hy.textDim)),
                const SizedBox(height: 14),
                _Faces(d.faces),
              ],
              if (films.length > 1) ...[
                const SizedBox(height: 30),
                const _Heading('Did you know'),
                const SizedBox(height: 12),
                _Trivia(d, first: first!, last: last!),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800));
}

/// Play (the next unwatched film, in the chosen order), and the usual round buttons.
class _Actions extends StatelessWidget {
  final _Data d;

  /// A custom page's colour for the play button.
  final Color? accent;
  const _Actions(this.d, {this.accent});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final box = d.box;
    final story = app.storyOrder.contains(box.id);
    final started = d.stopsWatched.isNotEmpty || d.stops.any((s) => s.resumePosition > Duration.zero);
    final done = d.stops.isNotEmpty && d.stopsWatched.length == d.stops.length;
    final inList = app.myList.contains(box.id);
    final narrow = isNarrow(context);
    final play = FilledButton.icon(
      autofocus: Device.isTv,
      onPressed: () async {
        final t = await playTarget(jf(context), box, story: story);
        // Started from here, it plays on along this collection's path.
        if (t != null && context.mounted) context.push('/play/${t.id}?in=${box.id}');
      },
      style: FilledButton.styleFrom(
        backgroundColor: accent ?? Colors.white,
        foregroundColor: accent == null || accent!.computeLuminance() > .5 ? Colors.black : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
      icon: const Icon(Icons.play_arrow_rounded, size: 26),
      label: Text(done ? 'Watch again' : (started ? 'Continue' : (narrow ? 'Start' : 'Start from the beginning'))),
    );
    final rounds = [
      _Round(icon: inList ? Icons.check_rounded : Icons.add_rounded, label: 'My List', active: inList, onTap: () => app.toggleMyList(box.id)),
      _Round(
        icon: Icons.groups_rounded,
        label: 'Watch together',
        onTap: () => showWatchTogether(context, item: box),
      ),
      if (!Device.isTv)
        _Round(
          icon: Icons.cast_rounded,
          label: 'Play on…',
          onTap: () => showPlayOn(context, item: box),
        ),
    ];
    // Phones: the play button takes what the round buttons leave, all on one line.
    if (narrow) {
      return Row(
        children: [
          Expanded(child: play),
          for (final r in rounds) ...[const SizedBox(width: 10), r],
        ],
      );
    }
    return Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [play, ...rounds]);
  }
}

class _Round extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _Round({required this.icon, required this.label, required this.onTap, this.active = false});
  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Hy.orange.withValues(alpha: .15) : Colors.black26,
          border: Border.all(color: active ? Hy.orange : Colors.white60, width: 2),
        ),
        child: Icon(icon, color: active ? Hy.orange : Colors.white),
      ),
    ),
  );
}

class _Progress extends StatelessWidget {
  final int watched, total;
  final Duration left;
  final Item? next;
  const _Progress({required this.watched, required this.total, required this.left, this.next});
  @override
  Widget build(BuildContext context) {
    final done = total > 0 && watched == total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Hy.surface,
        borderRadius: BorderRadius.circular(Hy.radius + 4),
        border: Border.all(color: Hy.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$watched', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w300, height: 1)),
              Text(' of $total watched', style: const TextStyle(color: Hy.textDim, fontSize: 16)),
              const Spacer(),
              Text(
                done ? 'All done' : '${_hours(left)} to go',
                style: TextStyle(color: done ? Hy.orange : Hy.textDim, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(value: total == 0 ? 0 : watched / total, minHeight: 6, color: Hy.orange, backgroundColor: Colors.white12),
          ),
          if (next != null && !done) ...[
            const SizedBox(height: 12),
            Text.rich(
              TextSpan(
                children: [
                  const TextSpan(
                    text: 'Up next  ',
                    style: TextStyle(color: Hy.orange, fontWeight: FontWeight.w800, fontSize: 12.5, letterSpacing: 1),
                  ),
                  TextSpan(
                    text: next!.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (next!.year != null)
                    TextSpan(
                      text: '  (${next!.year})',
                      style: const TextStyle(color: Hy.textDim),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  final List<(String, String)> tiles;
  const _Stats({required this.tiles});
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 12,
    runSpacing: 12,
    children: [
      for (final (big, small) in tiles)
        Container(
          width: isNarrow(context) ? (MediaQuery.sizeOf(context).width - pagePadding(context) * 2 - 12) / 2 : 190,
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(color: Hy.surface, borderRadius: BorderRadius.circular(Hy.radius + 4)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(big, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -.5)),
              const SizedBox(height: 2),
              Text(small, style: const TextStyle(color: Hy.textDim, fontSize: 13)),
            ],
          ),
        ),
    ],
  );
}

class _Faces extends StatelessWidget {
  final List<(Person, int)> faces;
  const _Faces(this.faces);
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 168,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: faces.length,
      separatorBuilder: (_, _) => const SizedBox(width: 14),
      itemBuilder: (context, i) {
        final (p, n) = faces[i];
        return HoverScale(
          scale: 1.04,
          onTap: () => openPerson(context, jellyfinId: p.id, name: p.name),
          child: SizedBox(
            width: 104,
            child: Column(
              children: [
                SizedBox(
                  width: 96,
                  height: 96,
                  child: ClipOval(
                    child: NetImage(
                      jf(context).personImage(p, width: 240),
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
                  'in $n films',
                  style: const TextStyle(color: Hy.orange, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _Trivia extends StatelessWidget {
  final _Data d;
  final Item first, last;
  const _Trivia(this.d, {required this.first, required this.last});
  @override
  Widget build(BuildContext context) {
    final timed = d.films.where((f) => f.runtime != null).toList()..sort((a, b) => a.runtime!.compareTo(b.runtime!));
    final rated = d.films.where((f) => f.criticRating != null || f.communityRating != null).toList()
      ..sort((a, b) => (b.criticRating ?? (b.communityRating! * 10)).compareTo(a.criticRating ?? (a.communityRating! * 10)));
    final byYear = [...d.films]..sort((a, b) => (a.year ?? 0).compareTo(b.year ?? 0));
    final total = d.total;
    final facts = <(IconData, String)>[
      if (byYear.first.year != null) (Icons.flag_rounded, 'It started with ${byYear.first.name} in ${byYear.first.year}.'),
      if (byYear.last.year != null && byYear.last.id != byYear.first.id)
        (Icons.new_releases_rounded, 'The latest here is ${byYear.last.name} (${byYear.last.year}).'),
      if (timed.length > 1)
        (
          Icons.hourglass_bottom_rounded,
          '${timed.last.name} is the longest at ${_hours(timed.last.runtime!)}; ${timed.first.name} the shortest at ${_hours(timed.first.runtime!)}.',
        ),
      if (rated.isNotEmpty)
        (
          Icons.emoji_events_rounded,
          '${rated.first.name} is the best reviewed${rated.first.criticRating != null ? ' (${rated.first.criticRating}% with critics)' : ''}.',
        ),
      if (total.inHours >= 24)
        (
          Icons.bedtime_rounded,
          'Back to back it runs ${total.inHours ~/ 24} day${total.inHours ~/ 24 == 1 ? '' : 's'} and ${total.inHours % 24} hours, without sleep.',
        )
      else
        (Icons.weekend_rounded, 'Back to back it runs ${_hours(total)}: one long weekend on the sofa.'),
    ];
    return Column(
      children: [
        for (final (icon, text) in facts)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: Hy.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4))),
              ],
            ),
          ),
      ],
    );
  }
}

/// All franchise collections, as a wall of posters with how far you've got in each.
class CollectionsPage extends StatelessWidget {
  const CollectionsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final top = MediaQuery.paddingOf(context).top + (isNarrow(context) ? 70 : 90);
    return Loader<List<Item>>(
      load: () => jf(context).collections(),
      builder: (context, list) => CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, top, pad, 16),
            sliver: const SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Collections', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                  SizedBox(height: 4),
                  Text('Franchises and universes, to watch in order', style: TextStyle(color: Hy.textDim)),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 100),
            sliver: SliverGrid.extent(
              maxCrossAxisExtent: isNarrow(context) ? 150 : 200,
              childAspectRatio: 2 / 3.35,
              mainAxisSpacing: 14,
              crossAxisSpacing: 12,
              children: [
                for (final (n, b) in list.indexed)
                  FadeIn(
                    delay: Duration(milliseconds: 25 * n),
                    child: HoverScale(
                      scale: 1.04,
                      onTap: () => context.push('/item/${b.id}'),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(Hy.radius),
                              child: SizedBox.expand(child: NetImage(jf(context).poster(b, width: 400), fallbackText: b.name)),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            b.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          Text(
                            [if (b.isUniverse) 'Universe', if (b.childCount != null) '${b.childCount} titles'].join(' · '),
                            style: const TextStyle(color: Hy.textMute, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Part of": every collection a film is in, as links (its "… Collection" and the
/// universe it belongs to).
class PartOf extends StatelessWidget {
  final Item item;
  const PartOf(this.item, {super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<List<Item>>(
    future: jf(context).collectionsOf(item.id),
    builder: (context, snap) {
      final list = snap.data ?? const [];
      if (list.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text('Part of', style: TextStyle(color: Hy.textMute, fontSize: 13)),
            for (final b in list)
              HoverScale(
                scale: 1.04,
                onTap: () => context.push('/item/${b.id}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: b.isUniverse ? Hy.orange.withValues(alpha: .14) : Hy.surfaceHigh,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: b.isUniverse ? Hy.orange : Hy.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.collections_bookmark_rounded, size: 16, color: b.isUniverse ? Hy.orange : Hy.textDim),
                      const SizedBox(width: 6),
                      Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 2),
                      const Icon(Icons.chevron_right_rounded, size: 16, color: Hy.textDim),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
