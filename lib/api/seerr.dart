import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class SeerrException implements Exception {
  final String message;
  final int? status;
  SeerrException(this.message, [this.status]);
  @override
  String toString() => message;
}

/// Seerr's media status (mediaInfo.status).
enum MediaStatus {
  unknown,
  pending,
  processing,
  partial,
  available,
  deleted;

  static MediaStatus of(int? s) => switch (s) {
    2 => pending,
    3 => processing,
    4 => partial,
    5 => available,
    6 => deleted,
    _ => unknown,
  };

  String get label => switch (this) {
    // Requests that go straight through are processing at once; pending ones wait for an admin.
    pending => 'Waiting for approval',
    processing => 'Downloading',
    partial => 'Partly available',
    available => 'Available',
    _ => '',
  };

  bool get requestable => this == unknown || this == deleted || this == partial;
}

/// A movie or show as Seerr (TMDB) knows it.
class SeerrMedia {
  final Map<String, dynamic> raw;
  SeerrMedia(this.raw);

  int get tmdbId => (raw['id'] as num).toInt();
  String get mediaType => (raw['mediaType'] as String?) ?? (raw['firstAirDate'] != null || raw['name'] != null ? 'tv' : 'movie');
  bool get isTv => mediaType == 'tv';
  String get title => (raw['title'] as String?) ?? (raw['name'] as String?) ?? '';
  String? get overview => raw['overview'] as String?;
  String? get tagline => raw['tagline'] as String?;
  String? get posterPath => raw['posterPath'] as String?;
  String? get backdropPath => raw['backdropPath'] as String?;
  double? get voteAverage => (raw['voteAverage'] as num?)?.toDouble();
  int? get year => int.tryParse(((raw['releaseDate'] ?? raw['firstAirDate']) as String? ?? '').split('-').first);
  int? get runtime => raw['runtime'] as int? ?? ((raw['episodeRunTime'] as List?)?.firstOrNull as int?);
  List<String> get genres => ((raw['genres'] as List?) ?? const []).map((g) => (g as Map)['name'] as String).toList();

  /// The official trailer on YouTube (details only).
  String? get trailerUrl {
    final vids = ((raw['relatedVideos'] as List?) ?? const []).cast<Map>().where((v) => v['site'] == 'YouTube' && v['type'] == 'Trailer').toList()
      ..sort((a, b) => ('${a['name']}'.toLowerCase().contains('official') ? 0 : 1).compareTo('${b['name']}'.toLowerCase().contains('official') ? 0 : 1));
    return vids.firstOrNull?['url'] as String?;
  }

  Map<String, dynamic>? get _info => (raw['mediaInfo'] as Map?)?.cast<String, dynamic>();
  MediaStatus get status => MediaStatus.of(_info?['status'] as int?);
  String? get jellyfinId => _info?['jellyfinMediaId'] as String?;

  /// Download progress 0..1 from Sonarr/Radarr, if something is downloading.
  double? get downloadProgress {
    final list = (_info?['downloadStatus'] as List?) ?? const [];
    var size = 0.0, left = 0.0;
    for (final d in list) {
      size += ((d as Map)['size'] as num?)?.toDouble() ?? 0;
      left += (d['sizeLeft'] as num?)?.toDouble() ?? 0;
    }
    return size > 0 ? ((size - left) / size).clamp(0, 1) : null;
  }

  /// Season numbers (TV only, specials excluded).
  List<int> get seasonNumbers => ((raw['seasons'] as List?) ?? const []).map((s) => (s as Map)['seasonNumber'] as int).where((n) => n > 0).toList();

  /// Status per season, from Seerr's media info.
  Map<int, MediaStatus> get seasonStatus {
    final out = <int, MediaStatus>{};
    for (final s in (_info?['seasons'] as List?) ?? const []) {
      out[(s as Map)['seasonNumber'] as int] = MediaStatus.of(s['status'] as int?);
    }
    // Seasons someone already asked for count as requested.
    for (final r in (_info?['requests'] as List?) ?? const []) {
      if ((r as Map)['status'] == 3) continue; // declined
      for (final s in (r['seasons'] as List?) ?? const []) {
        out.putIfAbsent((s as Map)['seasonNumber'] as int, () => MediaStatus.pending);
      }
    }
    return out;
  }
}

