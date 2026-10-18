import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/main_scaffold.dart';
import 'package:mykerawang/utils/responsive.dart';
import 'package:mykerawang/widgets/app_sidebar.dart';
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

    await tester.tap(find.text('Market'));
    await tester.tap(find.text('Events'));
    await tester.tap(find.text('Profile'));
    await tester.tap(find.text('Home'));
    expect(picked, [
      ShellBranch.market,
      ShellBranch.events,
      ShellBranch.profile,
      ShellBranch.home,
    ]);
  });

  testWidgets('no right rail between 900 and 1199', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 1000);
    await pumpScreen(tester, frame());
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.byType(RightRail), findsNothing);
  });
}
