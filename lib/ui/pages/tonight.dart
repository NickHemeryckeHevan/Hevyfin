import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/jellyfin.dart';
import '../../api/niql.dart';
import '../../state/device.dart';
import '../../state/tonight.dart';
import '../../state/voice.dart';
import '../../theme.dart';
import '../shell.dart';
import '../widgets/billboard.dart';
import '../widgets/common.dart';

/// "What tonight?": ask the recommendation service (if any) in your own words, or tap a few choices and get three ideas
/// from the library.
class TonightPage extends StatefulWidget {
  /// A question to put to the recommendation service straight away (from Search).
  final String ask;
  const TonightPage({super.key, this.ask = ''});
  @override
  State<TonightPage> createState() => _TonightPageState();
}

class _TonightPageState extends State<TonightPage> {
  late final _question = TextEditingController(text: widget.ask);
  var _ask = const TonightAsk();

  /// The ideas on show, and where they came from.
  List<Item>? _picks;
  Map<String, String> _why = {};
  String? _niqlSays;
  bool _asking = false;
  bool _voice = false;

  /// Where the ideas start: the page scrolls there when they come in.
  final _results = GlobalKey();

  @override
  void initState() {
    super.initState();
    Voice.available().then((v) => mounted ? setState(() => _voice = v) : null);
    if (widget.ask.isNotEmpty && Niql.enabled) WidgetsBinding.instance.addPostFrameCallback((_) => _askNiql());
  }

  void _showResults() => WidgetsBinding.instance.addPostFrameCallback((_) {
    final ctx = _results.currentContext;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: .02, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  });

  @override
  void dispose() {
    _question.dispose();
    super.dispose();
  }

  Future<void> _surprise() async {
    final all = await jf(context).everything();
    if (!mounted) return;
    setState(() {
      _picks = pickTonight(all, _ask);
      _why = {};
      _niqlSays = null;
    });
    _showResults();
  }

