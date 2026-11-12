// Page tips: the first time someone opens a page, the page dims around one
// control with a short card beside it ("1 of 3"). Shown once per page per
// account; Settings can bring them back.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/widgets/info_tip.dart';
import 'package:mykerawang/widgets/page_tips.dart';
import 'package:mykerawang/widgets/welcome_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/pump_app.dart';

class _Page extends StatelessWidget {
  final bool withB;
  const _Page({this.withB = true});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ListView(
          children: [
            const TipAnchor(id: 'a', child: SizedBox(height: 60, child: Text('control A'))),
            const SizedBox(height: 900),
            if (withB) const TipAnchor(id: 'b', child: SizedBox(height: 60, child: Text('control B'))),
            const TipAnchor(id: 'c', child: SizedBox(height: 60, child: Text('control C'))),
          ],
        ),
      );
}

List<TipStep> _steps() => const [
      TipStep('a', 'Tip about A'),
      TipStep('b', 'Tip about B'),
      TipStep('c', 'Tip about C'),
    ];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WelcomeTour.debugReset();
    PageTips.debugReset();
  });

  BuildContext pageContext(WidgetTester tester) => tester.element(find.byType(_Page));

  /// Starts maybeShow and lets the tips open.
  Future<Future<bool>> open(WidgetTester tester, String page, {String user = 'u1'}) async {
    final opened = PageTips.maybeShow(pageContext(tester), page, _steps, userId: user);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('walks every tip, scrolling each control into view, and ends on Got it', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const _Page());

    final opened = await open(tester, 'market');
    expect(find.text('Tip about A'), findsOneWidget);
    expect(find.text('1 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tips-next')));
    await tester.pumpAndSettle();
    expect(find.text('Tip about B'), findsOneWidget);
    // B was far below the fold; it is scrolled on screen.
    expect(tester.getTopLeft(find.text('control B')).dy, lessThan(812));

    await tester.tap(find.byKey(const ValueKey('tips-next')));
    await tester.pumpAndSettle();
    expect(find.text('3 of 3'), findsOneWidget);
    expect(find.text('Got it'), findsOneWidget);
    expect(find.byKey(const ValueKey('tips-skip')), findsNothing);

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.text('Tip about C'), findsNothing);
    expect(await opened, isTrue);
  });

  testWidgets('shows once per page; Skip ends early; reset brings them back', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const _Page());

    await open(tester, 'market');
    await tester.tap(find.byKey(const ValueKey('tips-skip')));
    await tester.pumpAndSettle();
    expect(find.text('Tip about A'), findsNothing);

    // Seen: never again for this account and page.
    expect(await (await open(tester, 'market')), isFalse);
    expect(find.text('Tip about A'), findsNothing);
    // Another page, or another account, still gets its own.
    final other = await open(tester, 'market', user: 'u2');
    expect(find.text('Tip about A'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tips-skip')));
    await tester.pumpAndSettle();
    expect(await other, isTrue);

    await PageTips.resetAll(userId: 'u1');
    final again = await open(tester, 'market');
    expect(find.text('Tip about A'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tips-skip')));
    await tester.pumpAndSettle();
    expect(await again, isTrue);
  });

  testWidgets('a control that is not on the page is skipped, and the count says so', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const _Page(withB: false));

    await open(tester, 'event');
    expect(find.text('1 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tips-next')));
    await tester.pumpAndSettle();
    expect(find.text('Tip about C'), findsOneWidget);
  });

  testWidgets('never right after, or while waiting for, the welcome tour', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const _Page());

    WelcomeTour.shownThisSession = true;
    expect(await (await open(tester, 'market')), isFalse);
    WelcomeTour.shownThisSession = false;

    await WelcomeTour.markPending('u1', 'Nadia');
    expect(await (await open(tester, 'market')), isFalse);
  });

  testWidgets('(i) shows its text when tapped', (tester) async {
    await initTestSupabase(tester);
    await pumpScreen(
        tester,
        const Scaffold(
          body: Center(child: LabelWithInfo('Open to', info: 'Only a label on the event page.')),
        ));
    expect(find.text('Only a label on the event page.'), findsNothing);
    await tester.tap(find.byType(InfoTip));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Only a label on the event page.'), findsOneWidget);
  });
}
