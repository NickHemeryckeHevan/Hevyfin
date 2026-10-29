import 'dart:convert';
import 'dart:math';

import 'package:collection/collection.dart' show mergeSort;
import 'package:http/http.dart' as http;

import '../state/device.dart';
import '../host.dart';

const appVersion = '0.9.16';

class JellyfinException implements Exception {
  final String message;
  final int? status;
  JellyfinException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// What we keep between launches: enough to talk to the server without the password.
class Session {
  final String userId;
  final String userName;
  final String token;
  const Session(this.userId, this.userName, this.token);
}

/// A movie, series, season or episode. Thin wrapper over Jellyfin's BaseItemDto.
class Item {
  final Map<String, dynamic> raw;
  Item(this.raw);

  String get id => raw['Id'] as String;
  String get name => (raw['Name'] as String?) ?? '';
  String get type => (raw['Type'] as String?) ?? '';
  bool get isMovie => type == 'Movie';
  bool get isSeries => type == 'Series';
  bool get isEpisode => type == 'Episode';
  bool get isSeason => type == 'Season';

  /// Opened from a universe's path (see [JellyfinClient.onPath]): its stop there, else null.
  Stop? get pathStop => raw['PathStop'] as Stop?;

  /// A show opened as one of its seasons (or cuts) that a universe makes a mini series of
  /// its own: that stop, else null.
  Stop? get miniStop => pathStop?.mini == true ? pathStop : null;

  /// A franchise collection ("Harry Potter Collection"); genre groupings are left out.
  bool get isCollection => type == 'BoxSet';

  List<String> get tags => ((raw['Tags'] as List?) ?? const []).cast<String>();

  /// Collections made by hand or by a server script (a whole universe, a franchise) carry this tag.
  bool get isUniverse => isCollection && tags.contains('franchise');

  /// This title's place in [collection]'s story order (tags "story:COLLECTION:NN", set on
  /// the server by server/universes.py, see docs/custom-collections.md), if it has one.
  int? storyPlace(String collection) {
    final prefix = 'story:$collection:';
    for (final t in tags) {
      if (t.startsWith(prefix)) return int.tryParse(t.substring(prefix.length));
    }
    return null;
  }

  String? get overview => raw['Overview'] as String?;
  String? get tagline => (raw['Taglines'] as List?)?.cast<String>().firstOrNull;
  int? get year => raw['ProductionYear'] as int?;
  String? get officialRating => raw['OfficialRating'] as String?;
  double? get communityRating => (raw['CommunityRating'] as num?)?.toDouble();
  int? get criticRating => (raw['CriticRating'] as num?)?.toInt();
  List<String> get genres => ((raw['Genres'] as List?) ?? const []).cast<String>();
  String? get status => raw['Status'] as String?;
  int? get childCount => raw['ChildCount'] as int?;
  DateTime? get premiereDate => DateTime.tryParse((raw['PremiereDate'] as String?) ?? '');

  Duration? get runtime {
    final t = raw['RunTimeTicks'] as num?;
    // An unknown length (not yet aired, say) comes as 0.
    return t == null || t <= 0 ? null : Duration(microseconds: t ~/ 10);
  }

  String? get seriesId => raw['SeriesId'] as String?;

  /// Live TV: a channel's number, a programme's channel and times.
  String? get channelNumber => (raw['ChannelNumber'] ?? raw['Number']) as String?;
  String? get channelId => raw['ChannelId'] as String?;
  DateTime? get startDate => DateTime.tryParse((raw['StartDate'] as String?) ?? '')?.toLocal();
  DateTime? get endDate => DateTime.tryParse((raw['EndDate'] as String?) ?? '')?.toLocal();
  String? get episodeTitle => raw['EpisodeTitle'] as String?;
  String? get seriesName => raw['SeriesName'] as String?;
  String? get seasonId => raw['SeasonId'] as String?;
  int? get indexNumber => raw['IndexNumber'] as int?;
  int? get parentIndexNumber => raw['ParentIndexNumber'] as int?;

  /// "S2:E5" for episodes.
  String get episodeCode => 'S${parentIndexNumber ?? '?'}:E${indexNumber ?? '?'}';

  /// What a card shows: the series for an episode, otherwise the item itself.
  String get displayTitle => isEpisode ? (seriesName ?? name) : name;

  Map<String, dynamic> get _userData => (raw['UserData'] as Map?)?.cast<String, dynamic>() ?? const {};
  bool get played => _userData['Played'] == true;
  bool get favorite => _userData['IsFavorite'] == true;
  int? get unplayedCount => _userData['UnplayedItemCount'] as int?;
  Duration get resumePosition => Duration(microseconds: ((_userData['PlaybackPositionTicks'] as num?) ?? 0) ~/ 10);
  double? get playedPercentage => (_userData['PlayedPercentage'] as num?)?.toDouble();
  DateTime? get lastPlayed => DateTime.tryParse((_userData['LastPlayedDate'] as String?) ?? '');

  /// Progress 0..1 for a resume bar, null when not started.
  double? get progress {
    final p = playedPercentage;
    if (p != null && p > 0) return (p / 100).clamp(0, 1);
    final r = runtime;
    if (r == null || r.inSeconds == 0 || resumePosition == Duration.zero) return null;
    return (resumePosition.inSeconds / r.inSeconds).clamp(0, 1);
  }

  Map<String, String> get providerIds => ((raw['ProviderIds'] as Map?) ?? const {}).map((k, v) => MapEntry('$k'.toLowerCase(), '$v'));
  int? get tmdbId => int.tryParse(providerIds['tmdb'] ?? '');

  /// The trailer on YouTube, from TMDb (only on full item loads).
  String? get remoteTrailer {
    final list = ((raw['RemoteTrailers'] as List?) ?? const []).cast<Map>();
    final yt = list.where((t) => '${t['Url']}'.contains('youtu')).toList()
      ..sort(
        (a, b) =>
            ('${a['Name']}'.toLowerCase().contains('official trailer') ? 0 : 1).compareTo('${b['Name']}'.toLowerCase().contains('official trailer') ? 0 : 1),
      );
    return yt.firstOrNull?['Url'] as String?;
  }

  Map<String, String> get imageTags => ((raw['ImageTags'] as Map?) ?? const {}).map((k, v) => MapEntry('$k', '$v'));
  List<String> get backdropTags => ((raw['BackdropImageTags'] as List?) ?? const []).cast<String>();

  List<Person> get people => ((raw['People'] as List?) ?? const []).map((p) => Person((p as Map).cast<String, dynamic>())).toList();
  List<MediaStream> get streams {
    final sources = raw['MediaSources'] as List?;
    final list = (sources?.firstOrNull as Map?)?['MediaStreams'] as List? ?? raw['MediaStreams'] as List? ?? const [];
    return list.map((m) => MediaStream((m as Map).cast<String, dynamic>())).toList();
  }

