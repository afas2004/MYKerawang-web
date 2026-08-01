import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/event_detail_screen.dart';
import 'screens/events_screen.dart';
import 'screens/home_screen.dart';
import 'screens/item_detail_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_scaffold.dart';
import 'screens/marketplace_screen.dart';
import 'screens/notification_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/post_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'widgets/app_sidebar.dart';

/// Notifies the router whenever Supabase auth state changes, so the
/// redirect below re-runs on login/logout.
class AuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  AuthChangeNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((_) {
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() {
  final authNotifier = AuthChangeNotifier();

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    refreshListenable: authNotifier,

    // Auth gate. Also drops the OAuth "?code=..." from the address bar,
    // because redirecting rewrites the location without the query.
    redirect: (context, state) {
      final loggedIn = Supabase.instance.client.auth.currentSession != null;
      final path = state.uri.path;
      final atLogin = path == '/login';
      final atOnboarding = path == '/onboarding';

      if (!loggedIn) return atLogin ? null : '/login';

      // Logged in: bounce away from the login page, and strip any
      // leftover OAuth query parameters.
      if (atLogin) return '/home';
      if (state.uri.queryParameters.containsKey('code') && !atOnboarding) {
        return path == '/' ? '/home' : path;
      }
      return null;
    },

    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/home'),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),

      // --- MAIN TABS (state preserved per branch, like IndexedStack) ---
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainScaffold(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: _shellKey,
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/market',
              builder: (context, state) => const MarketplaceScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/events',
              builder: (context, state) => const EventsScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/profile',
              builder: (context, state) => const ProfileScreen(),
            ),
          ]),
        ],
      ),

      // --- SHAREABLE DETAIL ROUTES ---
      // `extra` carries the already-loaded row for instant in-app pushes;
      // deep links / refreshes fall back to fetching by id.
      GoRoute(
        path: '/item/:id',
        // Push onto the root navigator so the browser URL updates
        // (inside a shell branch it would stay on the tab's URL).
        parentNavigatorKey: _rootKey,
        builder: (context, state) => DesktopChrome(
          child: _DetailLoader(
            table: 'listings',
            id: state.pathParameters['id']!,
            initial: state.extra as Map<String, dynamic>?,
            build: (data) => ItemDetailScreen(item: data),
          ),
        ),
      ),
      GoRoute(
        path: '/event/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => DesktopChrome(
          child: _DetailLoader(
            table: 'events',
            id: state.pathParameters['id']!,
            initial: state.extra as Map<String, dynamic>?,
            build: (data) => EventDetailScreen(event: data),
          ),
        ),
      ),
      GoRoute(
        path: '/post/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => DesktopChrome(
          child: _DetailLoader(
            table: 'posts_public', // anonymity-safe view
            id: state.pathParameters['id']!,
            select: '*',
            initial: state.extra as Map<String, dynamic>?,
            build: (data) => PostDetailScreen(post: data),
          ),
        ),
      ),
      GoRoute(
        path: '/u/:id',
        parentNavigatorKey: _rootKey,
        builder: (context, state) => DesktopChrome(
          child: ProfileScreen(userId: state.pathParameters['id']),
        ),
      ),

      // --- SECONDARY PAGES ---
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            const DesktopChrome(child: SettingsScreen()),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootKey,
        builder: (context, state) =>
            const DesktopChrome(child: NotificationScreen()),
      ),
    ],

    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.explore_off_outlined, size: 48),
            const SizedBox(height: 12),
            const Text("Page not found"),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/home'),
              child: const Text("Go home"),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Renders a detail screen from `extra` when available (instant),
/// otherwise fetches the row by id — which is what makes deep links,
/// refreshes and shared URLs work.
class _DetailLoader extends StatefulWidget {
  final String table;
  final String id;
  final String select;
  final Map<String, dynamic>? initial;
  final Widget Function(Map<String, dynamic>) build;

  const _DetailLoader({
    required this.table,
    required this.id,
    required this.initial,
    required this.build,
    this.select = '*',
  });

  @override
  State<_DetailLoader> createState() => _DetailLoaderState();
}

class _DetailLoaderState extends State<_DetailLoader> {
  Map<String, dynamic>? _data;
  bool _notFound = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initial;
    if (_data == null) _fetch();
  }

  Future<void> _fetch() async {
    try {
      final row = await Supabase.instance.client
          .from(widget.table)
          .select(widget.select)
          .eq('id', widget.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _data = row;
        _notFound = row == null;
      });
    } catch (_) {
      if (mounted) setState(() => _notFound = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_data != null) return widget.build(_data!);

    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: _notFound
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search_off, size: 48),
                  const SizedBox(height: 12),
                  const Text("This content is no longer available"),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text("Go home"),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
