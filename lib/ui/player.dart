import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../api/jellyfin.dart';
import '../state/app_state.dart';
import '../state/device.dart';
import '../state/downloads.dart';
import '../state/link.dart';
import '../state/pip.dart';
import '../state/tv_home.dart';
import '../theme.dart';
import 'player_controls.dart';
import 'widgets/common.dart';
import 'widgets/screensaver.dart';
import '../host.dart';
import 'mpv/mpv.dart';
import 'web_player.dart';

/// Full-window video player (mpv via media_kit). Resumes where you left off, reports
/// progress to Jellyfin, offers skip-intro and rolls into the next episode.
class PlayerPage extends StatefulWidget {
  final String id;

  /// Where to begin (the TV preview hands over its position); else resume as usual.
  final Duration? start;

  /// Opened by a watch party: start paused and wait for the group.
  final bool sync;

  /// Play the copy downloaded to this device (works offline).
  final bool local;

  /// A title's trailer (server/library-trailers.py): nothing is reported to Jellyfin, so it
  /// never shows up in Continue Watching.
  final bool trailer;

  /// What a trailer is for: its title on screen (the file itself is just named by its TMDb id).
  final String? name;

  /// Started from a collection's page (its id): what's next follows that collection's path
  /// (a universe's seasons and cuts too), not each title's own franchise or show.
  final String? universe;
  const PlayerPage({super.key, required this.id, this.start, this.sync = false, this.local = false, this.trailer = false, this.name, this.universe});
  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver implements PlaybackTarget {
  late final AppState _app = context.read<AppState>();
  late final Link _link = context.read<Link>();
  late final Downloads _downloads = context.read<Downloads>();
  Timer? _syncStart;
  bool get _party => _link.inParty && widget.sync;
  JellyfinClient get _c => _app.client!;
  static bool get _desktop => Host.isComputer;

  /// On the desktop mpv draws subtitles itself (styled ASS, and image-based PGS/VobSub
  /// that a text overlay can't show). On Android libass draws nothing on the phone even
  /// though the text is decoded, so text subtitles go through the Flutter overlay there,
  /// and mpv only draws image-based ones (see [_onTrack]).
  /// HEVYFIN_LIBASS=0 forces the Flutter overlay on the desktop for testing.
  static final bool _libass = !Host.isWeb && !Host.isAndroid && Host.env('HEVYFIN_LIBASS') != '0';

  @visibleForTesting
  Player get debugPlayer => _player;

  late final Player _player = Player(
    configuration: PlayerConfiguration(title: 'Hevyfin', bufferSize: 64 << 20, libass: _libass),
  );

  static const _imageSubs = {'hdmv_pgs_subtitle', 'pgs', 'dvd_subtitle', 'dvdsub', 'vobsub', 'dvb_subtitle'};

  /// Android: let mpv draw a picture subtitle track, hide its own rendering for text ones.
  Future<void> _onTrack(Track t) async {
    if (_libass) return;
    if (!hasMpv(_player)) return;
    final image = _imageSubs.contains((t.subtitle.codec ?? '').toLowerCase());
    await mpvSet(_player, 'sub-visibility', image ? 'yes' : 'no');
  }

  // Android: decode in hardware but copy frames back so mpv can draw subtitles on top.
  // Direct-to-surface decoding ("mediacodec") skips mpv's renderer, and subtitles with it.
  // TVs (weak CPUs): hardware decoding straight onto the screen, no copies at all. Text
  // subtitles are drawn by Flutter, so mpv doesn't need the frames.
  late final VideoController _video = VideoController(
    _player,
    configuration: Device.isTv
        ? const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec')
        : VideoControllerConfiguration(hwdec: Host.isAndroid ? 'mediacodec-copy' : null),
  );

  Item? _item;
  Item? _next;
  PlaybackInfo? _info;
  List<Segment> _segments = const [];

  /// A film's bonus scenes in its credits, when they were measured.
  ({Duration credits, List<Scene> scenes})? _scenes;
  List<SubtitleTrack> _externalSubs = const [];
  String? _error;
  Timer? _progressTimer;
  final _subs = <StreamSubscription>[];
  bool _reportedStart = false;
  bool _leaving = false;
  int? _countdown;
  String _overlayFlags = '';
  Timer? _countdownTimer;
  Trickplay? _trick;
  Download? _local;

  /// Web: the audio track playing and the subtitle showing (Jellyfin stream indexes), the
  /// text subtitle's lines, and whether the subtitle is burnt into the picture by the server.
  int? _webAudio, _webSub;
  List<Cue> _cues = const [];
  bool _burnt = false;

  /// The credits card was waved away ("Watch credits") for this episode.
  bool _creditsDismissed = false;

  /// Episodes that rolled on by themselves since anyone last touched a key or the screen;
  /// at 3 the player asks whether anyone's still watching before the next one.
  static int _autoAdvances = 0;
  bool _askStillWatching = false;
  final _controls = GlobalKey<PlayerControlsState>();
  bool _fullscreen = false;

  /// Sleep timer: pause at [_sleepAt], or once this episode or film ends ([_sleepAtEnd]).
  DateTime? _sleepAt;
  bool _sleepAtEnd = false;
  Timer? _sleepTick;

  /// The sleep timer went off: paused, asking whether anyone's still up.
  bool _asleep = false;
  Timer? _sleepLeave;

  /// "Previously on": the last episode watched (or this one, when resuming), shown before
  /// playing when the show hasn't been watched for a week.
  Item? _recap;

  bool get _tracked => !widget.trailer;

  /// Desktop: the window itself goes fullscreen; the controls stay ours.
  Future<void> _toggleFullscreen() async {
    if (!_desktop) return;
    _fullscreen ? await defaultExitNativeFullscreen() : await defaultEnterNativeFullscreen();
    if (mounted) setState(() => _fullscreen = !_fullscreen);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onAnyKey);
    _link.target = this;
    Screensaver.players.value++;
    // Read these now: dispose() can't look providers up any more.
    _downloads.hashCode;
    _app.hashCode;
    _link.addListener(_onLink);
    Pip.active.addListener(_onPip);
    // Buttons in the floating mini player.
    Pip.onAction = (a) {
      switch (a) {
        case 'toggle':
          _player.playOrPause();
        case 'back':
          _seekBy(-10);
        case 'forward':
          _seekBy(10);
      }
    };
    if (!_desktop) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    _start(widget.id);
  }

