import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/services/saved_items.dart';
import 'package:mykerawang/theme_cubit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Phone, tablet, desktop.
const kTestWidths = [375.0, 768.0, 1280.0];

bool _supabaseReady = false;

/// Supabase pointed at nowhere, signed out. Screens that build a client
/// in a field initializer can then be pumped; any query fails fast
/// (the test binding answers HTTP with 400).
Future<void> initTestSupabase(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  SavedItems.debugSignedIn = () => false;
  if (_supabaseReady) return;
  await tester.runAsync(() => Supabase.initialize(
        url: 'http://localhost:54321',
        anonKey: 'test-anon-key',
        authOptions: const FlutterAuthClientOptions(
          localStorage: EmptyLocalStorage(),
          autoRefreshToken: false,
        ),
      ));
  _supabaseReady = true;
}

Future<void> setWidth(WidgetTester tester, double width,
    {double height = 900}) async {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Pumps [home] inside the app's providers and a router, so screens that
/// call `context.go` / `GoRouterState.of` work. Plain Material theme:
/// the app themes fetch Google Fonts, which tests can't.
Future<void> pumpScreen(WidgetTester tester, Widget home) async {
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(path: '/:rest(.*)', builder: (_, __) => const SizedBox()),
  ]);
  await tester.pumpWidget(MultiBlocProvider(
    providers: [
      BlocProvider(create: (_) => LanguageCubit()),
      BlocProvider(create: (_) => ThemeCubit()),
    ],
    child: MaterialApp.router(
      theme: ThemeData(useMaterial3: true),
      routerConfig: router,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}
