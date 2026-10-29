import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/state/live.dart';

Pool fakePool() {
  final rng = Random(1);
  final movies = [
    for (var i = 0; i < 40; i++)
      Title(
        id: 'm$i',
        name: 'Movie $i',
        runtime: Duration(minutes: 85 + rng.nextInt(70)),
        critic: i % 3 == 0 ? 90 : (i % 3 == 1 ? 70 : 40),
        age: [0, 8, 12, 13, 16, 17][i % 6],
        animated: i % 4 == 0,
        genres: i % 5 == 0 ? const ['Horror', 'Thriller'] : const ['Drama'],
      ),
  ];
  final series = [
    for (var s = 0; s < 10; s++)
      Series('s$s', 'Show $s', [7, 14, 17][s % 3], s % 3 == 0, sitcom: s == 2 || s == 4, [
        for (var e = 0; e < 12; e++)
          Title(id: 's$s-e$e', name: 'Ep $e', runtime: Duration(minutes: s.isEven ? 22 : 45), seriesId: 's$s', seriesName: 'Show $s', code: 'S1:E${e + 1}', age: [7, 14, 17][s % 3], animated: s % 3 == 0),
      ]),
  ];
  final clips = [
    for (var i = 0; i < 8; i++) Clip('t$i', 'Trailer $i', const Duration(seconds: 150)),
  ];
  return Pool(movies, series, clips);
}