  /// "4K", "HD" or null, from the video stream width.
  String? get quality {
    final v = streams.where((s) => s.type == 'Video').firstOrNull;
    final w = v?.width ?? (raw['Width'] as int?);
    if (w == null) return null;
    if (w >= 3200) return '4K';
    if (w >= 1200) return 'HD';
    return 'SD';
  }
}

/// A stop on a universe's path: a film or a whole show, or one season or a hand-picked cut
/// of a show's episodes (the universe job lists them on the collection, "HevyfinStory").
class Stop {
  /// The film or show it belongs to: its page and its art.
  final Item item;

  /// What there is to watch: a season's or cut's episodes, else the title itself.
  final List<Item> parts;

  /// A season stop's own season, for its poster.
  final Item? season;

  /// A cut's own poster: the universe job keeps it on the cut's first episode, as a "Box" image.
  final ({String id, String? tag})? art;
  final String title;

  /// Under a season or cut: "Season 2", "S1 · E16–17". Null for a whole title.
  final String? code;
  final String? group;
  final DateTime? date;

  /// A season or cut that opens as a mini series of its own.
  final bool mini;

  /// The universe whose path it's on, when the universe job listed it there.
  final String? box;

  /// What to remember from the stops before it, shown on its page when opened from the path.
  final String? previously;
  Stop(this.item, {List<Item>? parts, this.season, this.art, String? title, this.code, this.group, DateTime? date, this.mini = false, this.box, this.previously})
    : parts = parts ?? [item],
      title = title ?? item.name,
      date = date ?? item.premiereDate;

  bool get isPart => code != null;
  bool get played => parts.every((p) => p.played);
  Duration get runtime => parts.fold(Duration.zero, (s, p) => s + (p.runtime ?? Duration.zero));
  Duration get resumePosition => parts.fold(Duration.zero, (s, p) => s + (p.played ? Duration.zero : p.resumePosition));
  Duration get left => parts.where((p) => !p.played).fold(Duration.zero, (s, p) => s + (p.runtime ?? Duration.zero) - p.resumePosition);

  /// A season's or cut's first episode still to watch (a half-watched one counts), else its first.
  Item get nextPart => parts.where((p) => !p.played).firstOrNull ?? parts.first;

  /// Where a tap goes: the title's page (a season or cut: its show on that season, or a mini
  /// series of its own), on the path it's from.
  String get route => '/item/${isPart ? (parts.first.seasonId ?? item.id) : item.id}${box == null ? '' : '?in=$box'}';
}

class Person {
  final Map<String, dynamic> raw;
  Person(this.raw);
  String get id => raw['Id'] as String;
  String get name => (raw['Name'] as String?) ?? '';
  String? get role => raw['Role'] as String?;
  String get type => (raw['Type'] as String?) ?? '';
  String? get imageTag => raw['PrimaryImageTag'] as String?;
}

class MediaStream {
  final Map<String, dynamic> raw;
  MediaStream(this.raw);
  String get type => (raw['Type'] as String?) ?? '';
  int get index => raw['Index'] as int;
  String? get codec => raw['Codec'] as String?;
  String? get language => raw['Language'] as String?;
  String get title => (raw['DisplayTitle'] as String?) ?? (raw['Title'] as String?) ?? language ?? 'Track $index';
  bool get isExternal => raw['IsExternal'] == true;
  bool get isText => raw['IsTextSubtitleStream'] == true;
  int? get width => raw['Width'] as int?;
}

class Genre {
  final String id;
  final String name;
  Genre(this.id, this.name);
}

/// Media segments (intro, outro, recap) when the server knows them.
class Segment {
  final String type;
  final Duration start;
  final Duration end;
  Segment(this.type, this.start, this.end);
}

/// A bonus scene in a film's credits (the universe job's "HevyfinScenes"): mid- or
/// post-credits, and whether it gives away a later stop in story order.
class Scene {
  final Duration start, end;
  final String kind;
  final bool spoiler;
  Scene(this.start, this.end, this.kind, this.spoiler);

  /// [item]'s bonus scenes and where its credits start; null when they weren't measured.
  static ({Duration credits, List<Scene> scenes})? of(Item item) {
    try {
      final m = jsonDecode(item.providerIds['hevyfinscenes'] ?? '') as Map;
      Duration at(Object? s) => Duration(milliseconds: ((s as num) * 1000).round());
      final scenes = [
        for (final x in (m['scenes'] as List).cast<Map>()) Scene(at(x['start']), at(x['end']), '${x['kind']}', x['spoiler'] == true),
      ];
      return scenes.isEmpty ? null : (credits: at(m['credits']), scenes: scenes);
    } catch (_) {
      return null;
    }
  }
}

/// Scrub previews (Jellyfin "trickplay"): small frames every [interval], packed into tile
/// images of [cols] x [rows].
class Trickplay {
  final int width, height, cols, rows, count;
  final Duration interval;
  final String Function(int tile) url;
  const Trickplay({
    required this.width,
    required this.height,
    required this.cols,
    required this.rows,
    required this.count,
    required this.interval,
    required this.url,
  });

  /// The tile image holding the frame at [pos], and the frame's column and row in it.
  (String, int, int) at(Duration pos) {
    final n = (pos.inMilliseconds ~/ max(interval.inMilliseconds, 1)).clamp(0, max(count - 1, 0)).toInt();
    final per = cols * rows;
    return (url(n ~/ per), n % per % cols, n % per ~/ cols);
  }
}

const _itemFields = 'Overview,Genres,ProviderIds,PrimaryImageAspectRatio,ChildCount,Taglines,MediaSourceCount,DateCreated,Width,Tags';

class JellyfinClient {
  final String server;
  final String deviceId;
  final Session? session;
  final http.Client _http;

  JellyfinClient(String server, this.deviceId, {this.session, http.Client? httpClient})
    : server = server.trim().replaceAll(RegExp(r'/+$'), ''),
      _http = httpClient ?? http.Client();

  JellyfinClient withSession(Session s) => JellyfinClient(server, deviceId, session: s, httpClient: _http);

  String get _device => Host.isWeb ? 'Web' : (Host.isAndroid ? 'Android' : (Host.isWindows ? 'Windows' : 'Linux'));
  String get token => session?.token ?? '';
  String get userId => session?.userId ?? '';

  Map<String, String> get _headers {
    var auth = 'MediaBrowser Client="Hevyfin", Device="$_device", DeviceId="$deviceId", Version="$appVersion"';
    if (session != null) auth += ', Token="${session!.token}"';
    return {'Authorization': auth, 'Content-Type': 'application/json', 'Accept': 'application/json'};
  }

