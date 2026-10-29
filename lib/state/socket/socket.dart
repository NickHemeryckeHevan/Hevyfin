import 'socket_io.dart' if (dart.library.js_interop) 'socket_web.dart' as impl;

/// Link's live line to Jellyfin: dart:io's WebSocket in the apps, the browser's on the web.
abstract class LinkSocket {
  /// Messages as they come; [onDone] once the line drops (or fails).
  void listen(void Function(dynamic message) onData, {required void Function() onDone});
  void add(String message);
  Future<void> close();

  /// Opens [uri], signing in with [headers]. A browser can't send headers, so the web
  /// version puts the token in the address and its server turns it back into a header
  /// (server/web/nginx.conf).
  static Future<LinkSocket> connect(Uri uri, Map<String, String> headers) => impl.connect(uri, headers);
}
