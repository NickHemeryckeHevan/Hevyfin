import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/jellyfin.dart';
import '../api/niql.dart';
import '../api/seerr.dart';
import '../host.dart';

/// No server is built in: the first sign-in asks for it. The fallback is an optional second
/// address for the same server (e.g. a VPN address for when you're away from home).
const defaultServer = '';
const defaultFallback = '';

/// Seerr is looked for on the Jellyfin host, on its default port, unless set in Settings.
const seerrPort = 5055;

/// "jellyfin.local:8096" → "http://jellyfin.local:8096"; trailing slashes go.
String normalizeServer(String s) {
  var t = s.trim();
  if (t.isEmpty) return t;
  if (!t.contains('://')) t = 'http://$t';
  while (t.endsWith('/')) {
    t = t.substring(0, t.length - 1);
  }
  return t;
}

/// The web version reaches everything through the address it was opened from: its server
/// passes /jellyfin, /seerr and /niql on (server/web/nginx.conf).
String get webServer => '${Host.origin}/jellyfin';
String get webSeerr => '${Host.origin}/seerr';

/// A household member's Jellyfin account, kept on this device for "Who's watching?".
class Profile {
  final String userId, name, token;

  /// Hashed 4-digit PIN that guards switching to this profile, if set.
  final String? pin;
  final String? seerrCookie;
  const Profile(this.userId, this.name, this.token, {this.pin, this.seerrCookie});

  Profile copyWith({String? token, String? pin, bool clearPin = false, String? seerrCookie}) =>
      Profile(userId, name, token ?? this.token, pin: clearPin ? null : (pin ?? this.pin), seerrCookie: seerrCookie ?? this.seerrCookie);

  Map<String, dynamic> toJson() => {'id': userId, 'name': name, 'token': token, 'pin': ?pin, 'seerr': ?seerrCookie};
  factory Profile.fromJson(Map j) =>
      Profile(j['id'] as String, j['name'] as String, j['token'] as String, pin: j['pin'] as String?, seerrCookie: j['seerr'] as String?);

  static String hashPin(String userId, String pin) => sha256.convert(utf8.encode('hevyfin:$userId:$pin')).toString();
}

/// Login, server choice, Seerr session and settings.
class AppState extends ChangeNotifier {
  final SharedPreferences prefs;
  AppState(this.prefs);

  String server = defaultServer;
  String fallback = defaultFallback;
  late String deviceId;
  JellyfinClient? client;
  bool offline = false;

  /// Empty = Seerr on the same host as Jellyfin, port 5055.
  String seerrOverride = '';
  SeerrClient? seerr;
  bool seerrReady = false;

  /// Preferred audio language (ISO 639-2, e.g. "eng"), and subtitles ("" = off).
  String audioLang = 'eng';
  String subtitleLang = '';

  /// Max streaming bitrate in Mbps (0 = original file, no transcoding).
  int maxMbps = 0;

  /// Jump over intros and recaps without asking.
  bool autoSkip = false;

  /// TV: a title's trailer plays silently behind it after resting on it.
  bool trailerPreviews = true;

  /// TV: Dolby/DTS sent untouched to the TV or soundbar over HDMI. Off by default: on the
  /// Chromecast an AC3 film never started (its audio output didn't open, and the picture waits
  /// for the sound), so the Chromecast decodes it unless this is switched on.
  bool passthrough = false;

  /// Subtitle look on this device: size (1 = normal), text colour, and a dark box behind.
  double subSize = 1;
  String subColor = 'white';
  bool subBox = false;

  /// Collections (ids) watched in story order instead of release order.
  Set<String> storyOrder = {};

  /// Ids in "My List" (Jellyfin favourites), so cards can show a tick.
  final Set<String> myList = {};

  /// Bumped when something changes that lists should reload for (played state, list, requests).
  int revision = 0;

  /// Everyone signed in on this device; the picker shows when there's more than one.
  List<Profile> profiles = [];

  /// "Who's watching?" is up (at launch, after "Switch profile", or after signing out).
  bool choosing = false;

  /// Signing in someone else, to add them as a profile.
  bool adding = false;

