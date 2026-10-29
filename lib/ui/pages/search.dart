import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../api/niql.dart';
import '../../api/seerr.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../state/voice.dart';
import '../../theme.dart';
import '../shell.dart';
import '../widgets/common.dart';

/// Search the library; whatever isn't there can be requested from Seerr right below.
class SearchPage extends StatefulWidget {
  final String query;
  const SearchPage({super.key, this.query = ''});
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final _ctrl = TextEditingController(text: widget.query);
  Timer? _debounce;
  String _q = '';
  Future<List<Item>>? _library;
  Future<List<SeerrMedia>>? _seerr;
  bool _voice = false;

  @override
  void initState() {
    super.initState();
    if (widget.query.isNotEmpty) _run(widget.query);
    Voice.available().then((v) => mounted ? setState(() => _voice = v) : null);
  }

  /// Search by voice: the TV remote's microphone, or the phone's.
  Future<void> _speak() async {
    final t = await Voice.listen();
    if (t == null || !mounted) return;
    _ctrl.text = t;
    _run(t);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _run(v));
  }

  void _run(String v) {
    final q = v.trim();
    if (q == _q) return;
    final app = context.read<AppState>();
    setState(() {
      _q = q;
      if (q.isEmpty) {
        _library = null;
        _seerr = null;
        return;
      }
      _library = app.client!.items(search: q, limit: 60, sortBy: 'SortName');
      _seerr = app.seerrReady ? app.seerr!.search(q).then((r) => r.where((m) => m.status != MediaStatus.available).toList()) : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, topInset(context) + 8, pad, 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Row(
                children: [
                  if (_voice) ...[
                    // On a TV the remote lands here: OK, then speak.
                    IconButton.filledTonal(autofocus: Device.isTv, tooltip: 'Search by voice', onPressed: _speak, icon: const Icon(Icons.mic_rounded)),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      autofocus: !Device.isTv || !_voice,
                      onChanged: _changed,
                      onSubmitted: _run,
                      style: const TextStyle(fontSize: 18),
                      decoration: InputDecoration(
                        hintText: 'Titles, people, genres',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _ctrl.text.isEmpty
                            ? null
                            : IconButton(
                                onPressed: () {
                                  _ctrl.clear();
                                  _run('');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // TV: What tonight? lives here rather than in the menu.
        if (_q.isEmpty && Device.isTv)
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(pagePadding(context), 18, pagePadding(context), 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: HoverScale(
                  scale: 1.03,
                  radius: 14,
                  onTap: () => context.push('/tonight'),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(22, 18, 28, 18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(colors: [Hy.orange.withValues(alpha: .28), Hy.surfaceHigh]),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome_rounded, color: Hy.orange, size: 30),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('What should I watch tonight?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 2),
                            Text(
                              Niql.enabled ? 'A few picks for your mood, or just ask' : 'A few picks for your mood',
                              style: const TextStyle(color: Hy.textDim, fontSize: 15),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_q.isEmpty) const _GenreTiles() else ..._results(),
      ],
    );
  }

  List<Widget> _results() {
    final pad = pagePadding(context);
    Widget heading(String t) => SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(pad, 18, pad, 4),
        child: Text(t, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
    );
    return [
      // Questions ("something scary for tonight") go to the recommendation service instead.
      if (Niql.enabled) SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(pad, 8, pad, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => context.push('/tonight?ask=${Uri.encodeQueryComponent(_q)}'),
              icon: const Icon(Icons.auto_awesome_rounded, color: Hy.orange),
              label: Text('Ask: “$_q”', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ),
      ),
      heading('On Hevyfin'),
      FutureBuilder<List<Item>>(
        key: ValueKey('lib$_q'),
        future: _library,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const SliverToBoxAdapter(
              child: LinearProgressIndicator(color: Hy.orange, backgroundColor: Colors.transparent),
            );
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: pad, vertical: 8),
                child: Text('Nothing in your library matches "$_q".', style: const TextStyle(color: Hy.textDim)),
              ),
            );
          }
          return PosterGrid(padding: EdgeInsets.fromLTRB(pad, 8, pad, 10), children: [for (final i in items) PosterCard(i)]);
        },
      ),
      if (_seerr != null) ...[
        heading('Not on Hevyfin yet – request it'),
        FutureBuilder<List<SeerrMedia>>(
          key: ValueKey('seerr$_q'),
          future: _seerr,
          builder: (context, snap) {
            if (snap.hasError) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: Text('${snap.error}', style: const TextStyle(color: Hy.danger)),
                ),
              );
            }
            if (!snap.hasData) {
              return const SliverToBoxAdapter(
                child: LinearProgressIndicator(color: Hy.orange, backgroundColor: Colors.transparent),
              );
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: pad),
                  child: const Text('No other matches.', style: TextStyle(color: Hy.textDim)),
                ),
              );
            }
            return PosterGrid(children: [for (final m in items) SeerrCard(m)]);
          },
        ),
      ] else
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
            child: TextButton.icon(
              onPressed: () => context.go('/new'),
              icon: const Icon(Icons.link_rounded),
              label: const Text('Connect Seerr to request things that are missing'),
            ),
          ),
        ),
    ];
  }
}

class _GenreTiles extends StatelessWidget {
  const _GenreTiles();
  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    return Loader<List<Genre>>(
      sliver: true,
      load: () => jf(context).genres(),
      builder: (context, genres) => SliverPadding(
        padding: EdgeInsets.fromLTRB(pad, 16, pad, 40),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 260,
            childAspectRatio: 16 / 7,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
          ),
          delegate: SliverChildListDelegate([
            for (final g in genres)
              HoverScale(
                scale: 1.03,
                onTap: () => context.push('/genre/${Uri.encodeComponent(g.name)}'),
                child: Container(
                  decoration: BoxDecoration(gradient: Hy.gradientFor(g.name), borderRadius: BorderRadius.circular(Hy.radius)),
                  padding: const EdgeInsets.all(14),
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    g.name,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, shadows: [Shadow(blurRadius: 8)]),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
