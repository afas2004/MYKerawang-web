import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/create_announcement_screen.dart';
import 'package:mykerawang/services/announcement_service.dart';
import 'package:mykerawang/services/club_service.dart';
import 'package:mykerawang/utils/announcement_rules.dart';
import 'package:mykerawang/widgets/announcement_view.dart';
import 'package:mykerawang/widgets/brand/brand.dart';

import 'helpers/feed_fixtures.dart';

const _club = PostAsOption.club(clubId: 'c1', label: 'Kelab Debat', handle: 'debat');

AnnouncePermission officer() => const AnnouncePermission(
    allowed: true, categories: kClubAnnouncementCategories, clubs: [_club]);
AnnouncePermission admin() => const AnnouncePermission(
    allowed: true, categories: kAnnouncementCategories, clubs: [], isAdmin: true);

Finder _scrollable() =>
    find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first;

void main() {
  setUp(installFeedHooks);
  tearDown(() {
    resetFeedHooks();
    AnnouncementService.debugPermission = null;
  });

  Future<void> open(WidgetTester tester, Size size, AnnouncePermission p,
      {Map<String, dynamic>? edit}) async {
    AnnouncementService.debugPermission = () async => p;
    await pumpAt(tester, size, CreateAnnouncementScreen(editPost: edit));
    await tester.pumpAndSettle();
  }

  for (final size in [kCompact, kExpanded]) {
    final w = size.width.toInt();
    testWidgets('officer at $w px: club speaker, club categories only', (tester) async {
      await open(tester, size, officer());
      expect(tester.takeException(), isNull);
      expect(find.text('New announcement'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Kelab Debat'), findsOneWidget);
      for (final c in ['Club', 'Event', 'General']) {
        expect(find.widgetWithText(ChoiceChip, c), findsOneWidget, reason: c);
      }
      expect(find.widgetWithText(ChoiceChip, 'Kolej'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'JPK'), findsNothing);
      // Scroll the whole form: no overflow anywhere.
      await tester.scrollUntilVisible(find.text('Also show in the Home feed'), 400,
          scrollable: _scrollable());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('admin gets every category incl. Kolej and JPK', (tester) async {
    await open(tester, kCompact, admin());
    expect(find.widgetWithText(ChoiceChip, 'Kolej'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'JPK'), findsOneWidget);
  });

  testWidgets('students are told they cannot announce', (tester) async {
    await open(tester, kCompact, AnnouncePermission.none);
    expect(find.text('Only club officers and admins can post announcements.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Publish'), findsNothing);
  });

  testWidgets('publishing without a title shows the error, nothing is saved', (tester) async {
    await open(tester, kCompact, officer());
    await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
    await tester.pumpAndSettle();
    expect(find.text('Add a title'), findsWidgets); // field error + snackbar
  });

  testWidgets('bad action links are flagged on the field', (tester) async {
    await open(tester, kCompact, officer());
    await tester.enterText(find.widgetWithText(TextField, "What's the announcement?"), 'Mesyuarat');
    await tester.scrollUntilVisible(find.text('Add a button'), 300, scrollable: _scrollable());
    await tester.tap(find.text('Add a button'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Button label'), 'Daftar');
    await tester.enterText(find.widgetWithText(TextField, 'Link'), 'http://forms.gle/x');
    await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
    await tester.pumpAndSettle();
    expect(find.text('Use a secure https:// link'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Link'), '/not-a-page');
    await tester.pumpAndSettle();
    expect(find.text("That isn't a page in the app"), findsOneWidget);
  });

  testWidgets('preview shows the reader view', (tester) async {
    await open(tester, kCompact, officer());
    await tester.enterText(find.widgetWithText(TextField, "What's the announcement?"), 'Mesyuarat Agung');
    await tester.tap(find.byTooltip('Preview'));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementView), findsOneWidget);
    expect(find.text('Mesyuarat Agung'), findsOneWidget);
    expect(find.text('Official'), findsOneWidget);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.byType(AnnouncementView), findsNothing);
  });

  testWidgets('edit flow loads the announcement', (tester) async {
    await open(tester, kCompact, officer(), edit: {
      'id': 'a1',
      'is_announcement': true,
      'club_id': 'c1',
      'announcement_category': 'event',
      'title': 'Old title',
      'body': 'Body',
      'action_links': [
        {'label': 'Join', 'url': '/events'}
      ],
      'comments_enabled': false,
    });
    expect(find.text('Edit announcement'), findsOneWidget);
    expect(find.text('Old title'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Allow comments'), 400, scrollable: _scrollable());
    final sw = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Allow comments'));
    expect(sw.value, isFalse);
    expect(find.byIcon(AppIcons.delete), findsOneWidget); // the loaded button row
  });
}
