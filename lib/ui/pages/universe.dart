part of 'collection.dart';

// The custom page a special collection can carry (a universe, a big franchise). The
// design lives on the server in the collection's provider ids ("HevyfinPage"): an accent
// colour, an eyebrow and tagline, and sections in order. Everything else stays standard.

/// The custom page design for [box], if it has one.
Map<String, dynamic>? pageDesign(Item box) {
  final raw = ((box.raw['ProviderIds'] as Map?) ?? const {})['HevyfinPage'];
  if (raw is! String || raw.isEmpty) return null;
  try {
    return (jsonDecode(raw) as Map).cast<String, dynamic>();
  } catch (_) {
    return null;
  }
}

Color _accentOf(Map<String, dynamic> page) {
  final hex = '${page['accent'] ?? ''}'.replaceFirst('#', '');
  final v = int.tryParse(hex, radix: 16);
  return hex.length == 6 && v != null ? Color(0xFF000000 | v) : Hy.orange;
}

/// A collection with a custom page: loads like the standard one, then lays out its custom design (docs/custom-collections.md).
class UniverseView extends StatelessWidget {
  final Item box;
  final Map<String, dynamic> page;
  const UniverseView(this.box, this.page, {super.key});

  @override
  Widget build(BuildContext context) {
    final story = context.select<AppState, bool>((a) => a.storyOrder.contains(box.id));
    return Loader<_Data>(
      key: ValueKey('${box.id}$story'),
      load: () async {
        final c = jf(context);
        final films = await c.collectionItems(box.id, story: story, name: box.name);
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
        return _Data(box, films, await c.universeStops(box, films, story: story));
      },
      builder: (context, d) => _Universe(d, page, story: story),
    );
  }
}

class _Universe extends StatelessWidget {
  final _Data d;
  final Map<String, dynamic> page;
  final bool story;
  const _Universe(this.d, this.page, {required this.story});

  @override
  Widget build(BuildContext context) {
    final accent = _accentOf(page);
    final pad = pagePadding(context);
    final sections = ((page['sections'] as List?) ?? const []).whereType<Map>().map((s) => s.cast<String, dynamic>()).toList();
    // TV: the remote moves line by line through the whole page, so every section is built
    // up front (a lazy list hides the ones further down from it).
    return TvPageNav(
      builder: (scroll) => CustomScrollView(
        controller: scroll,
        scrollCacheExtent: Device.isTv ? const ScrollCacheExtent.pixels(100000) : null,
        slivers: [
          SliverToBoxAdapter(child: _UniverseHero(d, page, accent)),
          SliverPadding(
            // No right padding: rows run off the right edge like Home's; everything else gets it back.
            padding: EdgeInsets.fromLTRB(pad, 8, 0, 90),
            sliver: SliverList.list(
              children: [
                for (final (i, s) in sections.indexed)
                  FadeIn(
                    delay: Duration(milliseconds: 60 * min(i, 6)),
                    child: Padding(padding: const EdgeInsets.only(top: 34), child: _section(context, s, accent)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, Map<String, dynamic> s, Color accent) {
    final title = s['title'] as String?;
    final edge = EdgeInsets.only(right: pagePadding(context));
    return switch (s['type']) {
      'timeline' || 'groups' || 'heroes' || 'missing' || 'upcoming' => _row(s, title, accent),
      _ => Padding(padding: edge, child: _block(s, title, accent)),
    };
  }

  Widget _row(Map<String, dynamic> s, String? title, Color accent) => switch (s['type']) {
    'timeline' => _Timeline(d, accent, story: story, title: title),
    'groups' => _Groups(d, accent, title: title),
    'heroes' => _Heroes(d, accent, title: title),
    'missing' => _Elsewhere(d.box, accent, upcoming: false, title: title, items: (s['items'] as List?)?.whereType<Map>().toList()),
    'upcoming' => _Elsewhere(d.box, accent, upcoming: true, title: title, items: (s['items'] as List?)?.whereType<Map>().toList()),
    _ => const SizedBox.shrink(),
  };

  Widget _block(Map<String, dynamic> s, String? title, Color accent) {
    return switch (s['type']) {
      'intro' || 'text' => TvReadStop(
        child: _Prose(title: title, text: '${s['text'] ?? ''}', accent: accent, big: s['type'] == 'intro'),
      ),
      'quote' => TvReadStop(
        child: _Quote(text: '${s['text'] ?? ''}', by: s['by'] as String?, accent: accent),
      ),
      'progress' => _UProgress(d, accent),
      'facts' => TvReadStop(
        child: _Facts(d, accent, title: title, items: ((s['items'] as List?) ?? const []).map((e) => '$e').toList()),
      ),
      _ => const SizedBox.shrink(),
    };
  }
}

class _UHeading extends StatelessWidget {
  final String text;
  final Color accent;
  final String? side;
  const _UHeading(this.text, this.accent, {this.side});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: 14, right: pagePadding(context)),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 24,
          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.3)),
        ),
        if (side != null)
          Text(
            side!,
            style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w600),
          ),
      ],
    ),
  );
}

