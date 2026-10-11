import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/api.dart';
import 'core/models.dart';
import 'core/theme.dart';
import 'core/realtime.dart';
import 'features/auth/auth_cubit.dart';
import 'features/auth/auth_pages.dart';
import 'features/feed/feed_pages.dart';
import 'features/feed/post_engagement_cubit.dart';
import 'features/clans/clan_pages.dart';
import 'features/gatherings/gathering_pages.dart';
import 'features/chat/chat_pages.dart';
import 'features/shop/shop_pages.dart';
import 'features/account/account_pages.dart';
import 'features/account/settings_pages.dart';
import 'shared/widgets.dart';

class TwonApp extends StatefulWidget {
  const TwonApp({super.key, required this.api, required this.preferences});
  final DioRepository api;
  final SharedPreferences preferences;
  @override
  State<TwonApp> createState() => _TwonAppState();
}

class _TwonAppState extends State<TwonApp> with WidgetsBindingObserver {
  late final auth = AuthCubit(widget.api);
  late final theme = ThemeCubit(widget.preferences);
  late final engagement = PostEngagementCubit(widget.api);
  StreamSubscription<AuthState>? engagementSession;
  String engagementUser = "";
  late final realtime = RealtimeService(widget.api);
  late final refresh = _AuthRefresh(auth);
  late final router = _router(auth, refresh);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    engagementSession = auth.stream.listen((state) {
      final user = entityId(state.user);
      if (user != engagementUser) {
        engagementUser = user;
        engagement.reset();
      }
    });
    auth.bootstrap();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      realtime.resume();
      if (auth.state.status == AuthStatus.authenticated) auth.refreshProfile();
    } else {
      realtime.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    router.dispose();
    refresh.dispose();
    engagementSession?.cancel();
    engagement.close();
    auth.close();
    theme.close();
    realtime.dispose();
    widget.api.dio.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => MultiRepositoryProvider(
    providers: [
      RepositoryProvider<AppRepository>.value(value: widget.api),
      RepositoryProvider<SharedPreferences>.value(value: widget.preferences),
      RepositoryProvider<RealtimeService>.value(value: realtime),
    ],
    child: MultiBlocProvider(
      providers: [
        BlocProvider<AuthCubit>.value(value: auth),
        BlocProvider<ThemeCubit>.value(value: theme),
        BlocProvider<PostEngagementCubit>.value(value: engagement),
      ],
      child: BlocBuilder<ThemeCubit, ThemeMode>(
        builder: (_, mode) => MaterialApp.router(
          title: 'TWON',
          debugShowCheckedModeBanner: false,
          theme: twonTheme(Brightness.light),
          darkTheme: twonTheme(Brightness.dark),
          themeMode: mode,
          routerConfig: router,
        ),
      ),
    ),
  );
}

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(AuthCubit auth) {
    subscription = auth.stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<AuthState> subscription;
  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }
}

