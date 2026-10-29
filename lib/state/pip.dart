import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../host.dart';

/// Android picture-in-picture (the floating mini player), driven by MainActivity.kt.
abstract final class Pip {
  static const _channel = MethodChannel('hevyfin/pip');

  /// True while the app is shrunk into the PiP window.
  static final active = ValueNotifier(false);

  static bool _init = false;
  static void _ensureInit() {
    if (_init) return;
    _init = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'changed') active.value = call.arguments == true;
      if (call.method == 'action') onAction?.call(call.arguments as String);
    });
  }

  /// Allow (or stop) going to PiP when the user leaves the app, at the video's aspect ratio.
  static Future<void> setEnabled(bool enabled, {int width = 16, int height = 9}) async {
    if (!Host.isAndroid) return;
    _ensureInit();
    try {
      await _channel.invokeMethod('setEnabled', {'enabled': enabled, 'width': width, 'height': height});
    } catch (e) {
      debugPrint('PiP unavailable: $e');
    }
    if (!enabled) active.value = false;
  }

  /// Called with 'toggle', 'back' or 'forward' when a mini-player button is pressed.
  static void Function(String action)? onAction;

  /// Keeps the mini player's play/pause button showing the right icon.
  static Future<void> setPlaying(bool playing) async {
    if (!Host.isAndroid) return;
    _ensureInit();
    try {
      await _channel.invokeMethod('setPlaying', playing);
    } catch (_) {}
  }

  static Future<bool> enter() async {
    if (!Host.isAndroid) return false;
    _ensureInit();
    try {
      return await _channel.invokeMethod<bool>('enter') ?? false;
    } catch (_) {
      return false;
    }
  }
}
