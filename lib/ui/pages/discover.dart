import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/seerr.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../shell.dart';
import '../widgets/common.dart';
import 'person.dart';

/// New & Popular: browse TMDB through Seerr and request what isn't on the server yet.
class DiscoverPage extends StatefulWidget {
  final String? tab;
  const DiscoverPage({super.key, this.tab});
  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

enum _Tab {
  trending('Trending'),
  movies('Movies'),
  shows('Shows'),
  upcoming('Coming Soon'),
  requests('My Requests');

  final String label;
  const _Tab(this.label);
}

class _DiscoverPageState extends State<DiscoverPage> {
  late _Tab _tab = _Tab.values.where((t) => t.name == widget.tab).firstOrNull ?? _Tab.trending;
  int? _genre;

  @override
  void didUpdateWidget(covariant DiscoverPage old) {
    super.didUpdateWidget(old);
    final t = _Tab.values.where((t) => t.name == widget.tab).firstOrNull;
    if (t != null && old.tab != widget.tab) _tab = t;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pad = pagePadding(context);
    if (!app.seerrReady) return const SeerrConnect();
    final seerr = app.seerr!;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, topInset(context) + 8, pad, 4),
            child: const Text('New & Popular', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad - 4, 10, pad, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in _Tab.values)
                  ChoiceChip(
                    label: Text(t.label),
                    selected: _tab == t,
                    onSelected: (_) => setState(() {
                      _tab = t;
                      _genre = null;
                    }),
                  ),
              ],
            ),
          ),
        ),
        if (_tab == _Tab.movies || _tab == _Tab.shows)
          SliverToBoxAdapter(
            child: _GenreChips(type: _tab == _Tab.movies ? 'movie' : 'tv', selected: _genre, onSelected: (g) => setState(() => _genre = g)),
          ),
        if (_tab == _Tab.requests)
          _Requests(seerr, key: ValueKey(app.revision))
        else
          _PagedGrid(
            key: ValueKey('$_tab$_genre'),
            load: (page) => switch (_tab) {
              _Tab.trending => seerr.trending(page: page),
              _Tab.movies => seerr.popularMovies(page: page, genre: _genre),
              _Tab.shows => seerr.popularTv(page: page, genre: _genre),
              _ => _upcoming(seerr, page),
            },
          ),
      ],
    );
  }

  Future<List<SeerrMedia>> _upcoming(SeerrClient s, int page) async {
    final both = await Future.wait([s.upcomingMovies(page: page), s.upcomingTv(page: page)]);
    final out = <SeerrMedia>[];
    for (var i = 0; i < 20; i++) {
      if (i < both[0].length) out.add(both[0][i]);
      if (i < both[1].length) out.add(both[1][i]);
    }
    return out;
  }
}

class _GenreChips extends StatelessWidget {
  final String type;
  final int? selected;
  final ValueChanged<int?> onSelected;
  const _GenreChips({required this.type, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Loader<List<SeerrGenre>>(
      key: ValueKey(type),
      loading: const SizedBox(height: 50),
      load: () => context.read<AppState>().seerr!.genres(type),
      builder: (context, genres) => SizedBox(
        height: 50,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(pad - 4, 10, pad, 0),
          children: [
            for (final g in [SeerrGenre(-1, 'All'), ...genres])
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: FilterChip(
                  label: Text(g.name),
                  selected: g.id == -1 ? selected == null : selected == g.id,
                  onSelected: (_) => onSelected(g.id == -1 ? null : g.id),
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: Hy.border),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Grid that loads the next page when you near the bottom.
class _PagedGrid extends StatefulWidget {
  final Future<List<SeerrMedia>> Function(int page) load;
  const _PagedGrid({super.key, required this.load});
  @override
  State<_PagedGrid> createState() => _PagedGridState();
}

class _PagedGridState extends State<_PagedGrid> {
  final _items = <SeerrMedia>[];
  final _seen = <String>{};
  int _page = 0;
  bool _loading = false, _done = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _more();
  }

  Future<void> _more() async {
    if (_loading || _done) return;
    setState(() => _loading = true);
    try {
      final next = await widget.load(_page + 1);
      _page++;
      if (next.isEmpty || _page >= 10) _done = true;
      for (final m in next) {
        if (_seen.add('${m.mediaType}${m.tmdbId}')) _items.add(m);
      }
      _error = null;
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _items.isEmpty) return SliverToBoxAdapter(child: ErrorView('$_error', onRetry: _more));
    final pad = pagePadding(context);
    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 18, pad, 0),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: posterWidth(context) + 20,
              childAspectRatio: 2 / 3,
              mainAxisSpacing: 14,
              crossAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate((context, i) {
              if (i >= _items.length - 8) WidgetsBinding.instance.addPostFrameCallback((_) => _more());
              return SeerrCard(_items[i]);
            }, childCount: _items.length),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(30),
            child: Center(child: _loading ? const CircularProgressIndicator(color: Hy.orange) : const SizedBox(height: 30)),
          ),
        ),
      ],
    );
  }
}