  /// A downloaded film or episode, from the file on this device.
  Future<void> _startLocal(String id) async {
    final dl = _downloads;
    final d = dl.of(id);
    try {
      if (d == null || !d.done) throw 'This download is gone';
      final file = await dl.video(id);
      await _player.open(Media(file.path, start: d.resume > const Duration(seconds: 30) ? d.resume : Duration.zero));
      final srt = await dl.subtitle(id);
      if (await srt.exists()) {
        final t = SubtitleTrack.uri(srt.uri.toString(), title: 'Subtitles', language: _app.subtitleLang);
        _externalSubs = [t];
        if (_app.subtitleLang.isNotEmpty) await _player.setSubtitleTrack(t);
      }
      setState(() {
        _item = Item({'Id': d.id, 'Name': d.name, 'Type': d.type, 'SeriesName': ?d.seriesName});
        _local = d;
      });
      _subs.add(_player.stream.completed.listen((done) => done ? _leave() : null));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _start(String id) async {
    if (widget.local) return _startLocal(id);
    try {
      var (item, info) = await _c.forPlayer(id, maxBitrate: _maxBitrate);
      // This show's own choice (made on any device) beats the general preference.
      final show = item.isEpisode && item.seriesId != null
          ? ((await _c.showTracks().timeout(const Duration(seconds: 3), onTimeout: () => {}))[item.seriesId] as Map?)
          : null;
      final audio = (show?['a'] as String?) ?? _app.audioLang;
      final sub = switch (show?['s'] as String?) {
        'off' => '',
        final String s => s,
        null => _app.subtitleLang,
      };
      if (hasMpv(_player)) {
        await mpvSet(_player, 'alang', _langs(audio));
        await mpvSet(_player, 'slang', sub.isEmpty ? '' : _langs(sub));
        await mpvSet(_player, 'sid', sub.isEmpty ? 'no' : 'auto');
        await _applyPassthrough();
        if (_libass) await mpvSubStyle(_player, _app);
      }
      if (Host.isWeb) info = await _webAudioFor(id, info, audio);
      final handover = id == widget.id ? widget.start : null;
      final start = handover ?? (item.resumePosition > const Duration(seconds: 30) && (item.progress ?? 0) < .95 ? item.resumePosition : Duration.zero);
      // Back to a show after a while: a reminder of where it was, before it plays.
      final recap = id == widget.id && !widget.sync && !widget.trailer && item.isEpisode ? await _recapFor(item, resuming: start > Duration.zero) : null;
      await _player.open(Media(_c.streamUrl(id, info), start: start), play: !widget.sync && recap == null);
      if (!Host.isWeb) {
        unawaited(ensureAudio(_player, audio));

        _externalSubs = [
          for (final s in info.streams.where((s) => s.type == 'Subtitle' && (s.isExternal || info.isTranscode) && s.isText))
            SubtitleTrack.uri(_c.subtitleUrl(id, info, s), title: s.title, language: s.language),
        ];
        // A transcode carries no subtitles, so load the preferred one ourselves.
        if (info.isTranscode && sub.isNotEmpty) {
          final want = info.streams.where((s) => s.type == 'Subtitle' && s.isText && _langMatches(s.language, sub));
          if (want.isNotEmpty) {
            await _player.setSubtitleTrack(SubtitleTrack.uri(_c.subtitleUrl(id, info, want.first), title: want.first.title, language: want.first.language));
          }
        }
      }

      setState(() {
        _item = item;
        _info = info;
        _next = null;
        _segments = const [];
        _scenes = item.isMovie ? Scene.of(item) : null;
        _countdown = null;
        _reportedStart = false;
        _trick = null;
        _creditsDismissed = false;
        _askStillWatching = false;
        _recap = recap;
      });
      // Web: the preferred subtitles, drawn by Hevyfin.
      final want = info.streams.where((s) => s.type == 'Subtitle' && s.isText && _langMatches(s.language, sub)).firstOrNull;
      if (Host.isWeb && sub.isNotEmpty && want != null) unawaited(_webShowSubtitle(id, info, want));
      _c.trickplay(id, info.mediaSourceId).then((t) => mounted ? setState(() => _trick = t) : null);
      if (_tracked) {
        _c
            .segments(id)
            .then((s) => mounted ? setState(() => _segments = s.where((x) => x.type == 'Intro' || x.type == 'Recap' || x.type == 'Outro').toList()) : null);
        final path = widget.universe == null
            ? Future<Item?>.value()
            : _c.nextInUniverse(widget.universe!, item, story: _app.storyOrder.contains(widget.universe)).catchError((_) => null);
        unawaited(
          path.then((n) {
            if (!mounted) return;
            if (n != null) return setState(() => _next = n);
            // Off the path (or not started from one): the show's next episode, and a film
            // from a franchise rolls into the next one, like episodes do.
            if (item.isEpisode) _c.nextEpisode(item).then((n) => mounted ? setState(() => _next = n) : null);
            if (item.isMovie) {
              _c.nextInCollection(item, storyOrder: _app.storyOrder).then((n) => mounted && n != null ? setState(() => _next = n.$1) : null).catchError((_) {});
            }
          }),
        );
      }

      for (final s in _subs) {
        s.cancel();
      }
      _subs
        ..clear()
        ..add(
          _player.stream.playing.listen((p) {
            Pip.setPlaying(p);
            if (p && !_reportedStart && _tracked) {
              _reportedStart = true;
              _c.reportStart(id, info, _player.state.position).catchError((_) {});
            }
            _report();
          }),
        )
        ..add(
          _player.stream.completed.listen((done) {
            if (done) _onFinished();
          }),
        )
        ..add(
          _player.stream.position.listen((_) {
            // Only rebuild when an overlay button appears or goes away.
            final seg = _activeSegment;
            // Skipping on its own (Settings): once per intro, so going back to watch it works.
            if (seg != null && _app.autoSkip && _player.state.playing && _autoSkipped.add('$id@${seg.start.inSeconds}')) {
              _player.seek(seg.end);
              if (mounted) toast(context, seg.type == 'Recap' ? 'Skipped the recap' : 'Skipped the intro');
            }
            final flags = '${seg?.start}|$_nearEnd|${_sceneSkip?.to}';
            if (flags != _overlayFlags) setState(() => _overlayFlags = flags);
            // The credits are rolling: count down to the next episode over them (unless the
            // sleep timer says this is the last one).
            if (_nearEnd && _countdown == null && !_creditsDismissed && !_askStillWatching && !_sleepAtEnd && _player.state.playing) _startCountdown(10);
          }),
        )
        ..add(
          // A watch party waits for everyone: say when this player is loading and when it's ready.
          _player.stream.buffering.listen((b) {
            if (_party) _link.partyReady(_player.state.position, _player.state.playing, buffering: b);
          }),
        )
        ..add(_player.stream.error.listen((e) => debugPrint('mpv error: $e')))
        ..add(_player.stream.track.listen(_onTrack))
        ..add(
          _player.stream.videoParams.listen((v) {
            // Allow the mini player once we know the video's shape.
            final w = v.dw ?? v.w, h = v.dh ?? v.h;
            if (w != null && h != null && w > 0 && h > 0 && !Device.isTv) Pip.setEnabled(true, width: w, height: h);
          }),
        );
      if (_player.state.playing && !_reportedStart && _tracked) {
        _reportedStart = true;
        _c.reportStart(id, info, _player.state.position).catchError((_) {});
      }
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) => _report());
      if (_party && !_player.state.buffering) _link.partyReady(_player.state.position, false);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  int? get _maxBitrate => _app.maxMbps > 0 ? _app.maxMbps * 1000000 : null;

  /// Web: the browser plays only a file's default audio track, so another language (or a
  /// track other than the one the server picked for its HLS) comes as the server's stream.
  Future<PlaybackInfo> _webAudioFor(String id, PlaybackInfo info, String lang) async {
    _webSub = null;
    _cues = const [];
    _burnt = false;
    final audios = info.streams.where((s) => s.type == 'Audio').toList();
    final playing = info.isTranscode ? info.defaultAudio : (audios.where((s) => s.raw['IsDefault'] == true).firstOrNull ?? audios.firstOrNull)?.index;
    final want = audios.where((s) => _langMatches(s.language, lang)).firstOrNull;
    _webAudio = playing;
    if (want == null || want.index == playing) return info;
    _webAudio = want.index;
    return _c.playbackInfo(id, maxBitrate: _maxBitrate, audioIndex: want.index, transcode: true);
  }

  Future<void> _webShowSubtitle(String id, PlaybackInfo info, MediaStream s) async {
    try {
      final cues = await loadCues(_c.subtitleUrl(id, info, s));
      if (!mounted || _info?.playSessionId != info.playSessionId) return;
      setState(() {
        _webSub = s.index;
        _cues = cues;
      });
    } catch (e) {
      if (mounted) toast(context, '$e');
    }
  }

  /// Web: plays on from here with another audio track, or with a picture subtitle burnt in
  /// (or no longer burnt in), as a new stream from the server.
  Future<void> _webReopen({required int? audio, required int? burn}) async {
    final item = _item, old = _info;
    if (item == null || old == null) return;
    final at = _player.state.position;
    try {
      final info = await _c.playbackInfo(item.id, maxBitrate: _maxBitrate, audioIndex: audio, subtitleIndex: burn ?? -1, transcode: true);
      unawaited(_c.endTranscode(old));
      await _player.open(Media(_c.streamUrl(item.id, info), start: at));
      if (!mounted) return;
      setState(() {
        _info = info;
        _webAudio = audio;
        _burnt = burn != null;
        if (_burnt) {
          _webSub = burn;
          _cues = const [];
        }
      });
    } catch (e) {
      if (mounted) toast(context, 'Could not switch: $e');
    }
  }

  /// mpv language lists: "eng" also matches "en".
  static String _langs(String iso3) => mpvLangs(iso3);
  static bool _langMatches(String? lang, String want) => langMatches(lang, want);

  void _report() {
    final info = _info, item = _item;
    if (info == null || item == null || !_reportedStart) return;
    _c.reportProgress(item.id, info, _player.state.position, !_player.state.playing).catchError((_) {});
  }

  Future<void> _stopReport() async {
    final d = _local;
    if (d != null) {
      // Offline: remember the spot here; the server hears about it once back online.
      final pos = _player.state.position;
      await _downloads.saveResume(d.id, pos);
      unawaited(
        _c.post('/UserItems/${d.id}/UserData', query: {'userId': _c.userId}, body: {'PlaybackPositionTicks': pos.inMicroseconds * 10}).catchError((_) => null),
      );
      return;
    }
    final info = _info, item = _item;
    if (info == null || item == null) return;
    try {
      // Never started (backed out of "Previously on"): nothing to tell Jellyfin but to stop transcoding.
      _tracked && _reportedStart ? await _c.reportStop(item.id, info, _player.state.position) : await _c.endTranscode(info);
    } catch (_) {}
  }

  /// The episode to recap before [ep] plays, if the show was last watched a week or more ago:
  /// [ep] itself when resuming it, else the one before it.
  Future<Item?> _recapFor(Item ep, {required bool resuming}) async {
    try {
      final all = (await _c.episodes(ep.seriesId!).timeout(const Duration(seconds: 4))).where((e) => (e.parentIndexNumber ?? 1) > 0).toList();
      final last = all.map((e) => e.lastPlayed).nonNulls.fold<DateTime?>(null, (a, b) => a == null || b.isAfter(a) ? b : a);
      if (last == null || DateTime.now().difference(last) < const Duration(days: 7)) return null;
      if (resuming) return ep;
      final i = all.indexWhere((e) => e.id == ep.id);
      return i > 0 ? all[i - 1] : null;
    } catch (_) {
      return null;
    }
  }

  void _endRecap() {
    if (_recap == null) return;
    setState(() => _recap = null);
    _player.play();
  }

  String? get _sleepLabel {
    if (_sleepAtEnd) return _item?.isEpisode ?? true ? 'End of episode' : 'End of film';
    final at = _sleepAt;
    if (at == null) return null;
    final left = at.difference(DateTime.now());
    return '${(left.inSeconds / 60).ceil().clamp(1, 999)} min';
  }

  Future<void> _sleepPicker() async {
    const mins = [15, 30, 45, 60, 90];
    final endLabel = _item?.isEpisode ?? true ? 'End of this episode' : 'End of this film';
    final i = await showBlurPicker(context, [
      'Off',
      endLabel,
      for (final m in mins) m < 60 ? '$m minutes' : (m == 60 ? '1 hour' : '1½ hours'),
    ], selected: _sleepAtEnd ? 1 : (_sleepAt == null ? 0 : null));
    if (i == null || !mounted) return;
    _sleepTick?.cancel();
    setState(() {
      _sleepAtEnd = i == 1;
      _sleepAt = i >= 2 ? DateTime.now().add(Duration(minutes: mins[i - 2])) : null;
      // No next-episode countdown when this is the last one tonight.
      if (_sleepAtEnd) {
        _countdownTimer?.cancel();
        _countdown = null;
      }
    });
    if (_sleepAt != null) {
      _sleepTick = Timer.periodic(const Duration(seconds: 15), (_) {
        if (!mounted) return;
        if (DateTime.now().isAfter(_sleepAt!)) return _fallAsleep();
        setState(() {});
      });
    }
    if (Device.isTv) _controls.currentState?.hide();
  }

  /// Pause and ask; nobody answers within a minute: leave the player.
  void _fallAsleep() {
    _sleepTick?.cancel();
    _player.pause();
    setState(() {
      _asleep = true;
      _sleepAt = null;
      _sleepAtEnd = false;
      _countdown = null;
    });
    _countdownTimer?.cancel();
    _sleepLeave = Timer(const Duration(seconds: 60), _leave);
  }

  void _wakeUp() {
    _sleepLeave?.cancel();
    setState(() => _asleep = false);
    _player.play();
  }

  void _onFinished() {
    if (_sleepAtEnd) return _fallAsleep();
    if (_next == null) {
      _leave();
      return;
    }
    // Credits counting down already: go now. Otherwise a short full-screen countdown.
    if (_countdown != null && !_creditsDismissed) return _autoNext();
    _creditsDismissed = false;
    _startCountdown(8);
  }

  void _startCountdown(int seconds) {
    if (_autoAdvances >= 3) {
      setState(() => _askStillWatching = true);
      return;
    }
    setState(() => _countdown = seconds);
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_countdown! <= 1) {
        t.cancel();
        _autoNext();
      } else {
        setState(() => _countdown = _countdown! - 1);
      }
    });
  }

  /// The next episode, started by the countdown rather than by anyone.
  void _autoNext() {
    if (_autoAdvances >= 3) {
      _countdownTimer?.cancel();
      _player.pause();
      setState(() {
        _countdown = null;
        _askStillWatching = true;
      });
      return;
    }
    _autoAdvances++;
    _playNext(auto: true);
  }

  void _watchCredits() {
    _countdownTimer?.cancel();
    setState(() {
      _countdown = null;
      _creditsDismissed = true;
    });
  }

  /// Any key or touch means someone's there.
  bool _onAnyKey(KeyEvent e) {
    _autoAdvances = 0;
    return false;
  }

  Future<void> _playNext({bool auto = false}) async {
    final n = _next;
    if (n == null) return;
    if (!auto) _autoAdvances = 0;
    _countdownTimer?.cancel();
    await _stopReport();
    setState(() {
      _item = null;
      _countdown = null;
    });
    await _start(n.id);
  }

  /// Switch to another episode without leaving the player.
  Future<void> _playEpisode(String id) async {
    _countdownTimer?.cancel();
    await _stopReport();
    if (!mounted) return;
    setState(() {
      _item = null;
      _countdown = null;
    });
    await _start(id);
  }

  void _episodesPanel(Item current) {
    // TV: back on the video when the list closes (the buttons have faded meanwhile).
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close',
      barrierColor: Colors.black.withValues(alpha: .85),
      transitionDuration: const Duration(milliseconds: 260),
      transitionBuilder: (_, a, _, child) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
      pageBuilder: (ctx, _, _) => _EpisodesPanel(
        client: _c,
        current: current,
        onPick: (e) {
          Navigator.pop(ctx);
          if (e.id != current.id) _playEpisode(e.id);
        },
      ),
    ).then((_) => Device.isTv ? _controls.currentState?.hide() : null);
  }

  Future<void> _leave() async {
    if (_leaving) return;
    _leaving = true;
    if (_party) unawaited(_link.leaveParty());
    await _stopReport();
    _app.bump();
    unawaited(TvHome.sync(_c, force: true));
    if (mounted && context.canPop()) context.pop();
  }

  void _onPip() => setState(() {});
  void _onLink() => mounted ? setState(() {}) : null;

  // ---- told by another device (phone as remote) ----
  @override
  void remotePause() => _player.pause();
  @override
  void remoteUnpause() => _player.play();
  @override
  void remoteToggle() => _player.playOrPause();
  @override
  void remoteSeek(Duration to) {
    _player.seek(to);
    _controls.currentState?.show();
  }

  @override
  void remoteStop() => _leave();
  @override
  void remoteNext() => _next == null ? null : _playNext();

  // ---- the watch party's commands, at the moment the server set for everyone ----
  @override
  void syncCommand(String command, DateTime when, Duration position) {
    _syncStart?.cancel();
    switch (command) {
      case 'Unpause':
        final wait = when.difference(DateTime.now());
        if (wait > Duration.zero) {
          _player.seek(position);
          _syncStart = Timer(wait, _player.play);
        } else {
          // Late: catch up by however long ago "now" was.
          _player.seek(position - wait);
          _player.play();
        }
      case 'Pause':
        _player.pause();
        _player.seek(position);
      case 'Seek':
        _player.pause();
        _player.seek(position).then((_) => _link.partyReady(position, false));
      case 'Stop':
        _leave();
    }
  }

  /// On a TV, OK presses the Skip Intro / Next Episode button while it's on screen.
  VoidCallback? get _overlayAction {
    if (_recap != null) return _endRecap;
    if (_asleep) return _wakeUp;
    final seg = _activeSegment;
    if (seg != null) return () => _player.seek(seg.end);
    final scene = _sceneSkip;
    if (scene != null) return () => _player.seek(scene.to);
    if (_askStillWatching) return _playNext;
    if (_nearEnd || _countdown != null) return _playNext;
    return null;
  }

  /// Leaving the app without PiP (or closing the PiP window) pauses playback.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _player.state.playing) _player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Screensaver.players.value--;
    HardwareKeyboard.instance.removeHandler(_onAnyKey);
    if (identical(_link.target, this)) _link.target = null;
    _link.removeListener(_onLink);
    _syncStart?.cancel();
    Pip.active.removeListener(_onPip);
    Pip.onAction = null;
    Pip.setEnabled(false);
    _progressTimer?.cancel();
    _countdownTimer?.cancel();
    _sleepTick?.cancel();
    _sleepLeave?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    if (!_leaving) {
      _stopReport();
      // Not during teardown: the lists refresh once this frame is done.
      final app = _app;
      WidgetsBinding.instance.addPostFrameCallback((_) => app.bump());
    }
    if (_fullscreen) defaultExitNativeFullscreen();
    _player.dispose();
    if (!_desktop) {
      SystemChrome.setPreferredOrientations([]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    super.dispose();
  }

  final _autoSkipped = <String>{};

  static List<String>? _hdmiFormats;

  /// TV: Dolby/DTS soundtracks go to the TV or soundbar untouched (Atmos included, in Dolby
  /// Digital Plus), when it says it takes them.
  Future<void> _applyPassthrough() async {
    if (!Device.isTv || !hasMpv(_player)) return;
    try {
      if (!_app.passthrough) return await mpvSet(_player, 'audio-spdif', '');
      _hdmiFormats ??= ((await const MethodChannel('hevyfin/device').invokeMethod<List>('passthrough')) ?? const []).cast<String>();
      await mpvSet(_player, 'audio-spdif', _hdmiFormats!.join(','));
    } catch (_) {}
  }

  Segment? get _activeSegment {
    final p = _player.state.position;
    for (final s in _segments) {
      if (p >= s.start && p < s.end - const Duration(seconds: 2) && s.type != 'Outro') return s;
    }
    return null;
  }

  /// In a film's credits, the button for the bonus scene coming up: "Skip spoiler" before
  /// (and during) one that gives a later stop away, past it; else a skip to the next scene.
  ({String label, Duration to})? get _sceneSkip {
    final s = _scenes, p = _player.state.position;
    if (s == null || p < s.credits) return null;
    for (final scene in s.scenes) {
      if (p >= scene.end) continue;
      if (scene.spoiler) return (label: 'Skip spoiler', to: scene.end);
      if (p >= scene.start - const Duration(seconds: 1)) return null; // it's on
      return (label: scene.kind == 'mid' ? 'Skip to mid-credits scene' : 'Skip to post-credits scene', to: scene.start);
    }
    return null;
  }

  bool get _nearEnd {
    final d = _player.state.duration, p = _player.state.position;
    if (_next == null || d == Duration.zero) return false;
    // A film's bonus scenes come before what's next: the countdown waits until the last is over.
    if (_scenes case final s?) return p >= s.scenes.last.end;
    final outro = _segments.where((s) => s.type == 'Outro').firstOrNull;
    if (outro != null) return p >= outro.start;
    return d - p < const Duration(seconds: 45);
  }

  @override
  Widget build(BuildContext context) {
    // Keyboard shortcuts (desktop), Netflix/YouTube style.
    final keys = <ShortcutActivator, VoidCallback>{
      const SingleActivator(LogicalKeyboardKey.escape): () => _fullscreen ? _toggleFullscreen() : _leave(),
      const SingleActivator(LogicalKeyboardKey.space): () => _controls.currentState?.togglePlay(),
      const SingleActivator(LogicalKeyboardKey.keyK): () => _controls.currentState?.togglePlay(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => _controls.currentState?.seekBy(-10),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => _controls.currentState?.seekBy(10),
      const SingleActivator(LogicalKeyboardKey.keyJ): () => _controls.currentState?.seekBy(-10),
      const SingleActivator(LogicalKeyboardKey.keyL): () => _controls.currentState?.seekBy(10),
      const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        _player.setVolume((_player.state.volume + 5).clamp(0, 100));
        _controls.currentState?.show();
      },
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        _player.setVolume((_player.state.volume - 5).clamp(0, 100));
        _controls.currentState?.show();
      },
      const SingleActivator(LogicalKeyboardKey.keyM): () => _player.setVolume(_player.state.volume > 0 ? 0 : 100),
      if (_next != null) const SingleActivator(LogicalKeyboardKey.keyN, shift: true): _playNext,
    };
    // Netflix-style: white, semi-bold, soft shadow, sized to the screen.
    final subStyle = TextStyle(
      fontSize: (_desktop ? 34 : (MediaQuery.sizeOf(context).shortestSide * .062).clamp(16.0, 40.0)) * _app.subSize,
      color: subColors[_app.subColor] ?? Colors.white,
      fontWeight: FontWeight.w600,
      height: 1.25,
      backgroundColor: _app.subBox ? const Color(0xB0000000) : null,
      shadows: _app.subBox ? null : const [Shadow(blurRadius: 8), Shadow(blurRadius: 3), Shadow(offset: Offset(1, 1), blurRadius: 2)],
    );
    final subPadding = EdgeInsets.fromLTRB(32, 0, 32, _desktop ? 48 : 28);
    final video = Video(
      controller: _video,
      fill: Colors.black,
      subtitleViewConfiguration: SubtitleViewConfiguration(
        // The web version draws its own (CueOverlay).
        visible: !_libass && !Host.isWeb && !Pip.active.value,
        style: subStyle,
        padding: subPadding,
        // media_kit shrinks text on small screens; on phones the size above is already right.
        textScaler: _desktop ? null : TextScaler.noScaling,
      ),
      // Phones get our own Netflix-style layer on top; in the mini player only the picture shows.
      controls: NoVideoControls,
    );
    final item = _item;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        // TV remote: Back first hides the controls, then leaves.
        final c = _controls.currentState;
        if (Device.isTv && c != null && c.visible) {
          c.hide();
        } else {
          _leave();
        }
      },
      child: CallbackShortcuts(
        bindings: _desktop && !Device.isTv ? keys : const {}, // TV mode on a desktop drives it like the remote
        child: Focus(
          // On TV the controls take the remote themselves; here it would swallow the first press.
          autofocus: !Device.isTv,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: _error != null
                ? Stack(
                    children: [
                      ErrorView(
                        "Couldn't play this: $_error",
                        onRetry: () {
                          setState(() => _error = null);
                          _start(widget.id);
                        },
                      ),
                      SafeArea(
                        child: IconButton(
                          onPressed: _leave,
                          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                        ),
                      ),
                    ],
                  )
                : Listener(
                    onPointerDown: (_) => _autoAdvances = 0,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        video,
                        if (Host.isWeb && _cues.isNotEmpty) CueOverlay(player: _player, cues: _cues, style: subStyle, padding: subPadding),
                        PlayerControls(
                          key: _controls,
                          player: _player,
                          desktop: _desktop && !Device.isTv,
                          tv: Device.isTv,
                          onOverlayAction: _overlayAction,
                          fullscreen: _fullscreen,
                          onFullscreen: _desktop ? _toggleFullscreen : null,
                          enabled: !Pip.active.value,
                          title: widget.trailer
                              ? (widget.name ?? 'Trailer')
                              : (item == null ? '' : (item.isEpisode ? item.seriesName ?? item.name : item.name)),
                          subtitle: widget.trailer
                              ? 'Trailer'
                              : item != null && item.isEpisode
                              ? '${item.episodeCode}  “${item.name}”'
                              : null,
                          onBack: _leave,
                          onTracks: () => _tracksSheet(context),
                          onEpisodes: item != null && item.isEpisode && item.seriesId != null ? () => _episodesPanel(item) : null,
                          onNext: _next == null ? null : _playNext,
                          preview: _trick == null ? null : (at) => TrickFrame(_trick!, at),
                          onTogglePlay: _party ? () => _link.partyToggle(_player.state.playing) : null,
                          onSeekTo: _party ? _link.partySeek : null,
                          onSleep: _sleepPicker,
                          sleep: _sleepLabel,
                        ),
                        if (_item == null) const Center(child: CircularProgressIndicator(color: Hy.orange)),
                        if (_party && !Pip.active.value)
                          Positioned(
                            top: MediaQuery.paddingOf(context).top + 14,
                            left: 0,
                            right: 0,
                            child: Center(child: _PartyPill(party: _link.party!)),
                          ),
                        if (_activeSegment != null && !Pip.active.value)
                          Positioned(
                            right: 40,
                            bottom: _desktop ? 110 : 130,
                            child: _OverlayButton(
                              label: _activeSegment!.type == 'Recap' ? 'Skip Recap' : 'Skip Intro',
                              onTap: () => _player.seek(_activeSegment!.end),
                            ),
                          ),
                        if (_sceneSkip != null && !Pip.active.value)
                          Positioned(
                            right: 40,
                            bottom: _desktop ? 110 : 130,
                            child: _OverlayButton(label: _sceneSkip!.label, onTap: () => _player.seek(_sceneSkip!.to)),
                          ),
                        if (_nearEnd && _countdown == null && !_askStillWatching && !Pip.active.value)
                          Positioned(
                            right: 40,
                            bottom: _desktop ? 110 : 130,
                            child: _OverlayButton(
                              label: _next!.isEpisode ? 'Next Episode' : 'Next Movie',
                              icon: Icons.skip_next_rounded,
                              onTap: _playNext,
                              filled: true,
                            ),
                          ),
                        // Over the credits: a small card in the corner, the credits keep playing.
                        if (_countdown != null && _next != null && !Pip.active.value && _player.state.completed == false && _nearEnd)
                          Positioned(
                            right: 40,
                            bottom: _desktop ? 110 : 130,
                            child: _CreditsCard(next: _next!, seconds: _countdown!, onPlay: _playNext, onWatchCredits: _watchCredits),
                          )
                        else if (_countdown != null && _next != null && !Pip.active.value)
                          _NextUpCard(next: _next!, seconds: _countdown!, onPlay: _playNext, onCancel: _leave),
                        if (_askStillWatching && !Pip.active.value) _StillWatching(series: _item?.seriesName ?? '', onContinue: _playNext, onLeave: _leave),
                        if (_recap != null && _item != null && !Pip.active.value)
                          _Recap(episode: _recap!, resuming: _recap!.id == _item!.id, onContinue: _endRecap, onBack: _leave),
                        if (_asleep && !Pip.active.value) _Asleep(onContinue: _wakeUp, onLeave: _leave),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  void _seekBy(int s) {
    final d = _player.state.duration;
    var p = _player.state.position + Duration(seconds: s);
    if (p < Duration.zero) p = Duration.zero;
    if (d > Duration.zero && p > d) p = d;
    _player.seek(p);
  }

  void _webTracksSheet(BuildContext context) {
    final info = _info;
    if (info == null) return;
    final remember = _item?.seriesId;
    showModalBottomSheet(
      context: context,
      backgroundColor: Hy.surface,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => WebTracksSheet(
        info: info,
        audio: _webAudio,
        subtitle: _webSub,
        onAudio: (a) {
          _webReopen(audio: a.index, burn: _burnt ? _webSub : null);
          if (remember != null && (a.language ?? '').isNotEmpty) _c.saveShowTrack(remember, audio: a.language).catchError((_) {});
        },
        onSubtitle: (s) {
          if (s != null && !s.isText) {
            _webReopen(audio: _webAudio, burn: s.index);
          } else {
            if (_burnt) _webReopen(audio: _webAudio, burn: null);
            setState(() {
              _webSub = null;
              _cues = const [];
            });
            if (s != null) _webShowSubtitle(_item!.id, info, s);
          }
          if (remember != null) _c.saveShowTrack(remember, subtitle: s == null ? 'off' : s.language).catchError((_) {});
        },
      ),
    ).then((_) => _controls.currentState?.hide());
  }

  Future<void> _tracksSheet(BuildContext context) async {
    if (Host.isWeb) return _webTracksSheet(context);
    final aid = await currentAid(_player);
    if (!context.mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Hy.surface,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 760),
      builder: (_) => TracksSheet(
        player: _player,
        external: _externalSubs,
        aid: aid,
        // A show remembers its languages for the next episodes, on every device.
        onChoice: switch (_item?.seriesId) {
          final sid? => (audio, subtitle) => _c.saveShowTrack(sid, audio: audio, subtitle: subtitle).catchError((_) {}),
          null => null,
        },
      ),
    ).then((_) => Device.isTv ? _controls.currentState?.hide() : null);
  }
}

/// One frame from the scrub-preview tiles: the tile image, moved so only that cell shows.
class TrickFrame extends StatelessWidget {
  final Trickplay t;
  final Duration at;
  const TrickFrame(this.t, this.at, {super.key});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final (url, col, row) = t.at(at);
      final w = c.maxWidth, h = w * t.height / t.width;
      return SizedBox(
        width: w,
        height: h,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: Transform.translate(
              offset: Offset(-col * w, -row * h),
              child: Image.network(
                url,
                width: w * t.cols,
                height: h * t.rows,
                fit: BoxFit.fill,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => SizedBox(width: w, height: h),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _OverlayButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool filled;
  const _OverlayButton({required this.label, required this.onTap, this.icon, this.filled = false});
  @override
  // On a TV the remote's OK presses this (it never takes focus), so it wears the outline.
  Widget build(BuildContext context) => ExcludeFocus(
    excluding: Device.isTv,
    child: FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: filled ? Colors.white : Colors.black.withValues(alpha: .6),
        foregroundColor: filled ? Colors.black : Colors.white,
        side: Device.isTv ? const BorderSide(color: Hy.orange, width: 3) : (filled ? null : const BorderSide(color: Colors.white70)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
      icon: icon == null ? const SizedBox.shrink() : Icon(icon),
      label: Text(label, style: const TextStyle(fontSize: 16)),
    ),
  );
}

/// Who's in the watch party, at the top of the screen.
class _PartyPill extends StatelessWidget {
  final Party party;
  const _PartyPill({required this.party});
  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.groups_rounded, color: Hy.orange, size: 18),
          const SizedBox(width: 8),
          Text(
            party.people.length <= 1 ? 'Watch party · waiting for others' : 'Watching together · ${party.people.join(', ')}',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

/// Netflix's corner card over the credits: the next episode, counting down.
class _CreditsCard extends StatelessWidget {
  final Item next;
  final int seconds;
  final VoidCallback onPlay, onWatchCredits;
  const _CreditsCard({required this.next, required this.seconds, required this.onPlay, required this.onWatchCredits});
  @override
  Widget build(BuildContext context) => Container(
    width: 340,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xE6101010),
      borderRadius: BorderRadius.circular(Hy.radius + 4),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(Hy.radius),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                NetImage(jf(context).thumb(next, width: 700), fallbackText: next.name),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: Duration(seconds: seconds),
                    builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 3, color: Hy.orange, backgroundColor: Colors.white24),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${next.isEpisode ? 'NEXT EPISODE' : 'NEXT MOVIE'} IN $seconds',
          style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w800, letterSpacing: 1.5, fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(
          next.isEpisode ? '${next.episodeCode}  ${next.name}' : next.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            TextButton(onPressed: onWatchCredits, child: const Text('Watch credits')),
            const Spacer(),
            FilledButton.icon(
              onPressed: onPlay,
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play now'),
            ),
          ],
        ),
      ],
    ),
  );
}

