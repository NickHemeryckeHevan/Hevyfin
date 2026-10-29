// The TV's "on the clock" shows: cinema screenings, private viewings, marathons and the
// three channels. Everything is a [Timeline]: a start time and a list of steps with known
// lengths, so the player can work out what's on at any moment and join halfway through.
import 'dart:math';

/// What a step shows.
enum StepKind {
  /// A trailer from the hidden Cinema library (Cinema/Trailers/).
  clip,

  /// An ident or card drawn by the app ([Step.bumper] names which).
  bumper,

  /// The 15-second "feature presentation" intro before a movie (cast and countdown).
  countdown,

  /// (Part of) a movie or episode, from [Step.from] for [Step.dur].
  program,

  /// The cinema's 10-minute break halfway through the movie.
  intermission,

  /// A marathon's break between two movies.
  pause,
}

class Step {
  final StepKind kind;
  final Duration dur;

  /// Clip or program: the Jellyfin item to play.
  final String? itemId;

  /// Where in the item this step begins (the second half of a movie starts at its middle).
  final Duration from;

  /// What the banner and guide show, e.g. "Shrek 2" / "S1:E3 · The Storm".
  final String title;
  final String sub;

  /// Item whose backdrop/poster represents it (the series for an episode).
  final String? artId;

  /// Bumper kind, or "trailer" for a clip.
  final String? tag;

  const Step(this.kind, this.dur, {this.itemId, this.from = Duration.zero, this.title = '', this.sub = '', this.artId, this.tag});

  bool get isVideo => kind == StepKind.clip || kind == StepKind.program;
  bool get isTrailer => kind == StepKind.clip && tag == 'trailer';

  Map<String, Object?> toJson() => {
    'k': kind.index,
    'd': dur.inMilliseconds,
    if (itemId != null) 'i': itemId,
    if (from != Duration.zero) 'f': from.inMilliseconds,
    if (title.isNotEmpty) 't': title,
    if (sub.isNotEmpty) 's': sub,
    if (artId != null) 'a': artId,
    if (tag != null) 'g': tag,
  };

  factory Step.fromJson(Map<String, dynamic> j) => Step(
    StepKind.values[j['k'] as int],
    Duration(milliseconds: j['d'] as int),
    itemId: j['i'] as String?,
    from: Duration(milliseconds: (j['f'] as int?) ?? 0),
    title: (j['t'] as String?) ?? '',
    sub: (j['s'] as String?) ?? '',
    artId: j['a'] as String?,
    tag: j['g'] as String?,
  );
}

/// Where a timeline is at a given moment.
class Position {
  final int index;
  final Duration offset;
  const Position(this.index, this.offset);
}

/// One listing in a guide: a movie or episode with its air time (breaks included in the
/// slot before it, the way TV listings round them).
class Listing {
  final String title, sub;
  final String? itemId, artId;
  final DateTime start, end;
  const Listing(this.title, this.sub, this.itemId, this.artId, this.start, this.end);
}

class Timeline {
  final String id;
  final String title;
  DateTime start;
  final List<Step> steps;
  Timeline(this.id, this.title, this.start, this.steps);

  Duration get length => steps.fold(Duration.zero, (a, s) => a + s.dur);
  DateTime get end => start.add(length);

  /// The step playing at [now]; null before the start or after the end.
  Position? at(DateTime now) {
    var t = now.difference(start);
    if (t.isNegative) return null;
    for (var i = 0; i < steps.length; i++) {
      if (t < steps[i].dur) return Position(i, t);
      t -= steps[i].dur;
    }
    return null;
  }

  /// When step [i] begins.
  DateTime startOf(int i) => start.add(steps.take(i).fold(Duration.zero, (a, s) => a + s.dur));

  /// Programs as a guide lists them: the two halves of a movie are one listing.
  List<Listing> listings() {
    final out = <Listing>[];
    var t = start;
    for (final s in steps) {
      final end = t.add(s.dur);
      if (s.kind == StepKind.program) {
        final last = out.lastOrNull;
        if (last != null && last.itemId == s.itemId) {
          out[out.length - 1] = Listing(last.title, last.sub, last.itemId, last.artId, last.start, end);
        } else {
          out.add(Listing(s.title, s.sub, s.itemId, s.artId, t, end));
        }
      }
      t = end;
    }
    return out;
  }

