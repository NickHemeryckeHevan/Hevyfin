import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/jellyfin.dart';
import 'app_state.dart';
import 'socket/socket.dart';

/// What the open player does when another device (or the watch party) tells it to.
abstract class PlaybackTarget {
  void remotePause();
  void remoteUnpause();
  void remoteToggle();
  void remoteSeek(Duration to);
  void remoteStop();
  void remoteNext();

  /// Watch together: the group's playback command, to carry out at [when] (local time).
  void syncCommand(String command, DateTime when, Duration position);
}

/// A watch party this device is in.
class Party {
  final String id, name;
  final List<String> people;
  const Party(this.id, this.name, this.people);
}

/// The app's live line to Jellyfin. Other devices on the account can start something here
/// and pause, seek or stop it (phone as remote), and SyncPlay keeps a watch party's
/// players in step. Reconnects by itself.
class Link extends ChangeNotifier {
  final AppState app;
  Link(this.app) {
    app.addListener(_onApp);
    _onApp();
  }

  JellyfinClient? _c;
  LinkSocket? _ws;
  Timer? _keepAlive, _retry;
  int _backoff = 2;

  /// Called to open the player for an item (wired up by the app's root).
  void Function(String itemId, Duration start, {bool sync})? openPlayer;

  /// The player that's open, if any.
  PlaybackTarget? target;

  // ---- watch together ----
  Party? party;

  /// The party's current queue item, for Ready/Buffering reports.
  String? playlistItemId;
  String? partyItemId;
  Duration _offset = Duration.zero;
  bool get inParty => party != null;

  void _onApp() {
    final c = app.client;
    if (c?.session?.token == _c?.session?.token && c?.server == _c?.server) return;
    _c = c;
    _close();
    if (c != null && c.session != null && !app.offline) _connect();
  }

  void _close() {
    _keepAlive?.cancel();
    _retry?.cancel();
    _ws?.close();
    _ws = null;
    if (party != null) {
      party = null;
      notifyListeners();
    }
  }

  Future<void> _connect() async {
    final c = _c;
    if (c == null) return;
    try {
      final ws = await LinkSocket.connect(c.socketUri(), c.socketHeaders).timeout(const Duration(seconds: 10));
      if (_c != c) {
        await ws.close();
        return;
      }
      _ws = ws;
      _backoff = 2;
      ws.listen(_onMessage, onDone: _reconnect);
      await c.announceCapabilities();
    } catch (e) {
      // Never print the exception itself: it can carry the address and sign-in.
      debugPrint('link: socket unavailable (${e is String ? e : e.runtimeType})');
      _reconnect();
    }
  }

