// The welcome tour: a centred popup a brand-new account sees once, right
// after account setup (onboarding queues it with markPending, then calls
// showPending). Existing accounts, with nothing queued, never see it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/widgets/welcome_tour.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/pump_app.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WelcomeTour.debugReset();
  });

  NavigatorState navOf(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  /// Starts showPending and lets the popup open.
  Future<Future<bool>> open(WidgetTester tester, String userId) async {
    final opened = WelcomeTour.showPending(userId: userId, navigator: navOf(tester));
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('a new account sees it once, greeted by name, and can walk all four cards', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const Scaffold(body: Text('home')));

    await WelcomeTour.markPending('new-user', 'Nadia');
    expect(await WelcomeTour.isPending('new-user'), isTrue);
    final opened = await open(tester, 'new-user');

    expect(find.text('Welcome to MYKerawang, Nadia'), findsOneWidget);
    // Seen as soon as it opens, so a reload never shows it again.
    expect(await WelcomeTour.isPending('new-user'), isFalse);

    await tester.tap(find.text('Show me'));
    await tester.pumpAndSettle();
    expect(find.text('Buy and sell in Kerawang'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("See what's on this week"), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Buy and sell in Kerawang'), findsOneWidget);

    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text("You're all set, Nadia"), findsOneWidget);
    expect(find.text('A community app, not an official UiTM or college service.'), findsOneWidget);

    await tester.tap(find.text('Start exploring'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeTourDialog), findsNothing);
    expect(await opened, isTrue);

    // Never twice.
    expect(await (await open(tester, 'new-user')), isFalse);
    expect(find.byType(WelcomeTourDialog), findsNothing);
  });

  testWidgets('existing accounts (nothing queued) never see it', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const Scaffold(body: Text('home')));

    expect(await (await open(tester, 'old-user')), isFalse);
    expect(find.byType(WelcomeTourDialog), findsNothing);
  });

  testWidgets('it is per account: queuing one user does not show it to another', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const Scaffold(body: Text('home')));

    await WelcomeTour.markPending('new-user', 'Nadia');
    expect(await (await open(tester, 'someone-else')), isFalse);
    expect(await WelcomeTour.isPending('new-user'), isTrue);
  });

  testWidgets('Skip and the close button both close it', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const Scaffold(body: Text('home')));

    await WelcomeTour.markPending('a', 'A');
    await open(tester, 'a');
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeTourDialog), findsNothing);

    await WelcomeTour.markPending('b', 'B');
    await open(tester, 'b');
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeTourDialog), findsNothing);
  });

  testWidgets('a blank name falls back to a plain greeting', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375, height: 812);
    await pumpScreen(tester, const Scaffold(body: Text('home')));

    await WelcomeTour.markPending('c', '  ');
    await open(tester, 'c');
    expect(find.text('Welcome to MYKerawang'), findsOneWidget);
  });

  // Overflow shows up as a test failure, so every card is checked on a
  // small phone and on desktop.
  for (final size in const [Size(320, 568), Size(1280, 800)]) {
    testWidgets('every card fits at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      await initTestSupabase(tester);
      await setWidth(tester, size.width, height: size.height);
      await pumpScreen(tester, const Scaffold(body: Text('home')));

      await WelcomeTour.markPending('d', 'Muhammad Aiman Hakimi');
      await open(tester, 'd');
      // On a small phone the card scrolls; the buttons are reachable.
      Future<void> press(String label) async {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await press('Show me');
      await press('Next');
      await press('Next');
      expect(find.text("You're all set, Muhammad Aiman Hakimi"), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