  Future<void> _askNiql() async {
    final q = _question.text.trim();
    if (q.isEmpty || _asking) return;
    FocusScope.of(context).unfocus();
    setState(() => _asking = true);
    try {
      final c = jf(context);
      final a = await Niql.ask(c, q);
      final items = await c.itemsByIds([for (final p in a.picks) p.id]);
      if (!mounted) return;
      setState(() {
        _niqlSays = a.answer;
        _picks = items;
        _why = {for (final p in a.picks) p.id: p.why};
      });
      _showResults();
    } catch (e) {
      if (mounted) toast(context, '$e');
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  Future<void> _speak() async {
    final t = await Voice.listen(prompt: 'What do you feel like watching?');
    if (t == null || !mounted) return;
    _question.text = t;
    _askNiql();
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final narrow = isNarrow(context);
    Widget label(String t) => Padding(
      padding: EdgeInsets.fromLTRB(0, narrow ? 14 : 18, 0, 8),
      child: Text(
        t,
        style: const TextStyle(fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w800, color: Hy.textMute),
      ),
    );
    Widget chips<T>(List<T> values, T selected, String Function(T) name, ValueChanged<T> onPick) {
      final all = [
        for (final v in values) ChoiceChip(label: Text(name(v)), selected: v == selected, showCheckmark: false, onSelected: (_) => setState(() => onPick(v))),
      ];
      // Phones: one line per question, swiped sideways, so the ideas aren't pushed off the screen.
      if (!narrow) return Wrap(spacing: 8, runSpacing: 8, children: all);
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        child: Row(
          children: [
            for (final (i, c) in all.indexed) ...[if (i > 0) const SizedBox(width: 8), c],
          ],
        ),
      );
    }

    final picks = _picks;
    return ListView(
      padding: EdgeInsets.fromLTRB(pad, topInset(context) + 8, pad, 60),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What tonight?',
                  style: TextStyle(fontSize: narrow ? 30 : 40, fontWeight: FontWeight.w900, letterSpacing: -.5),
                ),
                const SizedBox(height: 4),
                Text(
                  Niql.enabled ? 'Ask in your own words, or pick a few things below.' : 'Pick a few things below.',
                  style: const TextStyle(color: Hy.textDim, fontSize: 15),
                ),
                const SizedBox(height: 18),
                // Ask (only with a recommendation service set up).
                if (Niql.enabled) Row(
                  children: [
                    if (_voice) ...[
                      IconButton.filledTonal(tooltip: 'Say it', onPressed: _asking ? null : _speak, icon: const Icon(Icons.mic_rounded)),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: TextField(
                        controller: _question,
                        onSubmitted: (_) => _askNiql(),
                        textInputAction: TextInputAction.send,
                        decoration: InputDecoration(
                          hintText: narrow ? 'Something funny, short…' : 'Something funny we haven’t seen, under two hours',
                          prefixIcon: const Icon(Icons.auto_awesome_rounded, color: Hy.orange),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton(
                      // As tall as the field beside it.
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                      onPressed: _asking ? null : _askNiql,
                      child: _asking
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Text('Ask'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                label('WHAT'),
                chips(
                  TonightKind.values,
                  _ask.kind,
                  (k) => switch (k) {
                    TonightKind.any => 'Anything',
                    TonightKind.film => 'A film',
                    TonightKind.series => 'A series',
                  },
                  (v) => _ask = TonightAsk(kind: v, length: _ask.length, mood: _ask.mood, kids: _ask.kids, unseen: _ask.unseen),
                ),
                label('HOW LONG'),
                chips(
                  TonightLength.values,
                  _ask.length,
                  (l) => switch (l) {
                    TonightLength.any => 'Any length',
                    TonightLength.short => 'Under 1½ hours',
                    TonightLength.medium => 'Under 2 hours',
                    TonightLength.long => 'A long one',
                  },
                  (v) => _ask = TonightAsk(kind: _ask.kind, length: v, mood: _ask.mood, kids: _ask.kids, unseen: _ask.unseen),
                ),
                label('MOOD'),
                chips(
                  TonightMood.values,
                  _ask.mood,
                  (m) => m.label,
                  (v) => _ask = TonightAsk(kind: _ask.kind, length: _ask.length, mood: v, kids: _ask.kids, unseen: _ask.unseen),
                ),
                label('WHO’S WATCHING'),
                chips(
                  [false, true],
                  _ask.kids,
                  (k) => k ? 'With kids' : 'Grown-ups',
                  (v) => _ask = TonightAsk(kind: _ask.kind, length: _ask.length, mood: _ask.mood, kids: v, unseen: _ask.unseen),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Switch(
                      value: _ask.unseen,
                      onChanged: (v) => setState(() => _ask = TonightAsk(kind: _ask.kind, length: _ask.length, mood: _ask.mood, kids: _ask.kids, unseen: v)),
                    ),
                    const SizedBox(width: 8),
                    const Text('Only things not seen yet'),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  autofocus: Device.isTv,
                  onPressed: _surprise,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                    minimumSize: narrow ? const Size.fromHeight(52) : null,
                  ),
                  icon: const Icon(Icons.casino_rounded),
                  label: Text(picks == null || _niqlSays != null ? 'Surprise me' : 'Shuffle again'),
                ),
                SizedBox(key: _results, height: 26),
                if (_niqlSays != null && _niqlSays!.isNotEmpty) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.auto_awesome_rounded, color: Hy.orange, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(_niqlSays!, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
                if (picks != null && picks.isEmpty)
                  const Text('Nothing in the library fits all of that. Try fewer choices.', style: TextStyle(color: Hy.textDim)),
                if (picks != null && picks.isNotEmpty)
                  FadeIn(
                    key: ValueKey(picks.map((p) => p.id).join()),
                    child: narrow
                        ? Column(
                            children: [
                              for (final p in picks)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 18),
                                  child: _PickCard(p, why: _why[p.id]),
                                ),
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (final (n, p) in picks.indexed) ...[if (n > 0) const SizedBox(width: 18), Expanded(child: _PickCard(p, why: _why[p.id]))],
                              for (var n = picks.length; n < 3; n++) ...[const SizedBox(width: 18), const Expanded(child: SizedBox.shrink())],
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
}

/// One idea: wide art, what it is, why (from the recommendation service) or what it's about, and Play.
class _PickCard extends StatelessWidget {
  final Item item;
  final String? why;
  const _PickCard(this.item, {this.why});
  @override
  Widget build(BuildContext context) {
    final c = jf(context);
    final mins = item.runtime?.inMinutes;
    final meta = [
      if (item.year != null) '${item.year}',
      if (mins != null && mins > 0) item.isSeries ? '${mins}m episodes' : (mins >= 60 ? '${mins ~/ 60}h ${mins % 60}m' : '${mins}m'),
      ...item.genres.take(2),
    ].join('  ·  ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HoverScale(
          scale: 1.03,
          onTap: () => context.push('/item/${item.id}'),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(Hy.radius),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(c.thumb(item, width: 900), fallbackText: item.name),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: [.45, 1],
                        colors: [Colors.transparent, Color(0xD9000000)],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 14,
                    right: 14,
                    bottom: 12,
                    child: Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.1, shadows: [Shadow(blurRadius: 10)]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          meta,
          style: const TextStyle(color: Hy.textDim, fontSize: 13, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        if (why != null && why!.isNotEmpty)
          Text('“$why”', style: const TextStyle(fontSize: 14.5, height: 1.4, fontStyle: FontStyle.italic))
        else
          Text(
            item.overview ?? '',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.4, color: Hy.textDim),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            PlayButton(item),
            OutlinedButton(onPressed: () => context.push('/item/${item.id}'), child: const Text('More info')),
          ],
        ),
      ],
    );
  }
}
