import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'socket.dart';

Future<LinkSocket> connect(Uri uri, Map<String, String> headers) {
  final ws = web.WebSocket(uri.toString());
  final opened = Completer<LinkSocket>();
  final s = _WebSocket(ws);
  ws.onopen = ((web.Event _) => opened.complete(s)).toJS;
  ws.onmessage = ((web.MessageEvent e) => s._onData?.call((e.data as JSString).toDart)).toJS;
  void ended() {
    if (!opened.isCompleted) opened.completeError('WebSocket refused');
    final done = s._onDone;
    s._onDone = null;
    done?.call();
  }

  ws.onclose = ((web.CloseEvent _) => ended()).toJS;
  ws.onerror = ((web.Event _) => ended()).toJS;
  return opened.future;
}

class _WebSocket implements LinkSocket {
  final web.WebSocket _ws;
  _WebSocket(this._ws);
  void Function(dynamic)? _onData;
  void Function()? _onDone;

  @override
  void listen(void Function(dynamic message) onData, {required void Function() onDone}) {
    _onData = onData;
    _onDone = onDone;
  }

  @override
  void add(String message) => _ws.send(message.toJS);

  @override
  Future<void> close() async {
    _onDone = null;
    _ws.close();
  }
}
