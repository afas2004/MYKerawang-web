import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'language_cubit.dart';
import 'l10n/brand_strings.dart';
import 'screens/announcements/announcements_screen.dart';
import 'screens/create_event_screen.dart';
import 'screens/create_listing_screen.dart';
import 'screens/create_announcement_screen.dart';
import 'screens/create_post_screen.dart';
import 'screens/edit_profile_screen.dart';
import 'screens/event_detail_screen.dart';
import 'screens/follow_list_screen.dart';
import 'screens/privacy_policy_screen.dart';
import 'screens/tag_feed_screen.dart';
import 'screens/events/checkin_screens.dart';
import 'screens/events/event_form_screen.dart';
import 'screens/events/form_editor_screen.dart';
import 'screens/events/form_responses_screen.dart';
import 'screens/forms/my_forms_screen.dart';
import 'screens/guest_views.dart';
import 'screens/events_screen.dart';
import 'screens/home_screen.dart';
import 'screens/item_detail_screen.dart';
import 'screens/login_cubit.dart';
import 'screens/login_screen.dart';
import 'screens/main_scaffold.dart';
import 'screens/marketplace_screen.dart';
import 'screens/notification_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/post_detail_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/app_nav.dart';
import 'utils/guest_access.dart';
import 'utils/responsive.dart';
import 'widgets/app_sidebar.dart';
import 'widgets/brand/brand.dart' show AppIllo, BrandEmptyState, KRadius;
import 'screens/admin/moderation_routes.dart';

/// Notifies the router whenever Supabase auth state changes, so the
/// redirect below re-runs on login/logout.
class AuthChangeNotifier extends ChangeNotifier {
  late final StreamSubscription<AuthState> _sub;

  AuthChangeNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final user = data.session?.user;
      if (data.event == AuthChangeEvent.signedIn && user != null) {
        enforceStudentEmailForNewAccount(user);
      }
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

/// The root navigator, for dialogs raised from above the router.
///
/// [SessionWatcher] wraps the router's output, so it has no Navigator in
/// its own context; `showDialog` there would throw. Pushing on this state
/// works from anywhere.
NavigatorState? get rootNavigator => _rootKey.currentState;

final _shellKey = GlobalKey<NavigatorState>();

/// Guest mode: what a logged-out visitor may open (read-only).
/// Browse tabs, detail pages, public profiles, tag feeds and the privacy
/// policy. Everything else — create / edit forms, notifications, saved,
/// settings, own profile (/profile), admin, standing, follower lists —
/// needs an account.
final List<RegExp> _guestPaths = [
  RegExp(r'^/(home|announcements|market|events|search)/?$'),
  RegExp(r'^/(event|item|post|u)/[^/]+/?$'),
  RegExp(r'^/tag/[^/]+/?$'),
  // A shared form shows who made it and a sign-in bar; answering needs an account.
  RegExp(r'^/f/[^/]+/?$'),
  RegExp(r'^/settings/privacy/?$'),
];

/// True when [path] is open to guests.
bool isGuestPath(String path) => _guestPaths.any((r) => r.hasMatch(path));

/// The router's auth gate, as a pure function so it can be tested.
///
/// * Guests stay on guest paths; anything else goes to /login with
///   ?from= so login brings them back.
/// * Signed-in users leave /login for ?from= (or /home).
/// * The OAuth `code` query parameter is dropped from the address bar.
String? authRedirect(Uri uri, {required bool loggedIn}) {
  final path = uri.path;
  final atLogin = path == '/login';

  if (!loggedIn) {
    if (atLogin || isGuestPath(path)) {
      // Strip a stale OAuth code from guest pages too.
      if (!atLogin && uri.queryParameters.containsKey('code')) {
        final query = Map.of(uri.queryParameters)..remove('code');
        return Uri(path: path, queryParameters: query.isEmpty ? null : query)
            .toString();
      }
      return null;
    }
    final query = Map.of(uri.queryParameters)..remove('code');
    return loginPathFor(Uri(
      path: path,
      queryParameters: query.isEmpty ? null : query,
    ).toString());
  }

  // Logged in: leave the login page for wherever the visitor came from
  // (email and Google sign-in both land here), and strip any leftover
  // OAuth query parameters.
  if (atLogin) {
    return safeReturnPath(uri.queryParameters['from']) ?? '/home';
  }
  if (uri.queryParameters.containsKey('code') && path != '/onboarding') {
    return path == '/' ? '/home' : path;
  }
  return null;
}

GoRouter buildRouter() {
  // Pushed pages (details, forms) get their own URL in the address bar:
  // shareable, reload-safe, and what the history-aware back relies on.
  // go_router's default keeps the URL of the page underneath.
  GoRouter.optionURLReflectsImperativeAPIs = true;
  final authNotifier = AuthChangeNotifier();

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/home',
    observers: [OverlayTracker()],
    refreshListenable: authNotifier,

    // Auth gate with guest mode — see [authRedirect].
    redirect: (context, state) => authRedirect(
      state.uri,
      loggedIn: Supabase.instance.client.auth.currentSession != null,
    ),

    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/home'),
      GoRoute(
        path: '/login',
        builder: (context, state) =>
            LoginScreen(
              from: state.uri.queryParameters['from'],
              oauthError: state.uri.queryParameters['error_description'],
            ),
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
            // Each navigator reports its dialogs / sheets / menus, so a
            // browser back closes them before leaving the page.
            observers: [OverlayTracker()],
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(observers: [OverlayTracker()], routes: [
            GoRoute(
              path: '/announcements',
              builder: (context, state) => const AnnouncementsScreen(),
            ),
          ]),
          StatefulShellBranch(observers: [OverlayTracker()], routes: [
            GoRoute(
              path: '/search',
              builder: (context, state) => const SearchScreen(),
            ),
          ]),
          StatefulShellBranch(observers: [OverlayTracker()], routes: [
            GoRoute(
              path: '/market',
              builder: (context, state) => const MarketplaceScreen(),
            ),
          ]),
          StatefulShellBranch(observers: [OverlayTracker()], routes: [
            GoRoute(
              path: '/events',
              builder: (context, state) => const EventsScreen(),
            ),
          ]),
        ],
      ),