  void _reconnect() {
    _keepAlive?.cancel();
    _ws = null;
    if (_c == null) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _backoff), _connect);
    _backoff = (_backoff * 2).clamp(2, 60);
  }

  void _send(String type, [Object? data]) => _ws?.add(jsonEncode({'MessageType': type, 'Data': ?data}));

  static Duration _ticks(Object? t) => Duration(microseconds: ((t as num?) ?? 0) ~/ 10);

  void _onMessage(dynamic raw) {
    final Map m;
    try {
      m = jsonDecode(raw as String) as Map;
    } catch (_) {
      return;
    }
    final data = m['Data'];
    switch (m['MessageType']) {
      case 'ForceKeepAlive':
        final secs = ((data as num?) ?? 60).toInt();
        _keepAlive?.cancel();
        _keepAlive = Timer.periodic(Duration(seconds: (secs / 2).floor().clamp(5, 60)), (_) => _send('KeepAlive'));
        _send('KeepAlive');
      case 'Play':
        final d = (data as Map).cast<String, dynamic>();
        final ids = ((d['ItemIds'] as List?) ?? const []).cast<String>();
        if (ids.isNotEmpty) openPlayer?.call(ids.first, _ticks(d['StartPositionTicks']));
      case 'Playstate':
        final d = (data as Map).cast<String, dynamic>();
        final t = target;
        if (t == null) return;
        switch (d['Command']) {
          case 'Pause':
            t.remotePause();
          case 'Unpause':
            t.remoteUnpause();
          case 'PlayPause':
            t.remoteToggle();
          case 'Stop':
            t.remoteStop();
          case 'Seek':
            t.remoteSeek(_ticks(d['SeekPositionTicks']));
          case 'NextTrack':
            t.remoteNext();
        }
      case 'SyncPlayGroupUpdate':
        _onGroup((data as Map).cast<String, dynamic>());
      case 'SyncPlayCommand':
        final d = (data as Map).cast<String, dynamic>();
        final when = DateTime.parse(d['When'] as String).subtract(_offset).toLocal();
        target?.syncCommand(d['Command'] as String, when, _ticks(d['PositionTicks']));
    }
  }

  void _onGroup(Map<String, dynamic> u) {
    final d = u['Data'];
    switch (u['Type']) {
      case 'GroupJoined':
        final g = (d as Map).cast<String, dynamic>();
        party = Party(g['GroupId'] as String, (g['GroupName'] as String?) ?? 'Watch party', ((g['Participants'] as List?) ?? const []).cast<String>());
      case 'UserJoined':
        if (party != null) party = Party(party!.id, party!.name, [...party!.people, '$d']);
      case 'UserLeft':
        if (party != null) party = Party(party!.id, party!.name, [...party!.people]..remove('$d'));
      case 'GroupLeft' || 'NotInGroup' || 'GroupDoesNotExist':
        party = null;
        partyItemId = null;
        playlistItemId = null;
      case 'PlayQueue':
        final q = (d as Map).cast<String, dynamic>();
        final list = ((q['Playlist'] as List?) ?? const []).cast<Map>();
        final i = (q['PlayingItemIndex'] as num?)?.toInt() ?? 0;
        if (list.isEmpty || i < 0 || i >= list.length) return;
        final itemId = list[i]['ItemId'] as String;
        playlistItemId = list[i]['PlaylistItemId'] as String?;
        // A new film for the party: everyone opens it, paused, and says when they're ready.
        if (itemId != partyItemId || target == null) {
          partyItemId = itemId;
          openPlayer?.call(itemId, _ticks(q['StartPositionTicks']), sync: true);
        }
    }
    notifyListeners();
  }

  // ---- watch-party actions (from the app's buttons) ----

  /// Start a party around [item] and play it for everyone who joins.
  Future<void> startParty(Item item) async {
    final c = _c!;
    _offset = await c.clockOffset();
    if (inParty) await c.syncLeave();
    await c.syncNew("${app.userName}'s watch party");
    // The server answers GroupJoined over the socket; give it a moment, then set the film.
    for (var i = 0; i < 20 && party == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    await c.syncQueue(item.id);
  }

  Future<void> joinParty(String groupId) async {
    final c = _c!;
    _offset = await c.clockOffset();
    await c.syncJoin(groupId);
  }

  Future<void> leaveParty() async {
    if (!inParty) return;
    party = null;
    partyItemId = null;
    notifyListeners();
    await _c?.syncLeave().catchError((_) {});
  }

  /// The player's own buttons, while in a party: ask the group instead of acting alone.
  Future<void> partyToggle(bool playing) => (playing ? _c!.syncPause() : _c!.syncUnpause()).catchError((_) {});
  Future<void> partySeek(Duration to) => _c!.syncSeek(to).catchError((_) {});

  /// Tell the party whether this player is ready to go (loaded) or still loading.
  void partyReady(Duration pos, bool playing, {bool buffering = false}) {
    final id = playlistItemId, c = _c;
    if (!inParty || id == null || c == null) return;
    c.syncReady(DateTime.now().add(_offset), pos, playing, id, buffering: buffering).catchError((_) {});
  }

  @override
  void dispose() {
    app.removeListener(_onApp);
    _close();
    super.dispose();
  }
}
