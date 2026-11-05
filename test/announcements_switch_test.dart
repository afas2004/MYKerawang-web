// The owner's Announcements switch (admin Settings → App features).
// Off: the News tab shows "Coming soon", the composer pages send you Home, and
// announcement posts drop out of the feed, pins and search.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/screens/announcements/announcements_screen.dart';
import 'package:mykerawang/screens/announcements/announcements_tab.dart';
import 'package:mykerawang/screens/home_screen.dart';
import 'package:mykerawang/screens/main_scaffold.dart';
import 'package:mykerawang/services/feature_flags.dart';
import 'package:mykerawang/utils/announcement_rules.dart';
import 'package:mykerawang/widgets/right_rail.dart';

import 'helpers/pump_app.dart';

const _off = FeatureFlagsState(announcementsOn: false);

void main() {
  tearDown(() => FeatureFlags.debugSet(const FeatureFlagsState()));

  Widget frame({ValueChanged<int>? onSelect}) => ShellFrame(
    currentIndex: ShellBranch.home,
    onSelect: onSelect ?? (_) {},
    rightRail: RightRail(loader: () async => const RightRailData([], [])),
    child: const Center(child: Text('tab body')),
  );

  group('nav when off', () {
    // The News slot stays so the bar keeps its five-slot shape; the tab
    // itself shows "Coming soon" (see AnnouncementsTab below).
    testWidgets('bottom bar keeps News and it still selects its branch', (
      tester,
    ) async {
      FeatureFlags.debugSet(_off);
      await initTestSupabase(tester);
      await setWidth(tester, 375);
      final picked = <int>[];
      await pumpScreen(tester, frame(onSelect: picked.add));

      expect(find.text('News'), findsOneWidget);
      await tester.tap(find.text('News'));
      await tester.tap(find.text('Market'));
      expect(picked, [ShellBranch.announcements, ShellBranch.market]);
      expect(ShellBranch.navOrder, [
        ShellBranch.home,
        ShellBranch.announcements,
        ShellBranch.market,
        ShellBranch.events,
      ]);
    });

    testWidgets('sidebar keeps Announcements', (tester) async {
      FeatureFlags.debugSet(_off);
      await initTestSupabase(tester);
      await setWidth(tester, 1280);
      final picked = <int>[];
      await pumpScreen(tester, frame(onSelect: picked.add));

      expect(find.text('Announcements'), findsOneWidget);
      await tester.tap(find.text('Market'));
      expect(picked, [ShellBranch.market]);
    });
  });

  group('News tab', () {
    testWidgets('off: shows Coming soon; flipping on swaps it live', (
      tester,
    ) async {
      FeatureFlags.debugSet(_off);
      await initTestSupabase(tester);
      await setWidth(tester, 375);
      await pumpScreen(tester, const AnnouncementsTab());

      expect(find.byType(AnnouncementsComingSoon), findsOneWidget);
      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.byType(AnnouncementsScreen), findsNothing);

      FeatureFlags.debugSet(const FeatureFlagsState());
      await tester.pump();
      expect(find.byType(AnnouncementsComingSoon), findsNothing);
      expect(find.byType(AnnouncementsScreen), findsOneWidget);
    });
  });

  group('routes when off', () {
    test('announcementsOffRedirect', () {
      expect(announcementsOffRedirect(on: true), isNull);
      expect(announcementsOffRedirect(on: false), '/home');
      FeatureFlags.debugSet(_off);
      expect(announcementsOffRedirect(), '/home');
    });

    // Same wiring as router.dart: a route-level redirect on each page.
    for (final path in [
      '/create/announcement',
      '/post/abc/edit-announcement',
    ]) {
      testWidgets('deep link $path goes Home', (tester) async {
        FeatureFlags.debugSet(_off);
        GoRoute page(String p) => GoRoute(
          path: p,
          redirect: (_, __) => announcementsOffRedirect(),
          builder: (_, __) => const Text('announcement page'),
        );
        final router = GoRouter(
          initialLocation: path,
          routes: [
            GoRoute(path: '/home', builder: (_, __) => const Text('home')),
            page('/create/announcement'),
            page('/post/:id/edit-announcement'),
          ],
        );
        await tester.pumpWidget(MaterialApp.router(routerConfig: router));
        await tester.pumpAndSettle();
        expect(find.text('home'), findsOneWidget);
        expect(find.text('announcement page'), findsNothing);
      });
    }
  });

  group('content when off', () {
    final announcement = {'id': 'a', 'is_announcement': true};
    final post = {'id': 'p', 'is_announcement': false};

    test('announcementHidden only hides announcements, only when off', () {
      expect(announcementHidden(announcement, on: true), isFalse);
      expect(announcementHidden(announcement, on: false), isTrue);
      expect(announcementHidden(post, on: false), isFalse);
    });

    test('Home feed (and the pin bar, same rule) skips announcements', () {
      FeatureFlags.debugSet(_off);
      expect(showInHomeFeed(announcement), isFalse);
      expect(showInHomeFeed(post), isTrue);
      final items = buildFeedItems([announcement, post], const []);
      expect(items.map((i) => i['id']), ['p']);
    });

    test('on: announcements stay in the feed', () {
      final items = buildFeedItems([announcement, post], const []);
      expect(items.map((i) => i['id']), ['a', 'p']);
    });
  });
}
