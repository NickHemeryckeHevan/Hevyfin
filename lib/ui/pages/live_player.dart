import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart' hide Step;
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../state/free_tv.dart';
import '../../state/live.dart';
import '../../state/live_store.dart';
import '../../theme.dart';
import '../player.dart' show TracksSheet, mpvLangs, langMatches, ensureAudio, currentAid;
import '../widgets/common.dart' show formatRuntime;
import '../widgets/live_bumpers.dart';
import '../widgets/screensaver.dart';
import '../../host.dart';
import '../mpv/mpv.dart';

/// What the live player shows.
enum LiveKind { channel, screening, marathon, movie }

/// Plays a [Timeline] on the clock: channels, cinema screenings, marathons and private
/// viewings. One player for every step (clips, programs), the app's own bumpers drawn on
/// top. Live shows can't be paused or skipped; joining late starts where the show is now.
/// A private viewing (or a marathon started from the top) follows its own clock instead,
/// so it can be paused and trailers skipped.
class LivePlayerPage extends StatefulWidget {
  final LiveKind kind;
  final String id;
  final bool fromStart;
  const LivePlayerPage({super.key, required this.kind, required this.id, this.fromStart = false});
  @override
  State<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends State<LivePlayerPage> with WidgetsBindingObserver {
  late final AppState _app = context.read<AppState>();
  late final LiveStore _store = context.read<LiveStore>();
  JellyfinClient get _c => _app.client!;

  late final Player _player = Player(
    configuration: const PlayerConfiguration(title: 'Hevyfin', bufferSize: 32 << 20, libass: false),
  );
  late final VideoController _video = VideoController(
    _player,
    configuration: Device.isTv
        ? const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec')
        : VideoControllerConfiguration(hwdec: Host.isAndroid ? 'mediacodec-copy' : null),
  );

  Timeline? _tl;
  late int _channel = widget.kind == LiveKind.channel ? int.tryParse(widget.id) ?? 1 : 0;
  late final bool _private = widget.kind == LiveKind.movie || widget.fromStart;
  String? _error;

  int _index = -1;
  Step? _step;
  DateTime? _enteredAt;
  int _gen = 0;
  bool _ended = false;
  bool _waiting = false;
  DateTime? _pausedAt;
  Timer? _tick;
  int _ticks = 0;

  // Jellyfin's resume/watched state for programs.
  PlaybackInfo? _info;
  bool _reported = false;
  List<SubtitleTrack> _externalSubs = const [];

  /// Movie details for the feature intro (cast, year).
  final Map<String, Future<Item>> _details = {};

  /// Library posters the break screen turns over.
  late final List<String> _posters = [
    for (final m in [...?_store.pool?.movies]..shuffle()) _c.image(m.id, type: 'Primary', width: 600),
  ];

  bool _banner = false;
  Timer? _bannerTimer;
  bool _blackout = false;
  bool _sheetOpen = false;

  /// Phones and computers (private viewings only) use taps and clicks instead of a remote.
  static final _touch = !Device.isTv;
  static final _phone = _touch && Host.isAndroid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    Screensaver.players.value++;
    // So zapping past channel 4 knows the free channels.
    if (widget.kind == LiveKind.channel) WidgetsBinding.instance.addPostFrameCallback((_) => FreeTv.load(_c).catchError((_) {}));
    if (_phone) SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    _player.stream.completed.listen((done) {
      // A clip that ends a moment before the schedule says: in a private show, move on.
      if (done && _private && _step != null && _step!.isVideo) _skipStep();
    });
    _player.stream.track.listen(_onTrack);
    // Let the Video widget mount before mpv starts (mediacodec_embed needs its surface).
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      await _store.ensure();
      final tl = _timeline(DateTime.now());
      if (tl == null) {
        setState(() => _error = _store.error ?? "This show isn't on the schedule any more.");
        return;
      }
      _tl = tl;
      if (widget.kind == LiveKind.channel) _showBanner();
      _sync();
      _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _sync());
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Timeline? _timeline(DateTime now) {
    switch (widget.kind) {
      case LiveKind.channel:
        return _store.channel(_channel, now);
      case LiveKind.screening:
        return _store.screening(widget.id);
      case LiveKind.marathon:
        final m = _store.marathon(widget.id)?.show;
        if (m == null) return null;
        return widget.fromStart ? Timeline(m.id, m.title, now, m.steps) : m;
      case LiveKind.movie:
        final movie = _store.movie(widget.id);
        final pool = _store.pool;
        return movie == null || pool == null ? null : privateShow(movie, pool, now);
    }
  }