/// "Previously on": before an episode of a show nobody has watched for a week or more.
/// Counts down and plays by itself; OK (TV) or Continue plays straight away.
class _Recap extends StatelessWidget {
  final Item episode;
  final bool resuming;
  final VoidCallback onContinue, onBack;
  const _Recap({required this.episode, required this.resuming, required this.onContinue, required this.onBack});
  static const seconds = 20;
  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 700;
    return Stack(
      fit: StackFit.expand,
      children: [
        NetImage(jf(context).thumb(episode, width: 1600), fallbackText: ''),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [Color(0xF2000000), Color(0xB3000000), Color(0x4D000000)],
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: narrow ? 28 : 72, vertical: 28),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        resuming ? 'WHERE YOU LEFT OFF' : 'PREVIOUSLY ON',
                        style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w800, letterSpacing: 2.5, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        episode.seriesName ?? '',
                        style: TextStyle(fontSize: narrow ? 26 : 38, fontWeight: FontWeight.w900, height: 1.05),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${episode.episodeCode}  “${episode.name}”',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Hy.textDim),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        (episode.overview ?? '').isEmpty ? 'No summary for this one.' : episode.overview!,
                        maxLines: narrow ? 5 : 8,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: narrow ? 14.5 : 17, height: 1.5),
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: 260,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: 1),
                          duration: const Duration(seconds: seconds),
                          onEnd: onContinue,
                          builder: (_, v, _) => LinearProgressIndicator(value: v, minHeight: 3, color: Hy.orange, backgroundColor: Colors.white24),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // The TV's OK presses Continue (see _overlayAction), so the buttons don't take focus there.
                      ExcludeFocus(
                        excluding: Device.isTv,
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 10,
                          children: [
                            FilledButton.icon(
                              onPressed: onContinue,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                                side: Device.isTv ? const BorderSide(color: Hy.orange, width: 3) : null,
                              ),
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(resuming ? 'Resume' : 'Play episode'),
                            ),
                            if (!Device.isTv) OutlinedButton(onPressed: onBack, child: const Text('Back')),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The sleep timer went off: paused, and leaving by itself in a minute.
class _Asleep extends StatelessWidget {
  final VoidCallback onContinue, onLeave;
  const _Asleep({required this.onContinue, required this.onLeave});
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black.withValues(alpha: .85),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bedtime_rounded, color: Hy.orange, size: 44),
        const SizedBox(height: 18),
        const Text('Sleep timer', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text(
          'Paused. Hevyfin closes the video in a minute.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Hy.textDim, fontSize: 16),
        ),
        const SizedBox(height: 26),
        ExcludeFocus(
          excluding: Device.isTv,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                onPressed: onContinue,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  side: Device.isTv ? const BorderSide(color: Hy.orange, width: 3) : null,
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Keep watching'),
              ),
              if (!Device.isTv) ...[const SizedBox(width: 12), OutlinedButton(onPressed: onLeave, child: const Text('Stop'))],
            ],
          ),
        ),
      ],
    ),
  );
}

