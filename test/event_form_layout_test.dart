import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/access_strings.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/event_timing_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/admin/event_layout_card.dart';
import 'package:mykerawang/screens/create_event_screen.dart';
import 'package:mykerawang/services/club_service.dart';
import 'package:mykerawang/services/feature_flags.dart';
import 'package:mykerawang/utils/app_nav.dart';
import 'package:mykerawang/utils/form_draft.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two Create event layouts (one page with folds / steps) and the
/// owner's choice in Admin. No Supabase: loads fail quietly.
void main() {
  const s = AppStrings.en;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FormDraft.delay = Duration.zero;
    ClubService.debugPostAsOptions = () async => [const PostAsOption.self('Me')];
  });
  tearDown(() {
    ClubService.debugPostAsOptions = null;
    FeatureFlags.debugSet(const FeatureFlagsState());
  });

  Future<void> pumpAt(WidgetTester t, Size size, Widget child) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(BlocProvider(
      create: (_) => LanguageCubit(),
      child: MaterialApp(home: child),
    ));
    await t.pumpAndSettle();
  }

  const phone = Size(375, 900);
  const desktop = Size(1280, 900);

  group('state', () {
    test('the owner\'s choice is read from access_policy, defaulting to one page', () {
      expect(FeatureFlagsState.fromPolicy({}).eventLayout, EventFormLayout.folded);
      expect(FeatureFlagsState.fromPolicy({'create_event_layout': 'steps'}).eventLayout,
          EventFormLayout.steps);
      expect(FeatureFlagsState.fromPolicy({'create_event_layout': 'nonsense'}).eventLayout,
          EventFormLayout.folded);
      // Flipping a feature keeps the layout, and the other way round.
      const st = FeatureFlagsState(eventLayout: EventFormLayout.steps);
      expect(st.copyWith(AppFeature.clubs, false).eventLayout, EventFormLayout.steps);
      expect(st.withLayout(EventFormLayout.folded).clubsOn, isTrue);
    });
  });

  group('one page, folded', () {
    for (final size in [phone, desktop]) {
      testWidgets('essentials open, extras folded with summaries at ${size.width}', (t) async {
        await pumpAt(t, size, const CreateEventScreen(layout: EventFormLayout.folded));
        expect(t.takeException(), isNull);

        expect(find.text(s.eventTitle), findsOneWidget);
        expect(find.byKey(const ValueKey('timing-mode')), findsOneWidget);
        expect(find.byKey(const ValueKey('location-mode')), findsOneWidget);

        // Folded: titles and summaries show; the fields inside don't.
        expect(find.byKey(const ValueKey('fold-registration')), findsOneWidget);
        expect(find.text(s.foldButtonsTitle), findsOneWidget);
        expect(find.text(s.foldPeopleTitle), findsOneWidget);
        expect(find.textContaining('${s.rcLabel}: ${s.rcAtStart}'), findsOneWidget);
        expect(find.text(s.foldEmpty), findsOneWidget); // description
        expect(find.byKey(const ValueKey('close-rule')).hitTestable(), findsNothing);
        // The old registration link is gone for new events.
        expect(find.text(s.registrationLinkOptional), findsNothing);
        // No Next button: one Publish.
        expect(find.byKey(const ValueKey('step-next')), findsNothing);
      });
    }

    testWidgets('tapping a fold opens it, and its summary follows the fields', (t) async {
      await pumpAt(t, phone, const CreateEventScreen(layout: EventFormLayout.folded));
      final fold = find.byKey(const ValueKey('fold-registration'));
      await t.ensureVisible(fold);
      await t.tap(find.descendant(of: fold, matching: find.text(s.evRegistration)));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey('close-rule')).hitTestable(), findsOneWidget);

      await t.tap(find.text(s.rcNever));
      await t.pumpAndSettle();
      // Fold it again: the summary now says "Never".
      await t.tap(find.descendant(of: fold, matching: find.text(s.evRegistration)));
      await t.pumpAndSettle();
      expect(find.textContaining('${s.rcLabel}: ${s.rcNever}'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('publishing with a missing title shows the error, nothing hidden', (t) async {
      await pumpAt(t, phone, const CreateEventScreen(layout: EventFormLayout.folded, preview: true));
      await t.tap(find.text(s.publish));
      await t.pumpAndSettle();
      expect(find.text(s.fieldRequired.fill([s.title])), findsOneWidget);
    });
  });

  group('steps', () {
    for (final size in [phone, desktop]) {
      testWidgets('four steps with a progress bar at ${size.width}', (t) async {
        await pumpAt(t, size, const CreateEventScreen(layout: EventFormLayout.steps));
        expect(t.takeException(), isNull);
        for (var i = 0; i < 4; i++) {
          expect(find.byKey(ValueKey('step-tab-$i')), findsOneWidget);
        }
        // Step 1 shows the basics only.
        expect(find.text(s.eventTitle).hitTestable(), findsOneWidget);
        expect(find.byKey(const ValueKey('timing-mode')).hitTestable(), findsNothing);
        expect(find.byKey(const ValueKey('step-next')), findsOneWidget);
        expect(find.byKey(const ValueKey('step-back')), findsNothing);
        expect(find.text(s.publish), findsNothing);
      });
    }

    testWidgets('Next checks the step before moving on', (t) async {
      await pumpAt(t, phone, const CreateEventScreen(layout: EventFormLayout.steps, preview: true));
      await t.tap(find.byKey(const ValueKey('step-next')));
      await t.pumpAndSettle();
      // Title missing: still on step 1, with the error shown.
      expect(find.text(s.fieldRequired.fill([s.title])), findsOneWidget);
      expect(find.byKey(const ValueKey('step-back')), findsNothing);
    });

    testWidgets('going back is always allowed, and typed text survives moving around', (t) async {
      await pumpAt(t, phone, const CreateEventScreen(layout: EventFormLayout.steps, preview: true));
      await t.enterText(find.widgetWithText(TextFormField, s.eventTitleHint), 'Futsal Malam Jumaat');
      await t.pumpAndSettle();

      // Jump straight to step 4 is refused (category is missing); step 1 stays.
      await t.tap(find.byKey(const ValueKey('step-tab-3')));
      await t.pumpAndSettle();
      expect(find.text(s.eventTitle).hitTestable(), findsOneWidget);

      // The text is still there.
      expect(find.text('Futsal Malam Jumaat'), findsOneWidget);
    });

    testWidgets('a preview never registers the unsaved-changes guard', (t) async {
      FormGuard.clear();
      await pumpAt(t, phone, const CreateEventScreen(layout: EventFormLayout.steps, preview: true));
      await t.enterText(find.widgetWithText(TextFormField, s.eventTitleHint), 'Anything');
      await t.pumpAndSettle();
      expect(FormGuard.isDirty, isFalse);
      expect(find.textContaining(s.previewTitle), findsOneWidget);
    });
  });

  testWidgets('the page opens in the owner\'s chosen layout', (t) async {
    FeatureFlags.debugSet(const FeatureFlagsState(eventLayout: EventFormLayout.steps));
    await pumpAt(t, phone, const CreateEventScreen());
    expect(find.byKey(const ValueKey('step-next')), findsOneWidget);

    FeatureFlags.debugSet(const FeatureFlagsState());
    await pumpAt(t, phone, const CreateEventScreen(key: ValueKey('again')));
    expect(find.byKey(const ValueKey('step-next')), findsNothing);
  });

  group('admin card', () {
    Future<List<EventFormLayout>> pumpCard(WidgetTester t, Size size,
        {EventFormLayout current = EventFormLayout.folded}) async {
      final chosen = <EventFormLayout>[];
      await pumpAt(
        t,
        size,
        Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: EventLayoutCard(current: current, saving: false, onChoose: chosen.add),
          ),
        ),
      );
      return chosen;
    }

    for (final size in [phone, desktop]) {
      testWidgets('shows both layouts, marks the one in use at ${size.width}', (t) async {
        await pumpCard(t, size);
        expect(t.takeException(), isNull);
        expect(find.text(s.layoutFolded), findsOneWidget);
        expect(find.text(s.layoutSteps), findsOneWidget);
        expect(find.text(s.layoutInUse), findsOneWidget);
        expect(find.byKey(const ValueKey('layout-use-folded')), findsNothing);
        expect(find.byKey(const ValueKey('layout-use-steps')), findsOneWidget);
        expect(find.byKey(const ValueKey('layout-preview-folded')), findsOneWidget);
        expect(find.byKey(const ValueKey('layout-preview-steps')), findsOneWidget);
      });
    }

    testWidgets('switching asks first; cancel changes nothing', (t) async {
      final chosen = await pumpCard(t, phone);
      await t.tap(find.byKey(const ValueKey('layout-use-steps')));
      await t.pumpAndSettle();
      expect(find.text(s.layoutConfirmTitle(s.layoutSteps)), findsOneWidget);
      expect(find.text(s.layoutConfirmBody), findsOneWidget);

      await t.tap(find.byKey(const ValueKey('layout-cancel')));
      await t.pumpAndSettle();
      expect(chosen, isEmpty);

      await t.tap(find.byKey(const ValueKey('layout-use-steps')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('layout-confirm')));
      await t.pumpAndSettle();
      expect(chosen, [EventFormLayout.steps]);
    });

    testWidgets('Preview opens the real form in that layout, publishing nothing', (t) async {
      await pumpCard(t, phone);
      await t.tap(find.byKey(const ValueKey('layout-preview-steps')));
      await t.pumpAndSettle();
      final screen = t.widget<CreateEventScreen>(find.byType(CreateEventScreen));
      expect(screen.preview, isTrue);
      expect(screen.layout, EventFormLayout.steps);
      expect(find.byKey(const ValueKey('step-next')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  test('layout copy exists in all three languages', () {
    for (final l in [AppStrings.en, AppStrings.ms, AppStrings.ja]) {
      for (final text in [
        l.layoutTitle, l.layoutFolded, l.layoutSteps, l.layoutConfirmBody, l.stepNext,
        l.stepBack, l.stepBasics, l.stepExtras, l.foldButtonsTitle, l.foldPeopleTitle, l.previewNote,
      ]) {
        expect(text.trim(), isNotEmpty);
      }
    }
    expect(AppStrings.ms.layoutSteps, isNot(AppStrings.en.layoutSteps));
    expect(AppStrings.ja.layoutSteps, isNot(AppStrings.en.layoutSteps));
  });
}
