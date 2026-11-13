import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/form_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/forms/form_gallery_screen.dart';
import 'package:mykerawang/services/club_service.dart';
import 'package:mykerawang/services/my_forms_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'forms_for_all_test.dart' show FakeMyForms;

/// The Create form page (`/forms/new`) leads back to forms already made:
/// a "Your recent forms" strip with "See all", and a "My forms" rail item on
/// desktop.

Future<void> _pump(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => const FormGalleryScreen()),
    GoRoute(path: '/:rest(.*)', builder: (_, s) => Scaffold(body: Text('route ${s.uri}'))),
  ]);
  await tester.pumpWidget(BlocProvider(
    create: (_) => LanguageCubit(),
    child: MaterialApp.router(theme: ThemeData(useMaterial3: true), routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

final _forms = [
  for (var i = 0; i < 8; i++)
    MyForm(
      id: 'f$i',
      title: i == 0 ? 'A rather long form title that will need two lines or more' : 'Form $i',
      status: i == 2 ? 'draft' : 'open',
      clubName: i == 1 ? 'Robotics' : null,
      responses: i * 3,
      updatedAt: DateTime(2026, 11, 1 + i),
    ),
];

class _BrokenList extends FakeMyForms {
  _BrokenList() : super(const []);

  @override
  Future<List<MyForm>> myForms() => Future.error(Exception('not signed in'));
}

void main() {
  tearDown(() {
    MyFormsService.debugReset();
    ClubService.debugPostAsOptions = null;
  });

  setUp(() => ClubService.debugPostAsOptions = () async => const []);

  const phone = Size(375, 812);
  const small = Size(320, 568);
  const desktop = Size(1280, 800);

  testWidgets('with forms, the newest six show with their status and answers', (tester) async {
    MyFormsService.instance = FakeMyForms(_forms);
    await _pump(tester, phone);

    expect(find.byKey(const ValueKey('recent-forms')), findsOneWidget);
    expect(find.text('Your recent forms'), findsOneWidget);
    expect(find.byKey(const ValueKey('recent-see-all')), findsOneWidget);
    // Newest first, six at most: f7 … f2, not f1 or f0.
    for (var i = 2; i < 8; i++) {
      expect(find.byKey(ValueKey('recent-f$i'), skipOffstage: false), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('recent-f1'), skipOffstage: false), findsNothing);
    expect(find.text('Open · 21 responses'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [phone, desktop]) {
    testWidgets('with no forms at ${size.width.toInt()}, no strip and no error', (tester) async {
      MyFormsService.instance = FakeMyForms(const []);
      await _pump(tester, size);
      expect(find.byKey(const ValueKey('recent-forms')), findsNothing);
      expect(find.byKey(const ValueKey('start-blank')), findsOneWidget);
      // Desktop keeps the rail link even before the first form.
      expect(find.byKey(const ValueKey('rail-my-forms')),
          size.width >= 900 ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('a list that fails to load (e.g. a guest) shows nothing, not an error',
      (tester) async {
    MyFormsService.instance = _BrokenList();
    await _pump(tester, phone);
    expect(find.byKey(const ValueKey('recent-forms')), findsNothing);
    expect(find.textContaining('wrong'), findsNothing);
    expect(find.byKey(const ValueKey('start-blank')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [phone, desktop]) {
    testWidgets('"See all" at ${size.width.toInt()} goes to /forms', (tester) async {
      MyFormsService.instance = FakeMyForms(_forms);
      await _pump(tester, size);
      await tester.tap(find.byKey(const ValueKey('recent-see-all')));
      await tester.pumpAndSettle();
      expect(find.text('route /forms'), findsOneWidget);
    });
  }

  testWidgets('the desktop rail item goes to /forms', (tester) async {
    MyFormsService.instance = FakeMyForms(const []);
    await _pump(tester, desktop);
    await tester.tap(find.byKey(const ValueKey('rail-my-forms')));
    await tester.pumpAndSettle();
    expect(find.text('route /forms'), findsOneWidget);
  });

  testWidgets('a recent form opens its editor', (tester) async {
    MyFormsService.instance = FakeMyForms(_forms);
    await _pump(tester, phone);
    await tester.tap(find.byKey(const ValueKey('recent-f7')));
    await tester.pumpAndSettle();
    expect(find.text('route /f/f7/edit'), findsOneWidget);
  });

  for (final size in [small, desktop]) {
    // Larger text only on desktop: at 320 px the template cards' form sketch
    // already overflows at x1.3 on main (a separate issue).
    for (final scale in [1.0, if (size == desktop) 1.3]) {
      testWidgets('lays out at ${size.width.toInt()}x${size.height.toInt()} (text x$scale)',
          (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        MyFormsService.instance = FakeMyForms(_forms);
        await _pump(tester, size);
        expect(tester.takeException(), isNull);
        final strip = find.byKey(const ValueKey('recent-forms'));
        await tester.ensureVisible(strip);
        await tester.pumpAndSettle();
        expect(strip, findsOneWidget);
        // The strip header and "See all" stay inside the screen.
        final seeAll = tester.getRect(find.byKey(const ValueKey('recent-see-all')));
        expect(seeAll.right, lessThanOrEqualTo(size.width));
        expect(tester.takeException(), isNull);
      });
    }
  }

  test('copy exists in English, Malay and Japanese', () {
    for (final s in [AppStrings.en, AppStrings.ms, AppStrings.ja]) {
      expect(s.galleryRecentTitle, isNotEmpty);
      expect(s.gallerySeeAll, isNotEmpty);
      expect(s.galleryMyForms, isNotEmpty);
    }
    expect(AppStrings.ms.galleryRecentTitle, 'Borang terkini anda');
    expect(AppStrings.ja.gallerySeeAll, 'すべて表示');
  });
}