  Uri uri(String path, [Map<String, Object?> query = const {}]) {
    final q = <String, String>{};
    query.forEach((k, v) {
      if (v != null) q[k] = '$v';
    });
    return Uri.parse('$server$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, Object?> query = const {},
    Object? body,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final req = http.Request(method, uri(path, query))..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req).timeout(timeout));
    if (res.statusCode == 401) throw JellyfinException('Signed out by the server. Sign in again.', 401);
    if (res.statusCode >= 400) throw JellyfinException('Jellyfin error ${res.statusCode}', res.statusCode);
    if (res.body.isEmpty) return null;
    return jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> get(String path, [Map<String, Object?> query = const {}]) => _send('GET', path, query: query);
  Future<dynamic> post(String path, {Map<String, Object?> query = const {}, Object? body}) => _send('POST', path, query: query, body: body ?? const {});
  Future<dynamic> delete(String path, [Map<String, Object?> query = const {}]) => _send('DELETE', path, query: query);

  List<Item> _items(dynamic json) {
    final list = json is List ? json : (json as Map)['Items'] as List;
    return list.map((e) => Item((e as Map).cast<String, dynamic>())).toList();
  }

  // ---- auth ----

  Future<void> ping({Duration timeout = const Duration(seconds: 4)}) async {
    final res = await _http.get(Uri.parse('$server/System/Info/Public')).timeout(timeout);
    if (res.statusCode != 200) throw JellyfinException('Not a Jellyfin server');
  }

  Future<Session> login(String username, String password) async {
    try {
      final json = await _send('POST', '/Users/AuthenticateByName', body: {'Username': username, 'Pw': password}, timeout: const Duration(seconds: 10));
      final user = (json['User'] as Map).cast<String, dynamic>();
      return Session(user['Id'] as String, user['Name'] as String, json['AccessToken'] as String);
    } on JellyfinException catch (e) {
      if (e.status == 401) throw JellyfinException('Wrong username or password');
      rethrow;
    }
  }

  // ---- Quick Connect: sign a TV in by approving a code from a signed-in device ----

  /// Starts a request; returns (secret, code). The code is what the user approves.
  Future<(String, String)> quickConnectStart() async {
    final j = (await _send('POST', '/QuickConnect/Initiate', timeout: const Duration(seconds: 10))) as Map;
    return (j['Secret'] as String, j['Code'] as String);
  }

  /// Whether someone approved the code yet.
  Future<bool> quickConnectApproved(String secret) async {
    final j = (await get('/QuickConnect/Connect', {'secret': secret})) as Map;
    return j['Authenticated'] == true;
  }

  Future<Session> quickConnectFinish(String secret) async {
    final json = await _send('POST', '/Users/AuthenticateWithQuickConnect', body: {'Secret': secret});
    final user = (json['User'] as Map).cast<String, dynamic>();
    return Session(user['Id'] as String, user['Name'] as String, json['AccessToken'] as String);
  }

  /// Approve a code shown on another device (a TV) for this account.
  Future<void> quickConnectApprove(String code) async {
    try {
      await post('/QuickConnect/Authorize', query: {'code': code.trim().toUpperCase(), 'userId': userId});
    } on JellyfinException catch (e) {
      if (e.status == 404 || e.status == 400) throw JellyfinException('That code is not valid or has expired');
      rethrow;
    }
  }

  Future<void> logout() async {
    try {
      await post('/Sessions/Logout');
    } catch (_) {}
  }

  // ---- browsing ----

  Future<List<Item>> items({
    List<String> types = const ['Movie', 'Series'],
    String? genre,
    String sortBy = 'SortName',
    String sortOrder = 'Ascending',
    String? filters,
    String? search,
    int? limit,
    int? startIndex,
    String? parentId,
    bool recursive = true,
    String? personIds,
  }) async => _items(
    await get('/Items', {
      'userId': userId,
      'recursive': recursive,
      'includeItemTypes': types.join(','),
      'genres': genre,
      'sortBy': sortBy,
      'sortOrder': sortOrder,
      'filters': filters,
      'searchTerm': search,
      'limit': limit,
      'startIndex': startIndex,
      'parentId': parentId,
      'personIds': personIds,
      'fields': _itemFields,
      'enableImageTypes': 'Primary,Backdrop,Logo,Thumb',
      'imageTypeLimit': 1,
    }),
  );

  Future<Item> item(String id) async => Item((await get('/Items/$id', {'userId': userId}) as Map).cast<String, dynamic>());

  Future<List<Item>> resume({int limit = 20}) async => _items(
    await get('/UserItems/Resume', {
      'userId': userId,
      'limit': limit,
      'mediaTypes': 'Video',
      'fields': _itemFields,
      'enableImageTypes': 'Primary,Backdrop,Thumb,Logo',
    }),
  );

  Future<List<Item>> nextUp({int limit = 20, String? seriesId}) async => _items(
    await get('/Shows/NextUp', {
      'userId': userId,
      'limit': limit,
      'seriesId': seriesId,
      'fields': _itemFields,
      'enableResumable': false,
      'enableRewatching': false,
    }),
  );

  /// Newest additions; series are grouped so a new episode bumps its show.
  Future<List<Item>> latest(String type, {int limit = 24}) async =>
      _items(await get('/Items/Latest', {'userId': userId, 'includeItemTypes': type, 'limit': limit, 'fields': _itemFields}));

  Future<List<Item>> similar(String id, {int limit = 20}) async =>
      _items(await get('/Items/$id/Similar', {'userId': userId, 'limit': limit, 'fields': _itemFields}));

  /// Movies and episodes watched most recently, newest first.
  Future<List<Item>> recentlyWatched({int limit = 30}) =>
      items(types: ['Movie', 'Episode'], filters: 'IsPlayed', sortBy: 'DatePlayed', sortOrder: 'Descending', limit: limit);

  Future<List<Genre>> genres({List<String> types = const ['Movie', 'Series']}) async {
    final json = await get('/Genres', {'userId': userId, 'recursive': true, 'includeItemTypes': types.join(','), 'sortBy': 'SortName'});
    return ((json as Map)['Items'] as List).map((g) => Genre(g['Id'] as String, g['Name'] as String)).toList();
  }

  Future<List<Item>> seasons(String seriesId) async => _items(await get('/Shows/$seriesId/Seasons', {'userId': userId, 'fields': 'ChildCount'}));

  Future<List<Item>> episodes(String seriesId, {String? seasonId}) async =>
      _items(await get('/Shows/$seriesId/Episodes', {'userId': userId, 'seasonId': seasonId, 'fields': 'Overview,ProviderIds'}));

  // ---- collections (franchises, watched in order) ----

  static (DateTime, Map<String, List<Item>>)? _owners;

  /// Franchise collections. The library also has genre collections (made by a plugin),
  /// which aren't films to watch in order: only TMDb's "… Collection" ones and those
  /// tagged "franchise" (see docs/custom-collections.md) count. The
  /// tagged ones come first.
  Future<List<Item>> collections() async {
    final all = (await items(types: ['BoxSet'])).where((b) => b.name.endsWith('Collection') || b.isUniverse).toList();
    return [...all.where((b) => b.isUniverse), ...all.where((b) => !b.isUniverse)];
  }