class _Requests extends StatelessWidget {
  final SeerrClient seerr;
  const _Requests(this.seerr, {super.key});

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Loader<List<SeerrRequest>>(
      sliver: true,
      load: () async {
        final list = await seerr.myRequests();
        await Future.wait(
          list.map((r) async {
            try {
              r.details = await seerr.details(r.type, r.tmdbId);
            } catch (_) {}
          }),
        );
        return list;
      },
      builder: (context, list) => list.isEmpty
          ? const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(60),
                child: Center(
                  child: Text("You haven't requested anything yet.", style: TextStyle(color: Hy.textDim)),
                ),
              ),
            )
          : SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 18, pad, 60),
              sliver: SliverList.separated(
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, i) => _RequestTile(list[i]),
              ),
            ),
    );
  }
}

class _RequestTile extends StatelessWidget {
  final SeerrRequest r;
  const _RequestTile(this.r);

  @override
  Widget build(BuildContext context) {
    final d = r.details;
    final progress = r.downloadProgress;
    final color = switch (r.statusLabel) {
      'Available' => const Color(0xFF2ECC71),
      'Partly available' => const Color(0xFF2ECC71),
      'Downloading' => Hy.orange,
      'Declined' || 'Failed' => Hy.danger,
      _ => const Color(0xFFB98CFF),
    };
    return Material(
      color: Hy.surface,
      borderRadius: BorderRadius.circular(Hy.radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: d == null ? null : () => openSeerr(context, d),
        child: SizedBox(
          height: 120,
          child: Row(
            children: [
              AspectRatio(
                aspectRatio: 2 / 3,
                child: NetImage(d?.posterPath == null ? null : SeerrClient.image(d!.posterPath, size: 'w185'), fallbackText: d?.title ?? '?'),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d?.title ?? 'TMDB ${r.tmdbId}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (d?.year != null) '${d!.year}',
                          r.type == 'tv' ? (r.seasons.isEmpty ? 'Series' : 'Season${r.seasons.length > 1 ? 's' : ''} ${r.seasons.join(', ')}') : 'Movie',
                          if (r.createdAt != null) 'requested ${_ago(r.createdAt!)}',
                        ].join('  •  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Hy.textDim),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(color: color.withValues(alpha: .15), borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              r.statusLabel == 'Downloading' && progress != null ? 'Downloading ${(progress * 100).round()}%' : r.statusLabel,
                              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
                            ),
                          ),
                          if (progress != null && r.statusLabel == 'Downloading') ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: ClipRRect(borderRadius: BorderRadius.circular(2), child: ProgressStrip(progress)),
                            ),
                            const SizedBox(width: 16),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays > 0) return '${d.inDays}d ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    return '${d.inMinutes}m ago';
  }
}

/// Shown when Seerr isn't signed in: one password field (same account as Jellyfin).
class SeerrConnect extends StatefulWidget {
  final bool compact;
  const SeerrConnect({super.key, this.compact = false});
  @override
  State<SeerrConnect> createState() => _SeerrConnectState();
}

class _SeerrConnectState extends State<SeerrConnect> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<AppState>().seerrLogin(_pw.text);
    } catch (e) {
      _error = '$e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final body = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.add_to_queue_rounded, size: 52, color: Hy.orange),
          const SizedBox(height: 14),
          const Text(
            'Connect Seerr',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Requests go through Seerr at ${app.seerrUrl}. Enter your Jellyfin password for ${app.userName} to link it.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Hy.textDim, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _pw,
            obscureText: true,
            autofocus: !widget.compact,
            decoration: const InputDecoration(hintText: 'Password'),
            onSubmitted: (_) => _go(),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: const TextStyle(color: Hy.danger)),
            ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _busy ? null : _go,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Connect'),
          ),
        ],
      ),
    );
    return Center(
      child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(24, topInset(context), 24, 24), child: body),
    );
  }
}

