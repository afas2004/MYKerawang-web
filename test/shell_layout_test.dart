import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/main_scaffold.dart';
import 'package:mykerawang/widgets/app_sidebar.dart';
import 'package:mykerawang/widgets/brand/brand.dart';
import 'package:mykerawang/widgets/right_rail.dart';

import 'helpers/pump_app.dart';

void main() {

  Widget frame({int index = 0, ValueChanged<int>? onSelect}) => ShellFrame(
        currentIndex: index,
        onSelect: onSelect ?? (_) {},
        rightRail: RightRail(
          loader: () async => const RightRailData([], []),
        ),
        child: const Center(child: Text('tab body')),
      );

  for (final width in kTestWidths) {
    testWidgets('shell at ${width.toInt()} px lays out without overflow',
        (tester) async {
      await initTestSupabase(tester);
      await setWidth(tester, width);
      await pumpScreen(tester, frame());

      expect(tester.takeException(), isNull);
      expect(find.text('tab body'), findsOneWidget);
      switch (Responsive.sizeFor(width)) {
        case WindowSize.compact:
          expect(find.byType(CompactNavBar), findsOneWidget);
          expect(find.byTooltip('Create'), findsOneWidget);
          expect(find.byType(AppSidebar), findsNothing);
        case WindowSize.medium:
          expect(find.byType(NavigationRail), findsOneWidget);
          expect(find.byTooltip('Create'), findsOneWidget);
        case WindowSize.expanded:
        case WindowSize.large:
          expect(find.byType(AppSidebar), findsOneWidget);
          expect(find.text('Create'), findsOneWidget);
          // 1280 ≥ 1200: the rail is there.
          expect(find.byType(RightRail), findsOneWidget);
      }
    });
  }

  testWidgets('bottom bar maps slots to router branches', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375);
    final picked = <int>[];
    await pumpScreen(tester, frame(onSelect: picked.add));

    await tester.tap(find.text('News'));
    await tester.tap(find.text('Market'));
    await tester.tap(find.text('Events'));
    await tester.tap(find.text('Home'));
    expect(picked, [
      ShellBranch.announcements,
      ShellBranch.market,
      ShellBranch.events,
      ShellBranch.home,
    ]);
    // Profile is no longer a tab.
    expect(find.text('Profile'), findsNothing);
  });

  testWidgets('bottom bar order: Home · Announcements · Create · Market · Events',
      (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375);
    await pumpScreen(tester, frame());

    final xs = [
      for (final label in ['Home', 'News', 'Create', 'Market', 'Events'])
        tester.getCenter(find.text(label)).dx,
    ];
    expect(xs, orderedEquals([...xs]..sort()));
  });

  testWidgets('rail and sidebar list tabs in the same order', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 768);
    await pumpScreen(tester, frame());
    final railYs = [
      for (final label in ['Home', 'News', 'Market', 'Events'])
        tester.getCenter(find.text(label)).dy,
    ];
    expect(railYs, orderedEquals([...railYs]..sort()));

    await setWidth(tester, 1280);
    await pumpScreen(tester, frame());
    final sideYs = [
      for (final label in ['Home', 'Announcements', 'Search', 'Market', 'Events'])
        tester.getCenter(find.text(label)).dy,
    ];
    expect(sideYs, orderedEquals([...sideYs]..sort()));
  });

  testWidgets('guests get Sign in instead of notifications / settings',
      (tester) async {
    await initTestSupabase(tester); // signed out
    await setWidth(tester, 1280);
    await pumpScreen(tester, frame());
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.text('Join with student email'), findsOneWidget);
    expect(find.text('Notifications'), findsNothing);
    expect(find.text('Settings'), findsNothing);

    await setWidth(tester, 768);
    await pumpScreen(tester, frame());
    expect(find.byTooltip('Sign in'), findsOneWidget);
    expect(find.byTooltip('Notifications'), findsNothing);
  });

  testWidgets('no right rail between 900 and 1199', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 1000);
    await pumpScreen(tester, frame());
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.byType(RightRail), findsNothing);
  });

  testWidgets('Create sits in the bar at the same height as the tabs',
      (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375);
    await pumpScreen(tester, frame());

    final bar = tester.getRect(find.byType(CompactNavBar));
    final create = tester.getRect(find.text('Create'));
    final home = tester.getRect(find.text('Home'));
    // Inside the bar (doesn't stick up) and on the same label baseline.
    expect(create.top, greaterThanOrEqualTo(bar.top));
    expect(create.center.dy, closeTo(home.center.dy, 0.5));
  });

  testWidgets('Create asks guests to log in first', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375);
    await pumpScreen(tester, frame());

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('no lattice or motif in the sidebar', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 1280);
    await pumpScreen(tester, frame());
    expect(find.byType(LatticeBand), findsNothing);
    expect(find.byType(KerawangLattice), findsNothing);
  });
}
