import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/events/form_editor_screen.dart';
import 'package:mykerawang/screens/forms/form_gallery_screen.dart';
import 'package:mykerawang/services/club_service.dart';
import 'package:mykerawang/services/form_service.dart';
import 'package:mykerawang/services/google_form_import_service.dart';
import 'package:mykerawang/services/my_forms_service.dart';
import 'package:mykerawang/utils/google_form_import.dart';
import 'package:mykerawang/widgets/form_picker.dart';
import 'package:mykerawang/widgets/google_form_import.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'form_editor_test.dart' show FakeFormService;
import 'forms_for_all_test.dart' show FakeForms, FakeMyForms;
import 'helpers/toast_host.dart';

/// Import from Google Form: the paste → preview → create flow, on a phone
/// (bottom sheet) and a desktop (dialog), from the Create form page, the
/// composers' form picker and the composers' "turn this into a form?" hint.

Object? _fixture(String name) =>
    jsonDecode(File('test/fixtures/google_forms/$name').readAsStringSync());

class _FakeFetch implements GoogleFormImportService {
  _FakeFetch(this.result);
  GoogleFormFetch result;
  final List<String> calls = [];

  @override
  Future<GoogleFormFetch> fetch(String url) async {
    calls.add(url);
    return result;
  }
}

const _link = 'https://forms.gle/qphAyf6jEiWHK45o6';

Future<void> _pump(WidgetTester tester, double width, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, width < 600 ? 812 : 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(path: '/:rest(.*)', builder: (_, s) => Scaffold(body: Text('route ${s.uri}'))),
  ]);
  await tester.pumpWidget(BlocProvider(
    create: (_) => LanguageCubit(),
    child: MaterialApp.router(
      theme: ThemeData(useMaterial3: true),
      routerConfig: router,
      builder: withToasts,
    ),
  ));
  await tester.pumpAndSettle();
}

/// A page with one button that opens the import and shows what came back.
class _Opener extends StatefulWidget {
  const _Opener();
  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  GoogleFormDraft? result;
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            FilledButton(
              key: const ValueKey('open'),
              onPressed: () async {
                final d = await showGoogleFormImport(context);
                setState(() => result = d);
              },
              child: const Text('open'),
            ),
            if (result != null) Text('got ${result!.title} / ${result!.fields.length}'),
          ]),
        ),
      );
}

Finder get _create => find.byKey(const ValueKey('gf-create'));

Future<void> _paste(WidgetTester tester, String link) async {
  await tester.enterText(find.byKey(const ValueKey('gf-link')), link);
  await tester.tap(find.byKey(const ValueKey('gf-fetch')));
  await tester.pumpAndSettle();
}