  /// Work out what should be on now and switch to it.
  void _sync() {
    if (!mounted || _pausedAt != null) return;
    final now = DateTime.now();
    var tl = _tl;
    if (tl == null) return;
    var pos = tl.at(now);
    if (pos == null && !now.isBefore(tl.start) && widget.kind == LiveKind.channel) {
      // 06:00: on to the next broadcast day.
      _store.ensure();
      final next = _timeline(now);
      if (next != null && next.id != tl.id) {
        _tl = tl = next;
        _index = -1;
        pos = tl.at(now);
      }
    }
    if (pos == null) {
      final waiting = now.isBefore(tl.start);
      if (waiting != _waiting || _ended != !waiting) {
        setState(() {
          _waiting = waiting;
          _ended = !waiting;
        });
        if (_ended) {
          _leaveStep();
          if (widget.kind != LiveKind.channel) _keepTicket(tl);
        }
      }
      return;
    }
    if (_waiting) setState(() => _waiting = false);
    if (pos.index != _index) {
      _enter(pos.index, pos.offset);
      return;
    }
    final s = _step!;
    if (!s.isVideo || _enteredAt == null) return;
    if (++_ticks % 8 != 0) return; // every 2 s
    final since = now.difference(_enteredAt!);
    final actual = _player.state.position;
    if (since < const Duration(seconds: 4) || _player.state.duration == Duration.zero) return;
    final expected = s.from + pos.offset;
    final drift = actual - expected;
    if (_private) {
      // Our own show waits for the video (buffering), so move the clock instead.
      if (drift.abs() > const Duration(seconds: 1)) tl.start = tl.start.add(-drift);
    } else if (drift.abs() > const Duration(seconds: 5) && !_player.state.buffering) {
      // Live: catch up with the broadcast.
      _player.seek(expected);
    }
  }

  Future<void> _enter(int i, Duration offset) async {
    final tl = _tl!;
    final s = tl.steps[i];
    final prev = _step;
    final gen = ++_gen;
    // The second half of a movie (after the intermission) reuses the same stream.
    if (prev == null || prev.itemId != s.itemId || !s.isVideo) await _leaveStep();
    setState(() {
      _index = i;
      _step = s;
      _enteredAt = DateTime.now();
    });
    if (s.kind == StepKind.program && widget.kind == LiveKind.channel && offset < const Duration(seconds: 3)) _showBanner();
    try {
      if (s.isVideo) {
        await _openVideo(s, s.from + offset, gen);
      } else {
        await _player.stop();
        if (gen != _gen) return;
        final sound = switch (s.kind) {
          StepKind.countdown when offset < const Duration(seconds: 1) => 'sting.ogg',
          StepKind.bumper when (s.tag == 'ident' || s.tag == 'feature' || (s.tag ?? '').startsWith('ch')) && offset < const Duration(seconds: 1) => 'sting.ogg',
          _ => null,
        };
        if (sound != null) await _player.open(Media('asset:///assets/live/$sound', start: offset));
      }
    } catch (e) {
      debugPrint('live step failed: $e');
    }
  }