GoRouter _router(AuthCubit auth, Listenable refresh) {
  final createPostKey = GlobalKey<PostEditorState>();
  final editPostKey = GlobalKey<PostEditorState>();
  return GoRouter(
    initialLocation: '/feed',
    refreshListenable: refresh,
    redirect: (c, s) {
      final status = auth.state.status;
      if (status == AuthStatus.starting) {
        return s.uri.path == '/starting' ? null : '/starting';
      }
      final login = s.uri.path.startsWith('/auth');
      if (status != AuthStatus.authenticated) {
        return login ? null : '/auth/login';
      }
      return login || s.uri.path == '/starting' ? '/feed' : null;
    },
    errorBuilder: (c, s) => Scaffold(
      appBar: AppBar(title: const Text('TWON')),
      body: ErrorPanel('This page is unavailable.', retry: () => c.go('/feed')),
    ),
    routes: [
      GoRoute(
        path: '/starting',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(
        path: '/auth/:mode',
        builder: (_, s) => AuthPage(
          mode: s.pathParameters['mode']!,
          email: s.uri.queryParameters['email'] ?? '',
          token: s.uri.queryParameters['token'] ?? '',
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (c, s, shell) =>
            AppShell(path: s.uri.path, navigationShell: shell, child: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/feed', builder: (_, _) => const FeedPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/clans', builder: (_, _) => const ClansPage()),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/messages',
                builder: (_, _) => const ConversationsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/events',
                builder: (_, _) => const GatheringsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(path: '/merch', builder: (_, _) => const ShopPage()),
            ],
          ),
        ],
      ),
      ShellRoute(
        builder: (c, s, child) => AppShell(path: s.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/posts/new',
            onExit: (c, s) => auth.state.status != AuthStatus.authenticated
                ? true
                : createPostKey.currentState?.canLeave() ?? true,
            builder: (_, s) => PostEditor(
              key: createPostKey,
              clanId: s.uri.queryParameters['clan'],
              startPhotos: s.uri.queryParameters['photos'] == 'true',
              startAnonymous: s.uri.queryParameters['anonymous'] == 'true',
            ),
          ),
          GoRoute(
            path: '/posts/:id/edit',
            onExit: (c, s) => auth.state.status != AuthStatus.authenticated
                ? true
                : editPostKey.currentState?.canLeave() ?? true,
            builder: (_, s) => PostEditor(
              key: editPostKey,
              id: s.pathParameters['id'],
              initial: asJson(s.extra),
            ),
          ),
          GoRoute(
            path: '/posts/:id',
            builder: (_, s) => PostDetailPage(s.pathParameters['id']!),
          ),
          GoRoute(path: '/clans/new', builder: (_, _) => const ClanEditor()),
          GoRoute(
            path: '/clans/:id/feed',
            builder: (_, s) => ClanFeedPage(s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/clans/:id/edit',
            builder: (_, s) => ClanEditor(
              id: s.pathParameters['id'],
              initial: asJson(s.extra),
            ),
          ),
          GoRoute(
            path: '/clans/:id/members',
            builder: (_, s) => ClanMembersPage(
              s.pathParameters['id']!,
              membership: asJson(s.extra),
            ),
          ),
          GoRoute(
            path: '/clans/:id/requests',
            builder: (_, s) => ClanRequestsPage(s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/clans/:id/promotions',
            builder: (_, s) =>
                ClanRequestsPage(s.pathParameters['id']!, promotions: true),
          ),
          GoRoute(
            path: '/clans/:id/invite',
            builder: (_, s) =>
                ClanActionPage(s.pathParameters['id']!, 'invite'),
          ),
          GoRoute(
            path: '/clans/:id/broadcast',
            builder: (_, s) =>
                ClanActionPage(s.pathParameters['id']!, 'broadcast'),
          ),
          GoRoute(
            path: '/clans/:id',
            builder: (_, s) => ClanPage(s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/events/new',
            builder: (_, _) => const GatheringEditor(),
          ),
          GoRoute(
            path: '/events/:id/edit',
            builder: (_, s) => GatheringEditor(
              id: s.pathParameters['id'],
              initial: asJson(s.extra),
            ),
          ),
          GoRoute(
            path: '/events/:id',
            builder: (_, s) => GatheringPage(s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/messages/new',
            builder: (_, _) => const NewConversationPage(),
          ),
          GoRoute(
            path: '/messages/:id',
            builder: (_, s) => ChatPage(
              s.pathParameters['id']!,
              conversation: asJson(s.extra),
            ),
          ),
          GoRoute(path: '/orders', builder: (_, _) => const OrdersPage()),
          GoRoute(path: '/lookbook', builder: (_, _) => const LookbookPage()),
          GoRoute(
            path: '/lookbook/new',
            builder: (_, _) => const LookbookEditor(),
          ),
          GoRoute(
            path: '/profile/edit',
            builder: (_, s) => ProfileEditor(initial: asJson(s.extra)),
          ),
          GoRoute(path: '/profile', builder: (_, _) => const ProfilePage()),
          GoRoute(
            path: '/members/:handle',
            builder: (_, s) => ProfilePage(handle: s.pathParameters['handle']),
          ),
          GoRoute(
            path: '/members/:id/posts',
            builder: (_, s) => ProfilePostsPage(s.pathParameters['id']!),
          ),
          GoRoute(path: '/search', builder: (_, _) => const SearchPage()),
          GoRoute(
            path: '/notifications',
            builder: (_, _) => const NotificationsPage(),
          ),
          GoRoute(
            path: '/verification',
            builder: (_, _) => const VerificationPage(),
          ),
          GoRoute(path: '/support', builder: (_, _) => const SupportPage()),
          GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
          GoRoute(
            path: '/settings/preferences',
            builder: (_, _) => const PreferencesPage(),
          ),
          GoRoute(
            path: '/settings/password',
            builder: (_, _) => const PasswordPage(),
          ),
          GoRoute(
            path: '/settings/2fa',
            builder: (_, _) => const TwoFactorPage(),
          ),
          GoRoute(
            path: '/settings/sessions',
            builder: (_, _) => const SessionsPage(),
          ),
          GoRoute(
            path: '/settings/deletion',
            builder: (_, _) => const DeletionPage(),
          ),
        ],
      ),
    ],
  );
}

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.path,
    required this.child,
    this.navigationShell,
  });
  final String path;
  final Widget child;
  final StatefulNavigationShell? navigationShell;
  static const destinations = [
    ('/feed', 'Home', Icons.home_outlined, Icons.home_rounded),
    ('/clans', 'Clans', Icons.groups_outlined, Icons.groups_rounded),
    (
      '/messages',
      'Chat',
      Icons.chat_bubble_outline_rounded,
      Icons.chat_bubble_rounded,
    ),
    ('/events', 'Events', Icons.event_outlined, Icons.event_rounded),
    ('/merch', 'Gear', Icons.shopping_bag_outlined, Icons.shopping_bag_rounded),
  ];

  String get title => switch (path) {
    '/clans' => 'Clans',
    '/messages' => 'Pack Chat',
    '/events' => 'Gatherings',
    '/merch' => 'Pack Gear',
    _ => '',
  };

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    final primary = navigationShell != null;
    final titledPrimary = primary && path != '/feed' && title.isNotEmpty;
    final postEditor =
        path == '/posts/new' || RegExp(r'^/posts/[^/]+/edit$').hasMatch(path);
    if (postEditor) return Scaffold(body: SafeArea(child: child));

    return Scaffold(
      appBar: AppBar(
        leading: !primary && c.canPop()
            ? BackButton(onPressed: () => c.pop())
            : null,
        titleSpacing: titledPrimary ? 16 : 0,
        title: titledPrimary
            ? Text(title, overflow: TextOverflow.ellipsis)
            : const BrandWordmark(width: 104),
        actions: [
          IconButton(
            tooltip: path == '/messages' ? 'Search chats' : 'Find members',
            onPressed: () => path == '/messages'
                ? searchConversations(c)
                : c.push('/search'),
            icon: const Icon(Icons.search_rounded, size: 22),
          ),
          if (path != '/messages')
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => c.push('/notifications'),
              icon: const Icon(Icons.notifications_none_rounded, size: 23),
            ),
          if (path != '/messages')
            IconButton(
              tooltip: 'Settings',
              onPressed: () => c.push('/settings'),
              icon: const Icon(Icons.settings_outlined, size: 22),
            ),
          const SizedBox(width: 6),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            height: 1,
            color: scheme.outlineVariant.withValues(alpha: .22),
          ),
        ),
      ),
      floatingActionButton: path == '/messages'
          ? FloatingActionButton(
              tooltip: 'New message',
              backgroundColor: scheme.primary,
              foregroundColor: scheme.onPrimary,
              onPressed: () => c.push('/messages/new'),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      drawer: TwonDrawer(path: path),
      body: SafeArea(top: false, bottom: !primary, child: child),
      bottomNavigationBar: primary
          ? SocialBottomBar(
              selectedIndex: navigationShell!.currentIndex,
              onSelect: (index) {
                HapticFeedback.selectionClick();
                navigationShell!.goBranch(index);
              },
            )
          : null,
    );
  }
}

