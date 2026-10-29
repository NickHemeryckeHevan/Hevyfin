import 'package:flutter/services.dart';

import '../host.dart';

/// What kind of screen we run on. Android TV / Google TV is detected natively;
/// HEVYFIN_TV=1 turns the TV interface on elsewhere (for testing with a keyboard).
abstract final class Device {
  static bool isTv = false;

  static Future<void> init() async {
    if (Host.env('HEVYFIN_TV') == '1') {
      isTv = true;
      return;
    }
    if (!Host.isAndroid) return;
    try {
      isTv = await const MethodChannel('hevyfin/device').invokeMethod<bool>('isTv') ?? false;
    } catch (_) {}
  }
}