  Future<void> _openVideo(Step s, Duration at, int gen) async {
    final id = s.itemId!;
    final mbps = _app.maxMbps;
    final info = await _c.playbackInfo(id, maxBitrate: mbps > 0 ? mbps * 1000000 : null);
    if (gen != _gen || !mounted) return;
    if (s.kind == StepKind.program) {
      await mpvSet(_player, 'alang', mpvLangs(_app.audioLang));
      await mpvSet(_player, 'slang', _app.subtitleLang.isEmpty ? '' : mpvLangs(_app.subtitleLang));
      await mpvSet(_player, 'sid', _app.subtitleLang.isEmpty ? 'no' : 'auto');
    } else {
      await mpvSet(_player, 'sid', 'no');
    }
    await _player.open(Media(_c.streamUrl(id, info), start: at));
    unawaited(ensureAudio(_player, _app.audioLang));
    if (gen != _gen) return;
    if (s.kind == StepKind.program) {
      // Never reported to Jellyfin: a channel, screening, marathon or cinema showing must not
      // move anyone's place in a show, Continue Watching, Next Up or what counts as watched.
      _info = info;
      _reported = true;
      _externalSubs = [
        for (final x in info.streams.where((x) => x.type == 'Subtitle' && (x.isExternal || info.isTranscode) && x.isText))
          SubtitleTrack.uri(_c.subtitleUrl(id, info, x), title: x.title, language: x.language),
      ];
      if (info.isTranscode && _app.subtitleLang.isNotEmpty) {
        final want = info.streams.where((x) => x.type == 'Subtitle' && x.isText && langMatches(x.language, _app.subtitleLang));
        if (want.isNotEmpty) {
          await _player.setSubtitleTrack(SubtitleTrack.uri(_c.subtitleUrl(id, info, want.first), title: want.first.title, language: want.first.language));
        }
      }
    } else {
      _info = null;
      _externalSubs = const [];
    }
  }

  static const _imageSubs = {'hdmv_pgs_subtitle', 'pgs', 'dvd_subtitle', 'dvdsub', 'vobsub', 'dvb_subtitle'};

  /// Flutter draws text subtitles; mpv only draws picture ones (as in the normal player).
  Future<void> _onTrack(Track t) async {
    if (!hasMpv(_player)) return;
    final image = _imageSubs.contains((t.subtitle.codec ?? '').toLowerCase());
    await mpvSet(_player, 'sub-visibility', image ? 'yes' : 'no');
  }

  /// A showing that ran to the end leaves a ticket stub in the collection (once).
  Future<void> _keepTicket(Timeline tl) async {
    try {
      final all = await tickets(_c);
      if (all.any((t) => t['id'] == tl.id)) return;
      all.add({
        'id': tl.id,
        'title': tl.title,
        'when': tl.start.toIso8601String(),
        'seat': seatFor(tl.id),
        'art': ?tl.steps.where((s) => s.kind == StepKind.program).firstOrNull?.artId,
      });
      await _c.setSharedPref('tickets', jsonEncode(all));
    } catch (_) {}
  }

  Future<void> _leaveStep() async {
    final s = _step, info = _info;
    if (s != null && info != null && _reported) {
      _reported = false;
      _info = null;
      await _c.endTranscode(info);
    }
  }

  // ---- remote ----

  void _showBanner() {
    setState(() => _banner = true);
    _bannerTimer?.cancel();
    _bannerTimer = Timer(const Duration(seconds: 5), () => mounted ? setState(() => _banner = false) : null);
  }

  void _hideBanner() {
    _bannerTimer?.cancel();
    setState(() => _banner = false);
  }

  /// Private shows only: jump the clock to the end of this step.
  void _skipStep() {
    final tl = _tl, now = DateTime.now();
    final pos = tl?.at(now);
    if (tl == null || pos == null) return;
    tl.start = tl.start.subtract(tl.steps[pos.index].dur - pos.offset);
    _sync();
  }

  void _togglePause() {
    final tl = _tl;
    if (tl == null) return;
    if (_pausedAt == null) {
      _pausedAt = DateTime.now();
      _player.pause();
      _showBanner();
      _bannerTimer?.cancel();
    } else {
      tl.start = tl.start.add(DateTime.now().difference(_pausedAt!));
      _pausedAt = null;
      if (_step?.isVideo ?? false) _player.play();
      _showBanner();
    }
    setState(() {});
  }

