import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../api/jellyfin.dart';
import '../../state/device.dart';
import '../../state/free_tv.dart';
import '../../state/live.dart' as live show channels;
import '../../theme.dart';
import '../widgets/common.dart';
import '../widgets/screensaver.dart';

/// A free channel (5 and up) full screen, like a TV: up and down change channel, OK shows
/// what's on, Back goes back to the guide. The broadcaster's own stream plays as it is.
class FreeTvPlayer extends StatefulWidget {
  final String channelId;
  const FreeTvPlayer({super.key, required this.channelId});
  @override
  State<FreeTvPlayer> createState() => _FreeTvPlayerState();
}

class _FreeTvPlayerState extends State<FreeTvPlayer> {
  static const own = live.channels;

  late final _player = Player(
    configuration: const PlayerConfiguration(title: 'Hevyfin', bufferSize: 32 << 20),
  );
  late final _video = VideoController(
    _player,
    configuration: Device.isTv ? const VideoControllerConfiguration(vo: 'mediacodec_embed', hwdec: 'mediacodec') : const VideoControllerConfiguration(),
  );
  final _focus = FocusNode(debugLabel: 'freetv');
  late String _id = widget.channelId;
  String? _error;
  bool _banner = true;
  Timer? _hide, _tick, _tune;

  @override
  void initState() {
    super.initState();
    Screensaver.players.value++;
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => mounted ? setState(() {}) : null);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await FreeTv.load(jf(context));
      if (mounted) _play(_id);
    });
  }

  @override
  void dispose() {
    Screensaver.players.value--;
    _hide?.cancel();
    _tick?.cancel();
    _tune?.cancel();
    _focus.dispose();
    _player.dispose();
    super.dispose();
  }

  Item? get _channel => FreeTv.channels.where((c) => c.id == _id).firstOrNull;

  Future<void> _play(String id) async {
    setState(() => _error = null);
    _showBanner();
    try {
      final url = await FreeTv.stream(jf(context), id);
      if (!mounted || id != _id) return;
      if (url == null) throw Exception('no stream');
      await _player.open(Media(url));
    } catch (_) {
      if (mounted && id == _id) setState(() => _error = "This channel isn't available right now.");
    }
  }

  /// Up/down: the next or previous channel, tuned once the remote stops for a moment. Past
  /// either end it carries on into Hevyfin's own channels (1-4), like one line of channels.
  void _zap(int step) {
    final list = FreeTv.channels;
    if (list.isEmpty) return;
    final i = list.indexWhere((c) => c.id == _id) + step;
    if (i < 0 || i >= list.length) {
      context.pushReplacement('/live/channel/${i < 0 ? own.length : 1}');
      return;
    }
    setState(() => _id = list[i].id);
    _showBanner();
    _player.stop();
    _tune?.cancel();
    _tune = Timer(const Duration(milliseconds: 350), () => _play(_id));
  }

  void _showBanner() {
    setState(() => _banner = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 6), () => mounted ? setState(() => _banner = false) : null);
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      _zap(1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      _zap(-1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) {
      _banner ? setState(() => _banner = false) : _showBanner();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: GestureDetector(
        onTap: () => _banner ? setState(() => _banner = false) : _showBanner(),
        onVerticalDragEnd: (d) => _zap((d.primaryVelocity ?? 0) < 0 ? 1 : -1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Video(controller: _video, controls: NoVideoControls, fill: Colors.black),
            StreamBuilder<bool>(
              stream: _player.stream.buffering,
              builder: (_, b) =>
                  (b.data ?? true) && _error == null ? const Center(child: CircularProgressIndicator(color: Hy.orange)) : const SizedBox.shrink(),
            ),
            if (_error != null)
              Center(
                child: Text(_error!, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedSlide(
                offset: _banner ? Offset.zero : const Offset(0, 1),
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _banner ? 1 : 0,
                  duration: const Duration(milliseconds: 280),
                  child: _Banner(channel: _channel),
                ),
              ),
            ),
            if (!Device.isTv)
              Positioned(
                top: 12,
                left: 12,
                child: SafeArea(
                  child: IconButton(
                    onPressed: () => context.pop(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// What's on: channel, programme, how long it has left, and what's next.
class _Banner extends StatelessWidget {
  final Item? channel;
  const _Banner({required this.channel});

  @override
  Widget build(BuildContext context) {
    final ch = channel;
    if (ch == null) return const SizedBox.shrink();
    final now = DateTime.now();
    final p = FreeTv.now(ch.id, now);
    final next = FreeTv.on(ch.id).where((x) => x.startDate != null && !x.startDate!.isBefore(p?.endDate ?? now)).firstOrNull;
    final c = jf(context);
    String hm(DateTime t) => clockTime(t);
    final progress = p == null ? null : now.difference(p.startDate!).inSeconds / p.endDate!.difference(p.startDate!).inSeconds.clamp(1, 1 << 30);
    final left = p?.endDate?.difference(now);
    return Container(
      padding: const EdgeInsets.fromLTRB(64, 60, 64, 44),
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Color(0xF2000000)]),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                ch.channelNumber ?? '',
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Hy.orange, height: 1),
              ),
              const SizedBox(height: 8),
              if (ch.imageTags['Primary'] != null) Image.network(c.image(ch.id, type: 'Primary', width: 240), height: 44, width: 140, fit: BoxFit.contain),
            ],
          ),
          const SizedBox(width: 28),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ch.name.toUpperCase(),
                  style: const TextStyle(color: Hy.textDim, letterSpacing: 2.4, fontWeight: FontWeight.w800, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  p?.name ?? 'Live',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, letterSpacing: -.5),
                ),
                if ((p?.episodeTitle ?? '').isNotEmpty)
                  Text(
                    p!.episodeTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                  ),
                if (p != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '${hm(p.startDate!)} – ${hm(p.endDate!)}',
                        style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 14),
                      SizedBox(
                        width: 260,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(value: progress!.clamp(0, 1), minHeight: 4, color: Hy.orange, backgroundColor: Colors.white24),
                        ),
                      ),
                      const SizedBox(width: 14),
                      if (left != null)
                        Text(
                          '${left.inMinutes} min left',
                          style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ],
                if ((p?.overview ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    p!.overview!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFFDDDDDD), height: 1.35),
                  ),
                ],
              ],
            ),
          ),
          if (next != null) ...[
            const SizedBox(width: 28),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'NEXT',
                  style: TextStyle(color: Hy.textDim, letterSpacing: 2.4, fontWeight: FontWeight.w800, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text('${hm(next.startDate!)}  ${next.name}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ],
            ),
          ],
          const SizedBox(width: 20),
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_up_rounded, color: Hy.textDim),
              Text(
                'CH',
                style: TextStyle(color: Hy.textDim, fontWeight: FontWeight.w900, fontSize: 12),
              ),
              Icon(Icons.keyboard_arrow_down_rounded, color: Hy.textDim),
            ],
          ),
        ],
      ),
    );
  }
}
