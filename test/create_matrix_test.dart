import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/create_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/create_event_screen.dart';
import 'package:mykerawang/screens/create_listing_screen.dart';
import 'package:mykerawang/services/club_service.dart';
import 'package:mykerawang/utils/form_draft.dart';
import 'package:mykerawang/widgets/shell_actions.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// v1.4 create matrix in the UI: the create sheet by role, and the club
/// options on the listing and event forms. No Supabase: ClubService hooks.
void main() {
  const c = CreateStrings.en;
  const clubOption = PostAsOption.club(clubId: 'c1', label: 'Debate Society', handle: 'Debate', verified: true);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FormDraft.delay = Duration.zero;
  });
  tearDown(() {
    ClubService.debugPostAsOptions = null;
    ClubService.debugAnnouncementAbility = null;
  });

  Future<void> pumpAt(WidgetTester tester, double width, Widget child, {bool scaffold = true}) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp(home: scaffold ? Scaffold(body: child) : child),
    ));
    await tester.pumpAndSettle();
  }

  // ------------------------------------------------------------ pure
  test('AnnouncementAbility.fromJson', () {
    final a = AnnouncementAbility.fromJson({
      'allowed': true,
      'categories': ['club', 'event', 'general'],
      'clubs': [
        {'id': 'c1', 'name': 'Debate', 'handle': 'Debate', 'logo_url': null},
      ],
    });
    expect(a.allowed, isTrue);
    expect(a.categories, ['club', 'event', 'general']);
    expect(a.clubs.single['handle'], 'Debate');
    expect(AnnouncementAbility.none.allowed, isFalse);
  });

  test('applyTo leaves is_anonymous out of tables without it', () {
    expect(clubOption.applyTo({'title': 'x'}, hasAnonymous: false), {'title': 'x', 'club_id': 'c1'});
    expect(clubOption.applyTo({'title': 'x'})['is_anonymous'], isFalse);
  });

  test('every listing condition has a label in en and ms', () {
    for (final s in [CreateStrings.en, CreateStrings.ms]) {
      for (final k in CreateStrings.conditions) {
        expect(s.conditionLabel(k), isNotEmpty);
      }
    }
  });

  // ------------------------------------------------------------ create sheet
  for (final w in [375.0, 1280.0]) {
    testWidgets('students see Post, Event, Sell — no Announcement (${w.toInt()} px)', (tester) async {
      await pumpAt(
        tester,
        w,
        CreateOptionsList(
          ability: Future.value(AnnouncementAbility.none),
          onPost: () {},
          onEvent: () {},
          onSell: () {},
          onAnnouncement: () {},
        ),
      );
      expect(find.text(c.announcement), findsNothing);
      expect(find.byType(ListTile), findsNWidgets(3));
    });

    testWidgets('officers also see Announcement (${w.toInt()} px)', (tester) async {
      var opened = 0;
      await pumpAt(
        tester,
        w,
        CreateOptionsList(
          ability: Future.value(const AnnouncementAbility(allowed: true, categories: ['club', 'event', 'general'])),
          onPost: () {},
          onEvent: () {},
          onSell: () {},
          onAnnouncement: () => opened++,
        ),
      );
      expect(find.byType(ListTile), findsNWidgets(4));
      await tester.tap(find.text(c.announcement));
      expect(opened, 1);
    });

    // ---------------------------------------------------------- listing
    testWidgets('listing form: condition, meet-up; club adds quantity (${w.toInt()} px)', (tester) async {
      ClubService.debugPostAsOptions = () async => [const PostAsOption.self('Me'), clubOption];
      await pumpAt(tester, w, const CreateListingScreen(), scaffold: false);

      expect(find.text(c.sellingAs), findsOneWidget);
      expect(find.text(c.conditionLikeNew), findsOneWidget);
      expect(find.text(c.meetup), findsOneWidget);
      expect(find.text(c.quantity, skipOffstage: false), findsNothing, reason: 'quantity is for clubs');

      await tester.tap(find.text('Debate Society'));
      await tester.pumpAndSettle();
      expect(find.text(c.clubContactNote), findsOneWidget);
      await tester.scrollUntilVisible(find.text(c.quantity), 300, scrollable: find.byType(Scrollable).first);
      expect(find.text(c.quantity), findsOneWidget);

      await tester.ensureVisible(find.text(c.conditionUsed));
      await tester.pumpAndSettle();
      await tester.tap(find.text(c.conditionUsed));
      await tester.pumpAndSettle();
      final chip = tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, c.conditionUsed));
      expect(chip.selected, isTrue);
    });

    testWidgets('listing form hides post-as for non-officers (${w.toInt()} px)', (tester) async {
      ClubService.debugPostAsOptions = () async => [const PostAsOption.self('Me')];
      await pumpAt(tester, w, const CreateListingScreen(), scaffold: false);
      expect(find.text(c.sellingAs), findsNothing);
      expect(find.text(c.condition), findsOneWidget);
    });

    // ---------------------------------------------------------- event
    testWidgets('event form: host as club shows the official note (${w.toInt()} px)', (tester) async {
      ClubService.debugPostAsOptions = () async => [const PostAsOption.self('Me'), clubOption];
      await pumpAt(tester, w, const CreateEventScreen(), scaffold: false);
      expect(find.text(c.hostedBy), findsOneWidget);
      expect(find.text(c.clubEventNote), findsNothing);
      await tester.tap(find.text('Debate Society'));
      await tester.pumpAndSettle();
      expect(find.text(c.clubEventNote), findsOneWidget);
    });
  }
}
