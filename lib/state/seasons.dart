import '../api/jellyfin.dart';

/// A home row for a time of year, filled from the library's genres and TMDb keywords (tags).
class SeasonRow {
  final String title;
  final String? subtitle;
  final bool Function(Item) pick;
  const SeasonRow(this.title, this.pick, {this.subtitle});
}

String _words(Item i) => [...i.tags, ...i.genres, i.name].join(' | ').toLowerCase();

bool _scary(Item i) {
  final w = _words(i);
  return i.genres.contains('Horror') || w.contains('horror') || w.contains('halloween') || w.contains('slasher');
}

const _spooky = ['witch', 'ghost', 'vampire', 'werewolf', 'monster', 'haunted', 'wizard', 'zombie', 'skeleton', 'spooky', 'supernatural'];

/// The rows for [d]: Halloween all October, Christmas from 1 to 26 December, Valentine's from
/// 1 to 14 February and summer blockbusters in July and August. Nothing the rest of the year.
List<SeasonRow> seasonalRows(DateTime d) => switch ((d.month, d.day)) {
  (10, _) => [
    SeasonRow('Halloween Frights', _scary, subtitle: 'Lights off:'),
    SeasonRow('Spooky, Not Scary', (i) => !_scary(i) && _spooky.any(_words(i).contains), subtitle: 'For the whole family:'),
  ],
  (12, <= 26) => [SeasonRow('Christmas Movies', (i) => _words(i).contains('christmas') || _words(i).contains('xmas'), subtitle: 'Cosy up:')],
  (2, <= 14) => [SeasonRow("Valentine's Night", (i) => i.genres.contains('Romance') || _words(i).contains('valentine'), subtitle: 'Date night:')],
  (7 || 8, _) => [
    SeasonRow('Summer Blockbusters', (i) => i.isMovie && (i.genres.contains('Action') || i.genres.contains('Adventure')) && (i.communityRating ?? 0) >= 7),
  ],
  _ => const [],
};
