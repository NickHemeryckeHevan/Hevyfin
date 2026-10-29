import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/jellyfin.dart';
import '../state/app_state.dart';
import '../state/device.dart';
import '../state/live_store.dart';
import '../theme.dart';
import 'pages/live_player.dart';
import 'widgets/common.dart';
import 'widgets/together.dart';
import '../host.dart';

const topBarHeight = 68.0;
const _narrowBarHeight = 56.0;
const _chipsHeight = 46.0;

/// Pages that show the Shows / Movies / Categories chips on phones.
bool _hasChips(String path) => path == '/' || path == '/shows' || path == '/movies';

/// Space a page without a hero should leave for the floating top bar.
double topInset(BuildContext context) {
  final top = MediaQuery.paddingOf(context).top;
  if (Device.isTv) return 36; // no top bar on TV, just the overscan margin
  if (!isNarrow(context)) return topBarHeight + top;
  final path = GoRouterState.of(context).uri.path;
  return _narrowBarHeight + top + (_hasChips(path) ? _chipsHeight : 0);
}

class _Tab {
  final String label, path;
  final IconData icon, activeIcon;
  const _Tab(this.label, this.path, this.icon, this.activeIcon);
}

const _tabs = [
  _Tab('Home', '/', Icons.home_outlined, Icons.home_rounded),
  _Tab('Shows', '/shows', Icons.tv_outlined, Icons.tv_rounded),
  _Tab('Movies', '/movies', Icons.movie_outlined, Icons.movie_rounded),
  _Tab('New & Popular', '/new', Icons.local_fire_department_outlined, Icons.local_fire_department_rounded),
  _Tab('My List', '/my-list', Icons.bookmark_outline_rounded, Icons.bookmark_rounded),
];

/// Phones get Netflix mobile's three tabs; Shows and Movies live in the header chips.
/// (A narrow browser window gets them too, without Downloads.)
List<_Tab> get _mobileTabs => Host.isWeb ? _phoneTabs.where((t) => t.path != '/downloads').toList() : _phoneTabs;

const _phoneTabs = [
  _Tab('Home', '/', Icons.home_outlined, Icons.home_rounded),
  _Tab('New & Hot', '/new', Icons.local_fire_department_outlined, Icons.local_fire_department_rounded),
  _Tab('My List', '/my-list', Icons.bookmark_outline_rounded, Icons.bookmark_rounded),
  _Tab('Downloads', '/downloads', Icons.download_for_offline_outlined, Icons.download_for_offline_rounded),
];

/// Netflix-style frame: a top bar that floats over the hero and turns solid once
/// you scroll; on phones a blurred header with category chips and three bottom tabs.
class AppShell extends StatefulWidget {
  final Widget child;
  const AppShell({super.key, required this.child});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _solid = ValueNotifier(false);
  final _chips = ValueNotifier(true);
  String _lastPath = '';

  @override
  void dispose() {
    _solid.dispose();
    _chips.dispose();
    super.dispose();
  }

