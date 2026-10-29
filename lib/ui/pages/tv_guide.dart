import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/live.dart';
import '../../state/free_tv.dart';
import '../../state/live_store.dart';
import '../../theme.dart';
import '../widgets/common.dart';
import '../widgets/live_switch.dart';
import '../widgets/live_bumpers.dart';
import 'live_player.dart';

/// The TV tab: three channels, what's on now and next. OK on a channel tunes in.
class TvGuidePage extends StatefulWidget {
  const TvGuidePage({super.key});
  @override
  State<TvGuidePage> createState() => _TvGuidePageState();
}

class _TvGuidePageState extends State<TvGuidePage> {
  Timer? _minute;

  @override
  void initState() {
    super.initState();
    context.read<LiveStore>().ensure();
    _loadFree();
    _minute = Timer.periodic(const Duration(seconds: 30), (_) {
      setState(() {});
      _loadFree();
    });
  }

  @override
  void dispose() {
    _minute?.cancel();
    super.dispose();
  }

  Future<void> _loadFree() async {
    try {
      await FreeTv.load(jf(context));
      if (mounted) setState(() {});
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<LiveStore>();
    final now = DateTime.now();
    final days = store.pool == null ? const <Timeline>[] : store.channelsAt(now);
    return Scaffold(
      backgroundColor: Hy.bg,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(64, 40, 64, 40),
        children: [
          const LiveSwitch('/tv'),
          const SizedBox(height: 28),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('TV', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
              const SizedBox(width: 16),
              const Padding(
                padding: EdgeInsets.only(bottom: 6),
                child: Text('Always on. Join whenever, it carries on where it is.', style: TextStyle(color: Hy.textDim, fontSize: 18)),
              ),
              const Spacer(),
              Text(
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 26),
          if (store.error != null && store.pool == null)
            ErrorView("Couldn't load the schedule: ${store.error}", onRetry: store.ensure)
          else if (days.isEmpty)
            const Padding(
              padding: EdgeInsets.all(60),
              child: Center(child: CircularProgressIndicator(color: Hy.orange)),
            )
          else
            _Grid(rows: [..._ownRows(context, days, now), ..._freeRows(context, now)], now: now),
        ],
      ),
    );
  }
}

/// One line of the guide: a channel and what's on it.
class _Row {
  final Widget ident;
  final List<Listing> shows;
  final VoidCallback tune;

  /// Gets the channel ready while the remote rests on its line.
  final VoidCallback? warm;
  const _Row(this.ident, this.shows, this.tune, {this.warm});
}

/// Hevyfin's own channels (1-4).
List<_Row> _ownRows(BuildContext context, List<Timeline> days, DateTime now) => [
  for (final (i, t) in days.indexed)
    _Row(
      _Ident(
        number: channels[i].number,
        name: channels[i].nameAt(now),
        logo: FittedBox(
          child: ChannelIdent(number: channels[i].number, night: Channel.isNight(now)),
        ),
      ),
      t.listings(),
      () => goLive(context, LiveKind.channel, '${channels[i].number}'),
    ),
];

/// The free channels (5 and up), from Jellyfin Live TV.
List<_Row> _freeRows(BuildContext context, DateTime now) {
  final c = jf(context);
  return [
    for (final ch in FreeTv.channels)
      _Row(
        _Ident(
          number: int.tryParse(ch.channelNumber ?? '') ?? 0,
          name: ch.name,
          logo: ch.imageTags['Primary'] == null
              ? Text(
                  ch.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
                )
              : Image.network(c.image(ch.id, type: 'Primary', width: 240), height: 40, fit: BoxFit.contain),
        ),
        [
          for (final p in FreeTv.on(ch.id))
            if (p.startDate != null && p.endDate != null) Listing(p.name, p.episodeTitle ?? '', null, null, p.startDate!, p.endDate!),
        ],
        () => context.push('/freetv/${ch.id}'),
        warm: () => FreeTv.stream(c, ch.id).ignore(),
      ),
  ];
}

class _Ident extends StatelessWidget {
  final int number;
  final String name;
  final Widget logo;
  const _Ident({required this.number, required this.name, required this.logo});
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: Hy.surface, borderRadius: BorderRadius.circular(Hy.radius)),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 40, child: Center(child: logo)),
        const SizedBox(height: 6),
        Text(
          '$number  $name',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w700, fontSize: 12.5),
        ),
      ],
    ),
  );
}

