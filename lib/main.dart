import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'theme_cubit.dart';
import 'theme/app_themes.dart';
import 'language_cubit.dart';
import 'router.dart';
// --- IMPORT YOUR SERVICES ---
import 'services/notification_service.dart';
import 'services/category_service.dart';
import 'services/club_service.dart';
import 'services/admin_unlock.dart';
import 'services/known_accounts.dart';
import 'services/saved_items.dart';
import 'services/unread_notifications.dart';
import 'services/update_service.dart';
import 'services/art_credits.dart';
import 'widgets/update_banner.dart';
import 'widgets/brand/k_ground.dart';
import 'l10n/account_strings.dart';
import 'l10n/app_strings.dart';
import 'utils/responsive.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'screens/profile_cubit.dart';
import 'screens/search_screen.dart';
import 'screens/login_cubit.dart';
import 'utils/realtime_gate.dart';

/// Lets mouse users drag-scroll lists (like touch), on top of the wheel.
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
      };
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clean URLs on web (/market instead of /#/market). Firebase Hosting
  // rewrites all paths to index.html, so deep links resolve correctly.
  usePathUrlStrategy();

  // 1. Initialize Supabase
  //
  // Publishable key, not the legacy anon JWT. It is safe in a browser:
  // it only ever acts as `anon` and every table is behind RLS. The legacy
  // service_role key leaked into this repo's history, so the project
  // moves off JWT-based API keys entirely.
  await Supabase.initialize(
    url: 'https://zxjuqpqzyzmegdjttzyz.supabase.co',
    anonKey: 'sb_publishable_REqYNPrrJEIgmEjZjrJhtg_1JrLn_yO',
  );

  await NotificationService.init();

  // Warm the category cache so filter chips can render labels without an
  // await. Falls back to the bundled seeds; never throws.
  CategoryService.warm();

  // The Search tab's "All" results include a Clubs section; the hook is
  // optional so SearchScreen keeps working without the clubs feature.
  SearchScreen.clubSource = ClubService.searchRows;

  // Web: poll for newer deploys so phones don't sit on a stale build.
  UpdateService.instance.start();

  // Credit the bundled illustrations on the licences page.
  registerArtCredits();

  // The fonts first, behind the splash, so no text is measured with a
  // stand-in font.
  await preloadThemeFonts();

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    // 1. Initialize ALL Cubits here (Global State)
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => ProfileCubit()),
        BlocProvider(create: (context) => ThemeCubit()),
        BlocProvider(create: (context) => LanguageCubit()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: 'MYKerawang',
            scrollBehavior: AppScrollBehavior(),
            routerConfig: _router,

            // Session side effects (onboarding redirect, notification
            // stream) above every route. No mid-band clamp: MainScaffold
            // has a real medium (600–899) layout.
            builder: (context, child) => SessionWatcher(
              child: UpdateBanner(
                // The one ground behind every page (doodle wallpaper).
                child: KGround(
                  child: ResponsiveShell(clampMidBand: false, child: child!),
                ),
              ),
            ),

            // 3. Named theme (Kampus Bold / Istana Modern / Songket Noir)
            theme: buildAppTheme(themeState.appTheme),
          );
        },
      ),
    );
  }
}

/// Session side effects that used to live in AuthGate: send new users to
/// onboarding, request notification permission on fresh sign-in, and keep
/// the realtime notification stream running.
class SessionWatcher extends StatefulWidget {
  final Widget child;
  const SessionWatcher({super.key, required this.child});

  @override
  State<SessionWatcher> createState() => _SessionWatcherState();
}

class _SessionWatcherState extends State<SessionWatcher> {
  late final StreamSubscription<AuthState> _authSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _notificationSubscription;
  String? _liveUserId;
  Object? _lastShownId;

  @override
  void initState() {
    super.initState();

    // Handle a session that already exists at startup.
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      KnownAccounts.remember(session.user);
      _checkUserProfile(session.user.id);
      SavedItems.instance.start(session.user.id);
      _syncRealtime(null, session);
    }

    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final event = data.event;

      if (session == null) {
        _syncRealtime(event, null);
        SavedItems.instance.stop();
        AdminUnlock.instance.reset();
        return;
      }

      // No-ops for the same user; swap state on an account switch.
      SavedItems.instance.start(session.user.id);
      _syncRealtime(event, session);