/// The hero: the titles' wide art drifting and cross-fading, the accent glowing through,
/// the name, counters that tick up, and the play button.
class _UniverseHero extends StatefulWidget {
  final _Data d;
  final Map<String, dynamic> page;
  final Color accent;
  const _UniverseHero(this.d, this.page, this.accent);
  @override
  State<_UniverseHero> createState() => _UniverseHeroState();
}

class _UniverseHeroState extends State<_UniverseHero> with SingleTickerProviderStateMixin {
  late final _drift = AnimationController(vsync: this, duration: const Duration(seconds: 24))..repeat(reverse: true);
  Timer? _next;
  int _i = 0;

  late final List<String> _art = [
    for (final f in widget.d.films)
      if (f.backdropTags.isNotEmpty) ?jf(context).backdrop(f, width: 1920),
  ];

  @override
  void initState() {
    super.initState();
    _next = Timer.periodic(const Duration(seconds: 7), (_) => mounted && _art.length > 1 ? setState(() => _i = (_i + 1) % _art.length) : null);
  }

  @override
  void dispose() {
    _next?.cancel();
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.d, page = widget.page, accent = widget.accent;
    final size = MediaQuery.sizeOf(context);
    final narrow = isNarrow(context);
    final pad = pagePadding(context);
    final years = d.years;
    final groups = d.stops.map((s) => s.group).whereType<String>().toSet().length;
    final art = _art.isEmpty ? jf(context).backdrop(d.box) : _art[_i];
    return SizedBox(
      height: (narrow ? size.height * .78 : (size.height * .86).clamp(460.0, 900.0)).floorToDouble(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The drifting picture is drawn larger than the hero: keep it inside.
          ClipRect(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 1400),
              // Every picture fills the hero (the default layout would leave them unsized).
              layoutBuilder: (cur, prev) => Stack(fit: StackFit.expand, children: [...prev, ?cur]),
              child: AnimatedBuilder(
                key: ValueKey(art),
                animation: _drift,
                builder: (_, child) => Transform.scale(scale: 1.06 + .06 * _drift.value, alignment: Alignment(-.3 + .6 * _drift.value, -.2), child: child),
                child: NetImage(art, alignment: Alignment.topCenter),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-.7, .6),
                radius: 1.2,
                colors: [accent.withValues(alpha: .38), accent.withValues(alpha: .08), Colors.transparent],
                stops: const [0, .45, 1],
              ),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment(.5, 0), colors: [Color(0xE6000000), Colors.transparent]),
            ),
          ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, .5, 1],
                colors: [Color(0x55000000), Color(0x330E0E0E), Hy.bg],
              ),
            ),
          ),
          Positioned(
            left: pad,
            right: pad,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (page['eyebrow'] != null)
                  // One line: shrunk to fit on a phone rather than leaving a word on its own.
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '${page['eyebrow']}'.toUpperCase(),
                      maxLines: 1,
                      style: TextStyle(color: accent, fontWeight: FontWeight.w800, letterSpacing: narrow ? 2.5 : 3.5, fontSize: narrow ? 11.5 : 14),
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  d.box.name,
                  maxLines: 2,
                  style: TextStyle(fontSize: narrow ? 38 : 76, fontWeight: FontWeight.w900, height: .98, letterSpacing: narrow ? -1 : -2.4),
                ),
                const SizedBox(height: 10),
                Container(
                  width: narrow ? 70 : 120,
                  height: 4,
                  decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2)),
                ),
                if ((page['tagline'] ?? d.box.tagline) != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    '${page['tagline'] ?? d.box.tagline}',
                    style: TextStyle(fontSize: narrow ? 16 : 22, color: Hy.textDim, fontWeight: FontWeight.w300),
                  ),
                ],
                const SizedBox(height: 22),
                Wrap(
                  spacing: narrow ? 22 : 40,
                  runSpacing: 12,
                  children: [
                    _Counter(d.stops.length, d.spread ? 'stops' : 'titles', accent),
                    _Counter(d.stopsTotal.inHours, 'hours', accent),
                    if (groups > 1) _Counter(groups, 'chapters', accent) else if (years.length > 1) _Counter(years.last - years.first + 1, 'years', accent),
                    _Counter(d.stopsWatched.length, 'watched', accent),
                  ],
                ),
                const SizedBox(height: 22),
                _Actions(d, accent: accent),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A number that counts up when it first shows.