  bool get loggedIn => client?.session != null;
  String get userName => client?.session?.userName ?? '';

  Future<void> load() async {
    server = Host.isWeb ? webServer : prefs.getString('server') ?? defaultServer;
    fallback = Host.isWeb ? '' : prefs.getString('fallback') ?? defaultFallback;
    seerrOverride = prefs.getString('seerrUrl') ?? '';
    Niql.configured = prefs.getString('niqlUrl') ?? '';
    audioLang = prefs.getString('audioLang') ?? 'eng';
    subtitleLang = prefs.getString('subtitleLang') ?? '';
    maxMbps = prefs.getInt('maxMbps') ?? 0;
    prefs.remove('nightAudio'); // night mode was removed in 0.9.10
    autoSkip = prefs.getBool('autoSkip') ?? false;
    trailerPreviews = prefs.getBool('trailerPreviews') ?? true;
    passthrough = prefs.getBool('passthrough') ?? false;
    subSize = prefs.getDouble('subSize') ?? 1;
    subColor = prefs.getString('subColor') ?? 'white';
    subBox = prefs.getBool('subBox') ?? false;
    storyOrder = (prefs.getStringList('storyOrder') ?? const []).toSet();
    deviceId = prefs.getString('deviceId') ?? _newDeviceId();
    await prefs.setString('deviceId', deviceId);
    final uid = prefs.getString('userId'), name = prefs.getString('userName'), token = prefs.getString('token');
    try {
      profiles = [for (final p in jsonDecode(prefs.getString('profiles') ?? '[]') as List) Profile.fromJson(p as Map)];
    } catch (_) {
      profiles = [];
    }
    if (uid != null && name != null && token != null && !profiles.any((p) => p.userId == uid)) {
      profiles.add(Profile(uid, name, token, seerrCookie: prefs.getString('seerrCookie')));
      await _saveProfiles();
    }
    choosing = profiles.length > 1;
    if (uid != null && name != null && token != null) {
      await connect(Session(uid, name, token));
    }
  }

  Future<void> _saveProfiles() => prefs.setString('profiles', jsonEncode([for (final p in profiles) p.toJson()]));

  /// After a sign-in: remember the account as a profile (keeping its PIN).
  Future<void> _remember(Session s) async {
    final i = profiles.indexWhere((p) => p.userId == s.userId);
    if (i >= 0) {
      profiles[i] = profiles[i].copyWith(token: s.token);
    } else {
      profiles.add(Profile(s.userId, s.userName, s.token));
    }
    adding = false;
    choosing = false;
    await _saveProfiles();
  }

  Profile? get currentProfile => profiles.where((p) => p.userId == client?.session?.userId).firstOrNull;

  void chooseProfile() {
    choosing = true;
    notifyListeners();
  }

  void startAdding(bool on) {
    adding = on;
    notifyListeners();
  }

  /// Become [p]: their Continue watching, My List, requests and settings on the server.
  Future<void> switchTo(Profile p) async {
    // A browser keeps one Seerr sign-in: the next profile links its own.
    if (Host.isWeb) await seerr?.logout();
    final cur = currentProfile;
    if (cur != null) {
      final i = profiles.indexOf(cur);
      profiles[i] = cur.copyWith(seerrCookie: prefs.getString('seerrCookie') ?? '');
    }
    await prefs.setString('userId', p.userId);
    await prefs.setString('userName', p.name);
    await prefs.setString('token', p.token);
    (p.seerrCookie ?? '').isEmpty ? await prefs.remove('seerrCookie') : await prefs.setString('seerrCookie', p.seerrCookie!);
    await _saveProfiles();
    myList.clear();
    choosing = false;
    await connect(Session(p.userId, p.name, p.token));
    revision++;
    notifyListeners();
  }

  Future<void> setPin(Profile p, String? pin) async {
    final i = profiles.indexWhere((x) => x.userId == p.userId);
    if (i < 0) return;
    profiles[i] = pin == null ? p.copyWith(clearPin: true) : p.copyWith(pin: Profile.hashPin(p.userId, pin));
    await _saveProfiles();
    notifyListeners();
  }