      if (event == AuthChangeEvent.signedIn) {
        NotificationService.requestPermission();
        // Record every account; only warn once they are past onboarding.
        KnownAccounts.remember(session.user);
        _checkUserProfile(session.user.id).then((needsOnboarding) {
          if (!needsOnboarding) _warnOtherAccount(session.user);
        });
      }
    });
  }

  /// New users (no username yet) go to onboarding.
  ///
  /// Returns true when onboarding was started, so the caller can skip the
  /// duplicate-account prompt (a brand-new account is still being set up).
  Future<bool> _checkUserProfile(String userId) async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .maybeSingle();

      final needsOnboarding = data == null || data['username'] == null;
      if (needsOnboarding && mounted) {
        // Defer so the router is ready before we navigate.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) GoRouter.of(context).go('/onboarding');
        });
      }
      return needsOnboarding;
    } catch (e) {
      debugPrint("Profile check error: $e");
      // Fail open — let them into the app.
      return false;
    }
  }

  /// One account per person is the goal; two accounts on one device is
  /// the usual way that breaks. Warn once, never block.
  Future<void> _warnOtherAccount(User user) async {
    try {
      final others = await KnownAccounts.others(user.id);
      if (others.isEmpty) return;
      if (await KnownAccounts.hasBeenAsked(user.id)) return;
      final nav = rootNavigator;
      if (nav == null || !mounted) return;
      final other = others.first;
      await KnownAccounts.markAsked(user.id);
      if (nav.mounted) {
        await nav.push(DialogRoute<void>(
          context: nav.context,
          builder: (ctx) => _OtherAccountDialog(other: other),
        ));
      }
    } catch (e) {
      debugPrint("Other-account check failed: $e");
    }
  }

  /// Joins, rejoins or leaves the live channels for [session] — never
  /// with an expired token (see [realtimeStepFor]).
  void _syncRealtime(AuthChangeEvent? event, Session? session) {
    final step = realtimeStepFor(
      event,
      signedIn: session != null,
      expired: session?.isExpired ?? false,
      live: session != null && _liveUserId == session.user.id,
    );
    switch (step) {
      case RealtimeStep.stop:
        _notificationSubscription?.cancel();
        _notificationSubscription = null;
        _liveUserId = null;
        UnreadNotifications.instance.stop();
      case RealtimeStep.start:
        _liveUserId = session!.user.id;
        _startNotificationStream(session.user.id);
        UnreadNotifications.instance.start(session.user.id, rejoin: true);
      case RealtimeStep.wait:
        debugPrint("🔔 Notifications wait for a token refresh");
      case RealtimeStep.keep:
        break;
    }
  }

  void _startNotificationStream(String userId) {
    _notificationSubscription?.cancel();
    debugPrint("🔔 Notification Listener STARTED for $userId");

    _notificationSubscription = Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        // Only the newest row is used — don't pull the whole history.
        .order('created_at', ascending: false)
        .limit(1)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isEmpty) return;
          final latest = data.first;
          // A rejoin re-reads the newest row; don't pop it up twice.
          if (latest['id'] == _lastShownId) return;

          // Timezone Fix
          final created = DateTime.parse(latest['created_at']).toUtc();
          final now = DateTime.now().toUtc();
          final difference = now.difference(created).inSeconds.abs();

          if (difference < 30) {
            _lastShownId = latest['id'];
            NotificationService.showNotification(
              latest['title'],
              latest['message'] ?? latest['body'] ?? context.l10nRead.notifications,
            );
          }
        }, onError: (Object e) {
          // Without this a channel error surfaces as an uncaught error. The
          // next token refresh joins again.
          debugPrint("🔔 Notification stream error: $e");
        });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _notificationSubscription?.cancel();
    UnreadNotifications.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "This device has signed in as …" — informational, never blocking.
/// Switching signs out and pre-fills the login form; it cannot sign in for
/// them (no password, and Google needs the account picker).
class _OtherAccountDialog extends StatelessWidget {
  final KnownAccount other;
  const _OtherAccountDialog({required this.other});

  @override
  Widget build(BuildContext context) {
    final a = context.l10n.account;
    return AlertDialog(
      title: Text(a.otherAccountTitle),
      content: Text(a.otherAccountBody.fill([other.label])),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(a.otherAccountStay),
        ),
        FilledButton(
          onPressed: () async {
            final email = other.email;
            Navigator.pop(context);
            if (email.isNotEmpty) pendingLoginEmail.value = email;
            await Supabase.instance.client.auth.signOut();
          },
          child: Text(a.otherAccountSwitch.fill([other.label])),
        ),
      ],
    );
  }
}