class _Counter extends StatelessWidget {
  final int value;
  final String label;
  final Color accent;
  const _Counter(this.value, this.label, this.accent);
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: value.toDouble()),
    duration: const Duration(milliseconds: 1300),
    curve: Curves.easeOutCubic,
    builder: (_, v, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${v.round()}',
          style: TextStyle(fontSize: isNarrow(context) ? 26 : 38, fontWeight: FontWeight.w300, height: 1, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
        const SizedBox(height: 4),
        Text(
          label.toUpperCase(),
          style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
      ],
    ),
  );
}

class _Prose extends StatelessWidget {
  final String? title;
  final String text;
  final Color accent;
  final bool big;
  const _Prose({this.title, required this.text, required this.accent, this.big = false});
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 860),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) _UHeading(title!, accent),
        for (final (i, p) in text.split(RegExp(r'\n\s*\n')).indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              p.trim(),
              style: TextStyle(
                fontSize: big && i == 0 ? 19 : 15.5,
                height: 1.55,
                color: big && i == 0 ? Colors.white : const Color(0xFFDADADA),
                fontWeight: big && i == 0 ? FontWeight.w400 : FontWeight.w400,
              ),
            ),
          ),
      ],
    ),
  );
}

class _Quote extends StatelessWidget {
  final String text;
  final String? by;
  final Color accent;
  const _Quote({required this.text, this.by, required this.accent});
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(vertical: 26, horizontal: isNarrow(context) ? 8 : 40),
    child: Column(
      children: [
        Text(
          '“',
          style: TextStyle(color: accent, fontSize: 90, height: .6, fontWeight: FontWeight.w900),
        ),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: isNarrow(context) ? 22 : 32, fontWeight: FontWeight.w300, fontStyle: FontStyle.italic, height: 1.3),
        ),
        if (by != null) ...[
          const SizedBox(height: 14),
          Text(
            '— $by',
            style: TextStyle(color: accent, fontWeight: FontWeight.w700, letterSpacing: 1),
          ),
        ],
      ],
    ),
  );
}

