import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/jellyfin.dart';
import '../../api/seerr.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../widgets/common.dart';

/// An actor (or director): photo, biography, life dates, what's on Hevyfin and the full
/// filmography. Opened from a library cast list ([jellyfinId]) or a Seerr one ([tmdbId]).
class PersonPage extends StatefulWidget {
  final String? jellyfinId;
  final int? tmdbId;
  final String name;
  const PersonPage({super.key, this.jellyfinId, this.tmdbId, this.name = ''});
  @override
  State<PersonPage> createState() => _PersonPageState();
}

class _PersonData {
  final String name;
  final String? photo;
  final String bio;
  final DateTime? born, died;
  final String? place, knownFor, imdbId;
  final List<String> aka;
  final List<Item> library;
  final List<SeerrCredit> credits;
  _PersonData({
    required this.name,
    this.photo,
    this.bio = '',
    this.born,
    this.died,
    this.place,
    this.knownFor,
    this.imdbId,
    this.aka = const [],
    this.library = const [],
    this.credits = const [],
  });
}

class _PersonPageState extends State<PersonPage> {
  late Future<_PersonData> _future = _load();

  Future<_PersonData> _load() async {
    final app = context.read<AppState>();
    final c = app.client!;
    Item? jfPerson;
    var library = <Item>[];
    var tmdb = widget.tmdbId;
    if (widget.jellyfinId != null) {
      final r = await Future.wait([c.item(widget.jellyfinId!), c.items(personIds: widget.jellyfinId!, sortBy: 'PremiereDate', sortOrder: 'Descending')]);
      jfPerson = r[0] as Item;
      library = r[1] as List<Item>;
      tmdb ??= jfPerson.tmdbId;
    }
    SeerrPerson? sp;
    var credits = <SeerrCredit>[];
    if (app.seerrReady && tmdb != null) {
      try {
        final r = await Future.wait([app.seerr!.person(tmdb), app.seerr!.personCredits(tmdb)]);
        sp = r[0] as SeerrPerson;
        credits = r[1] as List<SeerrCredit>;
      } catch (_) {
        // Fall back to what Jellyfin knows.
      }
    }
    final raw = jfPerson?.raw ?? const <String, dynamic>{};
    final tag = (raw['ImageTags'] as Map?)?['Primary'] as String?;
    final jfPhoto = jfPerson != null && tag != null ? c.personImage(Person({'Id': jfPerson.id, 'PrimaryImageTag': tag}), width: 600) : null;
    return _PersonData(
      name: sp?.name ?? jfPerson?.name ?? widget.name,
      photo: sp?.profilePath != null ? SeerrClient.image(sp!.profilePath, size: 'h632') : jfPhoto,
      bio: (sp?.biography.isNotEmpty ?? false) ? sp!.biography : ((raw['Overview'] as String?) ?? ''),
      born: sp?.birthday ?? jfPerson?.premiereDate,
      died: sp?.deathday ?? DateTime.tryParse((raw['EndDate'] as String?) ?? ''),
      place: sp?.placeOfBirth ?? ((raw['ProductionLocations'] as List?)?.firstOrNull as String?),
      knownFor: sp?.knownFor,
      imdbId: sp?.imdbId ?? jfPerson?.providerIds['imdb'],
      aka: sp?.alsoKnownAs ?? const [],
      library: library,
      credits: credits,
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<_PersonData>(
    future: _future,
    builder: (context, snap) {
      if (snap.hasError) return ErrorView('${snap.error}', onRetry: () => setState(() => _future = _load()));
      final d = snap.data;
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: d == null ? _Loading(name: widget.name) : _Body(d, key: const ValueKey('body')),
      );
    },
  );
}

class _Loading extends StatelessWidget {
  final String name;
  const _Loading({required this.name});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top + 90),
    child: Column(
      children: [
        const Skeleton(width: 150, height: 150, radius: 75),
        const SizedBox(height: 18),
        Text(name, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
        const SizedBox(height: 22),
        for (var i = 0; i < 4; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 5),
            child: Skeleton(height: 14, width: i == 3 ? 180 : double.infinity),
          ),
      ],
    ),
  );
}

class _Body extends StatelessWidget {
  final _PersonData d;
  const _Body(this.d, {super.key});