void main() {
  late _FakeFetch fetch;
  late FakeMyForms mine;
  late FakeForms forms;

  setUp(() {
    fetch = _FakeFetch(GoogleFormFetch.ok(_fixture('upi_recruitment.json')));
    GoogleFormImportService.instance = fetch;
    mine = FakeMyForms(const []);
    MyFormsService.instance = mine;
    forms = FakeForms(const FormView(
      doc: FormDoc(id: 'new1', title: 'Imported', status: 'draft', standalone: true),
    ));
    FormService.instance = forms;
    ClubService.debugPostAsOptions = () async => const [];
  });

  tearDown(() {
    GoogleFormImportService.debugReset();
    MyFormsService.debugReset();
    FormService.debugReset();
    ClubService.debugPostAsOptions = null;
  });

  for (final width in [375.0, 1280.0]) {
    testWidgets('at $width: paste, preview, create', (tester) async {
      await _pump(tester, width, const _Opener());
      await tester.tap(find.byKey(const ValueKey('open')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gf-import')), findsOneWidget);

      await _paste(tester, '  forms.gle/qphAyf6jEiWHK45o6 ');
      expect(fetch.calls, [_link]);

      expect(find.byKey(const ValueKey('gf-preview')), findsOneWidget);
      expect(find.text('3 questions'), findsOneWidget);
      expect(find.text('NAMA PENUH *'), findsOneWidget);
      expect(find.text('NO MATRIK *'), findsOneWidget);
      expect(find.textContaining('AJK POSTER · AJK MAKANAN'), findsOneWidget);
      expect(find.byKey(const ValueKey('gf-skipped')), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byKey(const ValueKey('gf-title')), 'AJK UPI 2026');
      await tester.pumpAndSettle();
      await tester.tap(_create);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('gf-import')), findsNothing);
      expect(find.text('got AJK UPI 2026 / 4'), findsOneWidget);
    });
  }

  testWidgets('an untitled form needs a title; skipped and changed items are listed',
      (tester) async {
    final raw = _fixture('every_type.json') as List;
    (raw[1] as List)[8] = 'Untitled form';
    raw[3] = 'Untitled form';
    fetch.result = GoogleFormFetch.ok(raw);
    await _pump(tester, 375, const _Opener());
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await _paste(tester, _link);

    expect(find.text('This form had no title. Give it one.'), findsOneWidget);
    expect(tester.widget<FilledButton>(_create).onPressed, isNull);

    final skipped = find.byKey(const ValueKey('gf-skipped'));
    await tester.scrollUntilVisible(skipped, 200, scrollable: find.byType(Scrollable).last);
    expect(find.textContaining("Grid questions aren't supported."), findsOneWidget);
    expect(find.textContaining("File uploads aren't supported."), findsOneWidget);
    expect(find.textContaining('not allowed on MYKerawang forms'), findsOneWidget);
    expect(find.byKey(const ValueKey('gf-changed')), findsOneWidget);
    expect(find.textContaining('becomes short text (e.g. 14:30)'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('gf-title')), 'Every type');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(_create).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a sign-in-only form says why and how to fix it', (tester) async {
    fetch.result = const GoogleFormFetch.failed('sign_in');
    await _pump(tester, 375, const _Opener());
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await _paste(tester, _link);
    expect(find.byKey(const ValueKey('gf-error')), findsOneWidget);
    expect(find.textContaining('needs a Google sign-in'), findsOneWidget);
    expect(_create, findsNothing);
  });

  testWidgets('a page without form data reads as "couldn\'t read"', (tester) async {
    fetch.result = const GoogleFormFetch.ok('[null, "x"]');
    await _pump(tester, 375, const _Opener());
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await _paste(tester, _link);
    expect(find.textContaining("Couldn't read that form"), findsOneWidget);
  });

  testWidgets('a link that is not a Google Form is refused before any fetch', (tester) async {
    await _pump(tester, 375, const _Opener());
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    await _paste(tester, 'https://example.com/form');
    expect(fetch.calls, isEmpty);
    expect(find.textContaining("That isn't a Google Form link"), findsOneWidget);
  });

  for (final width in [375.0, 1280.0]) {
    testWidgets('at $width: the Create form page makes the form and opens its editor',
        (tester) async {
      await _pump(tester, width, const FormGalleryScreen());
      await tester.tap(find.byKey(const ValueKey('start-gform')));
      await tester.pumpAndSettle();
      await _paste(tester, _link);
      await tester.tap(_create);
      await tester.pumpAndSettle();

      expect(mine.calls,
          ['create:PENCARIAN AJK PELAJAR UNIT PEMBANGUNAN ISLAM (UPI) UiTMCTKKT:null:null:en']);
      expect(forms.saved.single.fields.map((f) => f.kind),
          ['short_text', 'student_id', 'single_choice', 'heading']);
      expect(find.text('route /f/new1/edit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('the form picker imports and attaches the new draft', (tester) async {
    MyForm? picked;
    await _pump(
      tester,
      375,
      Scaffold(body: Center(child: AttachFormButton(onPicked: (f) => picked = f))),
    );
    await tester.tap(find.byKey(const ValueKey('attach-form')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('picker-gform')));
    await tester.pumpAndSettle();
    await _paste(tester, _link);
    await tester.tap(_create);
    await tester.pumpAndSettle();

    expect(picked?.id, 'new1');
    expect(picked?.isDraft, isTrue);
    expect(forms.saved, hasLength(1));
    expect(find.textContaining('Form created as a draft'), findsOneWidget);
  });

  testWidgets('a picker for open forms only has no import (it would be a draft)',
      (tester) async {
    await _pump(
      tester,
      375,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            key: const ValueKey('pick'),
            onPressed: () => showFormPicker(context, openOnly: true),
            child: const Text('pick'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('pick')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('picker-gform')), findsNothing);
  });

  testWidgets('a composer with a Google Form link offers to import it', (tester) async {
    final body = TextEditingController(text: 'Hello');
    addTearDown(body.dispose);
    MyForm? got;
    await _pump(
      tester,
      375,
      Scaffold(
        body: GoogleFormSuggestion(sources: [body], onImported: (f) => got = f),
      ),
    );
    expect(find.byKey(const ValueKey('gf-suggest')), findsNothing);

    body.text = 'Daftar AJK: https://forms.gle/qphAyf6jEiWHK45o6 sebelum Jumaat';
    await tester.pumpAndSettle();
    expect(find.text('Turn this Google Form into a MYKerawang form?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gf-suggest-import')));
    await tester.pumpAndSettle();
    // The link is already filled in and read.
    expect(fetch.calls, [_link]);
    await tester.tap(_create);
    await tester.pumpAndSettle();
    expect(got?.id, 'new1');
    // Done for this link: the hint goes away.
    expect(find.byKey(const ValueKey('gf-suggest')), findsNothing);
  });

  testWidgets('"Not now" hides the hint for that link', (tester) async {
    final body = TextEditingController(text: 'https://forms.gle/qphAyf6jEiWHK45o6');
    addTearDown(body.dispose);
    await _pump(
      tester,
      375,
      Scaffold(body: GoogleFormSuggestion(sources: [body], onImported: (_) {})),
    );
    expect(find.byKey(const ValueKey('gf-suggest')), findsOneWidget);
    await tester.tap(find.byTooltip('Not now'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('gf-suggest')), findsNothing);
    expect(fetch.calls, isEmpty);
  });

  testWidgets("an event's form can start from a Google Form", (tester) async {
    final events = FakeFormService();
    FormService.instance = events;
    await _pump(tester, 375, const FormEditorScreen(eventId: 'e1'));
    await tester.scrollUntilVisible(find.byKey(const ValueKey('start-gform')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const ValueKey('start-gform')));
    await tester.pumpAndSettle();
    await _paste(tester, _link);
    await tester.tap(_create);
    await tester.pumpAndSettle();

    expect(events.blankCalls, 1);
    expect(events.doc?.title, startsWith('PENCARIAN AJK'));
    expect(events.saved.single.fields.map((f) => f.label).first, 'NAMA PENUH');
    // The editor is open on the new form.
    expect(find.text('Start from'), findsNothing);
    expect(find.text('NAMA PENUH'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