  void _seekBy(int seconds) {
    final tl = _tl, s = _step;
    if (tl == null || s == null || s.kind != StepKind.program) return;
    final pos = tl.at(DateTime.now());
    if (pos == null) return;
    final target = pos.offset + Duration(seconds: seconds);
    if (target.isNegative || target >= s.dur) return;
    tl.start = tl.start.subtract(Duration(seconds: seconds));
    _player.seek(s.from + target);
    _showBanner();
  }

  void _zap(int dir) {
    // Past channel 4 (or below 1) it carries on into the free channels (5 and up).
    final free = FreeTv.channels;
    if (free.isNotEmpty && ((dir > 0 && _channel == channels.length) || (dir < 0 && _channel == 1))) {
      context.pushReplacement('/freetv/${(dir > 0 ? free.first : free.last).id}');
      return;
    }
    _channel = (_channel - 1 + dir) % channels.length + 1;
    final tl = _timeline(DateTime.now());
    if (tl == null) return;
    setState(() => _blackout = true);
    Future.delayed(const Duration(milliseconds: 350), () => mounted ? setState(() => _blackout = false) : null);
    _tl = tl;
    _index = -1;
    _step = null;
    _leaveStep();
    _sync();
    _showBanner();
  }

  Future<void> _tracks() async {
    if (_sheetOpen || _step?.kind != StepKind.program) return;
    _sheetOpen = true;
    final aid = await currentAid(_player);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Hy.surface,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => TracksSheet(player: _player, external: _externalSubs, aid: aid),
    ).whenComplete(() => _sheetOpen = false);
  }

  /// OK on the remote, or a tap: pause the movie, skip trailers and breaks, else show what's on.
  void _ok() {
    final s = _step;
    if (!_private || s == null) {
      _showBanner();
    } else if (s.kind == StepKind.program) {
      _togglePause();
    } else if (s.kind != StepKind.countdown) {
      _skipStep();
    }
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    final k = e.logicalKey;
    final ok = k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.gameButtonA;
    // Holding OK: subtitles and audio.
    if (e is KeyRepeatEvent && ok) {
      _tracks();
      return KeyEventResult.handled;
    }
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (ok || k == LogicalKeyboardKey.mediaPlayPause || k == LogicalKeyboardKey.space) {
      _ok();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape && _touch) {
      context.pop();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      widget.kind == LiveKind.channel ? _zap(1) : _showBanner();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      widget.kind == LiveKind.channel ? _zap(-1) : _showBanner();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      _private ? _seekBy(k == LogicalKeyboardKey.arrowLeft ? -10 : 10) : _showBanner();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _player.pause();
    if (state == AppLifecycleState.resumed && !_private) {
      // Back on the air where the broadcast is now.
      _index = -1;
      _sync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Screensaver.players.value--;
    _tick?.cancel();
    _bannerTimer?.cancel();
    _leaveStep();
    _player.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_phone) SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }

  // ---- screen ----

  @override
  Widget build(BuildContext context) {
    final s = _step;
    final tl = _tl;
    final now = DateTime.now();
    final night = Channel.isNight(now);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Always mounted, so mpv has its surface before anything plays.
            Video(
              controller: _video,
              fill: Colors.black,
              controls: NoVideoControls,
              subtitleViewConfiguration: SubtitleViewConfiguration(
                visible: s?.kind == StepKind.program,
                style: TextStyle(
                  fontSize: (MediaQuery.sizeOf(context).shortestSide * .062).clamp(16.0, 40.0),
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                  shadows: const [
                    Shadow(blurRadius: 8),
                    Shadow(offset: Offset(1, 1), blurRadius: 2),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(32, 0, 32, 28),
                textScaler: TextScaler.noScaling,
              ),
            ),
            // Drawn for the TV's 1440-wide layout and scaled to fit phones and computers.
            Positioned.fill(
              child: LiveStage(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_error != null)
                      _Message(title: "Can't tune in", text: _error!)
                    else if (tl == null)
                      const Center(child: CircularProgressIndicator(color: Hy.orange))
                    else if (_waiting)
                      WaitingRoom(
                        title: tl.title,
                        start: tl.start,
                        art: switch (tl.steps.where((s) => s.kind == StepKind.program).firstOrNull?.artId) {
                          final id? => _c.image(id),
                          null => null,
                        },
                      )
                    else if (_ended && widget.kind != LiveKind.channel)
                      _Ticket(
                        timeline: tl,
                        art: switch (tl.steps.where((s) => s.kind == StepKind.program).firstOrNull?.artId) {
                          final id? => _c.image(id),
                          null => null,
                        },
                      )
                    else if (_ended)
                      _Message(title: 'That was the show', text: '${tl.title} has ended. Go back to pick another one.')
                    else if (s != null)
                      _overlay(s, tl),
                    // Trailers say what they're for.
                    if (s != null && s.isTrailer && !(_touch && _banner))
                      Positioned(left: 48, top: 36, child: _Tag('NOW IN CINEMAS · ${s.title.toUpperCase()}')),
                    // The channel's logo in the corner during programs, like real TV.
                    if (widget.kind == LiveKind.channel && s?.kind == StepKind.program)
                      Positioned(
                        right: 48,
                        top: 36,
                        child: Opacity(
                          opacity: .55,
                          child: ChannelIdent(number: _channel, size: .8, night: night),
                        ),
                      ),
                    if (_pausedAt != null && !(_touch && _banner)) const Center(child: Icon(Icons.pause_rounded, size: 120, color: Colors.white70)),
                    if (_banner && tl != null && !_waiting && !_ended)
                      _Banner(timeline: tl, kind: widget.kind, channel: _channel, private: _private, paused: _pausedAt != null, touch: _touch),
                  ],
                ),
              ),
            ),
            if (_touch) ..._touchControls(s),
            IgnorePointer(
              child: AnimatedOpacity(
                opacity: _blackout ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Phones and computers: a tap shows or hides the controls (leave, and play/pause and
  /// ±10 s in the movie). Trailers and breaks have their own skip button.
  List<Widget> _touchControls(Step? s) {
    final on = s != null && _error == null && !_ended && !_waiting;
    final skip = on && _private
        ? switch (s.kind) {
            StepKind.clip => 'Skip trailer',
            StepKind.bumper => 'Skip',
            StepKind.intermission || StepKind.pause => 'Start now',
            _ => null,
          }
        : null;
    final controls = _banner || _ended || _error != null;
    return [
      GestureDetector(behavior: HitTestBehavior.opaque, onTap: _banner ? _hideBanner : _showBanner, onLongPress: _tracks),
      if (on && _private && _banner && s.kind == StepKind.program)
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Round(Icons.replay_10_rounded, () => _seekBy(-10)),
              const SizedBox(width: 40),
              _Round(_pausedAt == null ? Icons.pause_rounded : Icons.play_arrow_rounded, _togglePause, big: true),
              const SizedBox(width: 40),
              _Round(Icons.forward_10_rounded, () => _seekBy(10)),
            ],
          ),
        ),
      if (skip != null)
        Positioned(
          right: 24,
          top: 24,
          child: SafeArea(
            child: _Skip(label: skip, onTap: _skipStep),
          ),
        ),
      if (controls)
        Positioned(
          left: 24,
          top: 24,
          child: SafeArea(
            child: IconButton(
              onPressed: () => context.pop(),
              tooltip: 'Leave',
              style: IconButton.styleFrom(backgroundColor: Colors.black54, foregroundColor: Colors.white),
              icon: const Icon(Icons.close_rounded, size: 28),
            ),
          ),
        ),
    ];
  }

  Widget _overlay(Step s, Timeline tl) {
    final pos = tl.at(DateTime.now());
    final offset = pos?.offset ?? Duration.zero;
    switch (s.kind) {
      case StepKind.bumper:
        var title = s.title, sub = s.sub;
        if (s.tag == 'next') {
          final next = tl.listingAt(DateTime.now().add(s.dur - offset + const Duration(seconds: 1)));
          title = next?.title ?? '';
          sub = next == null ? '' : [if (next.sub.isNotEmpty) next.sub, 'at ${_hm(next.start)}'].join('  ·  ');
        }
        return Bumper(key: ValueKey(_index), kind: s.tag ?? '', length: s.dur, offset: offset, title: title, sub: sub);
      case StepKind.countdown:
        // The movie that's about to start.
        final next = tl.steps.skip(_index).where((x) => x.kind == StepKind.program).firstOrNull;
        if (next == null) return Countdown(key: ValueKey(_index), offset: offset);
        final details = _details.putIfAbsent(next.itemId!, () => _c.item(next.itemId!));
        return FutureBuilder<Item>(
          future: details,
          builder: (context, snap) {
            final it = snap.data;
            return FeatureIntro(
              key: ValueKey(_index),
              title: next.title,
              meta: it == null
                  ? ''
                  : [
                      if (it.year != null) '${it.year}',
                      if (it.runtime != null) formatRuntime(it.runtime),
                      if (it.officialRating != null) it.officialRating!,
                      ...it.genres.take(2),
                    ].join('  ·  '),
              backdrop: _c.image(next.artId ?? next.itemId!, width: 1920),
              actors: details.then((i) => i.people.where((p) => p.type == 'Actor').take(3).map((p) => p.name).toList()).catchError((_) => <String>[]),
              length: s.dur,
              offset: offset,
            );
          },
        );
      case StepKind.intermission:
      case StepKind.pause:
        return BreakScreen(
          key: ValueKey(_index),
          heading: s.kind == StepKind.intermission ? 'INTERMISSION' : 'BREAK',
          title: s.kind == StepKind.intermission ? s.title : 'Up next: ${s.title}',
          posters: _posters,
          ends: tl.startOf(_index).add(s.dur),
          length: s.dur,
          hint: _private && !_touch ? 'Press OK to carry on now' : null,
        );
      case StepKind.clip:
      case StepKind.program:
        return const SizedBox.shrink();
    }
  }
}