/// One of the user's requests.
class SeerrRequest {
  final Map<String, dynamic> raw;
  SeerrMedia? details;
  SeerrRequest(this.raw);

  int get id => raw['id'] as int;

  /// 1 pending approval, 2 approved, 3 declined, 4 failed, 5 completed.
  int get requestStatus => raw['status'] as int;
  String get type => raw['type'] as String;
  DateTime? get createdAt => DateTime.tryParse((raw['createdAt'] as String?) ?? '');
  Map<String, dynamic> get _media => (raw['media'] as Map).cast<String, dynamic>();
  int get tmdbId => _media['tmdbId'] as int;
  MediaStatus get mediaStatus => MediaStatus.of(_media['status'] as int?);
  List<int> get seasons => ((raw['seasons'] as List?) ?? const []).map((s) => (s as Map)['seasonNumber'] as int).toList();

  double? get downloadProgress => SeerrMedia({'id': 0, 'mediaInfo': _media}).downloadProgress;

  String get statusLabel {
    if (requestStatus == 3) return 'Declined';
    if (requestStatus == 4) return 'Failed';
    if (mediaStatus == MediaStatus.available) return 'Available';
    if (downloadProgress != null) return 'Downloading';
    if (mediaStatus == MediaStatus.partial) return 'Partly available';
    if (requestStatus == 1) return 'Awaiting approval';
    return 'Requested';
  }
}

/// An actor or crew member, from TMDB via Seerr.
class SeerrPerson {
  final Map<String, dynamic> raw;
  SeerrPerson(this.raw);
  int get id => (raw['id'] as num).toInt();
  String get name => (raw['name'] as String?) ?? '';
  String get biography => (raw['biography'] as String?) ?? '';
  DateTime? get birthday => DateTime.tryParse((raw['birthday'] as String?) ?? '');
  DateTime? get deathday => DateTime.tryParse((raw['deathday'] as String?) ?? '');
  String? get placeOfBirth => raw['placeOfBirth'] as String?;
  String? get knownFor => raw['knownForDepartment'] as String?;
  String? get imdbId => raw['imdbId'] as String?;
  String? get profilePath => raw['profilePath'] as String?;
  List<String> get alsoKnownAs => ((raw['alsoKnownAs'] as List?) ?? const []).cast<String>();
}

/// One film or show in someone's filmography, with the part they played (or their job).
class SeerrCredit {
  final SeerrMedia media;
  final String? role;
  final int? episodes;
  SeerrCredit(this.media, this.role, this.episodes);
}

/// IMDb and Rotten Tomatoes scores, where Seerr has them.
class SeerrRatings {
  final double? imdb;
  final int? imdbVotes;
  final String? imdbUrl;
  final int? critics, audience;
  final String? criticsRating;
  const SeerrRatings({this.imdb, this.imdbVotes, this.imdbUrl, this.critics, this.audience, this.criticsRating});
  bool get isEmpty => imdb == null && critics == null && audience == null;
}

class SeerrGenre {
  final int id;
  final String name;
  SeerrGenre(this.id, this.name);
}

/// Seerr (Jellyseerr/Overseerr) over its API, signed in with the Jellyfin account.
class SeerrClient {
  final String server;
  String? cookie;
  final void Function(String? cookie)? onCookie;
  final http.Client _http = http.Client();

  SeerrClient(String server, {this.cookie, this.onCookie}) : server = server.trim().replaceAll(RegExp(r'/+$'), '');

  static String image(String? path, {String size = 'w342'}) => path == null ? '' : 'https://image.tmdb.org/t/p/$size$path';