  static int _age(DateTime born, DateTime at) {
    var a = at.year - born.year;
    if (at.month < born.month || (at.month == born.month && at.day < born.day)) a--;
    return a;
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final top = MediaQuery.paddingOf(context).top;
    final wide = !isNarrow(context);
    final fmt = DateFormat('d MMMM y');
    final libIds = {for (final i in d.library) i.tmdbId};
    final known = [...d.credits.where((c) => c.media.posterPath != null)]
      ..sort((a, b) => ((b.media.raw['voteCount'] as num?) ?? 0).compareTo((a.media.raw['voteCount'] as num?) ?? 0));
    final dated = [...d.credits]..sort((a, b) => (b.media.year ?? 9999).compareTo(a.media.year ?? 9999));

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Stack(
            children: [
              // The photo, blown up and blurred, as a soft backdrop.
              if (d.photo != null)
                Positioned.fill(
                  child: ShaderMask(
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.white, Colors.transparent],
                    ).createShader(r),
                    blendMode: BlendMode.dstIn,
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 40, sigmaY: 40, tileMode: TileMode.decal),
                      child: Opacity(opacity: .55, child: NetImage(d.photo)),
                    ),
                  ),
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(pad, top + (wide ? 100 : 80), pad, 8),
                child: _Header(
                  wide: wide,
                  children: [
                    FadeIn(
                      from: const Offset(0, .1),
                      child: Container(
                        width: wide ? 220 : 156,
                        height: wide ? 220 : 156,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Hy.orange, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30, offset: Offset(0, 12))],
                        ),
                        child: ClipOval(
                          child: NetImage(d.photo, fallbackText: d.name, alignment: Alignment.topCenter),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      d.name,
                      textAlign: wide ? TextAlign.start : TextAlign.center,
                      style: TextStyle(fontSize: wide ? 46 : 30, fontWeight: FontWeight.w900, letterSpacing: -.5, height: 1.1),
                    ),
                    if (d.knownFor != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        d.knownFor == 'Acting' ? 'ACTOR' : d.knownFor!.toUpperCase(),
                        style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w800, letterSpacing: 2.5, fontSize: 12),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: wide ? WrapAlignment.start : WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (d.born != null)
                          _Fact(Icons.cake_outlined, d.died == null ? '${fmt.format(d.born!)} · age ${_age(d.born!, DateTime.now())}' : fmt.format(d.born!)),
                        if (d.died != null)
                          _Fact(Icons.local_florist_outlined, '${fmt.format(d.died!)}${d.born != null ? ' · aged ${_age(d.born!, d.died!)}' : ''}'),
                        if (d.place != null && d.place!.isNotEmpty) _Fact(Icons.place_outlined, d.place!),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: wide ? WrapAlignment.start : WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (d.imdbId != null)
                          FilledButton.icon(
                            onPressed: () => launchUrl(Uri.parse('https://www.imdb.com/name/${d.imdbId}/'), mode: LaunchMode.externalApplication),
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFFF5C518),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                            ),
                            icon: const Text('IMDb', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -.5)),
                            label: const Icon(Icons.open_in_new_rounded, size: 16),
                          ),
                        if (d.credits.isNotEmpty) _Stat('${d.credits.length}', 'credits'),
                        if (d.library.isNotEmpty) _Stat('${d.library.length}', 'on Hevyfin'),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (d.bio.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 22, pad, 0),
            sliver: SliverToBoxAdapter(
              child: FadeIn(
                delay: const Duration(milliseconds: 80),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 900), child: _Bio(d.bio)),
                ),
              ),
            ),
          ),
        if (d.aka.isNotEmpty)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 12, pad, 0),
            sliver: SliverToBoxAdapter(
              child: Text('Also known as ${d.aka.take(3).join(', ')}', style: const TextStyle(color: Hy.textMute, fontSize: 13)),
            ),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 26)),
        if (d.library.isNotEmpty)
          SliverToBoxAdapter(
            child: FadeIn(
              delay: const Duration(milliseconds: 140),
              child: MediaRow(
                title: 'On Hevyfin',
                height: posterWidth(context) * 1.5 + 14,
                children: [for (final i in d.library) PosterCard(i, width: posterWidth(context))],
              ),
            ),
          ),
        if (known.isNotEmpty)
          SliverToBoxAdapter(
            child: FadeIn(
              delay: const Duration(milliseconds: 200),
              child: MediaRow(
                title: 'Known For',
                height: posterWidth(context) * 1.5 + 52,
                children: [for (final c in known.take(16)) _KnownForCard(c, inLibrary: libIds.contains(c.media.tmdbId))],
              ),
            ),
          ),
        if (dated.isNotEmpty) ...[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 4, pad, 8),
            sliver: const SliverToBoxAdapter(
              child: Text('Filmography', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          SliverPadding(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 60),
            sliver: SliverList.builder(
              itemCount: dated.length,
              itemBuilder: (context, i) {
                final c = dated[i];
                final showYear = i == 0 || dated[i - 1].media.year != c.media.year;
                return _CreditTile(c, showYear: showYear, inLibrary: libIds.contains(c.media.tmdbId));
              },
            ),
          ),
        ] else
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Fact(this.icon, this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(20)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Hy.textDim),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