/// The guide, like a TV's: channels down the side, time across (about three hours on screen,
/// scrolling on through the day as the remote moves right), programmes as long as they last,
/// and an orange line at the time it is now.
class _Grid extends StatelessWidget {
  final List<_Row> rows;
  final DateTime now;
  const _Grid({required this.rows, required this.now});

  static const _identW = 150.0, _rowH = 96.0, _gap = 10.0, _ruler = 30.0, _hours = 12;

  @override
  Widget build(BuildContext context) {
    // From about 20 minutes ago (on a quarter hour), so what's on now has room to read.
    final back = now.subtract(const Duration(minutes: 20));
    final from = DateTime(back.year, back.month, back.day, back.hour, back.minute - back.minute % 15);
    final to = from.add(const Duration(hours: _hours));
    return LayoutBuilder(
      builder: (context, box) {
        final perHour = (box.maxWidth - _identW - 12) / 3;
        final width = perHour * _hours;
        double x(DateTime t) => (t.difference(from).inSeconds / 3600).clamp(0.0, _hours.toDouble()) * perHour;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // The channels stay put while the time scrolls.
            SizedBox(
              width: _identW,
              child: Column(
                children: [
                  const SizedBox(height: _ruler),
                  for (final (i, r) in rows.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: _gap),
                      child: SizedBox(
                        height: _rowH,
                        child: HoverScale(autofocus: i == 0, onTap: r.tune, onFocus: (v) => v ? r.warm?.call() : null, child: r.ident),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                clipBehavior: ui.Clip.hardEdge,
                child: SizedBox(
                  width: width,
                  child: Stack(
                    clipBehavior: ui.Clip.none,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Half-hour marks.
                          SizedBox(
                            height: _ruler,
                            width: width,
                            child: Stack(
                              children: [
                                for (var m = (30 - from.minute % 30) % 30; m < _hours * 60; m += 30)
                                  Positioned(
                                    left: x(from.add(Duration(minutes: m))),
                                    child: Text(
                                      _hm(from.add(Duration(minutes: m))),
                                      style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (final r in rows)
                            Padding(
                              padding: const EdgeInsets.only(bottom: _gap),
                              child: SizedBox(
                                height: _rowH,
                                width: width,
                                child: Stack(
                                  children: [
                                    for (final l in r.shows.where((l) => l.end.isAfter(from) && l.start.isBefore(to)))
                                      Positioned(
                                        left: x(l.start),
                                        width: (x(l.end) - x(l.start) - 6).clamp(24.0, double.infinity),
                                        top: 0,
                                        bottom: 0,
                                        child: _Show(
                                          l,
                                          onFocus: r.warm,
                                          on: !now.isBefore(l.start) && now.isBefore(l.end),
                                          art: l.artId == null ? null : jf(context).image(l.artId!, width: 600),
                                          onTap: () {
                                            if (!now.isBefore(l.start) && now.isBefore(l.end)) {
                                              r.tune();
                                            } else {
                                              toast(context, '${l.title} starts at ${_hm(l.start)}');
                                            }
                                          },
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                      // Now.
                      Positioned(
                        left: x(now) - 1,
                        top: _ruler - 8,
                        bottom: _gap,
                        child: IgnorePointer(
                          child: Column(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: const BoxDecoration(color: Hy.orange, shape: BoxShape.circle),
                              ),
                              Expanded(child: Container(width: 2, color: Hy.orange)),
                            ],
                          ),
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

class _Show extends StatelessWidget {
  final Listing l;
  final bool on;
  final String? art;
  final VoidCallback onTap;
  final VoidCallback? onFocus;
  const _Show(this.l, {required this.on, required this.art, required this.onTap, this.onFocus});

  @override
  Widget build(BuildContext context) => HoverScale(
    scale: 1.03,
    onTap: onTap,
    onFocus: (v) => v && on ? onFocus?.call() : null,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(Hy.radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: on ? Hy.surfaceHigh : Hy.surface),
          if (on && art != null) Opacity(opacity: .35, child: NetImage(art)),
          if (on)
            const DecoratedBox(
              decoration: BoxDecoration(gradient: LinearGradient(colors: [Color(0xE6000000), Color(0x33000000)])),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${_hm(l.start)} – ${_hm(l.end)}',
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(color: on ? Hy.orange : Hy.textDim, fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
                const SizedBox(height: 3),
                Text(
                  l.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                if (l.sub.isNotEmpty)
                  Text(
                    l.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Hy.textDim, fontSize: 13),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