  /// In a browser the session cookie is the browser's to keep: it may not be set or read
  /// here, and it goes along by itself because Seerr is on the page's own address (/seerr).
  Map<String, String> get _headers => {'Content-Type': 'application/json', 'Accept': 'application/json', if (!kIsWeb) 'Cookie': ?cookie};

  Future<dynamic> _send(String method, String path, {Map<String, Object?> query = const {}, Object? body}) async {
    // Seerr rejects '+' for spaces, so encode the query by hand.
    final q = query.entries.where((e) => e.value != null).map((e) => '${e.key}=${Uri.encodeComponent('${e.value}')}').join('&');
    final url = Uri.parse('$server/api/v1$path${q.isEmpty ? '' : '?$q'}');
    final req = http.Request(method, url)..headers.addAll(_headers);
    if (body != null) req.body = jsonEncode(body);
    final res = await http.Response.fromStream(await _http.send(req).timeout(const Duration(seconds: 20)));
    final set = res.headers['set-cookie'];
    if (set != null) {
      final m = RegExp(r'connect\.sid=[^;]+').firstMatch(set);
      if (m != null && m.group(0) != cookie) {
        cookie = m.group(0);
        onCookie?.call(cookie);
      }
    }
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw SeerrException(path.startsWith('/auth') ? 'Seerr did not accept the login' : 'Seerr session expired', res.statusCode);
    }
    if (res.statusCode >= 400) {
      String msg = 'Seerr error ${res.statusCode}';
      try {
        msg = (jsonDecode(res.body) as Map)['message'] as String? ?? msg;
      } catch (_) {}
      throw SeerrException(msg, res.statusCode);
    }
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<void> loginWithJellyfin(String username, String password) async {
    await _send('POST', '/auth/jellyfin', body: {'username': username, 'password': password});
    if (cookie == null && !kIsWeb) throw SeerrException('Seerr did not start a session');
  }

  /// Ends the Seerr session (the web version, where one browser holds one Seerr sign-in for
  /// every profile).
  Future<void> logout() async {
    try {
      await _send('POST', '/auth/logout');
    } catch (_) {}
  }

  Future<bool> check() async {
    if (cookie == null && !kIsWeb) return false;
    try {
      await _send('GET', '/auth/me');
      return true;
    } catch (_) {
      return false;
    }
  }

  List<SeerrMedia> _results(dynamic json) => ((json as Map)['results'] as List)
      .map((r) => SeerrMedia((r as Map).cast<String, dynamic>()))
      .where((m) => m.raw['mediaType'] == null || m.raw['mediaType'] == 'movie' || m.raw['mediaType'] == 'tv')
      .toList();

  Future<List<SeerrMedia>> trending({int page = 1}) async => _results(await _send('GET', '/discover/trending', query: {'page': page}));
  Future<List<SeerrMedia>> popularMovies({int page = 1, int? genre}) async =>
      _results(await _send('GET', '/discover/movies', query: {'page': page, 'genre': genre}));
  Future<List<SeerrMedia>> popularTv({int page = 1, int? genre}) async => _results(await _send('GET', '/discover/tv', query: {'page': page, 'genre': genre}));
  Future<List<SeerrMedia>> upcomingMovies({int page = 1}) async => _results(await _send('GET', '/discover/movies/upcoming', query: {'page': page}));
  Future<List<SeerrMedia>> upcomingTv({int page = 1}) async => _results(await _send('GET', '/discover/tv/upcoming', query: {'page': page}));
  Future<List<SeerrMedia>> search(String query, {int page = 1}) async => _results(await _send('GET', '/search', query: {'query': query, 'page': page}));

  Future<List<SeerrMedia>> recommendations(String type, int tmdbId) async =>
      _results(await _send('GET', '/$type/$tmdbId/recommendations')).map((m) => SeerrMedia({...m.raw, 'mediaType': type})).toList();

  Future<List<SeerrGenre>> genres(String type) async =>
      ((await _send('GET', '/genres/$type')) as List).map((g) => SeerrGenre(g['id'] as int, g['name'] as String)).toList();