  int _tabIndex(String path, List<_Tab> tabs) {
    for (var i = tabs.length - 1; i >= 0; i--) {
      if (tabs[i].path == '/' ? path == '/' : path.startsWith(tabs[i].path)) return i;
    }
    return -1;
  }

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    _solid.value = n.metrics.pixels > 30;
    if (n is ScrollUpdateNotification && n.scrollDelta != null) {
      // Hide the chips when scrolling down, bring them back when scrolling up.
      if (n.metrics.pixels < 60 || n.scrollDelta! < -6) {
        _chips.value = true;
      } else if (n.scrollDelta! > 6) {
        _chips.value = false;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    if (Device.isTv) return _TvShell(path: path, child: widget.child);
    if (path != _lastPath) {
      _lastPath = path;
      _solid.value = false;
      _chips.value = true;
    }
    final narrow = isNarrow(context);
    final offline = context.select<AppState, bool>((a) => a.offline);
    var mIdx = _tabIndex(path, _mobileTabs);
    if (path == '/shows' || path == '/movies') mIdx = 0;

    return Scaffold(
      backgroundColor: Hy.bg,
      body: Stack(
        children: [
          NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.child),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: narrow ? _MobileTopBar(solid: _solid, chips: _chips, path: path) : _TopBar(solid: _solid, index: _tabIndex(path, _tabs), narrow: narrow),
          ),
          if (offline)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Material(
                color: Hy.danger,
                child: InkWell(
                  onTap: () => context.read<AppState>().retry(),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      "Can't reach Jellyfin at home or over Tailscale. Tap to retry.",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: narrow ? _BottomTabs(index: mIdx) : null,
    );
  }
}

/// Netflix mobile's bottom bar: icons that pop when chosen, over a frosted strip.
class _BottomTabs extends StatelessWidget {
  final int index;
  const _BottomTabs({required this.index});
  @override
  Widget build(BuildContext context) => ClipRect(
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
      child: Container(
        color: const Color(0xD90A0A0A),
        padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (final (i, t) in _mobileTabs.indexed)
                Expanded(
                  child: InkWell(
                    onTap: () => context.go(t.path),
                    splashColor: Colors.transparent,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: i == index ? 1.12 : 1,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          child: Icon(i == index ? t.activeIcon : t.icon, color: i == index ? Colors.white : Hy.textMute, size: 26),
                        ),
                        const SizedBox(height: 4),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 200),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                            color: i == index ? Colors.white : Hy.textMute,
                          ),
                          child: Text(t.label),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Phone header: title, search and profile, then chips; frosted once you scroll.
class _MobileTopBar extends StatelessWidget {
  final ValueNotifier<bool> solid, chips;
  final String path;
  const _MobileTopBar({required this.solid, required this.chips, required this.path});

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    final canPop = context.canPop();
    final name = context.select<AppState, String>((a) => a.userName);
    final hasChips = _hasChips(path);
    final title = switch (path) {
      '/' => name.isEmpty ? null : 'For ${name[0].toUpperCase()}${name.substring(1)}',
      '/shows' => 'Shows',
      '/movies' => 'Movies',
      '/new' => 'New & Hot',
      '/my-list' => 'My List',
      '/search' => 'Search',
      _ => null,
    };
    final root = _mobileTabs.any((t) => t.path == path) || hasChips || path == '/search';

    return ListenableBuilder(
      listenable: Listenable.merge([solid, chips]),
      builder: (context, _) {
        final showChips = hasChips && chips.value;
        final bar = AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          height: top + _narrowBarHeight + (showChips ? _chipsHeight : 0),
          decoration: BoxDecoration(
            color: solid.value ? const Color(0xCC0E0E0E) : null,
            gradient: solid.value
                ? null
                : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xB3000000), Colors.transparent]),
          ),
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxHeight: top + _narrowBarHeight + _chipsHeight,
              child: Padding(
                padding: EdgeInsets.only(top: top),
                child: Column(
                  children: [
                    SizedBox(
                      height: _narrowBarHeight,
                      child: Row(
                        children: [
                          if (canPop && !root)
                            IconButton(
                              tooltip: 'Back',
                              onPressed: () => context.pop(),
                              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                            )
                          else
                            const SizedBox(width: 16),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 250),
                              layoutBuilder: (cur, prev) => Stack(alignment: Alignment.centerLeft, children: [...prev, ?cur]),
                              child: title == null
                                  ? const Align(alignment: Alignment.centerLeft, child: Wordmark(size: 22))
                                  : Text(
                                      title,
                                      key: ValueKey(title),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.3),
                                    ),
                            ),
                          ),
                          if (path != '/search')
                            IconButton(
                              tooltip: 'Search',
                              onPressed: () => context.push('/search'),
                              icon: const Icon(Icons.search_rounded, color: Colors.white, size: 27),
                            ),
                          const _ProfileMenu(),
                          const SizedBox(width: 12),
                        ],
                      ),
                    ),
                    if (hasChips)
                      SizedBox(
                        height: _chipsHeight,
                        child: AnimatedOpacity(
                          opacity: showChips ? 1 : 0,
                          duration: const Duration(milliseconds: 180),
                          child: _Chips(path: path),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
        return solid.value
            ? ClipRect(
                child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: bar),
              )
            : bar;
      },
    );
  }
}

class _Chips extends StatelessWidget {
  final String path;
  const _Chips({required this.path});

