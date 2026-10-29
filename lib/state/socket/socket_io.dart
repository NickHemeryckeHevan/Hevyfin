import 'dart:io';

import 'socket.dart';

Future<LinkSocket> connect(Uri uri, Map<String, String> headers) async {
  try {
    return _IoSocket(await WebSocket.connect(uri.toString(), headers: headers));
  } on WebSocketException catch (e) {
    // Never pass the exception itself on: it can carry the address and sign-in.
    throw 'WebSocketException ${e.httpStatusCode}';
  }
}

class _IoSocket implements LinkSocket {
  final WebSocket _ws;
  _IoSocket(this._ws);

  @override
  void listen(void Function(dynamic message) onData, {required void Function() onDone}) =>
      _ws.listen(onData, onDone: onDone, onError: (_) => onDone(), cancelOnError: true);

  @override
  void add(String message) => _ws.add(message);

  @override
  Future<void> close() => _ws.close();
}