String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

/// A round button over the movie.
class _Round extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool big;
  const _Round(this.icon, this.onTap, {this.big = false});
  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onTap,
    iconSize: big ? 44 : 30,
    padding: EdgeInsets.all(big ? 18 : 12),
    style: IconButton.styleFrom(backgroundColor: Colors.black45, foregroundColor: Colors.white),
    icon: Icon(icon),
  );
}

/// "Skip trailer", top right, like a streaming site.
class _Skip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Skip({required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .6),
    shape: const StadiumBorder(side: BorderSide(color: Colors.white24)),
    child: InkWell(
      customBorder: const StadiumBorder(),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 10, 12, 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.skip_next_rounded, color: Colors.white, size: 22),
          ],
        ),
      ),
    ),
  );
}

class _Tag extends StatelessWidget {
  final String text;
  const _Tag(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
    decoration: BoxDecoration(
      color: const Color(0x99000000),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.white12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(color: Hy.orange, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        Text(
          text,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, letterSpacing: 3, fontSize: 13),
        ),
      ],
    ),
  );
}

class _Message extends StatelessWidget {
  final String title, text;
  const _Message({required this.title, required this.text});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900)),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Hy.textDim, fontSize: 22),
          ),
        ],
      ),
    ),
  );
}

/// What's on: channel or show, the program with its progress, and what's next.
class _Banner extends StatelessWidget {
  final Timeline timeline;
  final LiveKind kind;
  final int channel;
  final bool private, paused, touch;
  const _Banner({required this.timeline, required this.kind, required this.channel, required this.private, required this.paused, this.touch = false});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final all = timeline.listings();
    final cur = all.where((l) => now.isBefore(l.end)).firstOrNull;
    final next = cur == null ? null : all.skipWhile((l) => l != cur).skip(1).firstOrNull;
    final onAir = cur != null && !now.isBefore(cur.start);
    final progress = cur == null || !onAir ? 0.0 : now.difference(cur.start).inSeconds / cur.end.difference(cur.start).inSeconds.clamp(1, 1 << 30);
    final hint = touch
        ? (paused ? 'Paused' : 'Hold for subtitles')
        : private
        ? (paused ? 'OK to play' : 'OK pause · ◀ ▶ 10 s · hold OK for subtitles')
        : kind == LiveKind.channel
        ? '▲ ▼ change channel · hold OK for subtitles'
        : 'Live · hold OK for subtitles';
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(48, 80, 48, 36),
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Color(0xEE000000), Colors.transparent]),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (kind == LiveKind.channel) ...[
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ChannelIdent(number: channel, night: Channel.isNight(now)),
                  const SizedBox(height: 8),
                  Text(
                    '$channel',
                    style: const TextStyle(color: Hy.textDim, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(width: 32),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    kind == LiveKind.channel ? channels[channel - 1].nameAt(now).toUpperCase() : timeline.title.toUpperCase(),
                    style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w900, letterSpacing: 3, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cur?.title ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900),
                  ),
                  if ((cur?.sub ?? '').isNotEmpty)
                    Text(
                      cur!.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Hy.textDim, fontSize: 20),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (cur != null) Text(_hm(cur.start), style: const TextStyle(color: Hy.textDim, fontSize: 16)),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 420,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(value: progress.clamp(0, 1), minHeight: 5, color: Hy.orange, backgroundColor: Colors.white24),
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (cur != null) Text(_hm(cur.end), style: const TextStyle(color: Hy.textDim, fontSize: 16)),
                      if (!onAir && cur != null) ...[
                        const SizedBox(width: 18),
                        const Text(
                          'Coming up after the break',
                          style: TextStyle(color: Hy.orange, fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ],
                  ),
                  if (next != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Next  ${_hm(next.start)}  ${next.title}${next.sub.isEmpty ? '' : ' · ${next.sub}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Hy.textDim, fontSize: 18),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_hm(now), style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(hint, style: const TextStyle(color: Hy.textMute, fontSize: 15)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the live player.
void goLive(BuildContext context, LiveKind kind, String id, {bool fromStart = false}) =>
    context.push('/live/${kind.name}/$id${fromStart ? '?fromStart=1' : ''}');

/// Ticket stubs kept from showings, oldest first (saved on the server, so on every device).
Future<List<Map<String, dynamic>>> tickets(JellyfinClient c) async {
  try {
    return [for (final t in jsonDecode(await c.sharedPref('tickets') ?? '[]') as List) (t as Map).cast<String, dynamic>()];
  } catch (_) {
    return [];
  }
}

/// The end of a showing: the ticket stub, and the way out.
class _Ticket extends StatelessWidget {
  final Timeline timeline;
  final String? art;
  const _Ticket({required this.timeline, this.art});
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (art != null)
        Opacity(
          opacity: .18,
          child: Image.network(art!, fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox()),
        ),
      const DecoratedBox(
        decoration: BoxDecoration(gradient: RadialGradient(colors: [Color(0x33FF7A1A), Colors.black], radius: 1)),
      ),
      Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'THANKS FOR WATCHING',
              style: TextStyle(color: Hy.orange, fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 5),
            ),
            const SizedBox(height: 28),
            FadeTransitionIn(
              child: TicketStub(title: timeline.title, when: timeline.start, seat: seatFor(timeline.id)),
            ),
            const SizedBox(height: 26),
            const Text('Your stub is in Ticket stubs, under your profile.', style: TextStyle(color: Hy.textDim, fontSize: 20)),
            const SizedBox(height: 26),
            FilledButton(
              autofocus: true,
              onPressed: () => context.pop(),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 18),
              ),
              child: const Text('Done', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    ],
  );
}

/// Rises and fades in once.
class FadeTransitionIn extends StatelessWidget {
  final Widget child;
  const FadeTransitionIn({super.key, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 700),
    curve: Curves.easeOutCubic,
    builder: (_, v, c) => Opacity(
      opacity: v,
      child: Transform.translate(
        offset: Offset(0, 30 * (1 - v)),
        child: Transform.rotate(angle: -.03 * v, child: c),
      ),
    ),
    child: child,
  );
}