  /// The program on at [now] (during a break: the one coming up).
  Listing? listingAt(DateTime now) {
    final all = listings();
    for (final l in all) {
      if (now.isBefore(l.end)) return l;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'steps': [for (final s in steps) s.toJson()],
  };

  factory Timeline.fromJson(Map<String, dynamic> j) => Timeline(
    j['id'] as String,
    (j['title'] as String?) ?? '',
    DateTime.fromMillisecondsSinceEpoch(j['start'] as int),
    [for (final s in j['steps'] as List) Step.fromJson((s as Map).cast<String, dynamic>())],
  );
}

// ---------------------------------------------------------------------------------------
// What there is to schedule.

/// A movie or episode the schedulers can pick.
class Title {
  final String id;
  final String name;
  final Duration runtime;
  final int? critic;
  final double? community;
  final int age;
  final bool animated;
  final bool played;

  /// Movies: their genres (for themed nights).
  final List<String> genres;

  /// Episodes: their series, season/episode code and the series' name.
  final String? seriesId;
  final String? code;
  final String? seriesName;
  const Title({
    required this.id,
    required this.name,
    required this.runtime,
    this.critic,
    this.community,
    this.age = 12,
    this.animated = false,
    this.played = false,
    this.genres = const [],
    this.seriesId,
    this.code,
    this.seriesName,
  });

  /// Bad enough for the channels' late movie.
  bool get poorlyRated => critic != null ? critic! < 60 : (community ?? 10) < 6.5;

  /// Good enough to play twice in one day.
  bool get acclaimed => critic != null ? critic! >= 80 : (community ?? 0) >= 7.5;
  String get key => seriesId ?? id;

  Step program({Duration from = Duration.zero, Duration? to}) => Step(
    StepKind.program,
    (to ?? runtime) - from,
    itemId: id,
    from: from,
    title: seriesName ?? name,
    sub: seriesName == null ? '' : '$code · $name',
    artId: seriesId ?? id,
  );
}

class Series {
  final String id;
  final String name;
  final int age;
  final bool animated;
  final List<Title> episodes;

  /// On LOL TV's line-up (tagged "lol-tv" on the server): airs there and nowhere else.
  final bool sitcom;
  const Series(this.id, this.name, this.age, this.animated, this.episodes, {this.sitcom = false});
}

class Clip {
  final String id;
  final String name;
  final Duration dur;

  /// Always "trailer" (a movie now in cinemas): Hevyfin plays no ads.
  final String source;
  const Clip(this.id, this.name, this.dur, [this.source = 'trailer']);

  Step get step => Step(StepKind.clip, dur, itemId: id, title: name, tag: source, artId: id);
}

class Pool {
  final List<Title> movies;
  final List<Series> series;
  final List<Clip> clips;
  const Pool(this.movies, this.series, this.clips);

  List<Clip> get trailers => clips.where((c) => c.source == 'trailer').toList();
}

/// Age from a US or Belgian rating ("TV-MA", "PG-13", "BE-16" …).
int ageOf(String? rating) {
  if (rating == null || rating.isEmpty) return 12;
  final r = rating.toUpperCase().replaceAll(' ', '');
  const named = {
    'G': 0, 'TV-G': 0, 'TV-Y': 0, 'BE-AL': 0, 'AL': 0, 'KT': 0, //
    'TV-Y7': 7, 'TV-Y7-FV': 7, 'PG': 8, 'TV-PG': 8,
    'PG-13': 13, 'TV-14': 14, 'R': 17, 'TV-MA': 17, 'NC-17': 18, 'NR': 12, 'UNRATED': 12,
  };
  if (named.containsKey(r)) return named[r]!;
  final n = RegExp(r'(\d+)').firstMatch(r);
  return n == null ? 12 : int.parse(n.group(1)!);
}

// ---------------------------------------------------------------------------------------
// Building shows.

const _bumpers = {'ident': 8, 'phone': 8, 'feature': 7, 'theme': 8};

/// Themed evenings. On its weekday a theme picks the last screening, and every showing of
/// a film that fits one (any day, at home too) gets the theme's bumper in its pre-show.
class CinemaTheme {
  final String key, night, day, tagline;
  final int weekday;
  final List<String> genres;
  const CinemaTheme(this.key, this.night, this.day, this.weekday, this.genres, this.tagline);

