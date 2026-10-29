import 'package:flutter/services.dart';

import '../host.dart';

/// Speech to text through Android's own voice input (Google): on a Google TV the remote's
/// microphone, on a phone its mic. MainActivity.kt starts it and hands back what was heard.
abstract final class Voice {
  static const _channel = MethodChannel('hevyfin/voice');
  static bool? _available;

  /// Whether this device has voice input at all (asked once).
  static Future<bool> available() async {
    if (!Host.isAndroid) return false;
    try {
      return _available ??= await _channel.invokeMethod<bool>('available') ?? false;
    } catch (_) {
      return _available = false;
    }
  }

  /// What was said, or null if nothing was.
  static Future<String?> listen({String prompt = 'Say a title, an actor or a genre'}) async {
    try {
      final t = await _channel.invokeMethod<String>('listen', {'prompt': prompt});
      return (t ?? '').trim().isEmpty ? null : t!.trim();
    } catch (_) {
      return null;
    }
  }
}