class _Stat extends StatelessWidget {
  final String value, label;
  const _Stat(this.value, this.label);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      border: Border.all(color: Hy.border),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: value,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          TextSpan(
            text: ' $label',
            style: const TextStyle(color: Hy.textDim),
          ),
        ],
      ),
    ),
  );
}

/// Biography that opens up on tap.
class _Bio extends StatefulWidget {
  final String text;
  const _Bio(this.text);
  @override
  State<_Bio> createState() => _BioState();
}

class _BioState extends State<_Bio> {
  bool _open = false;
  @override
  Widget build(BuildContext context) {
    final long = widget.text.length > 320;
    return GestureDetector(
      onTap: long ? () => setState(() => _open = !_open) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Biography', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Text(
              widget.text,
              maxLines: _open || !long ? null : 5,
              overflow: _open || !long ? null : TextOverflow.fade,
              style: const TextStyle(fontSize: 15, height: 1.55, color: Color(0xFFDDDDDD)),
            ),
          ),
          if (long)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _open ? 'Show less' : 'Read more',
                style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
    );
  }
}

void _openCredit(BuildContext context, SeerrMedia m) => openSeerr(context, m);

class _KnownForCard extends StatelessWidget {
  final SeerrCredit c;
  final bool inLibrary;
  const _KnownForCard(this.c, {required this.inLibrary});
  @override
  Widget build(BuildContext context) {
    final w = posterWidth(context);
    return SizedBox(
      width: w,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SeerrCard(c.media, width: w),
          const SizedBox(height: 6),
          Text(
            c.role?.isNotEmpty == true ? c.role! : c.media.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Hy.textDim, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _CreditTile extends StatelessWidget {
  final SeerrCredit c;
  final bool showYear, inLibrary;
  const _CreditTile(this.c, {required this.showYear, required this.inLibrary});
  @override
  Widget build(BuildContext context) {
    final m = c.media;
    final have = inLibrary || m.status == MediaStatus.available || m.status == MediaStatus.partial;
    return InkWell(
      onTap: () => _openCredit(context, m),
      borderRadius: BorderRadius.circular(Hy.radius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 52,
              child: Text(
                showYear ? '${m.year ?? 'Soon'}' : '',
                style: const TextStyle(color: Hy.textMute, fontWeight: FontWeight.w800),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.title,
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: have ? Hy.text : const Color(0xFFDDDDDD)),
                  ),
                  if (c.role?.isNotEmpty == true || c.episodes != null)
                    Text(
                      [
                        if (c.role?.isNotEmpty == true) c.role!,
                        if (m.isTv && c.episodes != null) '${c.episodes} episode${c.episodes == 1 ? '' : 's'}',
                      ].join(' · '),
                      style: const TextStyle(color: Hy.textDim, fontSize: 13),
                    ),
                ],
              ),
            ),
            if (have)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(Icons.play_circle_fill_rounded, color: Hy.orange, size: 22),
              )
            else if (m.status != MediaStatus.unknown)
              Padding(padding: const EdgeInsets.only(left: 8), child: StatusPill(m.status, compact: true))
            else
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  m.isTv ? 'TV' : 'FILM',
                  style: const TextStyle(color: Hy.textMute, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Opens a person from anywhere: by library id when we have one, else by TMDB id.
void openPerson(BuildContext context, {String? jellyfinId, int? tmdbId, required String name}) {
  final n = Uri.encodeComponent(name);
  if (jellyfinId != null) {
    context.push('/person/$jellyfinId?name=$n');
  } else if (tmdbId != null) {
    context.push('/person/tmdb/$tmdbId?name=$n');
  }
}

/// Phones: everything centred under the photo. Wide screens: photo left, details right.
class _Header extends StatelessWidget {
  final bool wide;
  final List<Widget> children;
  const _Header({required this.wide, required this.children});
  @override
  Widget build(BuildContext context) {
    if (!wide) return Column(children: children);
    // children[0] is the photo; the rest stack beside it.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        children.first,
        const SizedBox(width: 56),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children.skip(1).toList()),
        ),
      ],
    );
  }
}