  bool pinMatches(Profile p, String pin) => p.pin == null || p.pin == Profile.hashPin(p.userId, pin);

  /// Forget a profile on this device (signs it out on the server if it's the current one).
  Future<void> removeProfile(Profile p) async {
    if (p.userId == client?.session?.userId) return logout();
    profiles.removeWhere((x) => x.userId == p.userId);
    await _saveProfiles();
    notifyListeners();
  }

  String _newDeviceId() {
    final r = Random.secure();
    return 'hevyfin-${List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join()}';
  }

  /// Pick the first server that answers; stay on the primary (offline) if none do.
  Future<void> connect(Session session) async {
    for (final s in [server, fallback].where((s) => s.trim().isNotEmpty)) {
      final c = JellyfinClient(s, deviceId, session: session);
      try {
        await c.ping(timeout: const Duration(seconds: 3));
        _setClient(c, offline: false);
        refreshMyList();
        _connectSeerr();
        return;
      } catch (_) {}
    }
    _setClient(JellyfinClient(server, deviceId, session: session), offline: true);
  }

  Future<void> retry() async {
    final s = client?.session;
    if (s != null) await connect(s);
  }

  void _setClient(JellyfinClient c, {required bool offline}) {
    client = c;
    this.offline = offline;
    notifyListeners();
  }

  String get seerrUrl {
    if (Host.isWeb) return webSeerr;
    if (seerrOverride.trim().isNotEmpty) return seerrOverride.trim();
    final u = Uri.tryParse(client?.server ?? server);
    return u == null ? '' : '${u.scheme}://${u.host}:$seerrPort';
  }

  SeerrClient _newSeerr() => SeerrClient(
    seerrUrl,
    cookie: prefs.getString('seerrCookie'),
    onCookie: (c) => c == null ? prefs.remove('seerrCookie') : prefs.setString('seerrCookie', c),
  );

  Future<void> _connectSeerr() async {
    seerr = _newSeerr();
    seerrReady = await seerr!.check();
    notifyListeners();
  }

  /// Sign Seerr in with the Jellyfin account (needed again when its session expires).
  Future<void> seerrLogin(String password) async {
    final s = _newSeerr()..cookie = null;
    await s.loginWithJellyfin(userName, password);
    seerr = s;
    seerrReady = true;
    notifyListeners();
  }

  /// The first of home/away servers that answers, for Quick Connect.
  Future<JellyfinClient> reachable({required String server, required String fallback}) async {
    Object? err;
    for (final s in [server, fallback].where((s) => s.trim().isNotEmpty)) {
      final c = JellyfinClient(s, deviceId);
      try {
        await c.ping();
        return c;
      } catch (e) {
        err ??= e;
      }
    }
    throw err ?? JellyfinException('No server answered');
  }

  /// Finish a Quick Connect sign-in (the TV flow). Seerr can be connected later.
  Future<void> loginQuickConnect(JellyfinClient c, String secret, {required String server, required String fallback}) async {
    final session = await c.quickConnectFinish(secret);
    this.server = server.trim();
    this.fallback = fallback.trim();
    await prefs.setString('server', this.server);
    await prefs.setString('fallback', this.fallback);
    await prefs.setString('userId', session.userId);
    await prefs.setString('userName', session.userName);
    await prefs.setString('token', session.token);
    await prefs.remove('seerrCookie');
    await _remember(session);
    _setClient(c.withSession(session), offline: false);
    refreshMyList();
    await _connectSeerr();
  }

  Future<void> login({required String server, required String fallback, required String username, required String password}) async {
    (server, fallback) = Host.isWeb ? (webServer, '') : (normalizeServer(server), normalizeServer(fallback));
    if (server.isEmpty) throw 'Enter your Jellyfin server address';
    Object? firstError;
    for (final s in [server, fallback].where((s) => s.trim().isNotEmpty)) {
      final c = JellyfinClient(s, deviceId);
      try {
        final session = await c.login(username.trim(), password);
        this.server = server.trim();
        this.fallback = fallback.trim();
        await prefs.setString('server', this.server);
        await prefs.setString('fallback', this.fallback);
        await prefs.setString('userId', session.userId);
        await prefs.setString('userName', session.userName);
        await prefs.setString('token', session.token);
        await prefs.remove('seerrCookie');
        await _remember(session);
        _setClient(c.withSession(session), offline: false);
        refreshMyList();
        try {
          await seerrLogin(password);
        } catch (e) {
          debugPrint('Seerr login failed: $e');
          seerr = _newSeerr();
          seerrReady = false;
          notifyListeners();
        }
        return;
      } on JellyfinException catch (e) {
        if (e.message.startsWith('Wrong')) rethrow;
        firstError ??= e;
      } catch (e) {
        firstError ??= e;
      }
    }
    throw firstError ?? JellyfinException('No server answered');
  }