  /// A collection's films (and series) in release order, or in story order if [story] and
  /// its titles carry story tags. [name] is the collection's name (the tags use it).
  Future<List<Item>> collectionItems(String id, {bool story = false, String? name}) async {
    final films = _items(
      await get('/Items', {
        'userId': userId,
        'parentId': id,
        'includeItemTypes': 'Movie,Series',
        'sortBy': 'PremiereDate,ProductionYear,SortName',
        'fields': _itemFields,
        'enableImageTypes': 'Primary,Backdrop,Logo,Thumb',
        'imageTypeLimit': 1,
      }),
    );
    if (story && name != null) {
      mergeSort(films, compare: (a, b) => (a.storyPlace(name) ?? 9999).compareTo(b.storyPlace(name) ?? 9999));
    }
    return films;
  }

  /// Every collection a film or series is in (looked up once, kept for half an hour): its
  /// own franchise first, then any universe (a film: its "… Collection", then its universe).
  Future<List<Item>> collectionsOf(String id) async {
    final cached = _owners;
    if (cached == null || DateTime.now().difference(cached.$1) > const Duration(minutes: 30)) {
      final owners = <String, List<Item>>{};
      final all = await collections();
      final lists = await Future.wait(all.map((b) => items(types: ['Movie', 'Series'], parentId: b.id, limit: 100)));
      for (final (i, b) in all.indexed) {
        for (final m in lists[i]) {
          owners.putIfAbsent(m.id, () => []).add(b);
        }
      }
      for (final l in owners.values) {
        mergeSort(l, compare: (a, b) => (a.isUniverse ? 1 : 0).compareTo(b.isUniverse ? 1 : 0));
      }
      _owners = (DateTime.now(), owners);
    }
    return _owners!.$2[id] ?? const [];
  }

  /// The franchise a film rolls on in: its own (part 2 into part 3) before a whole
  /// universe, which is theirs only when they have no other.
  Future<Item?> collectionOf(String movieId) async => (await collectionsOf(movieId)).firstOrNull;

  /// [box]'s path as stops, in story order, or by release unless [story]. The universe job
  /// can spread a show over the story (a season, a cut of episodes, each its own stop); a
  /// collection without its list, and titles it doesn't list (yet), get a stop per title.
  Future<List<Stop>> universeStops(Item box, List<Item> films, {bool story = false}) async {
    List<Map>? list;
    try {
      list = (jsonDecode(box.providerIds['hevyfinstory'] ?? '') as List).whereType<Map>().toList();
    } catch (_) {}
    if (list == null || list.isEmpty) return [for (final f in films) Stop(f, group: _groupOf(f, box.name))];
    final byId = {for (final f in films) f.id: f};
    // The seasons' and cuts' episodes and their seasons (their posters), in one go each.
    final parts = <String, Item>{};
    final want = {
      for (final s in list)
        if (s['series'] != null) ...((s['ids'] as List?) ?? const []).cast<String>(),
    };
    if (want.isNotEmpty) {
      final eps = _items(await get('/Items', {'userId': userId, 'ids': want.join(','), 'fields': _itemFields}));
      final seasons = {for (final e in eps) ?e.seasonId};
      final ss = seasons.isEmpty ? const <Item>[] : _items(await get('/Items', {'userId': userId, 'ids': seasons.join(',')}));
      for (final i in [...eps, ...ss]) {
        parts[i.id] = i;
      }
    }
    final stops = <Stop>[], seen = <String>{};
    for (final s in list) {
      final series = s['series'] as String?;
      final ids = ((s['ids'] as List?) ?? const []).cast<String>();
      final item = byId[series ?? ids.firstOrNull];
      if (item == null) continue;
      seen.add(item.id);
      final date = DateTime.tryParse('${s['date'] ?? ''}');
      final group = s['group'] as String? ?? _groupOf(item, box.name);
      final previously = s['previously'] as String?;
      if (series == null) {
        stops.add(Stop(item, group: group, date: date, box: box.id, previously: previously));
        continue;
      }
      final eps = [for (final id in ids) ?parts[id]];
      if (eps.isEmpty) continue;
      final season = s['kind'] == 'season' ? parts[eps.first.seasonId] : null;
      final art = s['art'] is Map && (s['art'] as Map)['id'] is String
          ? (id: (s['art'] as Map)['id'] as String, tag: (s['art'] as Map)['tag'] as String?)
          : null;
      stops.add(Stop(item, parts: eps, season: season, art: art, title: s['title'] as String?, code: '${s['code'] ?? ''}', group: group, date: date,
          mini: s['mini'] == true, box: box.id, previously: previously));
    }
    for (final f in films) {
      if (!seen.contains(f.id)) stops.add(Stop(f, group: _groupOf(f, box.name)));
    }
    if (!story) mergeSort(stops, compare: (a, b) => (a.date ?? DateTime(9999)).compareTo(b.date ?? DateTime(9999)));
    return stops;
  }

  /// [i] as a stop on the path of the universe [boxId], opened from there: a film or show
  /// with its stop (for "Previously", and Play carrying on along the path); a season the path
  /// makes a mini series (a show spread over the story, season by season) as its show,
  /// narrowed to that stop's episodes, with the season's own story and date. Null when the
  /// path has no such stop: then it opens as usual.
  Future<Item?> onPath(Item i, String boxId) async {
    final box = await item(boxId);
    final stops = await universeStops(box, await collectionItems(boxId), story: true);
    final stop = stops.where((s) => i.isSeason ? s.mini && s.parts.first.seasonId == i.id : !s.isPart && s.item.id == i.id).firstOrNull;
    if (stop == null) return null;
    if (!i.isSeason) return i..raw['PathStop'] = stop;
    final show = await item(stop.item.id), first = stop.parts.first;
    show.raw
      ..['PathStop'] = stop
      ..['PremiereDate'] = first.raw['PremiereDate']
      ..['ProductionYear'] = first.year;
    // A whole season has its own story; a cut of one keeps the show's.
    if (stop.season != null && (i.overview ?? '').isNotEmpty) show.raw['Overview'] = i.overview;
    return show;
  }

  static String? _groupOf(Item f, String box) {
    final prefix = 'group:$box:';
    return f.tags.where((t) => t.startsWith(prefix)).map((t) => t.substring(prefix.length)).firstOrNull;
  }

  /// What follows [current] on the path of the universe [boxId], when it was started from
  /// there: the next episode of its season or cut (a whole show plays on through), then the
  /// next stop: its first episode still to watch, a show where it's up to, or the film.
  /// Null when [current] isn't on that path or is the last of it.
  Future<Item?> nextInUniverse(String boxId, Item current, {bool story = false}) async {
    final box = await item(boxId);
    final stops = await universeStops(
      box,
      await collectionItems(boxId, story: story, name: box.name),
      story: story,
    );
    final at = stops.indexWhere((s) => s.parts.any((p) => p.id == current.id) || (!s.isPart && s.item.id == current.seriesId));
    if (at < 0) return null;
    final here = stops[at];
    if (here.isPart) {
      final i = here.parts.indexWhere((p) => p.id == current.id);
      if (i + 1 < here.parts.length) return here.parts[i + 1];
    } else if (current.isEpisode) {
      final n = await nextEpisode(current);
      if (n != null) return n;
    }
    if (at + 1 >= stops.length) return null;
    final next = stops[at + 1];
    if (next.isPart) return next.nextPart;
    if (!next.item.isSeries) return next.item;
    return (await nextUp(seriesId: next.item.id, limit: 1)).firstOrNull ??
        (await episodes(next.item.id)).where((e) => (e.parentIndexNumber ?? 0) > 0).firstOrNull;
  }