/// How far you are: a ring that fills, the hours left, and the next title as a wide card.
class _UProgress extends StatelessWidget {
  final _Data d;
  final Color accent;
  const _UProgress(this.d, this.accent);
  @override
  Widget build(BuildContext context) {
    final total = d.stops.length, watched = d.stopsWatched.length;
    final next = d.stops.where((s) => !s.played).firstOrNull;
    final ring = SizedBox(
      width: 130,
      height: 130,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: total == 0 ? 0 : watched / total),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (_, v, _) => CustomPaint(
          painter: _RingPainter(v, accent),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('${(v * 100).round()}%', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w300)),
                Text('$watched of $total', style: const TextStyle(color: Hy.textDim, fontSize: 12)),
              ],
            ),
          ),
        ),
      ),
    );
    final card = next == null
        ? const Text('You have seen all of it. Time for a rewatch?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))
        : HoverScale(
            scale: 1.02,
            onTap: () => context.push(next.route),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Hy.radius + 4),
              child: SizedBox(
                height: 150,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(jf(context).backdrop(next.item, width: 900), alignment: Alignment.topCenter),
                    const DecoratedBox(
                      decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xEE000000), Color(0x22000000)])),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            'UP NEXT',
                            style: TextStyle(color: accent, fontWeight: FontWeight.w800, letterSpacing: 2, fontSize: 12),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            next.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                          Text(
                            '${next.code == null ? '' : '${next.code} · '}${_hours(d.stopsLeft)} to go after this one starts',
                            style: const TextStyle(color: Hy.textDim, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
    return isNarrow(context)
        ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ring, const SizedBox(height: 16), card])
        : Row(
            children: [
              ring,
              const SizedBox(width: 28),
              Expanded(child: card),
            ],
          );
  }
}