  @override
  Widget build(BuildContext context) {
    final type = switch (path) {
      '/shows' => 'Series',
      '/movies' => 'Movie',
      _ => null,
    };
    Widget chip(String label, {VoidCallback? onTap, bool selected = false, bool dropdown = false, IconData? icon}) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: HoverScale(
        scale: 1,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: EdgeInsets.symmetric(horizontal: icon != null ? 8 : 15, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? Colors.white.withValues(alpha: .2) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selected ? Colors.transparent : Colors.white54),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) Icon(icon, size: 18, color: Colors.white) else Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              if (dropdown) const Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: Colors.white),
            ],
          ),
        ),
      ),
    );
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      children: [
        if (type != null) chip('', icon: Icons.close_rounded, onTap: () => context.go('/')),
        if (type != 'Movie') chip('Shows', selected: type == 'Series', onTap: () => context.go('/shows')),
        if (type != 'Series') chip('Movies', selected: type == 'Movie', onTap: () => context.go('/movies')),
        if (type == null) chip('Tonight?', onTap: () => context.push('/tonight')),
        chip(type == null ? 'Categories' : 'All Categories', dropdown: true, onTap: () => showCategories(context, type: type)),
      ],
    );
  }
}

/// Netflix's full-screen category picker: a blurred overlay with a centred list.
Future<void> showCategories(BuildContext context, {String? type}) {
  final c = jf(context);
  final router = GoRouter.of(context);
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (_, a, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
      child: child,
    ),
    pageBuilder: (ctx, _, _) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      // No blur on TV: too heavy for TV chips; the dark tint is enough.
      enabled: !Device.isTv,
      child: Material(
        color: Colors.black.withValues(alpha: Device.isTv ? .88 : .72),
        child: SafeArea(
          child: Stack(
            children: [
              FutureBuilder<List<Genre>>(
                future: c.genres(types: type == null ? const ['Movie', 'Series'] : [type]),
                builder: (ctx, snap) {
                  final genres = snap.data;
                  if (genres == null) return const Center(child: CircularProgressIndicator(color: Hy.orange));
                  final entries = [if (type == null) ('Home', null), for (final g in genres) (g.name, g.name)];
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(24, 60, 24, 140),
                    itemCount: entries.length,
                    itemBuilder: (ctx, i) {
                      final (label, genre) = entries[i];
                      return FadeIn(
                        delay: Duration(milliseconds: 15 * i.clamp(0, 20)),
                        from: const Offset(0, .3),
                        child: InkWell(
                          onTap: () {
                            Navigator.pop(ctx);
                            if (genre != null) router.push('/genre/${Uri.encodeComponent(genre)}${type == null ? '' : '?type=$type'}');
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 19,
                                fontWeight: genre == null ? FontWeight.w800 : FontWeight.w500,
                                color: genre == null ? Colors.white : Hy.textDim,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 28,
                child: Center(
                  child: FadeIn(
                    from: const Offset(0, .6),
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(),
                      child: IconButton(
                        iconSize: 30,
                        padding: const EdgeInsets.all(14),
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded, color: Colors.black),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _TopBar extends StatelessWidget {
  final ValueNotifier<bool> solid;
  final int index;
  final bool narrow;
  const _TopBar({required this.solid, required this.index, required this.narrow});

  @override
  Widget build(BuildContext context) {
    final pad = pagePadding(context);
    final canPop = context.canPop();
    return ValueListenableBuilder<bool>(
      valueListenable: solid,
      builder: (context, isSolid, child) {
        final bar = AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: topInset(context),
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top, left: canPop ? pad - 12 : pad, right: pad - 8),
          decoration: BoxDecoration(
            color: isSolid ? const Color(0xCC0E0E0E) : null,
            gradient: isSolid
                ? null
                : const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xCC000000), Colors.transparent]),
          ),
          child: child,
        );
        // Frosted glass once the page scrolls under it, like the phone header.
        return isSolid
            ? ClipRect(
                child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20), child: bar),
              )
            : bar;
      },
      child: Row(
        children: [
          if (canPop && index < 0)
            IconButton(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          GestureDetector(
            onTap: () => context.go('/'),
            child: const MouseRegion(cursor: SystemMouseCursors.click, child: Wordmark(size: 26)),
          ),
          const SizedBox(width: 36),
          // In a narrow window (a laptop with a big scale, a half-screen window) the tabs fold
          // into a Browse menu, like Netflix's, instead of running under search.
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) => box.maxWidth < 640
                  ? Align(
                      alignment: Alignment.centerLeft,
                      child: _BrowseMenu(index: index),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < _tabs.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: TextButton(
                                onPressed: () => context.go(_tabs[i].path),
                                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedDefaultTextStyle(
                                      duration: const Duration(milliseconds: 200),
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: i == index ? FontWeight.w800 : FontWeight.w500,
                                        color: i == index ? Colors.white : Hy.textDim,
                                      ),
                                      child: Text(_tabs[i].label),
                                    ),
                                    const SizedBox(height: 4),
                                    AnimatedContainer(
                                      duration: const Duration(milliseconds: 280),
                                      curve: Curves.easeOutCubic,
                                      height: 2.5,
                                      width: i == index ? 22 : 0,
                                      decoration: BoxDecoration(color: Hy.orange, borderRadius: BorderRadius.circular(2)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ),
          IconButton(
            tooltip: 'Search',
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.search_rounded, color: Colors.white, size: 26),
          ),
          IconButton(
            tooltip: 'What should I watch tonight?',
            onPressed: () => context.push('/tonight'),
            icon: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 24),
          ),
          const SizedBox(width: 4),
          const _ProfileMenu(),
        ],
      ),
    );
  }
}

class _BrowseMenu extends StatelessWidget {
  final int index;
  const _BrowseMenu({required this.index});
  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(
    tooltip: 'Browse',
    offset: const Offset(0, 44),
    color: Hy.surface,
    onSelected: (i) => context.go(_tabs[i].path),
    itemBuilder: (_) => [
      for (var i = 0; i < _tabs.length; i++)
        PopupMenuItem(
          value: i,
          child: Text(
            _tabs[i].label,
            style: TextStyle(fontWeight: i == index ? FontWeight.w800 : FontWeight.w500, color: i == index ? Colors.white : Hy.textDim),
          ),
        ),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(index >= 0 ? _tabs[index].label : 'Browse', style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800)),
          const Icon(Icons.arrow_drop_down_rounded, color: Colors.white),
        ],
      ),
    ),
  );
}

class _ProfileMenu extends StatelessWidget {
  const _ProfileMenu();
  @override
  Widget build(BuildContext context) {
    final name = context.select<AppState, String>((a) => a.userName);
    return PopupMenuButton<String>(
      tooltip: name,
      offset: const Offset(0, 48),
      onSelected: (v) {
        if (v == 'settings') context.push('/settings');
        if (v == 'requests') context.go('/new?tab=requests');
        if (v == 'marathons') context.push('/marathons');
        if (v == 'remote') showPlayOn(context);
        if (v == 'profiles') context.read<AppState>().chooseProfile();
        if (v == 'downloads') context.go('/downloads');
        if (v == 'tickets') context.push('/tickets');
        if (v == 'together') showWatchTogether(context);
        if (v == 'logout') context.read<AppState>().logout();
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            name,
            style: const TextStyle(color: Hy.textDim, fontWeight: FontWeight.w700),
          ),
        ),
        const PopupMenuItem(
          value: 'profiles',
          child: ListTile(dense: true, leading: Icon(Icons.switch_account_rounded), title: Text('Switch profile')),
        ),
        if (!Device.isTv && !Host.isWeb)
          const PopupMenuItem(
            value: 'downloads',
            child: ListTile(dense: true, leading: Icon(Icons.download_for_offline_rounded), title: Text('Downloads')),
          ),
        const PopupMenuItem(
          value: 'requests',
          child: ListTile(dense: true, leading: Icon(Icons.inbox_rounded), title: Text('My requests')),
        ),
        if (!Host.isWeb)
          const PopupMenuItem(
            value: 'marathons',
            child: ListTile(dense: true, leading: Icon(Icons.theaters_rounded), title: Text('Movie marathons')),
          ),
        if (!Device.isTv)
          const PopupMenuItem(
            value: 'remote',
            child: ListTile(dense: true, leading: Icon(Icons.settings_remote_rounded), title: Text('Control the TV')),
          ),
        const PopupMenuItem(
          value: 'together',
          child: ListTile(dense: true, leading: Icon(Icons.groups_rounded), title: Text('Watch together')),
        ),
        const PopupMenuItem(
          value: 'tickets',
          child: ListTile(dense: true, leading: Icon(Icons.confirmation_number_rounded), title: Text('Ticket stubs')),
        ),
        const PopupMenuItem(
          value: 'settings',
          child: ListTile(dense: true, leading: Icon(Icons.settings_rounded), title: Text('Settings')),
        ),
        const PopupMenuItem(
          value: 'logout',
          child: ListTile(dense: true, leading: Icon(Icons.logout_rounded), title: Text('Sign out')),
        ),
      ],
      child: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(gradient: Hy.orangeGradient, borderRadius: BorderRadius.circular(4)),
        child: Text(
          name.isEmpty ? '?' : name[0].toUpperCase(),
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 17),
        ),
      ),
    );
  }
}

