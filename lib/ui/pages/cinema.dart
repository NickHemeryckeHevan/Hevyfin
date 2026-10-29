import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/device.dart';
import '../../state/live.dart' hide Clip;
import '../../state/live_store.dart';
import '../../theme.dart';
import '../shell.dart' show topInset;
import '../widgets/common.dart';
import '../widgets/live_switch.dart';
import 'live_player.dart';

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _inTime(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'in a moment';
  if (m < 60) return 'in $m min';
  return 'in ${m ~/ 60} h ${(m % 60).toString().padLeft(2, '0')}';
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _dayName(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  // Calendar days, not 24-hour spans (the clocks change in March and October).
  final diff = DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  return '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// Where a show is right now, in words.
String showStatus(Timeline t, DateTime now) {
  if (now.isBefore(t.start)) return 'Starts ${_inTime(t.start.difference(now))}';
  final pos = t.at(now);
  if (pos == null) return 'Ended';
  final s = t.steps[pos.index];
  switch (s.kind) {
    case StepKind.clip:
    case StepKind.bumper:
    case StepKind.countdown:
      return t.steps.skip(pos.index).any((x) => x.kind == StepKind.program) && !t.steps.take(pos.index).any((x) => x.kind == StepKind.program)
          ? 'Trailers now'
          : 'Starting';
    case StepKind.intermission:
      return 'Intermission';
    case StepKind.pause:
      return 'Break · ${(s.dur - pos.offset).inMinutes + 1} min left';
    case StepKind.program:
      final l = t.listingAt(now);
      final into = l == null ? 0 : now.difference(l.start).inMinutes;
      return '${t.listings().length > 1 ? '${l?.title} · ' : ''}$into min in';
  }
}

/// The Cinema tab: today's three screenings and marathons. Private viewings start from a
/// movie's page ("Cinema mode" next to Play).
class CinemaPage extends StatefulWidget {
  const CinemaPage({super.key});
  @override
  State<CinemaPage> createState() => _CinemaPageState();
}

class _CinemaPageState extends State<CinemaPage> {
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    context.read<LiveStore>().ensure();
    _minute = Timer.periodic(const Duration(seconds: 30), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LiveStore>();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final ready = store.pool != null;
    final todays = ready ? store.screeningsOn(today) : const <Timeline>[];
    final tomorrow = ready ? store.screeningsOn(DateTime(today.year, today.month, today.day + 1)) : const <Timeline>[];
    final marathonToday = store.marathons.where((m) => _dayName(m.start) == 'Today' && now.isBefore(m.show.end)).toList();
    final later = store.marathons.where((m) => !marathonToday.contains(m) && now.isBefore(m.show.end)).toList();

    return Scaffold(
      backgroundColor: Hy.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 40, 0, 40),
        children: [
          const Padding(padding: EdgeInsets.symmetric(horizontal: 64), child: LiveSwitch('/cinema')),
          const SizedBox(height: 28),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 64),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'HEVYFIN CINEMA',
                  style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: Hy.orange, fontStyle: FontStyle.italic),
                ),
                SizedBox(width: 16),
                Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Text(
                    'Trailers, a countdown and an intermission. Come in late and you miss the start.',
                    style: TextStyle(color: Hy.textDim, fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          if (!ready)
            store.error != null
                ? ErrorView("Couldn't load the cinema: ${store.error}", onRetry: store.ensure)
                : const Padding(
                    padding: EdgeInsets.all(60),
                    child: Center(child: CircularProgressIndicator(color: Hy.orange)),
                  )
          else ...[
            for (final m in marathonToday) _MarathonToday(marathon: m, now: now),
            const _Heading("Today's screenings"),
            SizedBox(
              height: 300,
              child: Row(
                children: [
                  const SizedBox(width: 64),
                  for (final (i, t) in todays.indexed) ...[
                    if (i > 0) const SizedBox(width: 18),
                    Expanded(
                      child: _ScreeningCard(timeline: t, now: now, autofocus: marathonToday.isEmpty && i == todays.indexWhere((x) => now.isBefore(x.end))),
                    ),
                  ],
                  const SizedBox(width: 64),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 64),
              child: Text(
                'Tomorrow  ·  ${[for (final t in tomorrow) '${_hm(t.start)} ${t.title}'].join('   ·   ')}',
                style: const TextStyle(color: Hy.textMute, fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            const _Heading('Marathons'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 64),
              child: Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final m in later) _MarathonChip(marathon: m),
                  FilledButton.icon(
                    onPressed: () => context.push('/cinema/marathon/new'),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Plan a marathon'),
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

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(64, 0, 64, 14),
    child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
  );
}

class _ScreeningCard extends StatelessWidget {
  final Timeline timeline;
  final DateTime now;
  final bool autofocus;
  const _ScreeningCard({required this.timeline, required this.now, this.autofocus = false});

  @override
  Widget build(BuildContext context) {
    final store = context.read<LiveStore>();
    final prog = timeline.steps.firstWhere((s) => s.kind == StepKind.program);
    final movie = store.movie(prog.itemId!);
    final ended = !now.isBefore(timeline.end);
    final live = !ended && !now.isBefore(timeline.start);
    final status = showStatus(timeline, now);
    return Opacity(
      opacity: ended ? .4 : 1,
      child: HoverScale(
        scale: 1.03,
        autofocus: autofocus,
        onTap: ended ? null : () => goLive(context, LiveKind.screening, timeline.id),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Hy.radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              NetImage(jf(context).image(prog.artId!, width: 900), fallbackText: timeline.title),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Color(0xF5000000), Color(0x11000000)],
                    stops: [.1, 1],
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(color: live ? Hy.orange : Colors.black87, borderRadius: BorderRadius.circular(4)),
                  child: Text(
                    _hm(timeline.start),
                    style: TextStyle(color: live ? Colors.black : Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(color: live ? Hy.orange : Hy.textDim, fontWeight: FontWeight.w900, letterSpacing: 2, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      timeline.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, height: 1.1),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      [
                        if (movie?.critic != null) '🍅 ${movie!.critic}%',
                        if (movie != null) formatRuntime(movie.runtime),
                        'ends ${_hm(timeline.end)}',
                      ].join('  ·  '),
                      style: const TextStyle(color: Hy.textDim, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MarathonToday extends StatelessWidget {
  final Marathon marathon;
  final DateTime now;
  const _MarathonToday({required this.marathon, required this.now});
  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final t = marathon.show;
    final started = !now.isBefore(t.start);
    return Padding(
      padding: const EdgeInsets.fromLTRB(64, 0, 64, 34),
      child: Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Hy.radius * 2),
          gradient: const LinearGradient(colors: [Color(0xFF3A1600), Hy.surface]),
        ),
        child: Row(
          children: [
            for (final id in marathon.movieIds.take(5))
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(width: 70, height: 105, child: NetImage(c.image(id, type: 'Primary', width: 160))),
                ),
              ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MARATHON TONIGHT',
                    style: TextStyle(color: Hy.orange, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 14),
                  ),
                  const SizedBox(height: 6),
                  Text(marathon.name, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(
                    '${_hm(t.start)} – ${_hm(t.end)}  ·  ${marathon.movieIds.length} movies  ·  ${showStatus(t, now)}',
                    style: const TextStyle(color: Hy.textDim, fontSize: 17),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              autofocus: true,
              onPressed: () => goLive(context, LiveKind.marathon, marathon.id),
              icon: Icon(started ? Icons.login_rounded : Icons.hourglass_top_rounded),
              label: Text(started ? 'Join' : 'Go to the waiting room'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => goLive(context, LiveKind.marathon, marathon.id, fromStart: true),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('Start from the beginning'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarathonChip extends StatelessWidget {
  final Marathon marathon;
  const _MarathonChip({required this.marathon});
  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: () => context.push('/cinema/marathon/${marathon.id}'),
    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(marathon.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
        Text('${_dayName(marathon.start)} ${_hm(marathon.start)} · ${marathon.movieIds.length} movies', style: const TextStyle(color: Hy.textDim)),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------------------

/// Plan or edit a marathon with the remote: name, day, start time, movies and breaks.
class MarathonEditor extends StatefulWidget {
  final String id;
  const MarathonEditor({super.key, required this.id});
  @override
  State<MarathonEditor> createState() => _MarathonEditorState();
}

class _MarathonEditorState extends State<MarathonEditor> {
  late final LiveStore _store = context.read<LiveStore>();
  late final Marathon? _orig = _store.marathon(widget.id);
  late final _name = TextEditingController(text: _orig?.name ?? 'Movie marathon');
  late DateTime _day;
  late int _minutes; // start, minutes after midnight
  late final List<String> _movies = [...?_orig?.movieIds];
  late final List<int> _breaks = [...?_orig?.breaks];
  late final List<int> _inter = [for (var i = 0; i < _movies.length; i++) i < (_orig?.intermissions.length ?? 0) ? _orig!.intermissions[i] : 0];

  @override
  void initState() {
    super.initState();
    final s = _orig?.start ?? DateTime.now().add(const Duration(hours: 1));
    _day = DateTime(s.year, s.month, s.day);
    _minutes = _orig == null ? 20 * 60 : s.hour * 60 + s.minute;
    _store.ensure().then((_) => mounted ? setState(() {}) : null);
  }

  DateTime get _start => DateTime(_day.year, _day.month, _day.day, _minutes ~/ 60, _minutes % 60);

  /// Moves a movie with its own intermission setting.
  void _move(int from, int to) => setState(() {
    _movies.insert(to, _movies.removeAt(from));
    _inter.insert(to, _inter.removeAt(from));
  });

  void _remove(int i) => setState(() {
    _movies.removeAt(i);
    _inter.removeAt(i);
    // Drop the break after it (or before it, for the last one).
    if (_breaks.isNotEmpty) _breaks.removeAt(i.clamp(0, _breaks.length - 1));
    _fixBreaks();
  });

  void _fixBreaks() {
    while (_inter.length < _movies.length) {
      _inter.add(0);
    }
    while (_breaks.length < _movies.length - 1) {
      _breaks.add(0);
    }
    if (_movies.isEmpty) _breaks.clear();
    while (_breaks.length > (_movies.length - 1).clamp(0, 1 << 20)) {
      _breaks.removeLast();
    }
  }

  Future<void> _addMovie() async {
    final pool = _store.pool;
    if (pool == null) return;
    final movies = [...pool.movies]..sort((a, b) => a.name.compareTo(b.name));
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Hy.surface,
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 640,
          height: MediaQuery.sizeOf(ctx).height * .8,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('Add a movie', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final (i, m) in movies.indexed)
                      ListTile(
                        autofocus: i == 0,
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: SizedBox(width: 34, height: 50, child: NetImage(jf(context).image(m.id, type: 'Primary', width: 80))),
                        ),
                        title: Text(m.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          [formatRuntime(m.runtime), if (m.critic != null) '🍅 ${m.critic}%', if (_movies.contains(m.id)) 'already in'].join(' · '),
                        ),
                        onTap: () => Navigator.pop(ctx, m.id),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) {
      setState(() {
        _movies.add(picked);
        _fixBreaks();
      });
    }
  }

  bool _saving = false;

  Future<void> _save() async {
    if (_movies.isEmpty) {
      toast(context, 'Add at least one movie');
      return;
    }
    setState(() => _saving = true);
    await _store.saveMarathon(
      id: _orig?.id,
      name: _name.text.trim().isEmpty ? 'Movie marathon' : _name.text.trim(),
      start: _start,
      movieIds: _movies,
      breaks: _breaks,
      intermissions: _inter,
    );
    if (!mounted) return;
    if (!Device.isTv) toast(context, 'Saved. It shows up on the TV\'s Cinema tab.');
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final pool = _store.pool;
    // The same show the TV will play, to know when it ends.
    final ends = pool == null
        ? _start
        : marathonShow('preview', '', _start, [for (final id in _movies) ?_store.movie(id)], _breaks, pool, intermissions: _inter).end;

    Widget stepper(String label, String value, VoidCallback minus, VoidCallback plus) => Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      children: [
        Text(label, style: const TextStyle(color: Hy.textDim)),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.outlined(onPressed: minus, icon: const Icon(Icons.remove_rounded)),
            SizedBox(
              width: 90,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
            ),
            IconButton.outlined(onPressed: plus, icon: const Icon(Icons.add_rounded)),
          ],
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Hy.bg,
      body: pool == null
          ? const Center(child: CircularProgressIndicator(color: Hy.orange))
          : ListView(
              padding: EdgeInsets.fromLTRB(pagePadding(context), Device.isTv ? 40 : topInset(context) + 12, pagePadding(context), 60),
              children: [
                Text(_orig == null ? 'Plan a marathon' : 'Edit marathon', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900)),
                const SizedBox(height: 24),
                const Text('Day', style: TextStyle(color: Hy.textDim)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < 14; i++)
                      ChoiceChip(
                        label: Text(_dayName(DateTime(today.year, today.month, today.day + i))),
                        selected: _day == DateTime(today.year, today.month, today.day + i),
                        onSelected: (_) => setState(() => _day = DateTime(today.year, today.month, today.day + i)),
                      ),
                  ],
                ),
                const SizedBox(height: 22),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 30,
                  runSpacing: 10,
                  children: [
                    stepper(
                      'Starts at',
                      _hm(_start),
                      () => setState(() => _minutes = (_minutes - 15) % (24 * 60)),
                      () => setState(() => _minutes = (_minutes + 15) % (24 * 60)),
                    ),
                    Text(
                      _movies.isEmpty ? '' : 'Ends around ${_hm(ends)}${ends.day != _start.day ? ' (next day)' : ''}',
                      style: const TextStyle(color: Hy.orange, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
                const SizedBox(height: 30),
                const Text('Movies', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                const Text(
                  'Breaks are up to you: an intermission halfway through a movie, a break between movies, both or neither.',
                  style: TextStyle(color: Hy.textDim),
                ),
                const SizedBox(height: 12),
                for (final (i, id) in _movies.indexed) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Hy.surface, borderRadius: BorderRadius.circular(Hy.radius)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${i + 1}',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Hy.orange),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                '${_store.movie(id)?.name ?? '?'}  ·  ${formatRuntime(_store.movie(id)?.runtime)}',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(tooltip: 'Earlier', onPressed: i == 0 ? null : () => _move(i, i - 1), icon: const Icon(Icons.arrow_upward_rounded)),
                            IconButton(
                              tooltip: 'Later',
                              onPressed: i == _movies.length - 1 ? null : () => _move(i, i + 1),
                              icon: const Icon(Icons.arrow_downward_rounded),
                            ),
                            IconButton(tooltip: 'Remove', onPressed: () => _remove(i), icon: const Icon(Icons.close_rounded)),
                          ],
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 30, top: 4),
                          child: stepper(
                            'Intermission halfway',
                            _inter[i] == 0 ? 'None' : '${_inter[i]} min',
                            () => setState(() => _inter[i] = (_inter[i] - 5).clamp(0, 30)),
                            () => setState(() => _inter[i] = (_inter[i] + 5).clamp(0, 30)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (i < _breaks.length)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(40, 8, 0, 8),
                      child: stepper(
                        'Break before the next movie',
                        _breaks[i] == 0 ? 'None' : '${_breaks[i]} min',
                        () => setState(() => _breaks[i] = (_breaks[i] - 5).clamp(0, 60)),
                        () => setState(() => _breaks[i] = (_breaks[i] + 5).clamp(0, 60)),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(onPressed: _addMovie, icon: const Icon(Icons.add_rounded), label: const Text('Add movie')),
                const SizedBox(height: 28),
                // Below the rest, so the remote doesn't land on it (and pop up the keyboard) first.
                SizedBox(
                  width: 520,
                  child: TextField(
                    controller: _name,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(labelText: 'Name'),
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.check_rounded), label: Text(_saving ? 'Saving…' : 'Save')),
                    if (_orig != null) ...[
                      const SizedBox(width: 14),
                      TextButton.icon(
                        onPressed: () async {
                          await _store.deleteMarathon(_orig.id);
                          if (context.mounted) context.pop();
                        },
                        icon: const Icon(Icons.delete_outline_rounded, color: Hy.danger),
                        label: const Text('Delete', style: TextStyle(color: Hy.danger)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
    );
  }
}

/// Phone and computer: plan marathons here, watch them on the TV's Cinema tab.
class MarathonsPage extends StatefulWidget {
  const MarathonsPage({super.key});
  @override
  State<MarathonsPage> createState() => _MarathonsPageState();
}

class _MarathonsPageState extends State<MarathonsPage> {
  @override
  void initState() {
    super.initState();
    final store = context.read<LiveStore>();
    store.ensure().then((_) => store.syncMarathons(force: true));
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LiveStore>();
    final now = DateTime.now();
    final list = store.marathons.where((m) => now.isBefore(m.show.end)).toList();
    final pad = pagePadding(context);
    final c = jf(context);
    return Scaffold(
      backgroundColor: Hy.bg,
      floatingActionButton: store.pool == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.push('/cinema/marathon/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Plan a marathon'),
            ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(pad, topInset(context) + 12, pad, 100),
        children: [
          const Text('Movie marathons', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
            'Plan one here and it shows up on the TV\'s Cinema tab. At the start time the TV offers to start it: trailers, then the movies with your breaks in between.',
            style: TextStyle(color: Hy.textDim, height: 1.4),
          ),
          const SizedBox(height: 22),
          if (store.pool == null && store.error == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(color: Hy.orange),
              ),
            ),
          if (store.error != null) Text(store.error!, style: const TextStyle(color: Hy.danger)),
          if (store.pool != null && list.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text('Nothing planned yet.', style: TextStyle(color: Hy.textMute, fontSize: 16)),
              ),
            ),
          for (final m in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Hy.surface,
                borderRadius: BorderRadius.circular(Hy.radius * 2),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => context.push('/cinema/marathon/${m.id}'),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(m.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                            ),
                            Text(
                              showStatus(m.show, now),
                              style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_dayName(m.start)}  ·  ${_hm(m.show.start)} – ${_hm(m.show.end)}  ·  ${m.movieIds.length} movies',
                          style: const TextStyle(color: Hy.textDim),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 96,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final id in m.movieIds)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: SizedBox(
                                      width: 64,
                                      child: NetImage(c.image(id, type: 'Primary', width: 160), fallbackText: store.movie(id)?.name),
                                    ),
                                  ),
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
        ],
      ),
    );
  }
}
