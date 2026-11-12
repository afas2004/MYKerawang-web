// "What's new": a card shown once per new version (never to brand-new
// accounts, who get the welcome tour), the full list in Settings, and the
// owner's ready-made post.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/admin/whats_new_tab.dart';
import 'package:mykerawang/screens/whats_new_screen.dart';
import 'package:mykerawang/services/feature_flags.dart';
import 'package:mykerawang/services/update_service.dart';
import 'package:mykerawang/services/whats_new_notes.dart';
import 'package:mykerawang/widgets/whats_new.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/pump_app.dart';

final _notes = <ReleaseNote>[
  ReleaseNote('2.1.0', DateTime(2027, 1, 3), const [
    NoteLine('Newest thing', 'Benda terbaru', '最新'),
  ]),
  ReleaseNote('2.0.0', DateTime(2027, 1, 2), const [
    NoteLine('Second thing', 'Benda kedua', '二番目'),
    NoteLine('Club thing', 'Benda kelab', 'クラブ', needs: AppFeature.clubs),
  ]),
  ReleaseNote('1.9.0', DateTime(2027, 1, 1), const [
    NoteLine('Old thing', 'Benda lama', '古い'),
  ]),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    WhatsNew.debugReset();
    FeatureFlags.debugSet(const FeatureFlagsState());
  });

  NavigatorState navOf(WidgetTester tester) =>
      tester.state<NavigatorState>(find.byType(Navigator).first);

  Future<Future<bool>> open(WidgetTester tester, String version) async {
    final opened = WhatsNew.maybeShow(
        navigator: navOf(tester), version: version, notes: _notes);
    for (var i = 0; i < 3; i++) {
      await tester.pump();
    }
    await tester.pumpAndSettle();
    return opened;
  }

  Future<void> home(WidgetTester tester, {double w = 375, double h = 812}) async {
    await initTestSupabase(tester);
    await setWidth(tester, w, height: h);
    await pumpScreen(tester, const Scaffold(body: Text('home')));
  }

  testWidgets('shows once per version, with every release since the last one seen', (tester) async {
    await home(tester);
    await WhatsNew.markSeen('1.9.0');

    final opened = await open(tester, '2.1.0');
    expect(find.text("What's new in 2.1.0"), findsOneWidget);
    expect(find.text('Newest thing'), findsOneWidget);
    expect(find.text('Second thing'), findsOneWidget);
    expect(find.text('Old thing'), findsNothing);
    // Recorded as soon as it opens, so a reload never shows it again.
    expect(await WhatsNew.lastSeen(), '2.1.0');

    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(find.byType(WhatsNewDialog), findsNothing);
    expect(await opened, isTrue);

    expect(await (await open(tester, '2.1.0')), isFalse);
    expect(find.byType(WhatsNewDialog), findsNothing);
  });

  testWidgets('first run on a device shows only the running version', (tester) async {
    await home(tester);
    final opened = await open(tester, '2.0.0');
    expect(find.text('Second thing'), findsOneWidget);
    expect(find.text('Old thing'), findsNothing);
    await tester.tap(find.text('Got it'));
    await tester.pumpAndSettle();
    expect(await opened, isTrue);
  });

  testWidgets('never for a brand-new account (onboarding marks it seen)', (tester) async {
    await home(tester);
    await WhatsNew.markSeen(UpdateService.appVersion); // what onboarding does
    expect(await (await open(tester, UpdateService.appVersion)), isFalse);
    expect(find.byType(WhatsNewDialog), findsNothing);
  });

  testWidgets('a version with no notes shows nothing, but still counts as seen', (tester) async {
    await home(tester);
    await WhatsNew.markSeen('2.1.0');
    expect(await (await open(tester, '2.1.1')), isFalse);
    expect(await WhatsNew.lastSeen(), '2.1.1');
  });

  testWidgets('lines for a switched-off area are hidden', (tester) async {
    FeatureFlags.debugSet(const FeatureFlagsState(clubsOn: false));
    await home(tester);
    await open(tester, '2.0.0');
    expect(find.text('Second thing'), findsOneWidget);
    expect(find.text('Club thing'), findsNothing);
  });

  testWidgets('fits a 320×568 phone with three releases', (tester) async {
    await home(tester, w: 320, h: 568);
    await WhatsNew.markSeen('1.0.0');
    await open(tester, '2.1.0');
    expect(tester.takeException(), isNull);
    final dialog = tester.getRect(find.byType(WhatsNewDialog));
    expect(dialog.bottom, lessThanOrEqualTo(568));
    expect(tester.getRect(find.text('Got it')).bottom, lessThanOrEqualTo(568));
    expect(tester.getRect(find.text('See all updates')).bottom, lessThanOrEqualTo(568));
  });

  testWidgets('Settings › What\'s new lists every release, newest first', (tester) async {
    await initTestSupabase(tester);
    await setWidth(tester, 320, height: 568);
    await pumpScreen(tester, WhatsNewScreen(notes: _notes));
    expect(tester.takeException(), isNull);
    final newest = tester.getTopLeft(find.text('2.1.0')).dy;
    final older = tester.getTopLeft(find.text('2.0.0')).dy;
    expect(newest, lessThan(older));
    expect(find.text('Club thing'), findsOneWidget);
  });

  test('the real notes are newest first and every line is filled in', () {
    for (var i = 0; i < kReleaseNotes.length - 1; i++) {
      expect(compareVersions(kReleaseNotes[i].version, kReleaseNotes[i + 1].version), 1,
          reason: '${kReleaseNotes[i].version} should come before ${kReleaseNotes[i + 1].version}');
    }
    for (final r in kReleaseNotes) {
      for (final l in r.lines) {
        expect([l.en, l.ms, l.ja].every((t) => t.trim().isNotEmpty), isTrue);
      }
    }
    // Notes never run ahead of the app.
    expect(compareVersions(kReleaseNotes.first.version, UpdateService.appVersion) <= 0, isTrue);
  });

  test('compareVersions reads numbers, not text', () {
    expect(compareVersions('1.10.0', '1.9.0'), 1);
    expect(compareVersions('1.14.6', '1.14.6+46'), 0);
    expect(compareVersions('1.2', '1.2.1'), -1);
  });

  test('the owner\'s post has English, then Malay, and a link to the list', () {
    final p = releasePost(_notes[1]);
    expect(p.title, contains('2.0.0'));
    expect(p.body.indexOf('Second thing'), lessThan(p.body.indexOf('Benda kedua')));
    expect(p.body, contains('/settings/whats-new'));
    expect(p.title.length, lessThanOrEqualTo(120));
  });
}
