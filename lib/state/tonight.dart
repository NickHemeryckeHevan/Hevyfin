import 'dart:math';

import '../api/jellyfin.dart';

/// "What tonight?": the choices, and three titles from the library that fit them.
enum TonightKind { any, film, series }

enum TonightLength { any, short, medium, long }

enum TonightMood {
  any('Anything'),
  funny('Funny'),
  exciting('Exciting'),
  scary('Scary'),
  feelGood('Feel-good'),
  mindBending('Mind-bending'),
  magical('Magical'),
  real('True stories');

  final String label;
  const TonightMood(this.label);

  bool fits(Item i) {
    final g = i.genres.toSet();
    final tags = i.tags.join('|').toLowerCase();
    return switch (this) {
      any => true,
      funny => g.contains('Comedy'),
      exciting => g.intersection({'Action', 'Adventure', 'Thriller', 'Action & Adventure', 'War', 'Crime'}).isNotEmpty,
      scary => g.contains('Horror') || tags.contains('horror'),
      feelGood => g.intersection({'Family', 'Romance', 'Music', 'Animation'}).isNotEmpty && !g.contains('Horror'),
      mindBending => g.intersection({'Science Fiction', 'Mystery', 'Sci-Fi & Fantasy'}).isNotEmpty || tags.contains('time travel'),
      magical => g.intersection({'Fantasy', 'Sci-Fi & Fantasy'}).isNotEmpty || tags.contains('magic'),
      real => g.intersection({'Documentary', 'History'}).isNotEmpty || tags.contains('based on true story'),
    };
  }
}

/// Ratings fine for children (US, UK and Dutch/Belgian labels).
const _kidsRatings = {'G', 'PG', 'TV-Y', 'TV-Y7', 'TV-G', 'TV-PG', 'U', 'AL', 'KT', '6', '9', 'NL-AL', 'NL-6', 'NL-9', 'BE-AL', 'BE-6', 'BE-9'};

bool kidSafe(Item i) {
  final r = i.officialRating?.trim();
  if (r != null && r.isNotEmpty) return _kidsRatings.contains(r.toUpperCase());
  return i.genres.contains('Family') || i.genres.contains('Kids') || (i.genres.contains('Animation') && !i.genres.contains('Horror'));
}

class TonightAsk {
  final TonightKind kind;
  final TonightLength length;
  final TonightMood mood;
  final bool kids, unseen;
  const TonightAsk({this.kind = TonightKind.any, this.length = TonightLength.any, this.mood = TonightMood.any, this.kids = false, this.unseen = true});

  bool fits(Item i) {
    if (kind == TonightKind.film && !i.isMovie) return false;
    if (kind == TonightKind.series && !i.isSeries) return false;
    if (unseen && i.played) return false;
    if (kids && !kidSafe(i)) return false;
    final m = i.runtime?.inMinutes;
    // A series counts by its episodes, so "short" means short episodes.
    final ok = switch (length) {
      TonightLength.any => true,
      TonightLength.short => m != null && m <= 90,
      TonightLength.medium => m != null && m <= 120,
      TonightLength.long => m != null && m > 120,
    };
    return ok && mood.fits(i);
  }
}

/// Up to three that fit, at random, but not three of the same kind of thing: each pick
/// prefers a main genre the earlier picks didn't have.
List<Item> pickTonight(List<Item> all, TonightAsk ask, {Random? random}) {
  final pool = all.where(ask.fits).toList()..shuffle(random ?? Random());
  final out = <Item>[];
  final seen = <String>{};
  for (final i in pool) {
    if (out.length == 3) break;
    if (i.genres.isNotEmpty && seen.contains(i.genres.first)) continue;
    out.add(i);
    seen.addAll(i.genres.take(1));
  }
  for (final i in pool) {
    if (out.length == 3) break;
    if (!out.contains(i)) out.add(i);
  }
  return out;
}
