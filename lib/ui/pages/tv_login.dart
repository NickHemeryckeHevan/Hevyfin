import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/jellyfin.dart';
import '../../state/app_state.dart';
import '../../theme.dart';
import '../shell.dart';
import '../widgets/common.dart';
import 'login.dart';

/// Signing in on a TV without typing: show a Quick Connect code and wait until it is
/// approved from Hevyfin (Settings → Sign in a TV) or Jellyfin on another device.
class TvLoginPage extends StatefulWidget {
  const TvLoginPage({super.key});
  @override
  State<TvLoginPage> createState() => _TvLoginPageState();
}

class _TvLoginPageState extends State<TvLoginPage> {
  late final AppState _app = context.read<AppState>();
  JellyfinClient? _client;
  String? _secret, _code, _error;
  Timer? _poll;
  final _server = TextEditingController();

  /// No server known yet (first start): ask for its address before asking for a code.
  bool get _needServer => _app.server.isEmpty;

  Future<void> _setServer() async {
    if (normalizeServer(_server.text).isEmpty) return;
    await _app.setServers(_server.text, '');
    _start();
  }

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _server.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    _poll?.cancel();
    setState(() {
      _code = null;
      _error = null;
    });
    if (_needServer) return;
    try {
      final c = await _app.reachable(server: _app.server, fallback: _app.fallback);
      final (secret, code) = await c.quickConnectStart();
      if (!mounted) return;
      setState(() {
        _client = c;
        _secret = secret;
        _code = code;
      });
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _check());
    } catch (e) {
      if (mounted) setState(() => _error = "Couldn't start Quick Connect: $e");
    }
  }

  Future<void> _check() async {
    final c = _client, secret = _secret;
    if (c == null || secret == null) return;
    try {
      if (!await c.quickConnectApproved(secret)) return;
      _poll?.cancel();
      await _app.loginQuickConnect(c, secret, server: _app.server, fallback: _app.fallback);
    } catch (e) {
      // The code expired: get a fresh one.
      _poll?.cancel();
      if (mounted) _start();
    }
  }

  @override
  Widget build(BuildContext context) {
    final code = _code;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(center: Alignment(-.7, -.8), radius: 1.5, colors: [Color(0xFF3A1A05), Hy.bg]),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 64, vertical: 40),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Wordmark(size: 44),
                  const SizedBox(height: 28),
                  const Text('Sign in to watch', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 18),
                  const _Step(n: 1, text: 'On your phone or computer, open Hevyfin → profile → Settings → Sign in a TV.'),
                  const _Step(n: 2, text: 'Enter the code on the right. This screen signs in by itself.'),
                  const SizedBox(height: 8),
                  const Text('Jellyfin works too: Settings → Quick Connect.', style: TextStyle(color: Hy.textMute)),
                  const SizedBox(height: 28),
                  Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      OutlinedButton.icon(onPressed: _start, icon: const Icon(Icons.refresh_rounded), label: const Text('New code')),
                      if (_app.adding)
                        OutlinedButton.icon(onPressed: () => _app.startAdding(false), icon: const Icon(Icons.close_rounded), label: const Text('Cancel')),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LoginPage())),
                        icon: const Icon(Icons.keyboard_rounded),
                        label: const Text('Use a password instead'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 48),
            Expanded(
              child: Center(
                child: _needServer
                    ? ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Your Jellyfin server', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _server,
                              autofocus: true,
                              keyboardType: TextInputType.url,
                              decoration: const InputDecoration(hintText: 'http://jellyfin.local:8096'),
                              onSubmitted: (_) => _setServer(),
                            ),
                            const SizedBox(height: 14),
                            FilledButton(onPressed: _setServer, child: const Text('Connect')),
                          ],
                        ),
                      )
                    : _error != null
                    ? ErrorView(_error!, onRetry: _start)
                    : code == null
                    ? const CircularProgressIndicator(color: Hy.orange)
                    : FadeIn(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final ch in code.split(''))
                                  Container(
                                    width: 64,
                                    height: 84,
                                    margin: const EdgeInsets.symmetric(horizontal: 5),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: Hy.surfaceHigh,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: Hy.orange.withValues(alpha: .6), width: 2),
                                      boxShadow: const [BoxShadow(color: Color(0x44FF7A1A), blurRadius: 24)],
                                    ),
                                    child: Text(ch, style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w900)),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 26),
                            const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Hy.orange)),
                                SizedBox(width: 12),
                                Text('Waiting for approval…', style: TextStyle(color: Hy.textDim, fontSize: 16)),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;
  const _Step({required this.n, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Hy.orange, shape: BoxShape.circle),
          child: Text(
            '$n',
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 17, height: 1.4))),
      ],
    ),
  );
}
