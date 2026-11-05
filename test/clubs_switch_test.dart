import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/clubs/club_routes.dart';
import 'package:mykerawang/services/club_service.dart';
import 'package:mykerawang/services/feature_flags.dart';
import 'package:mykerawang/widgets/app_sidebar.dart' show SideNavTile;
import 'package:mykerawang/widgets/club_mention_chip.dart';
import 'package:mykerawang/widgets/clubs_nav_entry.dart';
import 'package:mykerawang/widgets/post_as_selector.dart';
import 'package:mykerawang/widgets/shell_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The owner's Clubs switch: off hides every way into clubs.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => FeatureFlags.debugSet(const FeatureFlagsState()));

  void clubsOff() =>
      FeatureFlags.debugSet(const FeatureFlagsState(clubsOn: false));

  Widget app(Widget child) => BlocProvider(
        create: (_) => LanguageCubit(),
        child: MaterialApp(home: Scaffold(body: child)),
      );

  group('routes', () {
    Future<void> open(WidgetTester tester, String location) async {
      final root = GlobalKey<NavigatorState>();
      final router = GoRouter(
        navigatorKey: root,
        initialLocation: location,
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const Text('HOME')),
          ...clubRoutes(root),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(BlocProvider(
        create: (_) => LanguageCubit(),
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();
    }

    for (final path in [
      '/clubs',
      '/clubs/register',
      '/c/DebateUiTM',
      '/c/DebateUiTM/manage',
    ]) {
      testWidgets('$path (deep link) goes home while clubs are off',
          (tester) async {
        clubsOff();
        await open(tester, path);
        expect(find.text('HOME'), findsOneWidget);
      });
    }

    test('every club route carries the guard', () {
      for (final r in clubRoutes(GlobalKey<NavigatorState>())) {
        expect((r as GoRoute).redirect, same(clubsOffRedirect), reason: r.path);
      }
    });
  });

  group('nav', () {
    testWidgets('sidebar Clubs row shows when on, hides live when off',
        (tester) async {
      await tester.pumpWidget(app(const ClubsNavEntry()));
      expect(find.byType(SideNavTile), findsOneWidget);

      clubsOff();
      await tester.pump();
      expect(find.byType(SideNavTile), findsNothing);
    });

    testWidgets('app-bar Clubs button hides when off', (tester) async {
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(app(const ShellClubsButton()));
      expect(find.byType(IconButton), findsOneWidget);

      clubsOff();
      await tester.pump();
      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('posting and display', () {
    testWidgets('post-as selector offers no club when off', (tester) async {
      clubsOff();
      await tester.pumpWidget(app(PostAsSelector(
        selfLabel: 'Aiman',
        value: null,
        onChanged: (_) {},
        options: const [
          PostAsOption.self('Aiman'),
          PostAsOption.club(clubId: 'c1', label: 'Debate Society', handle: 'debate'),
        ],
      )));
      await tester.pumpAndSettle();
      expect(find.text('Debate Society'), findsNothing);
    });

    test('postAsOptions and club search give nothing club-ish when off',
        () async {
      clubsOff();
      final opts = await ClubService.postAsOptions('Aiman');
      expect(opts.map((o) => o.isClub), [false]);
      expect(await ClubService.searchRows('debate', 5), isEmpty);
    });

    testWidgets('a club mention is plain text with no link when off',
        (tester) async {
      ClubMentionDirectory.debugSet(const [
        Club(id: '1', handle: 'Foto', name: 'Kelab Fotografi', category: 'arts'),
      ]);
      clubsOff();
      await tester.pumpWidget(app(const ClubMentionChip('foto')));
      expect(find.text('Kelab Fotografi'), findsOneWidget);
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