  Future<void> logout() async {
    final uid = client?.session?.userId;
    await client?.logout();
    if (Host.isWeb) await seerr?.logout();
    for (final k in ['userId', 'userName', 'token', 'seerrCookie']) {
      await prefs.remove(k);
    }
    profiles.removeWhere((p) => p.userId == uid);
    await _saveProfiles();
    // Someone else is still signed in here: back to "Who's watching?".
    choosing = profiles.isNotEmpty;
    client = null;
    seerr = null;
    seerrReady = false;
    myList.clear();
    notifyListeners();
  }

  // ---- My List ----

  Future<void> refreshMyList() async {
    final c = client;
    if (c == null) return;
    try {
      final items = await c.items(filters: 'IsFavorite');
      myList
        ..clear()
        ..addAll(items.map((i) => i.id));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleMyList(String id) async {
    final add = !myList.contains(id);
    add ? myList.add(id) : myList.remove(id);
    revision++;
    notifyListeners();
    try {
      await client!.setFavorite(id, add);
    } catch (_) {
      add ? myList.remove(id) : myList.add(id);
      notifyListeners();
      rethrow;
    }
  }

  void bump() {
    revision++;
    notifyListeners();
  }

  // ---- settings ----

  Future<void> setServers(String primary, String fb) async {
    server = normalizeServer(primary);
    fallback = normalizeServer(fb);
    await prefs.setString('server', server);
    await prefs.setString('fallback', fallback);
    await retry();
  }

  /// The optional recommendation service behind "Ask" (docs/niql.md); empty switches it off.
  Future<void> setNiqlUrl(String url) async {
    Niql.configured = url.trim();
    await prefs.setString('niqlUrl', Niql.configured);
    notifyListeners();
  }

  Future<void> setSeerrOverride(String url) async {
    seerrOverride = url.trim();
    await prefs.setString('seerrUrl', seerrOverride);
    await _connectSeerr();
  }

  Future<void> setAudioLang(String v) async {
    audioLang = v;
    await prefs.setString('audioLang', v);
    notifyListeners();
  }

  Future<void> setSubtitleLang(String v) async {
    subtitleLang = v;
    await prefs.setString('subtitleLang', v);
    notifyListeners();
  }

  Future<void> setStoryOrder(String collectionId, bool v) async {
    v ? storyOrder.add(collectionId) : storyOrder.remove(collectionId);
    await prefs.setStringList('storyOrder', storyOrder.toList());
    notifyListeners();
  }

  Future<void> setPassthrough(bool v) async {
    passthrough = v;
    await prefs.setBool('passthrough', v);
    notifyListeners();
  }

  Future<void> setTrailerPreviews(bool v) async {
    trailerPreviews = v;
    await prefs.setBool('trailerPreviews', v);
    notifyListeners();
  }

  Future<void> setAutoSkip(bool v) async {
    autoSkip = v;
    await prefs.setBool('autoSkip', v);
    notifyListeners();
  }

  Future<void> setSubStyle({double? size, String? color, bool? box}) async {
    subSize = size ?? subSize;
    subColor = color ?? subColor;
    subBox = box ?? subBox;
    await prefs.setDouble('subSize', subSize);
    await prefs.setString('subColor', subColor);
    await prefs.setBool('subBox', subBox);
    notifyListeners();
  }

  Future<void> setMaxMbps(int v) async {
    maxMbps = v;
    await prefs.setInt('maxMbps', v);
    notifyListeners();
  }
}