/// The HEVYFIN wordmark: heavy, condensed, orange.
class Wordmark extends StatelessWidget {
  final double size;
  const Wordmark({super.key, this.size = 28});
  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (r) => Hy.orangeGradient.createShader(r),
    child: Text(
      'HEVYFIN',
      style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: size * -0.02, color: Colors.white, height: 1, fontStyle: FontStyle.italic),
    ),
  );
}

/// Seven places and the profile: Cinema and the channels share Live (a switch at the top
/// of it), Collections are a Home row and What tonight? sits on Search.
const _tvTabs = [
  _Tab('Search', '/search', Icons.search_rounded, Icons.search_rounded),
  _Tab('Home', '/', Icons.home_outlined, Icons.home_rounded),
  _Tab('Shows', '/shows', Icons.tv_outlined, Icons.tv_rounded),
  _Tab('Movies', '/movies', Icons.movie_outlined, Icons.movie_rounded),
  _Tab('Live', '/tv', Icons.live_tv_outlined, Icons.live_tv_rounded),
  _Tab('New & Hot', '/new', Icons.local_fire_department_outlined, Icons.local_fire_department_rounded),
  _Tab('My List', '/my-list', Icons.bookmark_outline_rounded, Icons.bookmark_rounded),
];

/// The profile at the foot of the menu opens Settings.
const _tvSettings = _Tab('Settings', '/settings', Icons.settings_rounded, Icons.settings_rounded);