  bool fits(Title m) => m.genres.any(genres.contains);
}

const cinemaThemes = [
  CinemaTheme('horror', 'Horror Night', 'Horror Friday', DateTime.friday, ['Horror'], 'Lights off. Doors locked.'),
  CinemaTheme('family', 'Family Night', 'Family Saturday', DateTime.saturday, ['Animation', 'Family'], 'Popcorn for everyone.'),
  CinemaTheme('scifi', 'Sci-Fi Night', 'Sci-Fi Sunday', DateTime.sunday, ['Science Fiction', 'Sci-Fi'], 'Somewhere out there.'),
  CinemaTheme('comedy', 'Comedy Night', 'Comedy Wednesday', DateTime.wednesday, ['Comedy'], 'Laugh it off.'),
  CinemaTheme('action', 'Action Night', 'Action Thursday', DateTime.thursday, ['Action'], 'Buckle up.'),
];

/// The theme [m] belongs to on [day]: that weekday's own theme first, then any it fits.
CinemaTheme? themeFor(Title m, DateTime day) =>
    cinemaThemes.where((t) => t.weekday == day.weekday && t.fits(m)).firstOrNull ?? cinemaThemes.where((t) => t.fits(m)).firstOrNull;

/// The theme bumper: "Horror Friday" on Friday, "Horror Night" otherwise.
Step themeBumper(CinemaTheme t, DateTime day) => bumper('theme', title: t.weekday == day.weekday ? t.day : t.night, sub: t.tagline);

Step bumper(String kind, {Duration? dur, String title = '', String sub = ''}) => Step(
  StepKind.bumper,
  dur ?? Duration(seconds: _bumpers[kind] ?? 6),
  tag: kind,
  title: title,
  sub: sub,
);

/// The 15-second "feature presentation" intro right before a movie.
const countdown = Step(StepKind.countdown, Duration(seconds: 15));
const intermissionLength = Duration(minutes: 10);

/// The cinema pre-show: "Hevyfin presents", the evening's theme, up to five trailers,
/// "phones on silent", then the feature intro (poster, cast, countdown). No ads. Without
/// trailers it goes straight from the ident to the phone card and the countdown.
List<Step> preshow(Random rng, Pool pool, {Step? theme}) {
  final trailers = (pool.trailers..shuffle(rng)).take(5);
  return [bumper('ident'), ?theme, for (final c in trailers) c.step, bumper('phone'), countdown];
}

/// A movie with an intermission (10 minutes unless said otherwise) at its middle.
List<Step> withIntermission(Title m, [Duration length = intermissionLength]) {
  final half = Duration(seconds: m.runtime.inSeconds ~/ 2);
  return [m.program(to: half), Step(StepKind.intermission, length, title: m.name, artId: m.id), m.program(from: half)];
}

/// A private showing of [m] starting now.
Timeline privateShow(Title m, Pool pool, DateTime now, {Random? rng}) {
  final theme = themeFor(m, now);
  return Timeline('private-${m.id}', m.name, now, [
    ...preshow(rng ?? Random(), pool, theme: theme == null ? null : themeBumper(theme, now)),
    ...withIntermission(m),
  ]);
}

String dayKey(DateTime d) => '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
int _seed(String s) => s.codeUnits.fold(7, (h, c) => (h * 31 + c) & 0x3fffffff);

T _weighted<T>(Random rng, List<T> items, double Function(T) weight) {
  final w = [for (final i in items) max(weight(i), .001)];
  var r = rng.nextDouble() * w.reduce((a, b) => a + b);
  for (var i = 0; i < items.length; i++) {
    r -= w[i];
    if (r <= 0) return items[i];
  }
  return items.last;
}

/// The day's three cinema screenings. Better-reviewed movies come up more often, and
/// only acclaimed ones may play twice in a day.
List<Timeline> screenings(DateTime day, Pool pool) {
  final rng = Random(_seed('screen${dayKey(day)}'));
  const windows = [(13 * 60, 16 * 60 + 30), (17 * 60 + 30, 20 * 60), (20 * 60 + 30, 22 * 60 + 30)];
  final shown = <String, int>{};
  final out = <Timeline>[];
  final movies = pool.movies.where((m) => m.runtime > const Duration(minutes: 40)).toList();
  if (movies.isEmpty) return out;
  for (final (i, (from, to)) in windows.indexed) {
    final minute = from + rng.nextInt((to - from) ~/ 5 + 1) * 5;
    final start = DateTime(day.year, day.month, day.day).add(Duration(minutes: minute));
    var ok = movies.where((m) => (shown[m.id] ?? 0) < (m.acclaimed ? 2 : 1)).toList();
    // The evening screening follows the day's theme, when the library has something for it.
    final tonight = cinemaThemes.where((t) => t.weekday == day.weekday).firstOrNull;
    if (i == windows.length - 1 && tonight != null && ok.any(tonight.fits)) ok = ok.where(tonight.fits).toList();
    final m = _weighted(rng, ok.isEmpty ? movies : ok, (m) => 1 + (m.critic ?? ((m.community ?? 6) * 10)) / 25 + (m.played ? 0 : 1));
    shown[m.id] = (shown[m.id] ?? 0) + 1;
    final theme = themeFor(m, day);
    out.add(
      Timeline('screen-${dayKey(day)}-$i', m.name, start, [
        ...preshow(Random(_seed('pre${dayKey(day)}$i')), pool, theme: theme == null ? null : themeBumper(theme, day)),
        ...withIntermission(m),
      ]),
    );
  }
  return out;
}

/// A planned marathon: one pre-show, then the movies. Each movie can have its own
/// intermission halfway ([intermissions], minutes, 0 = none) and a break after it
/// ([breakMinutes], 0 = straight on).
Timeline marathonShow(String id, String name, DateTime start, List<Title> movies, List<int> breakMinutes, Pool pool, {List<int> intermissions = const []}) {
  final steps = <Step>[...preshow(Random(_seed('marathon$id')), pool)..removeLast()];
  for (final (i, m) in movies.indexed) {
    final inter = i < intermissions.length ? intermissions[i] : 0;
    steps
      ..add(countdown)
      ..addAll(inter > 0 ? withIntermission(m, Duration(minutes: inter)) : [m.program()]);
    if (i < movies.length - 1) {
      final mins = i < breakMinutes.length ? breakMinutes[i] : 0;
      final next = movies[i + 1];
      if (mins > 0) {
        steps.add(Step(StepKind.pause, Duration(minutes: mins), title: next.name, artId: next.id, itemId: next.id));
      }
    }
  }
  return Timeline('marathon-$id', name, start, steps);
}

// ---------------------------------------------------------------------------------------
// The channels.

class Channel {
  final int number;
  final String name;

