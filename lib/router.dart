import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'state/device.dart';
import 'ui/pages/browse.dart';
import 'ui/pages/cinema.dart';
import 'ui/pages/collection.dart';
import 'ui/pages/details.dart';
import 'ui/pages/downloads.dart';
import 'ui/pages/discover.dart';
import 'ui/pages/home.dart';
import 'ui/pages/live_player.dart';
import 'ui/pages/person.dart';
import 'ui/pages/tonight.dart';
import 'ui/pages/search.dart';
import 'ui/pages/free_tv_player.dart';
import 'ui/pages/settings.dart';
import 'ui/pages/tickets.dart';
import 'ui/pages/tv_guide.dart';
import 'ui/player.dart';
import 'ui/shell.dart';
import 'host.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

Page<void> _fade(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 200),
  reverseTransitionDuration: const Duration(milliseconds: 140),
  transitionsBuilder: (_, a, _, c) => FadeTransition(
    opacity: CurveTween(curve: Curves.easeOut).animate(a),
    child: c,
  ),
);

/// Pages you drill into (a title, a person) rise into place over the one below, Netflix-style.
Page<void> _rise(GoRouterState state, Widget child) => CustomTransitionPage(
  key: state.pageKey,
  child: child,
  transitionDuration: const Duration(milliseconds: 380),
  reverseTransitionDuration: const Duration(milliseconds: 260),
  transitionsBuilder: (_, a, secondary, c) {
    final curve = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    // The page underneath dims and recedes slightly.
    final under = CurvedAnimation(parent: secondary, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: Tween(begin: 1.0, end: .5).animate(under),
      child: ScaleTransition(
        scale: Tween(begin: 1.0, end: .96).animate(under),
        child: FadeTransition(
          opacity: curve,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, .08), end: Offset.zero).animate(curve),
            child: ScaleTransition(scale: Tween(begin: .97, end: 1.0).animate(curve), child: c),
          ),
        ),
      ),
    );
  },
);

GoRoute _route(String path, Widget Function(GoRouterState) page) => GoRoute(path: path, pageBuilder: (_, s) => _fade(s, page(s)));
GoRoute _drill(String path, Widget Function(GoRouterState) page) => GoRoute(path: path, pageBuilder: (_, s) => _rise(s, page(s)));

/// [initial] lets a developer open a page directly (`HEVYFIN_ROUTE=/item/<id>`).
GoRouter buildRouter({String? initial}) => GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: initial,
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        _route('/', (_) => const HomePage()),
        _route('/shows', (_) => const BrowsePage(key: ValueKey('Series'), type: 'Series')),
        _route('/movies', (_) => const BrowsePage(key: ValueKey('Movie'), type: 'Movie')),
        _route('/new', (s) => DiscoverPage(tab: s.uri.queryParameters['tab'])),
        _route('/my-list', (_) => const MyListPage()),
        _route('/search', (s) => SearchPage(query: s.uri.queryParameters['q'] ?? '')),
        _drill('/genre/:name', (s) => GenrePage(key: ValueKey(s.uri.toString()), name: s.pathParameters['name']!, type: s.uri.queryParameters['type'])),
        _drill(
          '/item/:id',
          (s) => DetailsPage(key: ValueKey(s.uri.toString()), id: s.pathParameters['id']!, universe: s.uri.queryParameters['in']),
        ),
        _drill(
          '/person/tmdb/:tmdb',
          (s) => PersonPage(key: ValueKey(s.uri.path), tmdbId: int.parse(s.pathParameters['tmdb']!), name: s.uri.queryParameters['name'] ?? ''),
        ),
        _drill('/person/:id', (s) => PersonPage(key: ValueKey(s.uri.path), jellyfinId: s.pathParameters['id']!, name: s.uri.queryParameters['name'] ?? '')),
        _drill(
          '/request/:type/:id',
          (s) => SeerrDetailsPage(key: ValueKey(s.uri.path), type: s.pathParameters['type']!, id: int.parse(s.pathParameters['id']!)),
        ),
        _drill('/settings', (_) => const SettingsPage()),
        _route('/cinema', (_) => const CinemaPage()),
        // The web version has no downloads, and marathons are planned in the apps.
        if (!Host.isWeb) _drill('/cinema/marathon/:id', (s) => MarathonEditor(key: ValueKey(s.pathParameters['id']), id: s.pathParameters['id']!)),
        _route('/tv', (_) => const TvGuidePage()),
        if (!Host.isWeb) _drill('/marathons', (_) => const MarathonsPage()),
        if (!Host.isWeb) _route('/downloads', (_) => const DownloadsPage()),
        _drill('/tickets', (_) => const TicketsPage()),
        _route('/collections', (_) => const CollectionsPage()),
        _drill('/tonight', (s) => TonightPage(key: ValueKey(s.uri.toString()), ask: s.uri.queryParameters['ask'] ?? '')),
      ],
    ),
    GoRoute(
      path: '/live/:kind/:id',
      parentNavigatorKey: rootNavigatorKey,
      // Screenings, channels and marathons are the TV's; phones and computers only get
      // a movie's "Cinema mode".
      redirect: (_, s) => !Device.isTv && !s.uri.path.startsWith('/live/${LiveKind.movie.name}/') ? '/' : null,
      pageBuilder: (_, s) => _fade(
        s,
        LivePlayerPage(
          key: ValueKey(s.uri.toString()),
          kind: LiveKind.values.byName(s.pathParameters['kind']!),
          id: s.pathParameters['id']!,
          fromStart: s.uri.queryParameters['fromStart'] == '1',
        ),
      ),
    ),
    // A free channel (5 and up), full screen.
    GoRoute(
      path: '/freetv/:id',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (_, s) => _fade(s, FreeTvPlayer(key: ValueKey(s.pathParameters['id']), channelId: s.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/play/:id',
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (_, s) {
        final ms = int.tryParse(s.uri.queryParameters['t'] ?? '');
        return _fade(
          s,
          PlayerPage(
            key: ValueKey(s.pathParameters['id']),
            id: s.pathParameters['id']!,
            start: ms == null ? null : Duration(milliseconds: ms),
            sync: s.uri.queryParameters['sync'] == '1',
            local: s.uri.queryParameters['local'] == '1',
            trailer: s.uri.queryParameters['trailer'] == '1',
            name: s.uri.queryParameters['name'],
            universe: s.uri.queryParameters['in'],
          ),
        );
      },
    ),
  ],
);