/// After three episodes in a row with nobody touching anything.
class _StillWatching extends StatelessWidget {
  final String series;
  final VoidCallback onContinue, onLeave;
  const _StillWatching({required this.series, required this.onContinue, required this.onLeave});
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black.withValues(alpha: .85),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.bedtime_rounded, color: Hy.orange, size: 44),
        const SizedBox(height: 18),
        Text(
          series.isEmpty ? 'Are you still watching?' : 'Are you still watching $series?',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 26),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            FilledButton.icon(
              autofocus: true,
              onPressed: onContinue,
              style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Continue watching'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: onLeave, child: const Text('Back to browse')),
          ],
        ),
      ],
    ),
  );
}

class _NextUpCard extends StatelessWidget {
  final Item next;
  final int seconds;
  final VoidCallback onPlay, onCancel;
  const _NextUpCard({required this.next, required this.seconds, required this.onPlay, required this.onCancel});
  @override
  Widget build(BuildContext context) => Container(
    color: Colors.black.withValues(alpha: .75),
    alignment: Alignment.center,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(Hy.radius),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: NetImage(jf(context).thumb(next, width: 1000), fallbackText: next.name),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${next.isEpisode ? 'Next episode' : 'Next movie'} in $seconds',
            style: const TextStyle(color: Hy.orange, fontWeight: FontWeight.w800, letterSpacing: 1),
          ),
          const SizedBox(height: 6),
          Text(
            next.isEpisode ? '${next.episodeCode}  ${next.name}' : next.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: onPlay,
                style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Play now'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: onCancel, child: const Text('Back to browse')),
            ],
          ),
        ],
      ),
    ),
  );
}