/// One TMDB title via Seerr: status, and the request button (with season picker for shows).
class SeerrDetailsPage extends StatefulWidget {
  final String type;
  final int id;
  const SeerrDetailsPage({super.key, required this.type, required this.id});
  @override
  State<SeerrDetailsPage> createState() => _SeerrDetailsPageState();
}

class _SeerrDetailsPageState extends State<SeerrDetailsPage> {
  late Future<SeerrMedia> _future = _load();
  final Set<int> _chosen = {};
  bool _sending = false;

  Future<SeerrMedia> _load() async {
    final m = await context.read<AppState>().seerr!.details(widget.type, widget.id);
    final status = m.seasonStatus;
    _chosen
      ..clear()
      ..addAll(m.seasonNumbers.where((n) => (status[n] ?? MediaStatus.unknown).requestable && status[n] != MediaStatus.partial));
    return m;
  }

  Future<void> _request(SeerrMedia m) async {
    setState(() => _sending = true);
    final app = context.read<AppState>();
    try {
      final approved = await app.seerr!.request(m, seasons: m.isTv ? (_chosen.toList()..sort()) : null);
      if (mounted) {
        toast(
          context,
          approved
              ? '${m.title} requested. It will show up in your library once it has downloaded.'
              : '${m.title} requested. It downloads once it has been approved.',
        );
      }
      app.bump();
      setState(() => _future = _load());
    } catch (e) {
      if (mounted) toast(context, 'Request failed: $e');
    }
    if (mounted) setState(() => _sending = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!context.select<AppState, bool>((a) => a.seerrReady)) return const SeerrConnect();
    return FutureBuilder<SeerrMedia>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView('${snap.error}', onRetry: () => setState(() => _future = _load()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator(color: Hy.orange));
        return _body(snap.data!);
      },
    );
  }

  Widget _body(SeerrMedia m) {
    final size = MediaQuery.sizeOf(context);
    final narrow = isNarrow(context);
    final pad = pagePadding(context);
    final heroH = (narrow ? size.width * .56 + 40 : (size.width * .4).clamp(340.0, (size.height * .62).clamp(340.0, double.infinity))).floorToDouble();
    final status = m.seasonStatus;
    final requestable = m.isTv
        ? m.seasonNumbers.any((n) => (status[n] ?? MediaStatus.unknown).requestable && status[n] != MediaStatus.partial)
        : m.status.requestable;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: heroH,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(m.backdropPath == null ? null : SeerrClient.image(m.backdropPath, size: 'w1280'), alignment: Alignment.topCenter),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0, .5, 1],
                      colors: [Colors.transparent, Hy.bg.withValues(alpha: .4), Hy.bg],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(pad, 0, pad, 60),
          sliver: SliverToBoxAdapter(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!narrow) ...[
                  Transform.translate(
                    offset: const Offset(0, -120),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Hy.radius),
                      child: SizedBox(
                        width: 220,
                        child: AspectRatio(
                          aspectRatio: 2 / 3,
                          child: NetImage(m.posterPath == null ? null : SeerrClient.image(m.posterPath, size: 'w500'), fallbackText: m.title),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.title,
                        style: TextStyle(fontSize: narrow ? 30 : 44, fontWeight: FontWeight.w900, height: 1.05),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (m.voteAverage != null && m.voteAverage! > 0)
                            Text(
                              '${(m.voteAverage! * 10).round()}% match',
                              style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w800),
                            ),
                          if (m.year != null)
                            Text(
                              '${m.year}',
                              style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w600),
                            ),
                          OutlineTag(m.isTv ? 'SERIES' : 'FILM'),
                          if (m.isTv && m.seasonNumbers.isNotEmpty)
                            Text('${m.seasonNumbers.length} Season${m.seasonNumbers.length > 1 ? 's' : ''}', style: const TextStyle(color: Hy.textDim)),
                          if (!m.isTv && m.runtime != null && m.runtime! > 0)
                            Text(
                              formatRuntime(Duration(minutes: m.runtime!)),
                              style: const TextStyle(color: Hy.textDim),
                            ),
                          if (m.status != MediaStatus.unknown) StatusPill(m.status, progress: m.downloadProgress),
                        ],
                      ),
                      if (m.genres.isNotEmpty) ...[const SizedBox(height: 10), Text(m.genres.join('  •  '), style: const TextStyle(color: Hy.textDim))],
                      if (m.tagline != null && m.tagline!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          m.tagline!,
                          style: const TextStyle(fontStyle: FontStyle.italic, color: Hy.textDim),
                        ),
                      ],
                      const SizedBox(height: 14),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: Text(m.overview ?? '', style: const TextStyle(fontSize: 16, height: 1.5)),
                      ),
                      const SizedBox(height: 22),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          if (m.jellyfinId != null && (m.status == MediaStatus.available || m.status == MediaStatus.partial))
                            FilledButton.icon(
                              onPressed: () => context.push('/item/${m.jellyfinId}'),
                              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                              icon: const Icon(Icons.play_arrow_rounded, size: 28),
                              label: const Text('Watch on Hevyfin'),
                            ),
                          if (m.trailerUrl != null)
                            OutlinedButton.icon(
                              onPressed: () => launchUrl(Uri.parse(m.trailerUrl!), mode: LaunchMode.externalApplication),
                              icon: const Icon(Icons.movie_filter_rounded),
                              label: const Text('Trailer'),
                            ),
                          if (requestable)
                            FilledButton.icon(
                              onPressed: _sending || (m.isTv && _chosen.isEmpty) ? null : () => _request(m),
                              icon: _sending
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                  : const Icon(Icons.add_rounded),
                              label: Text(m.isTv ? 'Request ${_chosen.length} season${_chosen.length == 1 ? '' : 's'}' : 'Request'),
                            ),
                        ],
                      ),
                      if (((m.raw['credits'] as Map?)?['cast'] as List?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 28),
                        const Text('Cast', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 150,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final p in ((m.raw['credits'] as Map)['cast'] as List).take(20).cast<Map>())
                                Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: HoverScale(
                                    scale: 1.04,
                                    onTap: () => openPerson(context, tmdbId: p['id'] as int, name: p['name'] as String? ?? ''),
                                    child: SizedBox(
                                      width: 86,
                                      child: Column(
                                        children: [
                                          ClipOval(
                                            child: SizedBox(
                                              width: 80,
                                              height: 80,
                                              child: NetImage(
                                                p['profilePath'] == null ? null : SeerrClient.image(p['profilePath'] as String, size: 'w185'),
                                                fallbackText: '${p['name'] ?? ''}'.split(' ').map((s) => s.isEmpty ? '' : s[0]).join(),
                                                alignment: Alignment.topCenter,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${p['name'] ?? ''}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                                          ),
                                          Text(
                                            '${p['character'] ?? ''}',
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(color: Hy.textDim, fontSize: 11.5),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                      if (m.isTv && m.seasonNumbers.isNotEmpty) ...[
                        const SizedBox(height: 28),
                        const Text('Seasons', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: Column(children: [for (final n in m.seasonNumbers) _seasonRow(n, status[n] ?? MediaStatus.unknown)]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _seasonRow(int n, MediaStatus s) {
    final can = s.requestable && s != MediaStatus.partial;
    return CheckboxListTile(
      value: can ? _chosen.contains(n) : true,
      onChanged: can ? (v) => setState(() => v == true ? _chosen.add(n) : _chosen.remove(n)) : null,
      activeColor: can ? Hy.orange : Hy.textMute,
      checkColor: Colors.black,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: EdgeInsets.zero,
      title: Text('Season $n', style: const TextStyle(fontWeight: FontWeight.w600)),
      secondary: s == MediaStatus.unknown ? null : StatusPill(s, compact: false),
    );
  }
}
