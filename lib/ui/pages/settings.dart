import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../api/niql.dart';
import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../theme.dart';
import '../player.dart' show subColors;
import '../shell.dart';
import '../widgets/common.dart';
import 'discover.dart';
import '../../host.dart';

const _languages = {'eng': 'English', 'dut': 'Dutch', 'fre': 'French', 'ger': 'German', 'spa': 'Spanish', 'jpn': 'Japanese'};
const _qualities = {0: 'Original (no transcoding)', 40: '40 Mbps', 20: '20 Mbps – 1080p', 10: '10 Mbps', 6: '6 Mbps – 720p', 3: '3 Mbps – mobile data'};

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final AppState _app = context.read<AppState>();
  late final _server = TextEditingController(text: _app.server);
  late final _fallback = TextEditingController(text: _app.fallback);
  late final _seerr = TextEditingController(text: _app.seerrOverride);
  late final _niql = TextEditingController(text: Niql.configured);

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final pad = pagePadding(context);
    Widget section(String t) => Padding(
      padding: const EdgeInsets.fromLTRB(0, 28, 0, 10),
      child: Text(
        t,
        style: const TextStyle(fontSize: 13, letterSpacing: 2, fontWeight: FontWeight.w800, color: Hy.orange),
      ),
    );

    return ListView(
      padding: EdgeInsets.fromLTRB(pad, topInset(context) + 8, pad, 60),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Settings', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                section('ACCOUNT'),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_rounded),
                  title: Text(app.userName),
                  subtitle: Text('Connected to ${app.client?.server ?? '-'}${app.offline ? ' (offline)' : ''}'),
                  trailing: OutlinedButton(onPressed: () => app.logout(), child: const Text('Sign out')),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.switch_account_rounded),
                  title: const Text('Switch profile'),
                  subtitle: Text('${app.profiles.length} on this device · add, lock with a PIN or remove under Manage profiles'),
                  onTap: app.chooseProfile,
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.confirmation_number_rounded),
                  title: const Text('Ticket stubs'),
                  subtitle: const Text('Every Cinema mode showing watched to the end'),
                  onTap: () => context.push('/tickets'),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.tv_rounded),
                  title: const Text('Sign in a TV'),
                  subtitle: const Text('Enter the code Hevyfin shows on your TV'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _approveTv(context, app),
                ),
                section('PLAYBACK'),
                _Dropdown<String>(label: 'Audio language', value: app.audioLang, items: _languages, onChanged: app.setAudioLang),
                _Dropdown<String>(label: 'Subtitles by default', value: app.subtitleLang, items: {'': 'Off', ..._languages}, onChanged: app.setSubtitleLang),
                _Dropdown<double>(
                  label: 'Subtitle size',
                  value: app.subSize,
                  items: {.8: 'Small', 1.0: 'Normal', 1.25: 'Large', 1.5: 'Extra large'},
                  onChanged: (v) => app.setSubStyle(size: v),
                ),
                _Dropdown<String>(
                  label: 'Subtitle colour',
                  value: app.subColor,
                  items: const {'white': 'White', 'yellow': 'Yellow'},
                  onChanged: (v) => app.setSubStyle(color: v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Dark box behind subtitles', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  value: app.subBox,
                  onChanged: (v) => app.setSubStyle(box: v),
                ),
                const _SubtitlePreview(),
                const SizedBox(height: 10),
                if (Device.isTv)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Trailer previews', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Resting on a title plays its trailer silently behind it.'),
                    value: app.trailerPreviews,
                    onChanged: app.setTrailerPreviews,
                  ),
                if (Device.isTv)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Dolby passthrough', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                    subtitle: const Text('Sends Dolby sound untouched to the TV or soundbar. Off: decoded here, which always plays.'),
                    value: app.passthrough,
                    onChanged: app.setPassthrough,
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Skip intros and recaps', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
                  subtitle: const Text('Jump straight past them instead of showing a Skip button.'),
                  value: app.autoSkip,
                  onChanged: app.setAutoSkip,
                ),
                _Dropdown<int>(label: 'Streaming quality', value: app.maxMbps, items: _qualities, onChanged: app.setMaxMbps),
                const Text(
                  'Original plays the file as-is (best quality). A cap makes the server transcode on its GPU: handy away from home.',
                  style: TextStyle(color: Hy.textMute, fontSize: 13),
                ),
                // The web version always talks to the server it was opened from.
                if (!Host.isWeb) ...[
                  section('SERVERS'),
                  TextField(
                    controller: _server,
                    decoration: const InputDecoration(labelText: 'Jellyfin server'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fallback,
                    decoration: const InputDecoration(labelText: 'Second address (optional, e.g. a VPN for when you\'re away)'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      await app.setServers(_server.text, _fallback.text);
                      if (context.mounted) toast(context, app.offline ? 'Neither server answered' : 'Connected to ${app.client!.server}');
                    },
                    child: const Text('Save & reconnect'),
                  ),
                ],
                section('SEERR (REQUESTS)'),
                if (!Host.isWeb) ...[
                  TextField(
                    controller: _seerr,
                    decoration: InputDecoration(labelText: 'Seerr address', hintText: 'Automatic: ${app.seerrUrl}'),
                    onSubmitted: app.setSeerrOverride,
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Icon(
                      app.seerrReady ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                      color: app.seerrReady ? const Color(0xFF2ECC71) : Hy.textMute,
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(app.seerrReady ? 'Signed in to Seerr at ${app.seerrUrl}' : 'Not signed in to Seerr')),
                    if (!Host.isWeb) OutlinedButton(onPressed: () => app.setSeerrOverride(_seerr.text), child: const Text('Save')),
                  ],
                ),
                if (!app.seerrReady) const SizedBox(height: 380, child: SeerrConnect(compact: true)),
                if (!Host.isWeb) ...[
                  section('ASK (OPTIONAL)'),
                  const Text(
                    'A recommendation service of your own that answers "what should I watch?" questions. '
                    'Leave it empty to hide Ask. Questions are sent there with your Jellyfin sign-in.',
                    style: TextStyle(color: Hy.textMute, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _niql,
                          keyboardType: TextInputType.url,
                          decoration: const InputDecoration(labelText: 'Recommendation service address', hintText: 'Off'),
                          onSubmitted: app.setNiqlUrl,
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton(onPressed: () => app.setNiqlUrl(_niql.text), child: const Text('Save')),
                    ],
                  ),
                ],
                section('ABOUT'),
                const Text(
                  'Hevyfin $appVersion · a free Jellyfin + Seerr client (GPL-3.0) · github.com/NickHemeryckeHevan/Hevyfin',
                  style: TextStyle(color: Hy.textMute),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// What subtitles will look like, on a frame-ish dark background.
class _SubtitlePreview extends StatelessWidget {
  const _SubtitlePreview();
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Container(
      height: 110,
      width: double.infinity,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Hy.radius),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF3A4A5A), Color(0xFF1A1410)]),
      ),
      child: Text(
        'This is how subtitles look.',
        style: TextStyle(
          fontSize: 24 * app.subSize,
          color: subColors[app.subColor] ?? Colors.white,
          fontWeight: FontWeight.w600,
          backgroundColor: app.subBox ? const Color(0xB0000000) : null,
          shadows: app.subBox ? null : const [Shadow(blurRadius: 8), Shadow(blurRadius: 3), Shadow(offset: Offset(1, 1), blurRadius: 2)],
        ),
      ),
    );
  }
}

class _Dropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final Map<T, String> items;
  final ValueChanged<T> onChanged;
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
        ),
        DropdownButton<T>(
          value: items.containsKey(value) ? value : items.keys.first,
          dropdownColor: Hy.surfaceHigh,
          underline: const SizedBox.shrink(),
          items: [for (final e in items.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: (v) => v == null ? null : onChanged(v),
        ),
      ],
    ),
  );
}

/// Quick Connect from this side: approve the code a TV is showing.
Future<void> _approveTv(BuildContext context, AppState app) async {
  final ctrl = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: Hy.surface,
      title: const Text('Sign in a TV'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Type the code shown on the TV.', style: TextStyle(color: Hy.textDim)),
          const SizedBox(height: 14),
          TextField(
            controller: ctrl,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 8),
            decoration: const InputDecoration(hintText: 'CODE'),
            onSubmitted: (v) => Navigator.pop(c, v),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('Approve')),
      ],
    ),
  );
  if (code == null || code.trim().isEmpty || !context.mounted) return;
  try {
    await app.client!.quickConnectApprove(code);
    if (context.mounted) toast(context, 'TV approved. It signs in within a few seconds.');
  } catch (e) {
    if (context.mounted) toast(context, '$e');
  }
}