class _RingPainter extends CustomPainter {
  final double v;
  final Color accent;
  _RingPainter(this.v, this.accent);
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromCircle(center: size.center(Offset.zero), radius: size.shortestSide / 2 - 6);
    canvas.drawArc(
      r,
      0,
      2 * pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..color = Colors.white10,
    );
    canvas.drawArc(
      r,
      -pi / 2,
      2 * pi * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.v != v || old.accent != accent;
}

/// The titles as a path: posters on a line, watched ones lit, the next one ringed; in
/// release or story order.
class _Timeline extends StatelessWidget {
  final _Data d;
  final Color accent;
  final bool story;
  final String? title;
  const _Timeline(this.d, this.accent, {required this.story, this.title});
  @override
  Widget build(BuildContext context) {
    final hasStory = d.spread || d.films.any((m) => m.storyPlace(d.box.name) != null);
    final stops = d.stops;
    final next = stops.where((s) => !s.played).firstOrNull;
    final ni = next == null ? 0 : stops.indexOf(next);
    const w = 132.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UHeading(title ?? 'The path', accent),
        if (hasStory)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Release order'),
                  selected: !story,
                  selectedColor: accent.withValues(alpha: .35),
                  labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  onSelected: (_) => context.read<AppState>().setStoryOrder(d.box.id, false),
                ),
                ChoiceChip(
                  label: const Text('Story order'),
                  selected: story,
                  selectedColor: accent.withValues(alpha: .35),
                  labelStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  onSelected: (_) => context.read<AppState>().setStoryOrder(d.box.id, true),
                ),
              ],
            ),
          ),
        SizedBox(
          height: 300,
          child: ListView.builder(
            controller: ScrollController(initialScrollOffset: max(0, (ni - 1) * w)),
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.only(right: pagePadding(context)),
            itemCount: stops.length,
            itemBuilder: (context, i) {
              final f = stops[i];
              final isNext = identical(f, next);
              return HoverScale(
                scale: 1.04,
                onTap: () => context.push(f.route),
                child: SizedBox(
                  width: w,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 9),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(Hy.radius + 2),
                            border: Border.all(color: isNext ? accent : Colors.transparent, width: 3),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(Hy.radius),
                            child: Opacity(
                              opacity: f.played || isNext ? 1 : .62,
                              child: AspectRatio(
                                aspectRatio: 2 / 3,
                                child: NetImage(jf(context).stopPoster(f, width: 300), fallbackText: f.title),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // The line with this title's stop on it.
                      SizedBox(
                        height: 18,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Positioned(
                              left: i == 0 ? w / 2 : 0,
                              right: i == stops.length - 1 ? w / 2 : 0,
                              child: Container(height: 2, color: f.played ? accent : Colors.white24),
                            ),
                            Container(
                              width: isNext ? 16 : 12,
                              height: isNext ? 16 : 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: f.played ? accent : Hy.bg,
                                border: Border.all(color: f.played || isNext ? accent : Colors.white38, width: 2.5),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${i + 1}',
                        style: TextStyle(color: isNext ? accent : Hy.textDim, fontWeight: FontWeight.w800),
                      ),
                      // A season or cut says which part of its show it is; a cut its own name too.
                      Text(
                        f.code ?? '${f.item.year ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: f.isPart ? accent : Hy.textMute, fontSize: 12, fontWeight: f.isPart ? FontWeight.w700 : null),
                      ),
                      if (f.isPart && f.title != f.item.name)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            f.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Hy.textMute, fontSize: 11),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The titles per group (phases, eras), in order, each with how much of it you've seen.
class _Groups extends StatelessWidget {
  final _Data d;
  final Color accent;
  final String? title;
  const _Groups(this.d, this.accent, {this.title});
  @override
  Widget build(BuildContext context) {
    final groups = <String, List<Stop>>{};
    for (final s in d.stops) {
      groups.putIfAbsent(s.group ?? 'More', () => []).add(s);
    }
    if (groups.length < 2 && groups.keys.firstOrNull == 'More') return const SizedBox.shrink();
    final pw = isNarrow(context) ? 104.0 : 128.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UHeading(title ?? 'Chapters', accent),
        for (final e in groups.entries) ...[
          Padding(
            padding: EdgeInsets.only(top: 6, bottom: 10, right: pagePadding(context)),
            child: Row(
              children: [
                Text(
                  e.key.toUpperCase(),
                  style: TextStyle(color: accent, fontWeight: FontWeight.w800, letterSpacing: 2.5, fontSize: 13),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: e.value.where((f) => f.played).length / e.value.length,
                      minHeight: 3,
                      color: accent,
                      backgroundColor: Colors.white10,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text('${e.value.where((f) => f.played).length} of ${e.value.length}', style: const TextStyle(color: Hy.textDim, fontSize: 12.5)),
              ],
            ),
          ),
          SizedBox(
            height: pw * 1.5 + 8,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(right: pagePadding(context)),
              itemCount: e.value.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) =>
                  e.value[i].isPart ? _PartCard(e.value[i], accent, width: pw) : PosterCard(e.value[i].item, width: pw, route: e.value[i].route),
            ),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

/// A season or a cut of a show as a poster: which part it is along its foot.
class _PartCard extends StatelessWidget {
  final Stop stop;
  final Color accent;
  final double width;
  const _PartCard(this.stop, this.accent, {required this.width});
  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: HoverScale(
      onTap: () => context.push(stop.route),
      child: AspectRatio(
        aspectRatio: 2 / 3,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Hy.radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(jf(context).stopPoster(stop, width: (width * 2).round()), fallbackText: stop.title),
              // A cut's own poster already says what it is.
              if (stop.art == null) ...[
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment(0, .2), end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xE6000000)]),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (stop.title != stop.item.name)
                        Text(
                          stop.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, height: 1.15),
                        ),
                      Text(
                        stop.code ?? '',
                        style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              ],
              if (stop.played)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .75), borderRadius: BorderRadius.circular(20)),
                    child: const Icon(Icons.check_rounded, size: 14),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Who keeps coming back, with the character they play most.
class _Heroes extends StatelessWidget {
  final _Data d;
  final Color accent;
  final String? title;
  const _Heroes(this.d, this.accent, {this.title});
  @override
  Widget build(BuildContext context) {
    final roles = <String, Map<String, int>>{};
    for (final f in d.films) {
      for (final p in f.people.where((p) => p.type == 'Actor')) {
        final r = (p.role ?? '').trim();
        if (r.isNotEmpty) (roles[p.id] ??= {})[r] = ((roles[p.id] ?? const {})[r] ?? 0) + 1;
      }
    }
    final faces = d.faces;
    if (faces.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _UHeading(title ?? 'Heroes', accent),
        SizedBox(
          height: 226,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.only(right: pagePadding(context)),
            clipBehavior: Clip.none,
            itemCount: faces.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final (p, n) = faces[i];
              final role = (roles[p.id]?.entries.toList()?..sort((a, b) => b.value.compareTo(a.value)))?.firstOrNull?.key;
              void open() => openPerson(context, jellyfinId: p.id, name: p.name);
              return GestureDetector(
                onTap: open,
                child: SizedBox(
                  width: 124,
                  child: Column(
                    children: [
                      const SizedBox(height: 6),
                      // Only the face is framed when it has focus (a round frame, room to grow).
                      HoverScale(
                        scale: 1.04,
                        radius: 60,
                        onTap: open,
                        child: Container(
                          width: 112,
                          height: 112,
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: accent, width: 2),
                          ),
                          child: ClipOval(
                            child: NetImage(
                              jf(context).personImage(p, width: 260),
                              fallbackText: p.name.split(' ').map((s) => s.isEmpty ? '' : s[0]).join(),
                              alignment: Alignment.topCenter,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      const SizedBox(height: 10),
                      Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
                      ),
                      if (role != null)
                        Text(
                          'as $role',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Hy.textDim, fontSize: 12),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        '$n films',
                        style: TextStyle(color: accent, fontSize: 11.5, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Facts extends StatelessWidget {
  final _Data d;
  final Color accent;
  final String? title;
  final List<String> items;
  const _Facts(this.d, this.accent, {this.title, this.items = const []});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _UHeading(title ?? 'Did you know', accent),
      if (items.isEmpty && d.films.length > 1)
        _Trivia(d, first: d.films.first, last: d.films.last)
      else
        // As many columns of about 380 as fit, stretched to fill the line.
        LayoutBuilder(
          builder: (context, box) {
            final cols = isNarrow(context) ? 1 : max(1, ((box.maxWidth + 12) / 392).floor());
            final w = ((box.maxWidth - 12 * (cols - 1)) / cols).floorToDouble();
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (i, f) in items.indexed)
                  Container(
                    width: w,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Hy.surface,
                      borderRadius: BorderRadius.circular(Hy.radius + 4),
                      border: Border(left: BorderSide(color: accent, width: 3)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}'.padLeft(2, '0'),
                          style: TextStyle(color: accent, fontWeight: FontWeight.w900, fontSize: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(f, style: const TextStyle(fontSize: 14.5, height: 1.45))),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
    ],
  );
}

/// Titles that aren't in the library yet: released ones to request, announced ones with
/// their date and a countdown. From the section's items, else from the collection's tags.
class _Elsewhere extends StatelessWidget {
  final Item box;
  final Color accent;
  final bool upcoming;
  final String? title;
  final List<Map>? items;
  const _Elsewhere(this.box, this.accent, {required this.upcoming, this.title, this.items});

  List<(String, int, DateTime?)> get _wanted {
    if (items != null) {
      return [
        for (final m in items!)
          if (int.tryParse('${m['tmdb']}') case final id?) ('${m['kind'] ?? 'movie'}', id, DateTime.tryParse('${m['date'] ?? ''}')),
      ];
    }
    final out = <(String, int, DateTime?)>[];
    for (final t in box.tags) {
      final p = t.split(':');
      if (!upcoming && p.length == 3 && p[0] == 'missing') {
        if (int.tryParse(p[2]) case final id?) out.add((p[1], id, null));
      }
      if (upcoming && p.length == 4 && p[0] == 'upcoming') {
        if (int.tryParse(p[2]) case final id?) out.add((p[1], id, DateTime.tryParse(p[3])));
      }
    }
    // Dated ones first, soonest first.
    out.sort((a, b) => (a.$3 ?? DateTime(9999)).compareTo(b.$3 ?? DateTime(9999)));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final seerr = context.select<AppState, SeerrClient?>((a) => a.seerrReady ? a.seerr : null);
    final wanted = _wanted;
    if (seerr == null || wanted.isEmpty) return const SizedBox.shrink();
    final pw = isNarrow(context) ? 112.0 : 140.0;
    final heading = title ?? (upcoming ? 'Coming soon' : 'Not in your library yet');
    return FutureBuilder<List<(SeerrMedia, DateTime?)>>(
      // Kept across rebuilds (switching the order, a hover), or the posters load again each time.
      future: _loaded['${box.id}:$upcoming:${wanted.map((w) => w.$2).join(',')}'] ??= Future.wait([
        for (final (kind, id, date) in wanted.take(30)) seerr.details(kind, id).then<(SeerrMedia, DateTime?)?>((m) => (m, date)).catchError((_) => null),
      ]).then((l) => l.whereType<(SeerrMedia, DateTime?)>().toList()),
      builder: (context, snap) {
        final list = snap.data;
        if (list == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _UHeading(heading, accent, side: '${wanted.length}'),
              SizedBox(
                height: pw * 1.5 + 50,
                child: const Center(child: CircularProgressIndicator(color: Hy.orange)),
              ),
            ],
          );
        }
        // What's already requested or downloading gets its own row, above what's still to ask for.
        final coming = upcoming ? const <(SeerrMedia, DateTime?)>[] : list.where((e) => _onItsWay(e.$1)).toList();
        final rest = list.where((e) => !coming.contains(e)).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (coming.isNotEmpty) ...[
              _UHeading('On its way', accent, side: '${coming.length}'),
              _row(context, coming, pw),
              if (rest.isNotEmpty) const SizedBox(height: 30),
            ],
            if (rest.isNotEmpty) ...[_UHeading(heading, accent, side: '${rest.length}'), _row(context, rest, pw)],
          ],
        );
      },
    );
  }

  /// Requested in Seerr, already downloading, or being fetched by Sonarr/Radarr (the universe
  /// job tags those `coming:<kind>:<tmdb>`; Seerr misses shows wanted by the episode).
  bool _onItsWay(SeerrMedia m) =>
      m.status == MediaStatus.pending ||
      m.status == MediaStatus.processing ||
      m.downloadProgress != null ||
      box.tags.contains('coming:${m.mediaType}:${m.tmdbId}');

  Widget _row(BuildContext context, List<(SeerrMedia, DateTime?)> list, double pw) => SizedBox(
    height: pw * 1.5 + (upcoming ? 60 : 40),
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.only(right: pagePadding(context)),
      itemCount: list.length,
      separatorBuilder: (_, _) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final (m, date) = list[i];
        if (!upcoming) return SeerrCard(m, width: pw);
        final days = date?.difference(DateTime.now()).inDays;
        // Only the poster is framed when it has focus, so the frame never covers the name.
        return GestureDetector(
          onTap: () => openSeerr(context, m),
          child: SizedBox(
            width: pw,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HoverScale(
                  scale: 1.04,
                  onTap: () => openSeerr(context, m),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(Hy.radius),
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: NetImage(m.posterPath == null ? null : SeerrClient.image(m.posterPath), fallbackText: m.title),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  m.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  date == null ? 'Date to be announced' : (days! <= 0 ? 'Out now' : (days < 60 ? 'In $days days' : '${_month(date)} ${date.year}')),
                  style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );

  static final _loaded = <String, Future<List<(SeerrMedia, DateTime?)>>>{};

  static String _month(DateTime d) => const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1];
}