void main() {
  final pool = fakePool();
  final day = DateTime(2026, 10, 16);

  test('themed nights: Friday evening is horror, with the theme bumper', () {
    for (var w = 0; w < 6; w++) {
      final friday = DateTime(2026, 10, 16 + 7 * w);
      expect(friday.weekday, DateTime.friday);
      final evening = screenings(friday, pool).last;
      final film = pool.movies.firstWhere((m) => m.name == evening.title);
      expect(film.genres, contains('Horror'));
      final theme = evening.steps.where((s) => s.tag == 'theme').single;
      expect(theme.title, 'Horror Friday');
    }
  });

  test('themed nights: a horror film at home on a Tuesday is a Horror Night; a drama has no theme', () {
    final tuesday = DateTime(2026, 10, 20);
    final horror = pool.movies.firstWhere((m) => m.genres.contains('Horror'));
    final drama = pool.movies.firstWhere((m) => !m.genres.contains('Horror'));
    expect(privateShow(horror, pool, tuesday).steps.where((s) => s.tag == 'theme').single.title, 'Horror Night');
    expect(privateShow(drama, pool, tuesday).steps.where((s) => s.tag == 'theme'), isEmpty);
    // The theme comes straight after the ident.
    expect(privateShow(horror, pool, tuesday).steps.take(2).map((s) => s.tag), ['ident', 'theme']);
  });

  test('screenings: three a day in their windows, same every time', () {
    final a = screenings(day, pool), b = screenings(day, pool);
    expect(a.length, 3);
    expect([for (final t in a) t.start], [for (final t in b) t.start]);
    const windows = [(13 * 60, 16 * 60 + 30), (17 * 60 + 30, 20 * 60), (20 * 60 + 30, 22 * 60 + 30)];
    for (final (i, t) in a.indexed) {
      final m = t.start.hour * 60 + t.start.minute;
      expect(m, inInclusiveRange(windows[i].$1, windows[i].$2));
      expect(m % 5, 0);
    }
  });

  test('screenings: a movie plays at most twice, and twice only if acclaimed', () {
    for (var d = 0; d < 200; d++) {
      final list = screenings(day.add(Duration(days: d)), pool);
      final counts = <String, int>{};
      for (final t in list) {
        final id = t.steps.firstWhere((s) => s.kind == StepKind.program).itemId!;
        counts[id] = (counts[id] ?? 0) + 1;
      }
      for (final e in counts.entries) {
        final m = pool.movies.firstWhere((m) => m.id == e.key);
        expect(e.value, lessThanOrEqualTo(m.acclaimed ? 2 : 1));
      }
    }
  });

  test('pre-show without trailers: straight from the ident to the phone card and the countdown', () {
    final bare = Pool(pool.movies, pool.series, const []);
    final pre = preshow(Random(1), bare);
    expect([for (final s in pre) s.kind == StepKind.countdown ? 'countdown' : s.tag], ['ident', 'phone', 'countdown']);
    final themed = preshow(Random(1), bare, theme: bumper('theme', title: 'Horror Night'));
    expect([for (final s in themed) s.kind == StepKind.countdown ? 'countdown' : s.tag], ['ident', 'theme', 'phone', 'countdown']);
  });

  test('channel breaks: only idents, trailers and "up next" cards, never an ad', () {
    for (final pl in [pool, Pool(pool.movies, pool.series, const [])]) {
      for (final ch in channelDays(day, pl, {})) {
        for (final s in ch.steps) {
          if (s.kind == StepKind.clip) expect(s.isTrailer, isTrue);
          if (s.kind == StepKind.bumper) expect(s.tag == 'next' || s.tag == 'theme' || s.tag == 'feature' || s.tag!.startsWith('ch'), isTrue, reason: s.tag);
        }
      }
    }
  });

  test('pre-show: ident, five trailers, phone, countdown, intermission halfway; no ads', () {
    final t = screenings(day, pool).first;
    final pre = t.steps.takeWhile((s) => s.kind != StepKind.program).toList();
    expect(pre.first.tag, 'ident');
    expect(pre.where((s) => s.isTrailer).length, 5);
    expect(pre.where((s) => s.kind == StepKind.clip).every((s) => s.isTrailer), isTrue);
    expect(pre.where((s) => s.kind == StepKind.bumper).map((s) => s.tag).toSet().difference({'ident', 'theme', 'phone'}), isEmpty);
    expect(pre[pre.length - 2].tag, 'phone');
    expect(pre.last.kind, StepKind.countdown);
    final progs = t.steps.where((s) => s.kind == StepKind.program).toList();
    expect(progs.length, 2);
    expect(progs[1].from, progs[0].dur);
    final ii = t.steps.indexWhere((s) => s.kind == StepKind.intermission);
    expect(t.steps[ii - 1].kind, StepKind.program);
    expect(t.steps[ii].dur, intermissionLength);
  });

  test('timeline: joining late lands on the right step', () {
    final t = Timeline('x', 'x', DateTime(2026, 1, 1, 20), const [
      Step(StepKind.bumper, Duration(seconds: 10)),
      Step(StepKind.clip, Duration(seconds: 30), itemId: 'a'),
      Step(StepKind.program, Duration(minutes: 60), itemId: 'm'),
      Step(StepKind.intermission, Duration(minutes: 10)),
      Step(StepKind.program, Duration(minutes: 60), itemId: 'm', from: Duration(minutes: 60)),
    ]);
    expect(t.at(DateTime(2026, 1, 1, 19, 59)), isNull);
    expect(t.at(DateTime(2026, 1, 1, 20, 0, 5))!.index, 0);
    final ad = t.at(DateTime(2026, 1, 1, 20, 0, 25))!;
    expect((ad.index, ad.offset), (1, const Duration(seconds: 15)));
    final mid = t.at(DateTime(2026, 1, 1, 20, 30, 40))!;
    expect((mid.index, mid.offset), (2, const Duration(minutes: 30)));
    expect(t.at(DateTime(2026, 1, 1, 21, 5, 40))!.index, 3);
    final second = t.at(DateTime(2026, 1, 1, 21, 20, 40))!;
    expect((second.index, second.offset), (4, const Duration(minutes: 10)));
    expect(t.at(DateTime(2026, 1, 1, 23)), isNull);
    expect(t.listings().length, 1);
  });

  test('channels: cover the day, follow channel 3 rules, never clash, episodes in order', () {
    final cursors = <String, int>{};
    final days = channelDays(day, pool, cursors);
    expect(days.length, 4);
    final start = DateTime(2026, 10, 16, 6);
    for (final t in days) {
      expect(t.start, start);
      expect(t.end.isBefore(start.add(const Duration(days: 1))), isFalse);
      // Every program begins on a 5-minute mark.
      for (final l in t.listings()) {
        expect(l.start.difference(start).inSeconds % 300, 0, reason: '${t.title} ${l.title} at ${l.start}');
      }
    }
    // Channel 3: cartoons for kids by day, 14+ at night.
    final ch3 = days[2];
    final byId = {for (final m in pool.movies) m.id: m, for (final s in pool.series) for (final e in s.episodes) e.id: e};
    var tt = ch3.start;
    for (final s in ch3.steps) {
      if (s.kind == StepKind.program && s.from == Duration.zero) {
        final x = byId[s.itemId]!;
        if (Channel.isNight(tt)) {
          expect(x.age, greaterThanOrEqualTo(14), reason: '${x.name} at $tt');
        } else {
          expect(x.animated && x.age <= 12, isTrue, reason: '${x.name} at $tt');
        }
      }
      tt = tt.add(s.dur);
    }
    // The same title is never on two channels at once.
    final spans = [
      for (final (c, t) in days.indexed)
        for (final l in t.listings()) (c, byId[l.itemId]!.key, l.start, l.end),
    ];
    for (final a in spans) {
      for (final b in spans) {
        if (a.$1 != b.$1 && a.$2 == b.$2) expect(a.$3.isBefore(b.$4) && b.$3.isBefore(a.$4), isFalse, reason: '${a.$2} on ${a.$1 + 1} and ${b.$1 + 1}');
      }
    }
    // Movies only between 20:00 and midnight, badly rated, at most one per channel a day.
    for (final t in days) {
      final movies = t.listings().where((l) => pool.movies.any((m) => m.id == l.itemId)).toList();
      expect(movies.length, lessThanOrEqualTo(1));
      for (final l in movies) {
        final m = pool.movies.firstWhere((m) => m.id == l.itemId);
        expect(m.poorlyRated, isTrue, reason: m.name);
        expect(l.start.hour, greaterThanOrEqualTo(20));
        expect(l.end.isAfter(DateTime(2026, 10, 17)), isFalse, reason: '${m.name} ends ${l.end}');
      }
    }
    // Episodes come from all over: many different series in a day, mixed through each other.
    for (final t in days.take(2)) {
      final keys = [for (final l in t.listings()) byId[l.itemId]!.key];
      expect(keys.toSet().length, greaterThan(4));
      // Never three episodes of the same show after each other.
      for (var i = 2; i < keys.length; i++) {
        expect(keys[i] == keys[i - 1] && keys[i] == keys[i - 2], isFalse, reason: 'three of ${keys[i]} in a row');
      }
    }
  });

  test('LOL TV: sitcoms only, all day, no movies; other channels have none', () {
    final days = channelDays(day, pool, {});
    final sitcoms = {for (final s in pool.series.where((s) => s.sitcom)) for (final e in s.episodes) e.id};
    final lol = days.firstWhere((t) => t.title == 'LOL TV');
    final shows = lol.listings();
    expect(shows.length, greaterThan(30));
    expect(shows.every((l) => sitcoms.contains(l.itemId)), isTrue);
    expect(lol.end.isBefore(DateTime(2026, 10, 17, 6)), isFalse);
    for (final t in days.where((t) => t.title != 'LOL TV')) {
      expect(t.listings().any((l) => sitcoms.contains(l.itemId)), isFalse, reason: t.title);
    }
  });

  test('channels: no title on two channels at once, 60 days running', () {
    final cursors = <String, int>{};
    final byId = {for (final m in pool.movies) m.id: m.key, for (final s in pool.series) for (final e in s.episodes) e.id: e.key};
    var movieNights = 0;
    addTearDown(() {
      // Rare, but they do happen: roughly 3 in 10 evenings per channel.
      // ignore: avoid_print
      print('movie evenings: $movieNights of 180 (LOL TV has none)');
      expect(movieNights, inInclusiveRange(20, 90));
    });
    for (var d = 0; d < 60; d++) {
      final days = channelDays(DateTime(day.year, day.month, day.day + d), pool, cursors);
      for (final t in days) {
        if (t.listings().any((l) => pool.movies.any((m) => m.id == l.itemId))) movieNights++;
        final keys = [for (final l in t.listings()) byId[l.itemId]!];
        // LOL TV runs sitcoms back to back (up to four of a kind with two shows); others never three.
        final most = t.title == 'LOL TV' ? 4 : 2;
        for (var i = most; i < keys.length; i++) {
          expect(List.generate(most + 1, (k) => keys[i - k]).toSet().length == 1, isFalse, reason: 'day $d ${t.title}: too many of ${keys[i]} in a row');
        }
      }
      final spans = [
        for (final (c, t) in days.indexed)
          for (final l in t.listings()) (c, byId[l.itemId]!, l.start, l.end),
      ];
      for (final a in spans) {
        for (final b in spans) {
          if (a.$1 < b.$1 && a.$2 == b.$2) expect(a.$3.isBefore(b.$4) && b.$3.isBefore(a.$4), isFalse, reason: 'day $d: ${a.$2} at ${a.$3} and ${b.$3}');
        }
      }
    }
  });

  test('the night the clocks go back (25 Oct 2026) is still one full channel day', () {
    final dst = DateTime(2026, 10, 24);
    final days = channelDays(dst, pool, {});
    for (final t in days) {
      expect(t.start, DateTime(2026, 10, 24, 6));
      expect(t.end.isBefore(DateTime(2026, 10, 25, 6)), isFalse);
    }
    expect(channelDay(DateTime(2026, 10, 25, 3)), DateTime(2026, 10, 24, 6));
    expect(channelDay(DateTime(2026, 10, 25, 7)), DateTime(2026, 10, 25, 6));
  });

  test('marathon: breaks are optional and per movie', () {
    final ms = [pool.movies[0], pool.movies[1], pool.movies[2]];
    final plain = marathonShow('a', 'x', DateTime(2026, 10, 17, 20), ms, const [], pool);
    expect(plain.steps.where((s) => s.kind == StepKind.pause || s.kind == StepKind.intermission), isEmpty);
    final mixed = marathonShow('a', 'x', DateTime(2026, 10, 17, 20), ms, const [0, 10], pool, intermissions: const [15, 0, 5]);
    expect([for (final s in mixed.steps.where((s) => s.kind == StepKind.intermission)) s.dur.inMinutes], [15, 5]);
    expect([for (final s in mixed.steps.where((s) => s.kind == StepKind.pause)) s.dur.inMinutes], [10]);
    expect(mixed.length - plain.length, const Duration(minutes: 30));
    // The intermission sits in the middle of its own movie.
    final ii = mixed.steps.indexWhere((s) => s.kind == StepKind.intermission);
    expect(mixed.steps[ii - 1].itemId, ms[0].id);
    expect(mixed.steps[ii + 1].from, mixed.steps[ii - 1].dur);
  });

  test('marathon: one pre-show, countdown before each movie, breaks between', () {
    final t = marathonShow('id', 'Night', DateTime(2026, 10, 17, 20), [pool.movies[0], pool.movies[1], pool.movies[2]], [15, 20], pool);
    expect(t.steps.where((s) => s.kind == StepKind.countdown).length, 3);
    final pauses = t.steps.where((s) => s.kind == StepKind.pause).toList();
    expect([for (final p in pauses) p.dur.inMinutes], [15, 20]);
    expect(t.steps.where((s) => s.kind == StepKind.intermission), isEmpty);
    expect(t.steps.where((s) => s.isTrailer).length, 5);
  });
}