  /// Share of movies (the rest is episodes).
  final double movies;

  /// Sitcoms only, back to back, no movies (LOL TV).
  final bool sitcoms;
  const Channel(this.number, this.name, this.movies, {this.sitcoms = false});

  /// Channel 3 is a cartoon channel by day and After Hours (grown-up cartoons) at night.
  bool get split => number == 3;
  static bool isNight(DateTime t) => t.hour >= 20 || t.hour < 8;
  String nameAt(DateTime t) => split ? (isNight(t) ? 'After Hours' : 'Cartoons') : name;
}

/// How often a channel shows its one late movie on an evening.
const movieChance = .3;

const channels = [Channel(1, 'Movie Night', .6), Channel(2, 'Hevyfin Mix', .3), Channel(3, 'Cartoons', .4), Channel(4, 'LOL TV', 0, sitcoms: true)];

/// Channel days run 06:00 to 06:00 like a broadcaster's.
DateTime channelDay(DateTime now) {
  return DateTime(now.year, now.month, now.day - (now.hour < 6 ? 1 : 0), 6);
}

/// Next episode to air per channel and series (`1|seriesId` → index), carried from day to day.
typedef Cursors = Map<String, int>;

/// Builds one channel day for every channel: random episodes of every series mixed
/// together, with now and then a badly rated movie between 20:00 and midnight. Sitcoms
/// belong to LOL TV, which plays nothing else, often two or three episodes back to back.
/// ([cursors] is kept for saved state but no longer used: episodes are random.)
List<Timeline> channelDays(DateTime day, Pool pool, Cursors cursors) {
  final start = DateTime(day.year, day.month, day.day, 6);
  final end = DateTime(day.year, day.month, day.day + 1, 6);
  final busy = <(String, DateTime, DateTime)>[]; // what's on where, so channels never overlap
  final usedMovies = <String>{};
  final out = <Timeline>[];
  for (final ch in channels) {
    final rng = Random(_seed('ch${ch.number}${dayKey(day)}'));
    final shows = pool.series.where((s) => s.sitcom == ch.sitcoms).toList();
    final steps = <Step>[];
    var t = start;
    var lastKey = '';

    bool free(String key, DateTime from, DateTime to) => !busy.any((b) => b.$1 == key && b.$2.isBefore(to) && from.isBefore(b.$3));

    void add(Step s) {
      steps.add(s);
      t = t.add(s.dur);
    }

    // A break between programs (no ads): the channel's ident, now and then a trailer, and
    // an "up next" card so the next program starts on a 5-minute mark.
    void adBreak({bool short = false}) {
      add(bumper('ch${ch.number}${ch.split && Channel.isNight(t) ? 'n' : ''}', dur: const Duration(seconds: 5)));
      final trailers = pool.trailers;
      if (!short && trailers.isNotEmpty && rng.nextInt(3) == 0) add(trailers[rng.nextInt(trailers.length)].step);
      // Round up to the next 5 minutes with an "up next" card.
      final into = t.difference(start).inSeconds % 300;
      final pad = into == 0 ? 0 : 300 - into;
      if (pad > 0) add(bumper('next', dur: Duration(seconds: pad)));
    }

    bool fits(Title x, DateTime at) {
      if (!ch.split) return true;
      if (Channel.isNight(at)) {
        // After hours anything goes, edgy first, but it must be over before the cartoons start at 08:00.
        if (x.age < 14) return false;
        final morning = DateTime(at.year, at.month, at.day + (at.hour >= 20 ? 1 : 0), 8);
        return !at.add(x.runtime).isAfter(morning);
      }
      return x.animated && x.age <= 12;
    }

    final usedEps = <String>{};
    var triedMovie = ch.sitcoms; // LOL TV shows no movies
    var run = 0; // episodes of [lastKey] in a row
    Title? lastEp;
    while (t.isBefore(end)) {
      // Movies are rare: badly rated ones only, at most one an evening, between 20:00 and midnight.
      final midnight = DateTime(t.year, t.month, t.day + 1);
      if (t.hour >= 20 && !triedMovie) {
        triedMovie = true;
        if (rng.nextDouble() < movieChance) {
          final ok = pool.movies
              .where(
                (m) =>
                    m.poorlyRated &&
                    fits(m, t) &&
                    !t.add(m.runtime + const Duration(minutes: 9)).isAfter(midnight) &&
                    free(m.id, t, t.add(m.runtime + const Duration(minutes: 9))),
              )
              .where((m) => !usedMovies.contains(m.id))
              .toList();
          if (ok.isNotEmpty) {
            final m = ok[rng.nextInt(ok.length)];
            usedMovies.add(m.id);
            lastKey = m.id;
            final from = t;
            if (m.runtime > const Duration(minutes: 90)) {
              final half = Duration(minutes: m.runtime.inMinutes ~/ 2);
              add(m.program(to: half));
              adBreak(short: true);
              add(m.program(from: half));
            } else {
              add(m.program());
            }
            busy.add((m.id, from, t));
            run = 0;
            lastEp = null;
            adBreak();
            continue;
          }
        }
      }
      // Now and then a second episode of the same show (the next one), never a third.
      // LOL TV runs them back to back more often, up to three.
      final prev = lastEp;
      if (prev != null && (ch.sitcoms ? run < 3 && rng.nextDouble() < .55 : run == 1 && rng.nextDouble() < .25)) {
        final sr = shows.where((x) => x.id == prev.seriesId).firstOrNull;
        final i = sr?.episodes.indexWhere((e) => e.id == prev.id) ?? -1;
        final next = sr != null && i >= 0 && i + 1 < sr.episodes.length ? sr.episodes[i + 1] : null;
        if (next != null && fits(next, t) && free(sr!.id, t, t.add(next.runtime + const Duration(minutes: 1)))) {
          usedEps.add(next.id);
          final from = t;
          add(next.program());
          busy.add((sr.id, from, t));
          run++;
          lastEp = next;
          adBreak();
          continue;
        }
      }
      // Otherwise: a random episode of any series, all mixed through each other.
      final series = shows.where((s) {
        // A channel with one show (LOL TV, for now) may follow it with itself.
        if ((s.id == lastKey && shows.length > 1) || s.episodes.isEmpty) return false;
        final probe = Title(id: s.id, name: s.name, runtime: s.episodes.first.runtime, age: s.age, animated: s.animated);
        return fits(probe, t) && free(s.id, t, t.add(s.episodes.first.runtime + const Duration(minutes: 1)));
      }).toList();
      if (series.isEmpty) {
        // Nothing fits right now (e.g. late night with nothing short enough): a break.
        adBreak();
        continue;
      }
      final sr = series[rng.nextInt(series.length)];
      final fitting = sr.episodes.where((e) => fits(e, t) && free(sr.id, t, t.add(e.runtime + const Duration(minutes: 1)))).toList();
      final fresh = fitting.where((e) => !usedEps.contains(e.id)).toList();
      if (fitting.isEmpty) {
        adBreak();
        continue;
      }
      // Today's unseen episodes first; a small show may repeat late in the day.
      final ep = fresh.isNotEmpty ? fresh[rng.nextInt(fresh.length)] : fitting[rng.nextInt(fitting.length)];
      usedEps.add(ep.id);
      lastKey = sr.id;
      run = 1;
      lastEp = ep;
      final from = t;
      add(ep.program());
      busy.add((sr.id, from, t));
      adBreak();
    }
    out.add(Timeline('ch${ch.number}-${dayKey(day)}', ch.name, start, steps));
  }
  return out;
}
