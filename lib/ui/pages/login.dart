import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../theme.dart';
import '../shell.dart';
import '../../host.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  late final AppState _app = context.read<AppState>();
  late final _server = TextEditingController(text: _app.server);
  late final _fallback = TextEditingController(text: _app.fallback);
  final _user = TextEditingController();
  final _pw = TextEditingController();
  bool _busy = false;
  // The server fields show until a server is known.
  late bool _advanced = _app.server.isEmpty && !Host.isWeb;
  String? _error;

  Future<void> _submit() async {
    if (_user.text.trim().isEmpty) return setState(() => _error = 'Enter your Jellyfin username');
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _app.login(server: _server.text, fallback: _fallback.text, username: _user.text, password: _pw.text);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Container(
      decoration: const BoxDecoration(
        gradient: RadialGradient(center: Alignment(-.6, -.8), radius: 1.4, colors: [Color(0xFF3A1A05), Hy.bg]),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Center(child: Wordmark(size: 52)),
                  const SizedBox(height: 36),
                  Text(_app.adding ? 'Add a profile' : 'Sign in', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('Use your Jellyfin account. Seerr requests use the same login.', style: TextStyle(color: Hy.textDim)),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _user,
                    autofocus: true,
                    autofillHints: const [AutofillHints.username],
                    decoration: const InputDecoration(hintText: 'Username'),
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pw,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(hintText: 'Password'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (_advanced) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'Jellyfin server', hintText: 'http://jellyfin.local:8096'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _fallback,
                      decoration: const InputDecoration(labelText: 'Second address (optional, e.g. a VPN for when you\'re away)'),
                    ),
                  ],
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: const TextStyle(color: Hy.danger)),
                    ),
                  const SizedBox(height: 22),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Text('Sign in'),
                  ),
                  if (_app.adding) ...[const SizedBox(height: 8), OutlinedButton(onPressed: () => _app.startAdding(false), child: const Text('Cancel'))],
                  const SizedBox(height: 8),
                  // The web version signs in to the server it was opened from.
                  if (!Host.isWeb)
                    TextButton(
                      onPressed: () => setState(() => _advanced = !_advanced),
                      child: Text(
                        _advanced
                            ? 'Hide server settings'
                            : 'Server: ${Uri.tryParse(normalizeServer(_server.text))?.host ?? _server.text}',
                        style: const TextStyle(color: Hy.textMute),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
