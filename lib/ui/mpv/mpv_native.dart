import 'package:media_kit/media_kit.dart';

/// Whether [p] is mpv, which takes properties.
bool hasMpv(Player p) => p.platform is NativePlayer;

Future<void> mpvSet(Player p, String name, String value) async {
  final n = p.platform;
  if (n is NativePlayer) await n.setProperty(name, value);
}

Future<String?> mpvGet(Player p, String name) async {
  final n = p.platform;
  return n is NativePlayer ? n.getProperty(name) : null;
}
