// Other devices: start something on the TV from the phone and steer it (phone as remote),
// and watch parties (Jellyfin SyncPlay) that keep several players in step.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../state/app_state.dart';
import '../../state/link.dart';
import '../../theme.dart';
import 'billboard.dart' show playTarget;
import 'common.dart';

Future<void> _sheet(BuildContext context, Widget child) => showModalBottomSheet(
  context: context,
  backgroundColor: Hy.surface,
  isScrollControlled: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => SafeArea(child: child),
);

/// "Play on…": the account's other devices with Hevyfin (or another Jellyfin app) open.
/// With [item] it starts that there; without, it opens the remote for the chosen device.
Future<void> showPlayOn(BuildContext context, {Item? item}) => _sheet(context, _PlayOn(item: item));

class _PlayOn extends StatefulWidget {
  final Item? item;
  const _PlayOn({this.item});
  @override
  State<_PlayOn> createState() => _PlayOnState();
}

class _PlayOnState extends State<_PlayOn> {
  List<RemoteSession>? _list;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await jf(context).remoteSessions();
      if (mounted) setState(() => _list = l);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pick(RemoteSession s) async {
    final c = jf(context);
    final nav = Navigator.of(context);
    final item = widget.item;
    try {
      if (item != null) {
        final target = await playTarget(c, item, story: context.read<AppState>().storyOrder.contains(item.id));
        if (target == null) throw 'Nothing to play';
        await c.playOn(s.id, target.id, start: target.resumePosition);
      }
      nav.pop();
      if (nav.mounted) unawaited(_sheet(nav.context, RemoteControl(sessionId: s.id, device: s.device)));
    } catch (e) {
      if (mounted) toast(context, "Couldn't reach ${s.device}: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(widget.item == null ? 'Control a device' : 'Play on…', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('$_error', style: const TextStyle(color: Hy.textDim)),
            )
          else if (list == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: Hy.orange)),
            )
          else if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No other device is on. Open Hevyfin on the TV (or another device) and try again.', style: TextStyle(color: Hy.textDim)),
            )
          else
            for (final s in list)
              ListTile(
                leading: Icon(_icon(s), color: Hy.orange),
                title: Text(s.device, style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                  s.nowPlaying == null ? s.client : 'Playing ${s.nowPlaying!.displayTitle}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Hy.textDim),
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _pick(s),
              ),
        ],
      ),
    );
  }

  static IconData _icon(RemoteSession s) {
    final d = '${s.device} ${s.client}'.toLowerCase();
    if (d.contains('tv') || d.contains('chromecast') || d.contains('sabrina')) return Icons.tv_rounded;
    if (d.contains('android') || d.contains('phone')) return Icons.smartphone_rounded;
    return Icons.computer_rounded;
  }
}

/// A remote for another device: what's on, a progress bar, and the buttons.
class RemoteControl extends StatefulWidget {
  final String sessionId, device;
  const RemoteControl({super.key, required this.sessionId, required this.device});
  @override
  State<RemoteControl> createState() => _RemoteControlState();
}

