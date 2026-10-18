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
import 'services/update_service.dart';
import 'widgets/update_banner.dart';
import 'utils/responsive.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'screens/profile_cubit.dart';

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
  await Supabase.initialize(
    url: 'https://zxjuqpqzyzmegdjttzyz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp4anVxcHF6eXptZWdkanR0enl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ0MzAxNzIsImV4cCI6MjA4MDAwNjE3Mn0.UD_aL16G55CFD6TAOutU4oiGsJCaU5wq-wqFf6OnW5c',
  );

  await NotificationService.init();

  // Web: poll for newer deploys so phones don't sit on a stale build.
  UpdateService.instance.start();

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

            // Centre the app on desktop + run session side effects
            // (onboarding redirect, notification stream) above every route.
            builder: (context, child) => SessionWatcher(
              child: UpdateBanner(child: ResponsiveShell(child: child!)),
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

  @override
  void initState() {
    super.initState();

    // Handle a session that already exists at startup.
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      _checkUserProfile(session.user.id);
      _startNotificationStream(session.user.id);
    }

    _authSubscription =
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final event = data.event;

      if (session == null) {
        _notificationSubscription?.cancel();
        _notificationSubscription = null;
        return;
      }

      if (event == AuthChangeEvent.signedIn) {
        NotificationService.requestPermission();
        _checkUserProfile(session.user.id);
        _startNotificationStream(session.user.id);
      }
    });
  }

  /// New users (no username yet) go to onboarding.
  Future<void> _checkUserProfile(String userId) async {
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
    } catch (e) {
      debugPrint("Profile check error: $e");
      // Fail open — let them into the app.
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

          // Timezone Fix
          final created = DateTime.parse(latest['created_at']).toUtc();
          final now = DateTime.now().toUtc();
          final difference = now.difference(created).inSeconds.abs();

          if (difference < 30) {
            NotificationService.showNotification(
              latest['title'],
              latest['message'] ?? latest['body'] ?? 'New Notification',
            );
          }
        });
  }

  @override
  void dispose() {
    _authSubscription.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
