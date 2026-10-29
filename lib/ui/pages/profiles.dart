import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/device.dart';
import '../../theme.dart';
import '../shell.dart';
import '../widgets/common.dart';

/// Each profile's own colour, by position.
const _colors = [
  [Color(0xFFFF8A1F), Color(0xFFFF4D2E)],
  [Color(0xFF4FC3F7), Color(0xFF3A6FF7)],
  [Color(0xFF66E3A1), Color(0xFF1FA67A)],
  [Color(0xFFF06BD0), Color(0xFF9B5CF6)],
  [Color(0xFFFFD54F), Color(0xFFFF9F1C)],
];

/// "Who's watching?": everyone signed in on this device, plus adding someone. Each
/// profile is its own Jellyfin account, so Continue watching, My List and requests follow it.
class ProfilesPage extends StatefulWidget {
  const ProfilesPage({super.key});
  @override
  State<ProfilesPage> createState() => _ProfilesPageState();
}

class _ProfilesPageState extends State<ProfilesPage> {
  bool _manage = false;
  String? _busy;

  Future<void> _open(Profile p) async {
    final app = context.read<AppState>();
    if (_manage) return _edit(p);
    if (p.pin != null) {
      final pin = await _askPin(context, 'Enter ${p.name}\'s PIN');
      if (pin == null) return;
      if (!app.pinMatches(p, pin)) {
        if (mounted) toast(context, 'Wrong PIN');
        return;
      }
    }
    setState(() => _busy = p.userId);
    try {
      await app.switchTo(p);
    } catch (e) {
      if (mounted) toast(context, "Couldn't switch: $e");
    }
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _edit(Profile p) async {
    final app = context.read<AppState>();
    final choice = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        backgroundColor: Hy.surface,
        title: Text(p.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'pin'),
            child: ListTile(leading: const Icon(Icons.lock_rounded), title: Text(p.pin == null ? 'Add a PIN' : 'Change the PIN')),
          ),
          if (p.pin != null)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, 'nopin'),
              child: const ListTile(leading: Icon(Icons.lock_open_rounded), title: Text('Remove the PIN')),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, 'remove'),
            child: const ListTile(
              leading: Icon(Icons.person_remove_rounded, color: Hy.danger),
              title: Text('Remove from this device', style: TextStyle(color: Hy.danger)),
            ),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    // Changing or removing a PIN needs the current one.
    if (p.pin != null && choice != 'remove') {
      final old = await _askPin(context, 'Current PIN');
      if (old == null || !app.pinMatches(p, old)) {
        if (mounted && old != null) toast(context, 'Wrong PIN');
        return;
      }
    }
    if (!mounted) return;
    switch (choice) {
      case 'pin':
        final pin = await _askPin(context, 'New 4-digit PIN');
        if (pin != null) await app.setPin(p, pin);
      case 'nopin':
        await app.setPin(p, null);
      case 'remove':
        await app.removeProfile(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final wide = MediaQuery.sizeOf(context).width > 700;
    final tile = wide ? 150.0 : 104.0;
    return PopScope(
      // Back from the picker returns to whoever was watching.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && app.loggedIn) {
          app.choosing = false;
          app.bump();
        }
      },
      child: Scaffold(
        body: Container(
          decoration: const BoxDecoration(
            gradient: RadialGradient(center: Alignment(0, -1.1), radius: 1.3, colors: [Color(0xFF2A1405), Hy.bg]),
          ),
          child: SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 28),
                const Wordmark(size: 30),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _manage ? 'Manage profiles' : "Who's watching?",
                            style: TextStyle(fontSize: wide ? 44 : 28, fontWeight: FontWeight.w800, letterSpacing: -.5),
                          ),
                          SizedBox(height: wide ? 40 : 28),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: wide ? 28 : 18,
                            runSpacing: 22,
                            children: [
                              for (final (i, p) in app.profiles.indexed)
                                _Tile(
                                  size: tile,
                                  name: p.name,
                                  colors: _colors[i % _colors.length],
                                  locked: p.pin != null,
                                  editing: _manage,
                                  busy: _busy == p.userId,
                                  autofocus: i == 0,
                                  onTap: () => _open(p),
                                ),
                              if (!_manage) _Tile(size: tile, name: 'Add profile', add: true, onTap: () => app.startAdding(true)),
                            ],
                          ),
                          SizedBox(height: wide ? 48 : 34),
                          OutlinedButton(onPressed: () => setState(() => _manage = !_manage), child: Text(_manage ? 'Done' : 'Manage profiles')),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final double size;
  final String name;
  final List<Color> colors;
  final bool add, locked, editing, busy, autofocus;
  final VoidCallback onTap;
  const _Tile({
    required this.size,
    required this.name,
    required this.onTap,
    this.colors = const [Hy.surface, Hy.surface],
    this.add = false,
    this.locked = false,
    this.editing = false,
    this.busy = false,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) => HoverScale(
    scale: 1.06,
    autofocus: autofocus && Device.isTv,
    onTap: onTap,
    child: SizedBox(
      width: size,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: add ? null : LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              color: add ? Colors.white10 : null,
              borderRadius: BorderRadius.circular(size * .12),
              border: add ? Border.all(color: Colors.white24, width: 2) : null,
            ),
            child: busy
                ? const CircularProgressIndicator(color: Colors.black)
                : add
                ? Icon(Icons.add_rounded, size: size * .42, color: Colors.white70)
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      Text(
                        name.isEmpty ? '?' : name[0].toUpperCase(),
                        style: TextStyle(fontSize: size * .5, fontWeight: FontWeight.w900, color: Colors.black.withValues(alpha: .8)),
                      ),
                      if (editing)
                        Container(
                          decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(size * .12)),
                          child: Center(
                            child: Icon(Icons.edit_rounded, size: size * .3, color: Colors.white),
                          ),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w600),
                ),
              ),
              if (locked) ...[const SizedBox(width: 4), const Icon(Icons.lock_rounded, size: 14, color: Hy.textMute)],
            ],
          ),
        ],
      ),
    ),
  );
}

/// Asks for a 4-digit PIN; null if cancelled.
Future<String?> _askPin(BuildContext context, String title) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (d) => AlertDialog(
      backgroundColor: Hy.surface,
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        obscureText: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 28, letterSpacing: 16),
        onSubmitted: (v) => v.length == 4 ? Navigator.pop(d, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        FilledButton(onPressed: () => c.text.length == 4 ? Navigator.pop(d, c.text) : null, child: const Text('OK')),
      ],
    ),
  );
}