  Future<SeerrMedia> details(String type, int tmdbId) async =>
      SeerrMedia({...((await _send('GET', '/$type/$tmdbId')) as Map).cast<String, dynamic>(), 'mediaType': type});

  Future<SeerrPerson> person(int tmdbId) async => SeerrPerson(((await _send('GET', '/person/$tmdbId')) as Map).cast<String, dynamic>());

  /// Acting credits first (most-voted first), then directing/writing/producing.
  Future<List<SeerrCredit>> personCredits(int tmdbId) async {
    final json = (await _send('GET', '/person/$tmdbId/combined_credits')) as Map;
    SeerrCredit credit(Map m, String? role) => SeerrCredit(SeerrMedia(m.cast<String, dynamic>()), role, m['episodeCount'] as int?);
    final seen = <String>{};
    final out = <SeerrCredit>[];
    for (final c in (json['cast'] as List? ?? const [])) {
      final m = c as Map;
      if (m['mediaType'] != 'movie' && m['mediaType'] != 'tv') continue;
      // Talk shows and award ceremonies list people as "Self"; they are noise here.
      final role = m['character'] as String?;
      if (role != null && RegExp(r'^(self|himself|herself|themselves)\b', caseSensitive: false).hasMatch(role)) continue;
      if (seen.add('${m['mediaType']}${m['id']}')) out.add(credit(m, role));
    }
    for (final c in (json['crew'] as List? ?? const [])) {
      final m = c as Map;
      if (m['mediaType'] != 'movie' && m['mediaType'] != 'tv') continue;
      if (!const {'Director', 'Screenplay', 'Writer', 'Creator', 'Producer', 'Executive Producer'}.contains(m['job'])) continue;
      if (seen.add('${m['mediaType']}${m['id']}')) out.add(credit(m, m['job'] as String?));
    }
    return out;
  }

  Future<SeerrRatings> ratings(String type, int tmdbId) async {
    try {
      if (type == 'movie') {
        final j = (await _send('GET', '/movie/$tmdbId/ratingscombined')) as Map;
        final rt = j['rt'] as Map?, imdb = j['imdb'] as Map?;
        return SeerrRatings(
          imdb: (imdb?['criticsScore'] as num?)?.toDouble(),
          imdbVotes: imdb?['criticsScoreCount'] as int?,
          imdbUrl: imdb?['url'] as String?,
          critics: rt?['criticsScore'] as int?,
          audience: rt?['audienceScore'] as int?,
          criticsRating: rt?['criticsRating'] as String?,
        );
      }
      final rt = (await _send('GET', '/tv/$tmdbId/ratings')) as Map;
      return SeerrRatings(critics: rt['criticsScore'] as int?, audience: rt['audienceScore'] as int?, criticsRating: rt['criticsRating'] as String?);
    } catch (_) {
      return const SeerrRatings();
    }
  }

  Future<int> myId() async => ((await _send('GET', '/auth/me')) as Map)['id'] as int;

  Future<List<SeerrRequest>> myRequests({int take = 40}) async {
    final me = await myId();
    final json = await _send('GET', '/request', query: {'take': take, 'skip': 0, 'sort': 'added', 'requestedBy': me, 'filter': 'all'});
    return ((json as Map)['results'] as List).map((r) => SeerrRequest((r as Map).cast<String, dynamic>())).toList();
  }

  /// Ask for a movie, or for the given seasons of a show.
  /// True when it went straight through; false when it waits for an admin's approval
  /// (accounts without auto-approve, like the family's).
  Future<bool> request(SeerrMedia media, {List<int>? seasons}) async {
    final r = await _send(
      'POST',
      '/request',
      body: {'mediaType': media.mediaType, 'mediaId': media.tmdbId, if (media.isTv) 'seasons': seasons ?? media.seasonNumbers},
    );
    return !(r is Map && r['status'] == 1);
  }
}