class SocialBottomBar extends StatelessWidget {
  const SocialBottomBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;

  /// Fixed so the sliding pill has a stable track to travel along; the tab
  /// content is laid out to fit exactly this height.
  static const double _trackHeight = 54;

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(c);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 340);
    final curve = reduceMotion ? Curves.linear : Curves.easeOutCubic;
    // A touch of overshoot makes the pill feel like it is being flicked
    // rather than teleported, but only when motion is welcome.
    final spring = reduceMotion ? Curves.linear : Curves.easeOutBack;

    final count = AppShell.destinations.length;
    // -1..1 across the track, so each tab centre maps to a slot.
    final slotAlignment = (count - 1) == 0
        ? 0.0
        : (selectedIndex / (count - 1)) * 2 - 1;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: .45),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: Theme.of(c).brightness == Brightness.dark
                      ? 0.15
                      : 0.04,
                ),
                blurRadius: 18,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: SizedBox(
            height: _trackHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // One pill that slides across the whole bar, instead of five
                // independent backgrounds fading in place.
                AnimatedAlign(
                  duration: duration,
                  curve: spring,
                  alignment: Alignment(slotAlignment, 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / count,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: List.generate(count, (i) {
                    final item = AppShell.destinations[i];
                    final selected = i == selectedIndex;
                    return Expanded(
                      child: Semantics(
                        label: '${item.$2} tab',
                        button: true,
                        selected: selected,
                        child: Tooltip(
                          message: item.$2,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: ValueKey('tab-${item.$1}'),
                              borderRadius: BorderRadius.circular(20),
                              onTap: () {
                                // Re-tapping the live tab is a no-op rather
                                // than a re-navigation. The haptic lives in
                                // AppShell, which owns the branch switching.
                                if (selected) return;
                                onSelect(i);
                              },
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  AnimatedScale(
                                    scale: selected ? 1.14 : 1,
                                    duration: duration,
                                    curve: spring,
                                    child: Icon(
                                      selected ? item.$4 : item.$3,
                                      size: 23,
                                      color: selected
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  // AnimatedDefaultTextStyle so the weight and
                                  // colour cross-fade instead of snapping.
                                  AnimatedDefaultTextStyle(
                                    duration: duration,
                                    curve: curve,
                                    style: TextStyle(
                                      fontSize: 10,
                                      height: 1.1,
                                      fontWeight: selected
                                          ? FontWeight.w800
                                          : FontWeight.w500,
                                      color: selected
                                          ? scheme.primary
                                          : scheme.onSurfaceVariant,
                                    ),
                                    child: Text(
                                      item.$2,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TwonDrawer extends StatefulWidget {
  const TwonDrawer({super.key, required this.path});
  final String path;
  @override
  State<TwonDrawer> createState() => _TwonDrawerState();
}

class _TwonDrawerState extends State<TwonDrawer>
    with SingleTickerProviderStateMixin {
  /// One ticker drives the whole cascade: each row animates its own slice of
  /// this controller rather than owning a separate animation.
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Read here, not initState: MediaQuery is inherited and cannot be looked
    // up while this element is still building.
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
    } else {
      _reveal.forward();
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  /// Fades and slides one row in, offset by its position so the drawer
  /// cascades instead of appearing all at once.
  Widget _enter(int index, Widget child) {
    final start = (index * 0.05).clamp(0.0, 0.4);
    final curve = CurvedAnimation(
      parent: _reveal,
      curve: Interval(
        start,
        (start + 0.6).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic,
      ),
    );
    return AnimatedBuilder(
      animation: curve,
      child: child,
      builder: (context, kid) => Opacity(
        opacity: curve.value,
        child: Transform.translate(
          offset: Offset(-20 * (1 - curve.value), 0),
          child: kid,
        ),
      ),
    );
  }

  void navigate(BuildContext c, String target) {
    Navigator.pop(c);
    if (widget.path == target) return;
    if (AppShell.destinations.any((d) => d.$1 == target)) {
      c.go(target);
    } else {
      c.push(target);
    }
  }

  @override
  Widget build(BuildContext c) {
    final scheme = Theme.of(c).colorScheme;
    // Position counter for the cascade, consumed in build order.
    var step = 0;
    Widget enter(Widget child) => _enter(step++, child);

    return Drawer(
      width: MediaQuery.sizeOf(c).width.clamp(0, 350) - 20,
      backgroundColor: Theme.of(c).scaffoldBackgroundColor,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            enter(
              Row(
                children: [
                  const Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: BrandWordmark(width: 112),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close menu',
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            enter(
              BlocBuilder<AuthCubit, AuthState>(
                builder: (_, s) => Material(
                  color: scheme.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: () => navigate(c, '/profile'),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          MemberAvatar(s.user ?? {}, radius: 27),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${s.user?['fullName'] ?? 'Pack member'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '@${s.user?['handle'] ?? ''}',
                                  style: TextStyle(
                                    color: scheme.onSurfaceVariant,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            enter(_label(c, 'Community')),
            for (final d in AppShell.destinations.where(
              (d) => d.$1 != '/merch',
            ))
              enter(
                _item(
                  c,
                  d.$1,
                  d.$2 == 'Home'
                      ? 'Feed'
                      : d.$2 == 'Chat'
                      ? 'Messages'
                      : d.$2 == 'Events'
                      ? 'Gatherings'
                      : d.$2,
                  d.$3,
                ),
              ),
            enter(
              _item(
                c,
                '/notifications',
                'Notifications',
                Icons.notifications_none_rounded,
              ),
            ),
            const SizedBox(height: 14),
            enter(_label(c, 'Discover')),
            enter(
              _group(c, 'Pack Gear', Icons.shopping_bag_outlined, [
                ('/merch', 'Shop & basket', Icons.storefront_outlined),
                ('/orders', 'My orders', Icons.receipt_long_outlined),
                ('/lookbook', 'Lookbook', Icons.photo_library_outlined),
              ]),
            ),
            const SizedBox(height: 14),
            enter(_label(c, 'Account')),
            enter(
              _group(c, 'Settings & privacy', Icons.settings_outlined, [
                ('/settings', 'All settings', Icons.tune_rounded),
                (
                  '/settings/preferences',
                  'Notifications & privacy',
                  Icons.shield_outlined,
                ),
                ('/settings/password', 'Password', Icons.lock_outline_rounded),
                (
                  '/settings/2fa',
                  'Two-step verification',
                  Icons.verified_user_outlined,
                ),
                (
                  '/settings/sessions',
                  'Signed-in devices',
                  Icons.devices_outlined,
                ),
              ]),
            ),
            enter(
              _item(
                c,
                '/verification',
                'Identity verification',
                Icons.verified_outlined,
              ),
            ),
            enter(
              _item(
                c,
                '/support',
                'Help & support',
                Icons.support_agent_rounded,
              ),
            ),
            const SizedBox(height: 20),
            enter(
              ActionButton(
                label: 'Sign out',
                icon: Icons.logout_rounded,
                tonal: true,
                confirmation: 'Sign out of this device?',
                action: () => c.read<AuthCubit>().logout(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext c, String label) => Padding(
    padding: const EdgeInsets.only(left: 12, bottom: 8),
    child: Text(
      label,
      style: TextStyle(
        color: Theme.of(c).colorScheme.onSurfaceVariant,
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: .3,
      ),
    ),
  );
  Widget _item(
    BuildContext c,
    String target,
    String label,
    IconData icon,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: ListTile(
      minTileHeight: 52,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      selected: widget.path == target,
      selectedTileColor: Theme.of(c).colorScheme.primary.withValues(alpha: .12),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Theme.of(
            c,
          ).colorScheme.surfaceContainer.withValues(alpha: .65),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 20),
      ),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      onTap: () => navigate(c, target),
    ),
  );
  Widget _group(
    BuildContext c,
    String title,
    IconData icon,
    List<(String, String, IconData)> entries,
  ) => Theme(
    data: Theme.of(c).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      collapsedShape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      backgroundColor: Theme.of(c).colorScheme.surface,
      collapsedBackgroundColor: Theme.of(c).colorScheme.surface,
      leading: Icon(icon, size: 23),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
      ),
      initiallyExpanded: entries.any((e) => widget.path == e.$1),
      children: entries
          .map(
            (d) => Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _item(c, d.$1, d.$2, d.$3),
            ),
          )
          .toList(),
    ),
  );
}