const _railNarrow = 76.0;
const _railWide = 250.0;

/// The TV frame, after Google TV: a slim icon menu on the left that widens with labels
/// when the remote moves onto it, and the page beside it. Back from a top-level page
/// goes to the menu first, then leaves the app.
class _TvShell extends StatefulWidget {
  final String path;
  final Widget child;
  const _TvShell({required this.path, required this.child});
  @override
  State<_TvShell> createState() => _TvShellState();
}

class _TvShellState extends State<_TvShell> {
  final _rail = FocusScopeNode(debugLabel: 'rail');
  final _content = FocusScopeNode(debugLabel: 'content');
  String _shown = '';
  Timer? _marathons;

  @override
  void initState() {
    super.initState();
    _rail.addListener(_onRail);
    TvRemote.listen();
    FocusManager.instance.addListener(_onFocusMoved);
    _marathons = Timer.periodic(const Duration(seconds: 20), (_) => _checkMarathon());
  }

  /// A planned marathon's start time has come: offer to join it.
  void _checkMarathon() {
    final store = context.read<LiveStore>();
    // Pick up marathons planned on the phone or computer.
    store.syncMarathons();
    final m = store.due(DateTime.now());
    if (m == null || !mounted) return;
    // Already watching something live (maybe this marathon): don't interrupt.
    if (GoRouter.of(context).routerDelegate.currentConfiguration.uri.path.startsWith('/live')) return;
    store.prompted.add(m.id);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Hy.surface,
        title: Text('“${m.name}” starts now'),
        content: Text('${m.movieIds.length} movies, trailers first. Grab the popcorn.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Later')),
          FilledButton(
            autofocus: true,
            onPressed: () {
              Navigator.pop(ctx);
              goLive(context, LiveKind.marathon, m.id);
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _marathons?.cancel();
    _lost?.cancel();
    FocusManager.instance.removeListener(_onFocusMoved);
    _rail.removeListener(_onRail);
    _rail.dispose();
    _content.dispose();
    for (final n in _railNodes) {
      n.dispose();
    }
    super.dispose();
  }

  void _onRail() => setState(() {});

  Timer? _lost;

  /// The remote must always be on something. Focus can drop to nothing when the page it was
  /// on goes away (a menu change lands on the old page while it fades out, a row reloads):
  /// put it back on the page, or on the menu when the page has nothing to select.
  void _onFocusMoved() {
    final p = FocusManager.instance.primaryFocus;
    if (p != null && p is! FocusScopeNode) return;
    _lost?.cancel();
    _lost = Timer(const Duration(milliseconds: 450), () {
      final p = FocusManager.instance.primaryFocus;
      if (!mounted || (p != null && p is! FocusScopeNode)) return;
      // A player, dialog or sheet on top has its own focus.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (!_focusFirst(_content)) _focusRail();
    });
  }

  /// Open the menu on the current page's entry.
  void _focusRail() {
    final i = _index;
    if (i >= 0 && i < _railNodes.length) {
      _railNodes[i].requestFocus();
    } else {
      _focusFirst(_rail);
    }
  }

  late final _railNodes = [
    for (final t in [..._tvTabs, _tvSettings]) FocusNode(debugLabel: 'rail ${t.label}'),
  ];

  /// Put the remote on the page's first item once it has built.
  void _focusContent({int tries = 40}) {
    Future.delayed(const Duration(milliseconds: 250), () {
      if (!mounted || _rail.hasFocus) return;
      if (!_focusFirst(_content) && tries > 0) _focusContent(tries: tries - 1);
    });
  }

  /// Focus the scope's remembered item, else its first focusable one. False if it has none yet.
  static bool _focusFirst(FocusScopeNode scope) {
    final p = FocusManager.instance.primaryFocus;
    // Already on an item of this area (e.g. an autofocused Play button).
    if (p != null && p is! FocusScopeNode && (p == scope || p.ancestors.contains(scope))) return true;
    // A page that just opened has its own scope: use the newest one, not older pages below it.
    final within = p is FocusScopeNode && p.ancestors.contains(scope) ? p : scope;
    final remembered = within.focusedChild;
    if (remembered != null && remembered is! FocusScopeNode && remembered.context != null) {
      remembered.requestFocus();
      return true;
    }
    final first = within.traversalDescendants.where((n) => n.canRequestFocus && !n.skipTraversal && n is! FocusScopeNode && n.context != null).firstOrNull;
    first?.requestFocus();
    return first != null;
  }

  int get _index {
    final path = widget.path.startsWith('/cinema') ? '/tv' : widget.path;
    if (path.startsWith(_tvSettings.path)) return _tvTabs.length;
    for (var i = _tvTabs.length - 1; i >= 0; i--) {
      final t = _tvTabs[i];
      if (t.path == '/' ? path == '/' : path.startsWith(t.path)) return i;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.path != _shown) {
      _shown = widget.path;
      TvRemote.pageOpened = DateTime.now();
      _focusContent();
    }
    final open = _rail.hasFocus;
    final idx = _index;
    return BackButtonListener(
      onBackButtonPressed: () async {
        if (context.canPop()) return false;
        if (!_rail.hasFocus) {
          _focusRail();
          return true;
        }
        return false;
      },
      child: Scaffold(
        backgroundColor: Hy.bg,
        body: Stack(
          children: [
            Positioned.fill(
              left: _railNarrow,
              child: Actions(
                actions: {DirectionalFocusIntent: _EdgeAction(TraversalDirection.left, _focusRail, rowsIn: _content)},
                // Up/down leave text fields (search, settings), which otherwise keep them and
                // trap the remote.
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.arrowDown): DirectionalFocusIntent(TraversalDirection.down, ignoreTextFields: false),
                    SingleActivator(LogicalKeyboardKey.arrowUp): DirectionalFocusIntent(TraversalDirection.up, ignoreTextFields: false),
                  },
                  child: FocusScope(node: _content, child: widget.child),
                ),
              ),
            ),
            // Dim the page while the menu is open.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: open ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [Color(0xF2000000), Color(0x99000000), Colors.transparent], stops: [0, .35, .7]),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Actions(
                actions: {DirectionalFocusIntent: _EdgeAction(TraversalDirection.right, () => _focusFirst(_content))},
                child: FocusScope(
                  node: _rail,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    width: open ? _railWide : _railNarrow,
                    color: open ? Colors.transparent : const Color(0xE60A0A0A),
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(padding: const EdgeInsets.only(left: 22, bottom: 30), child: open ? const Wordmark(size: 24) : const _Monogram()),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final (i, t) in _tvTabs.indexed)
                                _RailItem(
                                  focusNode: _railNodes[i],
                                  tab: t,
                                  open: open,
                                  selected: i == idx,
                                  onTap: () {
                                    context.go(t.path);
                                    _shown = '';
                                    _content.requestFocus();
                                    _focusContent();
                                  },
                                ),
                            ],
                          ),
                        ),
                        _RailItem(
                          focusNode: _railNodes[_tvTabs.length],
                          tab: _tvSettings,
                          open: open,
                          selected: idx == _tvTabs.length,
                          leading: Container(
                            width: 30,
                            height: 30,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(gradient: Hy.orangeGradient, borderRadius: BorderRadius.circular(6)),
                            child: Text(
                              context.select<AppState, String>((a) => a.userName.isEmpty ? '?' : a.userName[0].toUpperCase()),
                              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                          ),
                          label: context.select<AppState, String>((a) => a.userName.isEmpty ? 'Settings' : '${a.userName} · Settings'),
                          onTap: () {
                            context.go(_tvSettings.path);
                            _shown = '';
                            _content.requestFocus();
                            _focusContent();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Arrow-key move that hands focus to the other area (menu ↔ page) when nothing is left
/// in that direction inside the current one.
class _EdgeAction extends Action<DirectionalFocusIntent> {
  final TraversalDirection edge;
  final VoidCallback onEdge;

  /// Content area: left/right only move along the current row. Without this, running off
  /// the end of a row jumps sideways to whatever is nearest, often in another row.
  final FocusScopeNode? rowsIn;
  _EdgeAction(this.edge, this.onEdge, {this.rowsIn});

  @override
  void invoke(DirectionalFocusIntent intent) {
    final node = primaryFocus;
    if (node == null) return;
    final d = intent.direction;
    final scope = rowsIn;
    if (scope != null && (d == TraversalDirection.left || d == TraversalDirection.right)) {
      final r = node.rect;
      final inRow = scope.traversalDescendants.any((n) {
        if (n == node || !n.canRequestFocus || n.skipTraversal || n is FocusScopeNode || n.context == null) return false;
        final c = n.rect.center;
        return c.dy > r.top && c.dy < r.bottom && (d == TraversalDirection.right ? c.dx > r.center.dx : c.dx < r.center.dx);
      });
      if (!inRow) {
        if (d == edge) onEdge(); // the first tile: on to the menu
        return; // the last tile: stay put
      }
    }
    if (scope != null && (d == TraversalDirection.up || d == TraversalDirection.down)) {
      _lineStep(scope, node, d == TraversalDirection.down);
      return;
    }
    var moved = node.focusInDirection(d);
    if (!moved && scope != null) moved = _intoLine(scope, node, d == TraversalDirection.right);
    if (!moved && d == edge) onEdge();
  }

  /// Left/right to something sitting on the focused item's line but inside its box (the
  /// watched button on an episode), which Flutter's own search doesn't count as beside it.
  static bool _intoLine(FocusScopeNode scope, FocusNode cur, bool right) {
    final r = cur.rect, route = cur.context == null ? null : ModalRoute.of(cur.context!);
    final near = scope.traversalDescendants.where((n) {
      if (identical(n, cur) || !n.canRequestFocus || n.skipTraversal || n is FocusScopeNode || n.context == null) return false;
      if (route != null && ModalRoute.of(n.context!) != route) return false;
      final c = n.rect.center;
      return c.dy > r.top && c.dy < r.bottom && (right ? c.dx > r.center.dx : c.dx < r.center.dx);
    }).toList()..sort((a, b) => (a.rect.center.dx - r.center.dx).abs().compareTo((b.rect.center.dx - r.center.dx).abs()));
    if (near.isEmpty) return false;
    near.first.requestFocus();
    return true;
  }

  /// The page's own vertical scroll: the nearest vertical scrollable that can actually move
  /// (a grid or list inside a page is often fixed and just part of the page).
  static ScrollableState? _pageOf(BuildContext context) {
    var s = Scrollable.maybeOf(context, axis: Axis.vertical);
    while (s != null && s.position.hasContentDimensions && s.position.maxScrollExtent <= 0) {
      final outer = Scrollable.maybeOf(s.context, axis: Axis.vertical);
      if (outer == null) break;
      s = outer;
    }
    return s;
  }

  /// Up/down: the nearest line of things above or below on screen and, in it, the one closest
  /// to straight above or below; brought to the upper part of the screen. Flutter's own search
  /// prefers anything in the same column however far down the page, and stops dead in rows
  /// that are scrolled sideways.
  static void _lineStep(FocusScopeNode scope, FocusNode cur, bool down) {
    final area = scope.rect, at = cur.rect;
    final pad = 40.0;
    // Only the page in front: a title opened from Home has Home still underneath.
    final route = cur.context == null ? null : ModalRoute.of(cur.context!);
    final lines = <(FocusNode, Rect)>[];
    for (final n in scope.traversalDescendants) {
      if (identical(n, cur) || !n.canRequestFocus || n.skipTraversal || n is FocusScopeNode || n.context == null) continue;
      if (n.ancestors.contains(cur) || cur.ancestors.contains(n)) continue;
      if (route != null && ModalRoute.of(n.context!) != route) continue;
      final r = n.rect;
      if (r.isEmpty || r.right < area.left + pad || r.left > area.right - 8) continue; // scrolled away in a row
      if (down ? r.top >= at.center.dy : r.bottom <= at.center.dy) lines.add((n, r));
    }
    final page = cur.context == null ? null : _pageOf(cur.context!)?.position;
    if (lines.isEmpty) {
      // Nothing more to land on: show the rest of the page (or nothing above: stay).
      if (down && page != null) {
        page.animateTo(
          (page.pixels + page.viewportDimension * .6).clamp(0, page.maxScrollExtent),
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    final edge = down ? lines.map((l) => l.$2.top).reduce(min) : lines.map((l) => l.$2.bottom).reduce(max);
    // From something page-wide (a banner, text) a row is entered at its start.
    final x = at.width > area.width * .6 ? area.left : at.center.dx;
    final line = lines.where((l) => down ? l.$2.top < edge + 40 : l.$2.bottom > edge - 40).toList()
      ..sort((a, b) => (a.$2.center.dx - x).abs().compareTo((b.$2.center.dx - x).abs()));
    // Straight above or below wins; where a whole line (an episode) and a small button on it
    // both are, the line: the button is reached with left/right.
    final across = line.where((l) => l.$2.left <= x && l.$2.right >= x).toList()..sort((a, b) => b.$2.width.compareTo(a.$2.width));
    if (across.isNotEmpty) line.insert(0, across.first);
    final next = line.first.$1;
    next.requestFocus();
    // Scroll only the page (not the row the item sits in) to bring it up into view.
    final pageState = _pageOf(next.context!), pagePos = pageState?.position;
    final view = pageState?.context.findRenderObject();
    if (pagePos != null && view is RenderBox && view.attached) {
      final r = line.first.$2, vp = pagePos.viewportDimension;
      final onPage = pagePos.pixels + r.top - view.localToGlobal(Offset.zero).dy; // where it sits on the whole page
      // Near the top of the page (a billboard's buttons): show the page from its top.
      final target = onPage + r.height < vp * .8 ? 0.0 : onPage - vp * (r.height > vp * .6 ? .05 : TvRowAnchor.of(next.context!));
      pagePos.animateTo(
        target.clamp(pagePos.minScrollExtent, pagePos.maxScrollExtent),
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
  }
}

class _Monogram extends StatelessWidget {
  const _Monogram();
  @override
  Widget build(BuildContext context) => ShaderMask(
    shaderCallback: (r) => Hy.orangeGradient.createShader(r),
    child: const Text(
      'H',
      style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, fontStyle: FontStyle.italic, color: Colors.white, height: 1),
    ),
  );
}

class _RailItem extends StatefulWidget {
  final _Tab tab;
  final bool open, selected;
  final VoidCallback onTap;
  final FocusNode focusNode;

  /// In place of the icon (the profile's initial) and the tab's name.
  final Widget? leading;
  final String? label;
  const _RailItem({required this.tab, required this.open, required this.selected, required this.onTap, required this.focusNode, this.leading, this.label});
  @override
  State<_RailItem> createState() => _RailItemState();
}

class _RailItemState extends State<_RailItem> {
  bool _focus = false;
  @override
  Widget build(BuildContext context) {
    final t = widget.tab;
    final color = _focus ? Colors.black : (widget.selected ? Hy.orange : Hy.textDim);
    return FocusableActionDetector(
      focusNode: widget.focusNode,
      onShowFocusHighlight: (v) => setState(() => _focus = v),
      onFocusChange: (v) => setState(() => _focus = v),
      actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => widget.onTap())},
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(color: _focus ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(26)),
          child: UnconstrainedBox(
            alignment: Alignment.centerLeft,
            constrainedAxis: Axis.vertical,
            clipBehavior: Clip.hardEdge,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _railWide - 52),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  widget.leading ?? Icon(widget.selected ? t.activeIcon : t.icon, color: color, size: 24),
                  if (widget.open) ...[
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        widget.label ?? t.label,
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
