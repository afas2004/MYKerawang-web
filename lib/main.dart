import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:mykerawang/screens/main_scaffold.dart';
import 'package:mykerawang/screens/onboarding_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme_cubit.dart';
import 'language_cubit.dart';
// --- IMPORT YOUR SERVICES ---
import 'services/notification_service.dart';
import 'utils/responsive.dart';

// --- IMPORT YOUR SCREENS ---
import 'screens/login_screen.dart';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'screens/events_cubit.dart';
import 'screens/marketplace_cubit.dart';
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

  // 1. Initialize Supabase
  await Supabase.initialize(
    url: 'https://zxjuqpqzyzmegdjttzyz.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp4anVxcHF6eXptZWdkanR0enl6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjQ0MzAxNzIsImV4cCI6MjA4MDAwNjE3Mn0.UD_aL16G55CFD6TAOutU4oiGsJCaU5wq-wqFf6OnW5c',
  );

  await NotificationService.init();

  runApp(const MyApp());
}

/// Songket gold — MYKerawang's secondary identity color,
/// used for highlights, ornaments and "featured" accents.
const Color kSongketGold = Color(0xFFC9A227);

/// Builds the Kerawang theme: Material 3 from the user's seed color,
/// with a crafted serif (Fraunces) for headings and songket gold as
/// the tertiary accent.
ThemeData buildKerawangTheme(Color seedColor, Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
  ).copyWith(tertiary: kSongketGold);

  final base = ThemeData(useMaterial3: true, colorScheme: scheme);

  TextStyle? serif(TextStyle? s) =>
      s == null ? null : GoogleFonts.fraunces(textStyle: s);

  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displayLarge: serif(base.textTheme.displayLarge),
      displayMedium: serif(base.textTheme.displayMedium),
      displaySmall: serif(base.textTheme.displaySmall),
      headlineLarge: serif(base.textTheme.headlineLarge),
      headlineMedium: serif(base.textTheme.headlineMedium),
      headlineSmall: serif(base.textTheme.headlineSmall),
      titleLarge: serif(base.textTheme.titleLarge),
    ),
    appBarTheme: AppBarTheme(
      titleTextStyle: GoogleFonts.fraunces(
        textStyle: base.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainer,
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Initialize ALL Cubits here (Global State)
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => EventsCubit()),
        BlocProvider(create: (context) => MarketplaceCubit()),
        BlocProvider(create: (context) => ProfileCubit()),
        BlocProvider(create: (context) => ThemeCubit()),
        BlocProvider(create: (context) => LanguageCubit()),
      ],
      child: BlocBuilder<ThemeCubit, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'MYKerawang',
            scrollBehavior: AppScrollBehavior(),

            // Center the app at a comfortable width on desktop/web,
            // full-width on phones. See lib/utils/responsive.dart.
            builder: (context, child) => ResponsiveShell(child: child!),

            // 3. LIGHT + DARK: Kerawang theme (serif headings, songket gold)
            theme: buildKerawangTheme(themeState.seedColor, Brightness.light),
            darkTheme: buildKerawangTheme(themeState.seedColor, Brightness.dark),

            // 5. CONNECT THE MODE
            themeMode: themeState.themeMode,
            home: const AuthGate(),
          );
        },
      ),
    );
  }
}

// --- UPDATED AUTH GATE ---
// This widget watches for Login/Logout AND listens for new Notifications
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  bool _hasProfile = false;
  // Keep track of the subscription to cancel it later
  late final StreamSubscription<AuthState> _authSubscription;

  @override
  void initState() {
    super.initState();
    _setupAuthListener();
  }

  void _setupAuthListener() {
    // 1. Listen to Auth Changes (Login, Logout, Deep Links)
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      final event = data.event;

      if (session != null) {
        // User just logged in (or was already logged in)
        // 1. Check their profile status to decide navigation
        _checkUserProfile(session.user.id);
        
        // 2. Trigger your Notification Logic (Only if it's a fresh sign-in)
        if (event == AuthChangeEvent.signedIn) {
           NotificationService.requestPermission();
           _startNotificationStream(session.user.id);
        }
        
        // 3. Ensure notification stream runs if we just booted up already logged in
        if (event == AuthChangeEvent.initialSession) {
           _startNotificationStream(session.user.id);
        }

      } else {
        // User is logged out
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasProfile = false;
          });
        }
      }
    });
  }

  // Your original logic to check if they completed onboarding
  Future<void> _checkUserProfile(String userId) async {
    try {
      final data = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _hasProfile = (data != null && data['username'] != null);
          _isLoading = false; // Stop buffering!
        });
      }
    } catch (e) {
      debugPrint("AuthGate Error: $e");
      // Fallback: Stop buffering even if error, so they aren't stuck
      if (mounted) {
        setState(() {
          _hasProfile = true; // Fail open (assume profile exists) to let them into Home
          _isLoading = false;
        });
      }
    }
  }

  // Extracted your notification logic into a clean function
  void _startNotificationStream(String userId) {
    debugPrint("🔔 Notification Listener STARTED for $userId");
    
    Supabase.instance.client
        .from('notifications')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .listen((List<Map<String, dynamic>> data) {
          
          if (data.isNotEmpty) {
            final latest = data.last; 
            
            // Timezone Fix
            final created = DateTime.parse(latest['created_at']).toUtc(); 
            final now = DateTime.now().toUtc(); 
            final difference = now.difference(created).inSeconds.abs();

            if (difference < 30) {
                NotificationService.showNotification(
                  latest['title'], 
                  latest['message'] ?? latest['body'] ?? 'New Notification'
                );
            }
          }
        });
  }

  @override
  void dispose() {
    _authSubscription.cancel(); // Prevent memory leaks
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. Loading Spinner
    if (_isLoading) {
      return const Scaffold(
        // No hardcoded color — follows light/dark theme
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final session = Supabase.instance.client.auth.currentSession;

    // 2. Not Logged In -> Login Screen
    if (session == null) {
      return const LoginScreen();
    }

    // 3. Logged In BUT No Profile -> Onboarding
    if (!_hasProfile) {
      return const OnboardingScreen(); 
    }

    // 4. Fully Ready -> Main App
    return const MainScaffold();
  }
}