  /// The film after [movie] in its franchise, if any, in story order for the collections in
  /// [storyOrder] (ids).
  Future<(Item, Item)?> nextInCollection(Item movie, {Set<String> storyOrder = const {}}) async {
    final b = await collectionOf(movie.id);
    if (b == null) return null;
    final list = await collectionItems(b.id, story: storyOrder.contains(b.id), name: b.name);
    final i = list.indexWhere((m) => m.id == movie.id);
    return i >= 0 && i + 1 < list.length ? (list[i + 1], b) : null;
  }

  /// The episode after [episode] in the same show, if any.
  Future<Item?> nextEpisode(Item episode) async {
    final all = _items(await get('/Shows/${episode.seriesId}/Episodes', {'userId': userId, 'startItemId': episode.id, 'limit': 2}));
    return all.length > 1 ? all[1] : null;
  }

  Future<void> setFavorite(String id, bool fav) =>
      fav ? post('/UserFavoriteItems/$id', query: {'userId': userId}) : delete('/UserFavoriteItems/$id', {'userId': userId});
  Future<void> setPlayed(String id, bool played) =>
      played ? post('/UserPlayedItems/$id', query: {'userId': userId}) : delete('/UserPlayedItems/$id', {'userId': userId});

  /// The scrub previews of a video, if the server has made them. Jellyfin 12 takes the key for
  /// these only as "ApiKey" (it refuses "api_key").
  Future<Trickplay?> trickplay(String id, String mediaSourceId) async {
    try {
      final j = (await get('/Items', {'userId': userId, 'ids': id, 'fields': 'Trickplay'}) as Map)['Items'] as List;
      final all = ((j.firstOrNull as Map?)?['Trickplay'] as Map?) ?? const {};
      final bySource = (all[mediaSourceId] ?? all.values.firstOrNull) as Map?;
      if (bySource == null || bySource.isEmpty) return null;
      // The smallest size is plenty for a preview and quickest to load.
      final w = bySource.keys.map((k) => int.parse('$k')).reduce(min);
      final t = (bySource['$w'] as Map).cast<String, dynamic>();
      return Trickplay(
        width: t['Width'] as int,
        height: t['Height'] as int,
        cols: t['TileWidth'] as int,
        rows: t['TileHeight'] as int,
        count: t['ThumbnailCount'] as int,
        interval: Duration(milliseconds: t['Interval'] as int),
        url: (tile) => uri('/Videos/$id/Trickplay/$w/$tile.jpg', {'mediaSourceId': mediaSourceId, 'ApiKey': token}).toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<List<Segment>> segments(String id) async {
    try {
      final json = await get('/MediaSegments/$id');
      return ((json as Map)['Items'] as List)
          .map(
            (s) => Segment(s['Type'] as String, Duration(microseconds: (s['StartTicks'] as num) ~/ 10), Duration(microseconds: (s['EndTicks'] as num) ~/ 10)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ---- small shared settings ----

  /// A string saved on the server for this user, shared by all their Hevyfin devices
  /// (kept in Jellyfin's display preferences).
  Future<String?> sharedPref(String key) async {
    final j = await get('/DisplayPreferences/hevyfin-shared', {'userId': userId, 'client': 'hevyfin'}) as Map;
    return ((j['CustomPrefs'] as Map?) ?? const {})[key] as String?;
  }

  Future<void> setSharedPref(String key, String value) async {
    final j = (await get('/DisplayPreferences/hevyfin-shared', {'userId': userId, 'client': 'hevyfin'}) as Map).cast<String, dynamic>();
    final prefs = ((j['CustomPrefs'] as Map?) ?? const {}).cast<String, dynamic>();
    prefs[key] = value;
    await post(
      '/DisplayPreferences/hevyfin-shared',
      query: {'userId': userId, 'client': 'hevyfin'},
      body: {...j, 'Id': 'hevyfin-shared', 'Client': 'hevyfin', 'CustomPrefs': prefs},
    );
  }

  /// Audio and subtitle language chosen per show, on every device:
  /// {seriesId: {"a": "jpn", "s": "eng" | "off"}}.
  Future<Map<String, dynamic>> showTracks() async {
    try {
      return (jsonDecode(await sharedPref('showTracks') ?? '{}') as Map).cast<String, dynamic>();
    } catch (_) {
      return {};
    }
  }

  Future<void> saveShowTrack(String seriesId, {String? audio, String? subtitle}) async {
    final all = await showTracks();
    final cur = ((all[seriesId] as Map?) ?? const {}).cast<String, dynamic>();
    all[seriesId] = {...cur, 'a': ?audio, 's': ?subtitle};
    await setSharedPref('showTracks', jsonEncode(all));
  }

  // ---- other devices: remote control and watching together ----

  /// This device can be told what to play and be paused, seeked and stopped from others.
  Future<void> announceCapabilities() => post(
    '/Sessions/Capabilities/Full',
    body: {
      'PlayableMediaTypes': ['Video'],
      'SupportedCommands': ['DisplayMessage', 'SetSubtitleStreamIndex', 'SetAudioStreamIndex'],
      'SupportsMediaControl': true,
      'SupportsPersistentIdentifier': true,
    },
  );

  /// The address of the live socket that brings commands from other devices; it signs in
  /// with [socketHeaders] (Jellyfin 12 refuses a key in the address). A browser can't send
  /// headers, so the web version's server makes one from `api_key` and drops the key.
  Uri socketUri() {
    final u = Uri.parse(server);
    return Uri(
      scheme: u.scheme == 'https' ? 'wss' : 'ws',
      host: u.host,
      port: u.port,
      path: '${u.path}/socket',
      queryParameters: {'deviceId': deviceId, if (Host.isWeb) 'api_key': token},
    );
  }

  Map<String, String> get socketHeaders => {'Authorization': _headers['Authorization']!};

  /// Other devices signed in to this account that take remote commands, most recent first.
  Future<List<RemoteSession>> remoteSessions() async {
    final list = await get('/Sessions', {'controllableByUserId': userId, 'activeWithinSeconds': 900}) as List;
    return [
      for (final s in list.cast<Map>())
        if (s['SupportsRemoteControl'] == true && s['DeviceId'] != deviceId) RemoteSession(s.cast<String, dynamic>()),
    ];
  }

  Future<void> playOn(String sessionId, String itemId, {Duration start = Duration.zero}) =>
      post('/Sessions/$sessionId/Playing', query: {'playCommand': 'PlayNow', 'itemIds': itemId, 'startPositionTicks': start.inMicroseconds * 10});

  /// Pause, Unpause, PlayPause, Stop, NextTrack, PreviousTrack, or Seek with [seek].
  Future<void> commandOn(String sessionId, String command, {Duration? seek}) =>
      post('/Sessions/$sessionId/Playing/$command', query: {if (seek != null) 'seekPositionTicks': seek.inMicroseconds * 10});

  /// How far the server's clock is ahead of ours (SyncPlay schedules by the server's time).
  Future<Duration> clockOffset() async {
    final t0 = DateTime.now().toUtc();
    final j = await get('/GetUtcTime') as Map;
    final t3 = DateTime.now().toUtc();
    final t1 = DateTime.parse(j['RequestReceptionTime'] as String), t2 = DateTime.parse(j['ResponseTransmissionTime'] as String);
    return Duration(microseconds: ((t1.difference(t0).inMicroseconds) + (t2.difference(t3).inMicroseconds)) ~/ 2);
  }

  Future<List<Map<String, dynamic>>> syncGroups() async => [for (final g in (await get('/SyncPlay/List') as List).cast<Map>()) g.cast<String, dynamic>()];
  Future<void> syncNew(String name) => post('/SyncPlay/New', body: {'GroupName': name});
  Future<void> syncJoin(String groupId) => post('/SyncPlay/Join', body: {'GroupId': groupId});
  Future<void> syncLeave() => post('/SyncPlay/Leave');
  Future<void> syncQueue(String itemId, {Duration start = Duration.zero}) => post(
    '/SyncPlay/SetNewQueue',
    body: {
      'PlayingQueue': [itemId],
      'PlayingItemPosition': 0,
      'StartPositionTicks': start.inMicroseconds * 10,
    },
  );
  Future<void> syncPause() => post('/SyncPlay/Pause');
  Future<void> syncUnpause() => post('/SyncPlay/Unpause');
  Future<void> syncSeek(Duration to) => post('/SyncPlay/Seek', body: {'PositionTicks': to.inMicroseconds * 10});
  Future<void> syncReady(DateTime when, Duration pos, bool playing, String playlistItemId, {bool buffering = false}) => post(
    buffering ? '/SyncPlay/Buffering' : '/SyncPlay/Ready',
    body: {'When': when.toUtc().toIso8601String(), 'PositionTicks': pos.inMicroseconds * 10, 'IsPlaying': playing, 'PlaylistItemId': playlistItemId},
  );

  // ---- cinema and channels ----

  /// Everything the TV's channels and cinema can schedule: movies, and series with their
  /// episodes in order (specials left out).
  Future<(List<Item>, List<Item>, List<Item>)> schedulable() async {
    const fields = 'Genres,OfficialRating,CriticRating,CommunityRating,RunTimeTicks,ProviderIds,Tags';
    final movies = _items(await get('/Items', {'userId': userId, 'recursive': true, 'includeItemTypes': 'Movie', 'fields': fields}));
    final series = _items(await get('/Items', {'userId': userId, 'recursive': true, 'includeItemTypes': 'Series', 'fields': fields}));
    final episodes = _items(
      await get('/Items', {
        'userId': userId,
        'recursive': true,
        'includeItemTypes': 'Episode',
        'fields': 'RunTimeTicks',
        'sortBy': 'SeriesSortName,ParentIndexNumber,IndexNumber',
        'enableImages': false,
      }),
    );
    return (movies, series, episodes);
  }

  /// Trailers in the hidden "Cinema" library (…/Cinema/Trailers/, see docs/tv-channels.md).
  /// It is left out of the user's views, so find its items by path instead.
  Future<List<Item>> cinemaClips() async {
    final all = _items(await get('/Items', {'userId': userId, 'recursive': true, 'includeItemTypes': 'Video', 'fields': 'Path', 'enableImages': false}));
    return all.where((i) => ((i.raw['Path'] as String?) ?? '').contains('/Cinema/Trailers/')).toList();
  }

  static (DateTime, Map<String, String>)? _trailers;

  /// The video id of [i]'s trailer, if the server has saved one (server/library-trailers.py
  /// keeps them in the hidden Cinema library as `Library/movie-<tmdb>.mp4` or `tv-<tmdb>.mp4`).
  Future<String?> libraryTrailer(Item i) async {
    final tmdb = i.tmdbId;
    if (tmdb == null) return null;
    final t = _trailers;
    if (t == null || DateTime.now().difference(t.$1) > const Duration(minutes: 10)) {
      final all = _items(await get('/Items', {'userId': userId, 'recursive': true, 'includeItemTypes': 'Video', 'fields': 'Path', 'enableImages': false}));
      _trailers = (
        DateTime.now(),
        {
          for (final v in all)
            if (((v.raw['Path'] as String?) ?? '').contains('/Cinema/Library/')) (v.raw['Path'] as String).split('/').last.split('.').first: v.id,
        },
      );
    }
    return _trailers!.$2['${i.isSeries ? 'tv' : 'movie'}-$tmdb'];
  }

  static (DateTime, List<Item>)? _everything;

  /// Every film and series (with tags and genres), kept for a few minutes: the library is
  /// small enough to filter here for seasonal rows and "What tonight?".
  Future<List<Item>> everything() async {
    final e = _everything;
    if (e != null && DateTime.now().difference(e.$1) < const Duration(minutes: 5) && e.$2.isNotEmpty) return e.$2;
    final all = _items(
      await get('/Items', {
        'userId': userId,
        'recursive': true,
        'includeItemTypes': 'Movie,Series',
        'collapseBoxSetItems': false,
        'fields': '$_itemFields,OfficialRating',
        'enableImageTypes': 'Primary,Backdrop,Logo,Thumb',
        'imageTypeLimit': 1,
      }),
    );
    _everything = (DateTime.now(), all);
    return all;
  }

  /// These items, in this order (missing ones left out).
  Future<List<Item>> itemsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final got = _items(await get('/Items', {'userId': userId, 'ids': ids.join(','), 'fields': _itemFields, 'enableImageTypes': 'Primary,Backdrop,Logo,Thumb'}));
    final by = {for (final i in got) i.id: i};
    return [for (final id in ids) ?by[id]];
  }

  // ---- images ----

  String _img(String id, String type, {String? tag, int? width, int index = 0}) {
    final path = type == 'Backdrop' ? '/Items/$id/Images/Backdrop/$index' : '/Items/$id/Images/$type';
    // Cards ask for twice their size (phone screens); the TV's 1080p screen needs about
    // three quarters of that, and smaller files decode faster on its slow CPU.
    final w = width == null ? null : (Device.isTv ? (width * .75).round() : width);
    return uri(path, {'tag': tag, 'maxWidth': w, 'quality': Device.isTv ? 82 : 90}).toString();
  }

  /// Portrait poster; an episode shows its series' poster.
  String? poster(Item i, {int width = 400}) {
    if (i.isEpisode && i.raw['SeriesPrimaryImageTag'] != null) return _img(i.seriesId!, 'Primary', tag: i.raw['SeriesPrimaryImageTag'], width: width);
    if (i.isSeason && i.imageTags['Primary'] == null && i.seriesId != null) return _img(i.seriesId!, 'Primary', width: width);
    final tag = i.imageTags['Primary'];
    return tag == null ? null : _img(i.id, 'Primary', tag: tag, width: width);
  }

  /// A stop's poster: a cut's own, a season's, else its film's or show's.
  String? stopPoster(Stop s, {int width = 400}) {
    final art = s.art;
    if (art != null) return _img(art.id, 'Box', tag: art.tag, width: width);
    return poster(s.season ?? s.item, width: width);
  }

  /// Wide art: own backdrop, else the parent's (episodes, seasons).
  String? backdrop(Item i, {int width = 1920}) {
    if (i.backdropTags.isNotEmpty) return _img(i.id, 'Backdrop', tag: i.backdropTags.first, width: width);
    final parent = i.raw['ParentBackdropItemId'] as String?;
    final tags = (i.raw['ParentBackdropImageTags'] as List?)?.cast<String>();
    if (parent != null && tags != null && tags.isNotEmpty) return _img(parent, 'Backdrop', tag: tags.first, width: width);
    return null;
  }

  /// Landscape still for "continue watching": the episode frame, else thumb, else backdrop.
  String? thumb(Item i, {int width = 640}) {
    if (i.isEpisode && i.imageTags['Primary'] != null) return _img(i.id, 'Primary', tag: i.imageTags['Primary'], width: width);
    if (i.imageTags['Thumb'] != null) return _img(i.id, 'Thumb', tag: i.imageTags['Thumb'], width: width);
    final parentThumb = i.raw['ParentThumbItemId'] as String?;
    if (parentThumb != null) return _img(parentThumb, 'Thumb', tag: i.raw['ParentThumbImageTag'] as String?, width: width);
    return backdrop(i, width: width);
  }

  String? logo(Item i, {int width = 600}) {
    if (i.imageTags['Logo'] != null) return _img(i.id, 'Logo', tag: i.imageTags['Logo'], width: width);
    final parent = i.raw['ParentLogoItemId'] as String?;
    if (parent != null) return _img(parent, 'Logo', tag: i.raw['ParentLogoImageTag'] as String?, width: width);
    return null;
  }

  /// An item's image by id alone (no cache tag), for things we only know the id of.
  String image(String id, {String type = 'Backdrop', int width = 1280}) => _img(id, type, width: width);

  String? personImage(Person p, {int width = 240}) => p.imageTag == null ? null : _img(p.id, 'Primary', tag: p.imageTag, width: width);

  // ---- playback ----

  // ---- free TV channels (Jellyfin Live TV: an M3U of broadcasters' own streams + XMLTV) ----

  Future<List<Item>> tvChannels() async =>
      _items(await get('/LiveTv/Channels', {'userId': userId, 'sortBy': 'SortName', 'enableImages': true}))
        ..sort((a, b) => (int.tryParse(a.channelNumber ?? '') ?? 999).compareTo(int.tryParse(b.channelNumber ?? '') ?? 999));

  /// Programmes on any channel between [from] and [to].
  Future<List<Item>> tvPrograms(DateTime from, DateTime to) async => _items(
    await get('/LiveTv/Programs', {
      'userId': userId,
      'MinEndDate': from.toUtc().toIso8601String(),
      'MaxStartDate': to.toUtc().toIso8601String(),
      'SortBy': 'StartDate',
      'Fields': 'Overview',
      'enableImages': false,
    }),
  );

  /// The broadcaster's own stream address for a channel (played as it is, no server work).
  Future<String?> channelStream(String channelId) async {
    final j = await post('/Items/$channelId/PlaybackInfo', query: {'userId': userId, 'autoOpenLiveStream': false}, body: {'UserId': userId});
    return (((j as Map)['MediaSources'] as List?)?.firstOrNull as Map?)?['Path'] as String?;
  }

  // ---- getting ready to play before OK is pressed (TV: resting on Play) ----

  final _warm = <String, (DateTime, Future<Item>, Future<PlaybackInfo>)>{};

  /// Starts fetching what the player needs for [id], so pressing Play starts sooner.
  void prewarm(String id, {int? maxBitrate}) {
    final key = '$id|$maxBitrate';
    final had = _warm[key];
    if (had != null && DateTime.now().difference(had.$1) < const Duration(seconds: 45)) return;
    final item = this.item(id), info = _playbackInfo(id, maxBitrate: maxBitrate);
    // A failed warm-up is just a miss: the player asks again.
    item.ignore();
    info.ignore();
    _warm[key] = (DateTime.now(), item, info);
  }

  /// [item] and [playbackInfo] for the player, from a warm-up when there is a fresh one.
  Future<(Item, PlaybackInfo)> forPlayer(String id, {int? maxBitrate}) async {
    final w = _warm.remove('$id|$maxBitrate');
    if (w != null && DateTime.now().difference(w.$1) < const Duration(seconds: 45)) {
      try {
        return (await w.$2, await w.$3);
      } catch (_) {}
    }
    return (await item(id), await _playbackInfo(id, maxBitrate: maxBitrate));
  }

  /// [audioIndex] and [subtitleIndex] are for the web version, which can't switch tracks
  /// itself: [transcode] has the server send that audio track (or burn in a picture
  /// subtitle) in its own stream.
  Future<PlaybackInfo> playbackInfo(String id, {int? maxBitrate, int? audioIndex, int? subtitleIndex, bool transcode = false}) =>
      _playbackInfo(id, maxBitrate: maxBitrate, audioIndex: audioIndex, subtitleIndex: subtitleIndex, transcode: transcode);

  Future<PlaybackInfo> _playbackInfo(String id, {int? maxBitrate, int? audioIndex, int? subtitleIndex, bool transcode = false}) async {
    final json = await post(
      '/Items/$id/PlaybackInfo',
      query: {'userId': userId},
      body: {
        'UserId': userId,
        'MaxStreamingBitrate': maxBitrate ?? 1000000000,
        'AudioStreamIndex': ?audioIndex,
        // The web version never lets the server pick a subtitle by itself: it would burn it in.
        'SubtitleStreamIndex': subtitleIndex ?? (Host.isWeb ? -1 : null),
        if (transcode) 'EnableDirectPlay': false,
        // A browser plays a file as it is or the server's HLS; never a remuxed file.
        if (Host.isWeb) 'EnableDirectStream': false,
        'DeviceProfile': Host.isWeb ? _browserProfile(maxBitrate) : _mpvProfile(maxBitrate),
      },
    );
    final source = ((json['MediaSources'] as List).first as Map).cast<String, dynamic>();
    return PlaybackInfo(json['PlaySessionId'] as String? ?? '', source);
  }

  // mpv plays everything, so ask for direct play unless a bitrate cap forces a transcode.
  static Map<String, Object?> _mpvProfile(int? maxBitrate) => {
    'MaxStreamingBitrate': maxBitrate ?? 1000000000,
    'DirectPlayProfiles': maxBitrate == null
        ? [
            {'Type': 'Video'},
          ]
        : [],
    'TranscodingProfiles': [
      {
        'Container': 'ts',
        'Type': 'Video',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac,ac3',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'MaxAudioChannels': '6',
        'BreakOnNonKeyFrames': true,
      },
    ],
    'SubtitleProfiles': [
      {'Format': 'srt', 'Method': 'External'},
      {'Format': 'ass', 'Method': 'External'},
      {'Format': 'vtt', 'Method': 'External'},
      {'Format': 'pgssub', 'Method': 'Encode'},
    ],
  };

  /// What a browser plays itself (Chrome and Firefox alike): MP4 and WebM with H.264, VP9 or
  /// AV1, 8-bit. Everything else (MKV, HEVC, DTS, 10-bit H.264) comes as the server's HLS,
  /// which copies the picture when it can and turns the sound into stereo AAC.
  static Map<String, Object?> _browserProfile(int? maxBitrate) => {
    'MaxStreamingBitrate': maxBitrate ?? 1000000000,
    'DirectPlayProfiles': maxBitrate == null
        ? [
            {'Container': 'mp4,m4v', 'Type': 'Video', 'VideoCodec': 'h264,vp9,av1', 'AudioCodec': 'aac,mp3,opus,flac'},
            {'Container': 'webm', 'Type': 'Video', 'VideoCodec': 'vp8,vp9,av1', 'AudioCodec': 'vorbis,opus'},
          ]
        : [],
    'TranscodingProfiles': [
      {
        'Container': 'ts',
        'Type': 'Video',
        'VideoCodec': 'h264',
        'AudioCodec': 'aac',
        'Protocol': 'hls',
        'Context': 'Streaming',
        'MaxAudioChannels': '2',
        'BreakOnNonKeyFrames': true,
      },
    ],
    'CodecProfiles': [
      {
        'Type': 'Video',
        'Codec': 'h264',
        'Conditions': [
          {'Condition': 'LessThanEqual', 'Property': 'VideoBitDepth', 'Value': '8', 'IsRequired': false},
        ],
      },
    ],
    // Text subtitles are fetched as WebVTT and drawn by Hevyfin; picture ones are burnt in.
    'SubtitleProfiles': [
      for (final f in ['vtt', 'srt', 'subrip', 'ass', 'ssa']) {'Format': f, 'Method': 'External'},
      for (final f in ['pgssub', 'dvdsub', 'dvbsub']) {'Format': f, 'Method': 'Encode'},
    ],
  };

  /// Direct file stream (original quality) or the server's HLS transcode.
  String streamUrl(String id, PlaybackInfo info) {
    final transcode = info.source['TranscodingUrl'] as String?;
    if (info.source['SupportsDirectPlay'] != true && info.source['SupportsDirectStream'] != true && transcode != null) {
      return '$server$transcode';
    }
    return uri('/Videos/$id/stream', {'static': true, 'mediaSourceId': info.mediaSourceId, 'api_key': token, 'PlaySessionId': info.playSessionId}).toString();
  }

  String subtitleUrl(String id, PlaybackInfo info, MediaStream s) {
    // The web version reads every text subtitle as WebVTT (the server converts SRT and ASS).
    if (Host.isWeb) return uri('/Videos/$id/${info.mediaSourceId}/Subtitles/${s.index}/0/Stream.vtt', {'api_key': token}).toString();
    final delivery = s.raw['DeliveryUrl'] as String?;
    if (delivery != null) return '$server$delivery';
    final ext = s.codec == 'ass' || s.codec == 'ssa' ? 'ass' : 'srt';
    return uri('/Videos/$id/${info.mediaSourceId}/Subtitles/${s.index}/0/Stream.$ext', {'api_key': token}).toString();
  }

  Future<void> reportStart(String id, PlaybackInfo info, Duration pos) => post('/Sessions/Playing', body: _progressBody(id, info, pos, false));
  Future<void> reportProgress(String id, PlaybackInfo info, Duration pos, bool paused) =>
      post('/Sessions/Playing/Progress', body: _progressBody(id, info, pos, paused));
  Future<void> reportStop(String id, PlaybackInfo info, Duration pos) async {
    await post('/Sessions/Playing/Stopped', body: _progressBody(id, info, pos, false));
    if (info.isTranscode) {
      try {
        await delete('/Videos/ActiveEncodings', {'deviceId': deviceId, 'playSessionId': info.playSessionId});
      } catch (_) {}
    }
  }

  /// Stop the server's transcode for a play session we never reported (cinema and TV).
  Future<void> endTranscode(PlaybackInfo info) async {
    if (!info.isTranscode) return;
    try {
      await delete('/Videos/ActiveEncodings', {'deviceId': deviceId, 'playSessionId': info.playSessionId});
    } catch (_) {}
  }

  Map<String, Object?> _progressBody(String id, PlaybackInfo info, Duration pos, bool paused) => {
    'ItemId': id,
    'MediaSourceId': info.mediaSourceId,
    'PlaySessionId': info.playSessionId,
    'PositionTicks': pos.inMicroseconds * 10,
    'IsPaused': paused,
    'CanSeek': true,
    'PlayMethod': info.isTranscode ? 'Transcode' : 'DirectPlay',
  };
}

/// Another device signed in to the account (a TV, a phone, a browser).
class RemoteSession {
  final Map<String, dynamic> raw;
  RemoteSession(this.raw);
  String get id => raw['Id'] as String;
  String get device => (raw['DeviceName'] as String?) ?? 'Device';
  String get client => (raw['Client'] as String?) ?? '';
  Item? get nowPlaying => raw['NowPlayingItem'] == null ? null : Item((raw['NowPlayingItem'] as Map).cast<String, dynamic>());
  Map<String, dynamic> get _state => ((raw['PlayState'] as Map?) ?? const {}).cast<String, dynamic>();
  bool get paused => _state['IsPaused'] == true;
  Duration get position => Duration(microseconds: ((_state['PositionTicks'] as num?) ?? 0) ~/ 10);
}

class PlaybackInfo {
  final String playSessionId;
  final Map<String, dynamic> source;
  PlaybackInfo(this.playSessionId, this.source);
  String get mediaSourceId => source['Id'] as String;
  bool get isTranscode => source['SupportsDirectPlay'] != true && source['SupportsDirectStream'] != true && source['TranscodingUrl'] != null;
  int? get defaultAudio => source['DefaultAudioStreamIndex'] as int?;
  List<MediaStream> get streams => ((source['MediaStreams'] as List?) ?? const []).map((m) => MediaStream((m as Map).cast<String, dynamic>())).toList();
}