      // Own profile: no longer a tab — opened from ProfileAvatarAction.
      // Members only (guests are sent to login by [authRedirect]).
      GoRoute(
        path: '/profile',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) =>
            const DesktopChrome(child: ProfileScreen()),
      ),

      // --- SHAREABLE DETAIL ROUTES ---
      // Pushed above the shell (root navigator) so the browser URL updates.
      // `extra` carries the already-loaded row for instant in-app pushes;
      // deep links / refreshes fall back to fetching by id. Back pops to
      // where you came from; opened cold, back goes to the matching tab
      // (see backFallbackFor). onExit keeps browser history in step.
      GoRoute(
        path: '/item/:id',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) => DesktopChrome(
          // Room for AdaptiveScaffoldBody's two columns on desktop.
          maxWidth: Responsive.detailMaxWidth,
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
        onExit: historyAwareExit,
        builder: (context, state) => DesktopChrome(
          maxWidth: Responsive.detailMaxWidth,
          child: _DetailLoader(
            table: 'events',
            id: state.pathParameters['id']!,
            initial: state.extra as Map<String, dynamic>?,
            build: (data) => EventDetailScreen(event: data),
          ),
        ),
      ),
      GoRoute(
        path: '/event/:id/checkin',
        // The phone-camera fallback: the attendance QR opens this URL.
        // Members only — authRedirect sends guests to login and back.
        builder: (context, state) => CheckinPage(
          eventId: state.pathParameters['id']!,
          token: state.uri.queryParameters['t'],
        ),
      ),
      GoRoute(
        path: '/event/:id/form',
        // Answering: open to guests (they see a sign-in bar). The server
        // decides whether an answer is accepted.
        //
        // onExit is not optional on the web: a pop reported as a new history
        // entry makes the browser's back return to the page you just left,
        // which is how the form "came back by itself".
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) => EventFormScreen(
          eventId: state.pathParameters['id']!,
          formId: state.uri.queryParameters['f'],
        ),
      ),
      GoRoute(
        path: '/event/:id/form/responses',
        // The organiser's report page: S1/S2/S3 and the CSV.
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) => FormResponsesScreen(
          eventId: state.pathParameters['id']!,
          formId: state.uri.queryParameters['f'],
        ),
      ),
      // Standalone forms (anyone's): answer, edit, responses, and the list.
      GoRoute(
        path: '/forms',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) => const MyFormsScreen(),
      ),
      GoRoute(
        path: '/f/:id',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) => EventFormScreen(formId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/f/:id/responses',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) =>
            FormResponsesScreen(formId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/f/:id/edit',
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        builder: (context, state) => FormEditorScreen(formId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/event/:id/form/edit',
        // The KI report survey: a form, so leaving with unsaved input asks
        // first (leaveFormRoute → FormGuard).
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        builder: (context, state) => FormEditorScreen(
          eventId: state.pathParameters['id']!,
          formId: state.uri.queryParameters['f'],
        ),
      ),
      GoRoute(
        path: '/post/:id',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) => DesktopChrome(
          maxWidth: Responsive.detailMaxWidth,
          child: _DetailLoader(
            table: 'posts_public', // anonymity-safe view
            id: state.pathParameters['id']!,
            select: '*',
            initial: state.extra as Map<String, dynamic>?,
            // Logged-out visitors get a read-only view; the full screen
            // assumes a signed-in user for commenting and reporting.
            // Same page for guests: read, share and see comments; actions
            // that need an account prompt sign-in (requireLogin).
            build: (data) => PostDetailScreen(post: data),
          ),
        ),
      ),
      GoRoute(
        path: '/u/:id',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) => DesktopChrome(
          child: isLoggedIn
              ? ProfileScreen(userId: state.pathParameters['id'])
              : GuestProfileScreen(userId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/u/:id/:type(followers|following)',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) => DesktopChrome(
          child: FollowListScreen(
            userId: state.pathParameters['id']!,
            type: state.pathParameters['type']!,
          ),
        ),
      ),
      GoRoute(
        path: '/tag/:tag',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) => DesktopChrome(
          child: TagFeedScreen(tag: state.pathParameters['tag']!),
        ),
      ),

      // --- CREATE / EDIT FORMS ---
      // Full screen on phones, a centred dialog-style page from 600px.
      // onExit asks before discarding unsaved input (close button,
      // Android back, browser back alike). Publishing replaces the form
      // with the new page (completePublish).
      GoRoute(
        path: '/create/post',
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        pageBuilder: (context, state) {
          final extra = state.extra as Map<String, dynamic>? ?? const {};
          return formPage(
            context,
            state,
            CreatePostScreen(
              sharedEvent: extra['sharedEvent'] as Map<String, dynamic>?,
              sharedListing: extra['sharedListing'] as Map<String, dynamic>?,
            ),
          );
        },
      ),
      GoRoute(
        path: '/create/event',
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        pageBuilder: (context, state) =>
            formPage(context, state, const CreateEventScreen()),
      ),
      GoRoute(
        path: '/create/listing',
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        pageBuilder: (context, state) =>
            formPage(context, state, const CreateListingScreen()),
      ),
      GoRoute(
        path: '/post/:id/edit',
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        pageBuilder: (context, state) => formPage(
          context,
          state,
          _DetailLoader(
            table: 'posts_public',
            id: state.pathParameters['id']!,
            initial: state.extra as Map<String, dynamic>?,
            build: (data) => CreatePostScreen(editPost: data),
          ),
        ),
      ),
      // v1.4 announcements: own composer (officers / admins only; the
      // screen checks can_post_announcement and the DB enforces it).
      GoRoute(
        path: '/create/announcement',
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        pageBuilder: (context, state) =>
            formPage(context, state, const CreateAnnouncementScreen()),
      ),
      GoRoute(
        path: '/post/:id/edit-announcement',
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        pageBuilder: (context, state) => formPage(
          context,
          state,
          _DetailLoader(
            table: 'posts_public',
            id: state.pathParameters['id']!,
            initial: state.extra as Map<String, dynamic>?,
            build: (data) => CreateAnnouncementScreen(editPost: data),
          ),
        ),
      ),
      GoRoute(
        path: '/event/:id/edit',
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        pageBuilder: (context, state) => formPage(
          context,
          state,
          _DetailLoader(
            table: 'events',
            id: state.pathParameters['id']!,
            initial: state.extra as Map<String, dynamic>?,
            build: (data) => CreateEventScreen(eventToEdit: data),
          ),
        ),
      ),
      GoRoute(
        path: '/item/:id/edit',
        parentNavigatorKey: _rootKey,
        onExit: leaveFormRoute,
        pageBuilder: (context, state) => formPage(
          context,
          state,
          _DetailLoader(
            table: 'listings',
            id: state.pathParameters['id']!,
            initial: state.extra as Map<String, dynamic>?,
            build: (data) => CreateListingScreen(itemToEdit: data),
          ),
        ),
      ),
      GoRoute(
        path: '/profile/edit',
        parentNavigatorKey: _rootKey,
        // Edit profile keeps its own unsaved-changes prompt; leaving it
        // refreshes the profile (its route result may never arrive on web).
        onExit: (context, state) {
          notifyContentChanged();
          return historyAwareExit(context, state);
        },
        builder: (context, state) =>
            const DesktopChrome(child: EditProfileScreen()),
      ),

      // --- SECONDARY PAGES ---
      GoRoute(
        path: '/settings',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) =>
            const DesktopChrome(child: SettingsScreen()),
      ),
      GoRoute(
        path: '/settings/privacy',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) =>
            const DesktopChrome(child: PrivacyPolicyScreen()),
      ),
      GoRoute(
        path: '/notifications',
        parentNavigatorKey: _rootKey,
        onExit: historyAwareExit,
        builder: (context, state) =>
            const DesktopChrome(child: NotificationScreen()),
      ),

      // --- MODERATION (/admin, /standing) ---
      ...moderationRoutes(_rootKey).map(_withHistoryAwareExit),
      ...clubRoutes(_rootKey).map(_withHistoryAwareExit),
    ],

    // The lost page: the kite's string snapped.
    errorBuilder: (context, state) => Scaffold(
      body: Semantics(
        label: context.l10n.pageNotFound,
        child: BrandEmptyState(
          illo: AppIllo.notFound,
          title: context.l10n.brand.lostTitle,
          message: context.l10n.brand.lostBody,
          actionLabel: context.l10n.goHome,
          onAction: () => context.go('/home'),
        ),
      ),
    ),
  );
}

