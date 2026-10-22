import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/notification_screen.dart';
import 'package:mykerawang/screens/onboarding_screen.dart';
import 'package:mykerawang/screens/search_screen.dart';
import 'package:mykerawang/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/pump_app.dart';

/// Signed-out renders of the redesigned screens at phone, tablet and
/// desktop widths: no overflow, key structure present.
void main() {
  final screens = <String, (Widget, List<String>)>{
    'settings': (
      const SettingsScreen(),
      ['Appearance', 'Language', 'Privacy & data'],
    ),
    'notifications': (
      const NotificationScreen(),
      ['Log in to see notifications'],
    ),
    'search': (
      const SearchScreen(),
      ['Search MYKerawang', 'All', 'People'],
    ),
    'onboarding': (
      const OnboardingScreen(),
      ['Step 1 of 2'],
    ),
  };

  for (final entry in screens.entries) {
    for (final width in kTestWidths) {
      testWidgets('${entry.key} at ${width.toInt()} px', (tester) async {
        await initTestSupabase(tester);
        await setWidth(tester, width);
        await pumpScreen(tester, entry.value.$1);

        expect(tester.takeException(), isNull);
        for (final text in entry.value.$2) {
          expect(find.text(text), findsWidgets, reason: text);
        }
      });
    }
  }

  testWidgets('search shows and clears recent searches', (tester) async {
    await initTestSupabase(tester);
    SharedPreferences.setMockInitialValues({
      'recentSearches': ['futsal', 'kalkulator'],
    });
    await setWidth(tester, 375);
    await pumpScreen(tester, const SearchScreen());

    expect(find.text('Recent searches'), findsOneWidget);
    expect(find.text('futsal'), findsOneWidget);
    await tester.tap(find.text('Clear'));
    await tester.pump();
    expect(find.text('futsal'), findsNothing);
    expect(find.text('Search MYKerawang'), findsOneWidget);
  });

  test('notification date buckets', () {
    final now = DateTime(2026, 10, 19, 15);
    expect(notificationBucket(DateTime(2026, 10, 19, 1), now), NotifBucket.today);
    expect(notificationBucket(DateTime(2026, 10, 18, 23), now), NotifBucket.thisWeek);
    expect(notificationBucket(DateTime(2026, 10, 13), now), NotifBucket.thisWeek);
    expect(notificationBucket(DateTime(2026, 10, 12), now), NotifBucket.earlier);
  });

  testWidgets('#tag search offers the tag feed instead of querying',
      (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 375);
    await pumpScreen(tester, const SearchScreen());

    await tester.enterText(find.byType(TextField), '#Futsal');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.text('See posts tagged #futsal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