/// Audio and subtitle picker.
class TracksSheet extends StatelessWidget {
  final Player player;
  final List<SubtitleTrack> external;

  /// mpv's own audio track id when it picked one itself (see [currentAid]).
  final String? aid;

  /// Called with the language picked (subtitle "off" for none).
  final void Function(String? audio, String? subtitle)? onChoice;
  const TracksSheet({super.key, required this.player, required this.external, this.aid, this.onChoice});

  static String _name(String? title, String? lang, String id) {
    final parts = [if (lang != null && lang.isNotEmpty) lang.toUpperCase(), if (title != null && title.isNotEmpty) title];
    return parts.isEmpty ? 'Track $id' : parts.join(' – ');
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<Tracks>(
    stream: player.stream.tracks,
    initialData: player.state.tracks,
    builder: (context, _) => StreamBuilder<Track>(
      stream: player.stream.track,
      initialData: player.state.track,
      builder: (context, snap) {
        final tracks = player.state.tracks;
        final cur = snap.data ?? player.state.track;
        final audio = tracks.audio.where((t) => t.id != 'auto' && t.id != 'no').toList();
        // "auto" means mpv picked one itself; which one is in its own `aid`.
        final playing = cur.audio.id == 'auto' ? aid : cur.audio.id;
        final subs = tracks.subtitle.where((t) => t.id != 'auto' && t.id != 'no').toList();
        final loaded = subs.map((s) => s.id).toSet();
        final extra = external.where((e) => !loaded.contains(e.id)).toList();

        Widget option(String label, bool selected, VoidCallback onTap) => ListTile(
          dense: true,
          autofocus: selected,
          onTap: onTap,
          leading: Icon(selected ? Icons.check_rounded : null, color: Hy.orange),
          title: Text(label, style: TextStyle(fontWeight: selected ? FontWeight.w800 : FontWeight.w500)),
        );

        final audioCol = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Audio', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            for (final a in audio)
              option(_name(a.title, a.language, a.id), playing == a.id, () {
                player.setAudioTrack(a);
                if ((a.language ?? '').isNotEmpty) onChoice?.call(a.language, null);
              }),
          ],
        );
        final subCol = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text('Subtitles', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            option('Off', cur.subtitle.id == 'no', () {
              player.setSubtitleTrack(SubtitleTrack.no());
              onChoice?.call(null, 'off');
            }),
            for (final s in [...subs, ...extra])
              option(_name(s.title, s.language, subs.contains(s) ? s.id : 'ext'), cur.subtitle.id == s.id, () {
                player.setSubtitleTrack(s);
                if ((s.language ?? '').isNotEmpty) onChoice?.call(null, s.language);
              }),
          ],
        );
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .7),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: isNarrow(context)
                  ? Column(children: [audioCol, const SizedBox(height: 12), subCol])
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: audioCol),
                        Expanded(child: subCol),
                      ],
                    ),
            ),
          ),
        );
      },
    ),
  );
}