/// Gives a route from elsewhere (moderation) the history-aware onExit.
RouteBase _withHistoryAwareExit(RouteBase route) {
  if (route is! GoRoute || route.onExit != null) return route;
  return GoRoute(
    path: route.path,
    name: route.name,
    builder: route.builder,
    pageBuilder: route.pageBuilder,
    parentNavigatorKey: route.parentNavigatorKey,
    redirect: route.redirect,
    onExit: historyAwareExit,
    routes: route.routes,
  );
}

/// Page for a create / edit form: full screen on phones; from 600px a
/// centred dialog-style page over the current screen.
Page<void> formPage(BuildContext context, GoRouterState state, Widget child) {
  final wide = MediaQuery.sizeOf(context).width >= Responsive.mediumBreakpoint;
  if (!wide) {
    return MaterialPage<void>(key: state.pageKey, fullscreenDialog: true, child: child);
  }
  return CustomTransitionPage<void>(
    key: state.pageKey,
    opaque: false,
    // Not dismissed by a stray click outside: that would throw input away.
    barrierDismissible: false,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 150),
    child: _FormDialogFrame(child: child),
    transitionsBuilder: (context, animation, _, child) {
      final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      if (reduce) return child;
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
            scale: Tween(begin: 0.97, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

class _FormDialogFrame extends StatelessWidget {
  final Widget child;
  const _FormDialogFrame({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 900),
            child: Material(
              clipBehavior: Clip.antiAlias,
              elevation: 8,
              shape: const RoundedRectangleBorder(borderRadius: KRadius.cut),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
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
                  Text(context.l10n.contentUnavailable),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: Text(context.l10n.goHome),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
