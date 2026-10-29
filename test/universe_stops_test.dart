import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hevyfin/api/jellyfin.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> raw(String id, {String type = 'Movie', String? date, String? series, String? season, int? s, int? e, bool played = false}) => {
  'Id': id,
  'Name': id,
  'Type': type,
  'PremiereDate': ?date,
  'SeriesId': ?series,
  'SeasonId': ?season,
  'ParentIndexNumber': ?s,
  'IndexNumber': ?e,
  'RunTimeTicks': 45 * 60 * 10000000,
  'UserData': {'Played': played},
};

void main() {
  // A film, a show's season 1 (two episodes), a one-episode cut of another show, a film.
  final films = [
    raw('first-film', date: '2008-05-02', played: true),
    raw('hero', type: 'Series', date: '2015-04-10'),
    raw('sideshow', type: 'Series', date: '2013-09-24'),
    raw('sequel', date: '2015-05-01'),
  ];
  final episodes = [
    raw('dd1', type: 'Episode', series: 'hero', season: 'dd-s1', s: 1, e: 1),
    raw('dd2', type: 'Episode', series: 'hero', season: 'dd-s1', s: 1, e: 2),
    raw('side16', type: 'Episode', series: 'sideshow', season: 'side-s1', s: 1, e: 16),
  ];
  final seasons = [raw('dd-s1', type: 'Season', series: 'hero'), raw('side-s1', type: 'Season', series: 'sideshow')];
  final story = [
    {'kind': 'movie', 'ids': ['first-film'], 'title': 'first-film', 'date': '2008-05-02', 'group': 'Phase One'},
    {'kind': 'season', 'ids': ['dd1', 'dd2'], 'series': 'hero', 'season': 1, 'title': 'hero', 'code': 'Season 1', 'date': '2015-04-10', 'group': 'TV'},
    {'kind': 'cut', 'ids': ['side16'], 'series': 'sideshow', 'season': 1, 'title': 'Side Story: The Turn', 'code': 'S1 · E16', 'date': '2014-04-08', 'group': 'TV', 'art': {'id': 'side16', 'tag': 't1'}},
    {'kind': 'movie', 'ids': ['sequel'], 'title': 'sequel', 'date': '2015-05-01', 'group': 'Phase Two'},
  ];
  final box = {...raw('saga', type: 'BoxSet'), 'Name': 'Example Saga', 'ProviderIds': {'HevyfinStory': jsonEncode(story)}};

  JellyfinClient client({bool withStory = true}) {
    final all = {for (final i in [...films, ...episodes, ...seasons]) i['Id']: i};
    final mock = MockClient((r) async {
      final q = r.url.queryParameters;
      Object? body;
      if (r.url.path == '/Items/saga') {
        body = withStory ? box : raw('saga', type: 'BoxSet');
      } else if (r.url.path == '/Items' && q['parentId'] == 'saga') {
        body = {'Items': films};
      } else if (r.url.path == '/Items' && q['ids'] != null) {
        body = {'Items': [for (final id in q['ids']!.split(',')) ?all[id]]};
      } else if (r.url.path == '/Shows/sideshow/Episodes') {
        body = {'Items': [episodes[2], raw('side17', type: 'Episode', series: 'sideshow', s: 1, e: 17)]};
      } else {
        body = {'Items': []};
      }
      return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
    });
    return JellyfinClient('http://jf', 'test', session: const Session('u', 'me', 't'), httpClient: mock);
  }

  List<Item> items(List<Map<String, dynamic>> l) => [for (final m in l) Item(m)];

  test('story order follows the job\'s list: seasons and cuts are their own stops', () async {
    final stops = await client().universeStops(Item(box), items(films), story: true);
    expect(stops.map((s) => s.title), ['first-film', 'hero', 'Side Story: The Turn', 'sequel']);
    expect(stops[1].parts.map((p) => p.id), ['dd1', 'dd2']);
    expect(stops[1].season?.id, 'dd-s1');
    expect(stops[1].code, 'Season 1');
    expect(stops[2].season, isNull);
    expect(stops[2].route, '/item/side-s1?in=saga');
    expect(stops[2].art?.id, 'side16'); // a cut's own poster, kept on its first episode
    expect(client().stopPoster(stops[2]), contains('/Items/side16/Images/Box'));
    expect(stops[1].art, isNull);
    expect(stops.first.played, isTrue);
    expect(stops[1].played, isFalse);
  });

  test('release order sorts the stops by date', () async {
    final stops = await client().universeStops(Item(box), items(films));
    expect(stops.map((s) => s.title), ['first-film', 'Side Story: The Turn', 'hero', 'sequel']);
  });

  test('without the job\'s list every title is a stop', () async {
    final stops = await client(withStory: false).universeStops(Item(raw('saga', type: 'BoxSet')), items(films), story: true);
    expect(stops.map((s) => s.item.id), ['first-film', 'hero', 'sideshow', 'sequel']);
    expect(stops.every((s) => !s.isPart), isTrue);
  });

  test('from the universe, what plays next follows its path', () async {
    final c = client();
    Future<String?> next(Map<String, dynamic> m) async => (await c.nextInUniverse('saga', Item(m), story: true))?.id;
    expect(await next(films[0]), 'dd1'); // a film into the next stop, a season: its first episode
    expect(await next(episodes[0]), 'dd2'); // on through the season
    expect(await next(episodes[1]), 'side16'); // the season's end: into the cut
    expect(await next(episodes[2]), 'sequel'); // the cut's end: not the show's E17, the next film
    expect(await next(films[3]), isNull); // the last stop
    expect(await next(raw('side17', type: 'Episode', series: 'sideshow', s: 1, e: 17)), isNull); // off the path
  });
}
