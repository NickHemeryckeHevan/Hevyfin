import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/api/jellyfin.dart';
import 'package:hevyfin/state/seasons.dart';
import 'package:hevyfin/state/tonight.dart';

Item item(String name, {String type = 'Movie', List<String> genres = const [], List<String> tags = const [], int mins = 100, String? rating, bool played = false}) =>
    Item({
      'Id': name,
      'Name': name,
      'Type': type,
      'Genres': genres,
      'Tags': tags,
      'RunTimeTicks': mins * 60 * 10000000,
      'OfficialRating': ?rating,
      'UserData': {'Played': played},
    });

void main() {
  final haunting = item('The Haunting Hour', genres: ['Horror'], tags: ['halloween'], rating: 'R');
  final wizard = item('The Wizard School', genres: ['Fantasy', 'Family'], tags: ['witch', 'ghost'], mins: 152, rating: 'PG');
  final snowpost = item('Snow Post', genres: ['Animation', 'Family'], tags: ['christmas'], mins: 97, rating: 'PG');
  final swamp = item('Swamp Tales', genres: ['Animation', 'Comedy'], mins: 90, rating: 'PG');
  final barFriends = item('Bar Friends', type: 'Series', genres: ['Comedy'], mins: 22, rating: 'TV-MA');
  final seen = item('High School Queens', genres: ['Comedy'], mins: 97, rating: 'PG-13', played: true);
  final all = [haunting, wizard, snowpost, swamp, barFriends, seen];

  test('October has a scary row and a family one', () {
    final rows = seasonalRows(DateTime(2026, 10, 19));
    expect(rows.map((r) => r.title), ['Halloween Frights', 'Spooky, Not Scary']);
    expect(all.where(rows[0].pick), [haunting]);
    expect(all.where(rows[1].pick), [wizard]);
  });

  test('Christmas until Boxing Day, nothing in November', () {
    expect(all.where(seasonalRows(DateTime(2026, 12, 20)).single.pick), [snowpost]);
    expect(seasonalRows(DateTime(2026, 12, 27)), isEmpty);
    expect(seasonalRows(DateTime(2026, 11, 5)), isEmpty);
  });

  test('tonight: funny, short, not seen', () {
    const ask = TonightAsk(mood: TonightMood.funny, length: TonightLength.short);
    expect(all.where(ask.fits).toSet(), {swamp, barFriends});
    expect(pickTonight(all, const TonightAsk(mood: TonightMood.funny, length: TonightLength.short, kind: TonightKind.film)), [swamp]);
  });

  test('with kids leaves out the R and TV-MA ones', () {
    const ask = TonightAsk(kids: true, unseen: false);
    expect(all.where(ask.fits).toSet(), {wizard, snowpost, swamp});
  });

  test('three picks, different main genres first', () {
    final many = [for (var n = 0; n < 6; n++) item('Comedy $n', genres: ['Comedy']), haunting, wizard];
    final p = pickTonight(many, const TonightAsk(), random: Random(1));
    expect(p, hasLength(3));
    expect(p.map((i) => i.genres.first).toSet(), hasLength(3));
  });
}