/// Netflix's in-player episode browser: seasons across the top, episodes as cards.
class _EpisodesPanel extends StatefulWidget {
  final JellyfinClient client;
  final Item current;
  final ValueChanged<Item> onPick;
  const _EpisodesPanel({required this.client, required this.current, required this.onPick});
  @override
  State<_EpisodesPanel> createState() => _EpisodesPanelState();
}

class _EpisodesPanelState extends State<_EpisodesPanel> {
  List<Item>? _seasons;
  String? _seasonId;
  List<Item>? _episodes;

  @override
  void initState() {
    super.initState();
    _seasonId = widget.current.seasonId;
    widget.client.seasons(widget.current.seriesId!).then((s) => mounted ? setState(() => _seasons = s) : null);
    _load();
  }

  Future<void> _load() async {
    setState(() => _episodes = null);
    final e = await widget.client.episodes(widget.current.seriesId!, seasonId: _seasonId);
    if (mounted) setState(() => _episodes = e);
  }

  @override
  Widget build(BuildContext context) {
    final eps = _episodes;
    final idx = eps?.indexWhere((e) => e.id == widget.current.id) ?? -1;
    const cardW = 280.0;
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 6),
                  Text(widget.current.seriesName ?? '', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final s in _seasons ?? const <Item>[])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(s.name),
                                selected: s.id == _seasonId,
                                onSelected: (_) {
                                  setState(() => _seasonId = s.id);
                                  _load();
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: eps == null
                  ? const Center(child: CircularProgressIndicator(color: Hy.orange))
                  : ListView.separated(
                      controller: ScrollController(initialScrollOffset: idx > 0 ? (idx - .3) * (cardW + 14) : 0),
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                      itemCount: eps.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 14),
                      itemBuilder: (context, i) {
                        final e = eps[i];
                        final now = e.id == widget.current.id;
                        return FadeIn(
                          delay: Duration(milliseconds: 30 * (i - idx).abs().clamp(0, 8)),
                          from: const Offset(.1, 0),
                          child: HoverScale(
                            scale: 1.03,
                            // The remote starts on the episode that's playing.
                            autofocus: now,
                            onTap: () => widget.onPick(e),
                            child: SizedBox(
                              width: cardW,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(Hy.radius + 2),
                                      border: Border.all(color: now ? Hy.orange : Colors.transparent, width: 2),
                                    ),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(Hy.radius),
                                      child: AspectRatio(
                                        aspectRatio: 16 / 9,
                                        child: Stack(
                                          fit: StackFit.expand,
                                          children: [
                                            NetImage(widget.client.thumb(e, width: 600), fallbackText: e.name),
                                            Center(
                                              child: Icon(now ? Icons.equalizer_rounded : Icons.play_circle_outline_rounded, size: 40, color: Colors.white),
                                            ),
                                            if (e.progress != null && !e.played) Positioned(left: 0, right: 0, bottom: 0, child: ProgressStrip(e.progress!)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${e.indexNumber ?? ''}. ${e.name}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontWeight: FontWeight.w800, color: now ? Hy.orange : Colors.white),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    e.overview ?? '',
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Hy.textDim, fontSize: 12.5, height: 1.35),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// mpv language lists: "eng" also matches "en".
String mpvLangs(String iso3) => switch (iso3) {
  'eng' => 'eng,en',
  'dut' || 'nld' => 'dut,nld,nl',
  'fre' || 'fra' => 'fre,fra,fr',
  'ger' || 'deu' => 'ger,deu,de',
  'spa' => 'spa,es',
  'jpn' => 'jpn,ja',
  _ => iso3,
};

/// The audio track mpv is playing ('no' for none), also when it picked it itself.
Future<String?> currentAid(Player p) async {
  try {
    return await mpvGet(p, 'aid');
  } catch (_) {
    return null;
  }
}

/// Makes sure a video that has sound plays it: mpv can come out of loading a file with no
/// audio track selected (seen on Android going from one episode to the next), which plays
/// silently with nothing ticked under Audio. Picks the [lang] track, else the first.
Future<void> ensureAudio(Player p, String lang) async {
  try {
    final tracks = await p.stream.tracks
        .map((t) => t.audio.where((a) => a.id != 'auto' && a.id != 'no').toList())
        .firstWhere((a) => a.isNotEmpty)
        .timeout(const Duration(seconds: 20));
    // Give mpv its own go at choosing first.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (p.state.track.audio.id != 'auto' && p.state.track.audio.id != 'no') return;
    if (await currentAid(p) != 'no') return;
    final pick = tracks.where((a) => langMatches(a.language, lang)).firstOrNull ?? tracks.first;
    debugPrint('no audio track selected, picking ${pick.id} (${pick.language})');
    await p.setAudioTrack(pick);
  } catch (_) {}
}

bool langMatches(String? lang, String want) => lang != null && mpvLangs(want).split(',').contains(lang.toLowerCase());

/// Subtitle text colours on offer (Settings, Subtitles).
const subColors = {'white': Colors.white, 'yellow': Color(0xFFFFE14D)};

/// mpv's own subtitle look (the desktop, where libass draws them), matching the settings.
Future<void> mpvSubStyle(Player p, AppState app) async {
  try {
    await mpvSet(p, 'sub-scale', '${app.subSize}');
    await mpvSet(p, 'sub-color', app.subColor == 'yellow' ? '#FFFFE14D' : '#FFFFFFFF');
    await mpvSet(p, 'sub-border-style', app.subBox ? 'background-box' : 'outline-and-shadow');
    await mpvSet(p, 'sub-back-color', '#B0000000');
  } catch (e) {
    debugPrint('subtitle style: $e');
  }
}