class _RemoteControlState extends State<RemoteControl> {
  RemoteSession? _s;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _refresh();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final all = await jf(context).remoteSessions();
      if (mounted) setState(() => _s = all.where((s) => s.id == widget.sessionId).firstOrNull);
    } catch (_) {}
  }

  Future<void> _cmd(String c, {Duration? seek}) async {
    try {
      await jf(context).commandOn(widget.sessionId, c, seek: seek);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _refresh();
    } catch (e) {
      if (mounted) toast(context, "Couldn't reach ${widget.device}");
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s, now = s?.nowPlaying;
    final len = now?.runtime ?? Duration.zero;
    final pos = s?.position ?? Duration.zero;
    String fmt(Duration d) =>
        '${d.inHours > 0 ? '${d.inHours}:' : ''}${(d.inMinutes % 60).toString().padLeft(d.inHours > 0 ? 2 : 1, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              const Icon(Icons.settings_remote_rounded, color: Hy.orange),
              const SizedBox(width: 10),
              Expanded(
                child: Text(widget.device, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (now == null)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Nothing playing there right now.', style: TextStyle(color: Hy.textDim)),
            )
          else ...[
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(Hy.radius),
                  child: SizedBox(
                    width: 120,
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: NetImage(jf(context).thumb(now, width: 400), fallbackText: now.name),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        now.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                      if (now.isEpisode)
                        Text(
                          '${now.episodeCode}  ${now.name}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Hy.textDim),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Slider(value: len.inSeconds == 0 ? 0 : (pos.inSeconds / len.inSeconds).clamp(0, 1), activeColor: Hy.orange, onChanged: null),
            Row(
              children: [
                Text(
                  fmt(pos),
                  style: const TextStyle(color: Hy.textDim, fontFeatures: [FontFeature.tabularFigures()]),
                ),
                const Spacer(),
                Text(
                  fmt(len),
                  style: const TextStyle(color: Hy.textDim, fontFeatures: [FontFeature.tabularFigures()]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  iconSize: 34,
                  onPressed: () => _cmd('Seek', seek: pos - const Duration(seconds: 10)),
                  icon: const Icon(Icons.replay_10_rounded),
                ),
                IconButton.filled(
                  iconSize: 44,
                  style: IconButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
                  onPressed: () => _cmd('PlayPause'),
                  icon: Icon(s!.paused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                ),
                IconButton(
                  iconSize: 34,
                  onPressed: () => _cmd('Seek', seek: pos + const Duration(seconds: 30)),
                  icon: const Icon(Icons.forward_30_rounded),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (now.isEpisode)
                  TextButton.icon(onPressed: () => _cmd('NextTrack'), icon: const Icon(Icons.skip_next_rounded), label: const Text('Next episode')),
                TextButton.icon(
                  onPressed: () => _cmd('Stop'),
                  icon: const Icon(Icons.stop_rounded, color: Hy.danger),
                  label: const Text('Stop', style: TextStyle(color: Hy.danger)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Watch together: start a party around [item], or join one someone else started.
Future<void> showWatchTogether(BuildContext context, {Item? item}) => _sheet(context, _Together(item: item));

class _Together extends StatefulWidget {
  final Item? item;
  const _Together({this.item});
  @override
  State<_Together> createState() => _TogetherState();
}

class _TogetherState extends State<_Together> {
  List<Map<String, dynamic>>? _groups;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    jf(context).syncGroups().then((g) => mounted ? setState(() => _groups = g) : null).catchError((_) => mounted ? setState(() => _groups = []) : null);
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        toast(context, "Couldn't do that: $e");
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final link = context.watch<Link>();
    final item = widget.item;
    final groups = _groups;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Watch together', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text(
              'Everyone in the party sees the same moment: pause, skip or seek on one device and it happens on all of them.',
              style: TextStyle(color: Hy.textDim, height: 1.35),
            ),
          ),
          if (link.inParty)
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Hy.danger),
              title: Text('Leave ${link.party!.name}'),
              subtitle: Text(link.party!.people.join(', '), style: const TextStyle(color: Hy.textDim)),
              onTap: _busy ? null : () => _run(link.leaveParty),
            ),
          if (item != null)
            ListTile(
              leading: const Icon(Icons.celebration_rounded, color: Hy.orange),
              title: Text('Start a party with ${item.displayTitle}', style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Others join from their own Hevyfin', style: TextStyle(color: Hy.textDim)),
              onTap: _busy
                  ? null
                  : () => _run(() async {
                      final target = await playTarget(jf(context), item, story: context.read<AppState>().storyOrder.contains(item.id));
                      if (target == null) throw 'Nothing to play';
                      await link.startParty(target);
                    }),
            ),
          if (groups == null)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator(color: Hy.orange)),
            )
          else
            for (final g in groups.where((g) => g['GroupId'] != link.party?.id))
              ListTile(
                leading: const Icon(Icons.groups_rounded, color: Hy.orange),
                title: Text('Join ${g['GroupName'] ?? 'a party'}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(((g['Participants'] as List?) ?? const []).join(', '), style: const TextStyle(color: Hy.textDim)),
                onTap: _busy ? null : () => _run(() => link.joinParty(g['GroupId'] as String)),
              ),
          if (groups != null && groups.isEmpty && item == null)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('No party going on. Start one from a movie or show (Watch together).', style: TextStyle(color: Hy.textDim)),
            ),
        ],
      ),
    );
  }
}
