import 'dart:io' as io show Platform;

import 'package:flutter/foundation.dart';

import 'host_io.dart' if (dart.library.js_interop) 'host_web.dart' as impl;

/// What the app runs on. `dart:io`'s Platform throws in a browser, so everything asks here.
abstract final class Host {
  static bool get isWeb => kIsWeb;
  static bool get isAndroid => !kIsWeb && io.Platform.isAndroid;
  static bool get isLinux => !kIsWeb && io.Platform.isLinux;
  static bool get isWindows => !kIsWeb && io.Platform.isWindows;

  /// A mouse-and-keyboard computer: the Linux and Windows apps, and the web version.
  static bool get isComputer => kIsWeb || isLinux || isWindows;

  /// An environment variable (testing switches like HEVYFIN_ROUTE); never set on the web.
  static String? env(String name) => kIsWeb ? null : io.Platform.environment[name];

  /// The web version's own address (e.g. "https://media.example.org"): Jellyfin, Seerr and the optional recommendation service
  /// are reached through it (/jellyfin, /seerr, /niql). Empty in the apps.
  static String get origin => impl.origin;
}
