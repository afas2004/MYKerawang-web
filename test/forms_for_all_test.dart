import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/form_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/router.dart' show isGuestPath;
import 'package:mykerawang/screens/events/event_form_screen.dart';
import 'package:mykerawang/screens/events/form_editor_screen.dart';
import 'package:mykerawang/screens/forms/form_gallery_screen.dart';
import 'package:mykerawang/screens/forms/my_forms_screen.dart';
import 'package:mykerawang/services/club_service.dart';
import 'package:mykerawang/services/form_service.dart';
import 'package:mykerawang/services/my_forms_service.dart';
import 'package:mykerawang/utils/announcement_rules.dart';
import 'package:mykerawang/utils/form_rules.dart';
import 'package:mykerawang/widgets/form_picker.dart';
import 'package:mykerawang/widgets/post_card.dart' show PostFormLinks;
import 'package:shared_preferences/shared_preferences.dart';

/// Forms for everyone: standalone forms (`/f/:id`), My forms, the composer
/// picker and the post button — at 375 and 1280, as a guest, signed in, and
/// in dark mode.

class FakeForms implements FormService {
  FakeForms(this.view);
  FormView view;
  final List<FormDoc> saved = [];
  Map<String, dynamic>? submitted;

  @override
  Future<List<FormTemplate>> templates() async => const [];
  @override
  Future<FormSummary?> summary(String eventId) async => null;
  @override
  Future<String?> openFormId(String eventId) async => null;
  @override
  Future<String?> myEmail() async => null;
  @override
  Future<String> createBlank(String eventId, {String? title}) => throw UnimplementedError();
  @override
  Future<String> createFromTemplate(String eventId, String slug) => throw UnimplementedError();
  @override
  Future<FormView> load(String formId) async => view;
  @override
  Future<void> save(FormDoc doc) async => saved.add(doc);
  @override
  Future<void> publish(String formId) async {}
  @override
  Future<FormAnalysis> analysis(String formId) async => const FormAnalysis();
  @override
  Future<List<FormResponse>> responses(String formId) async => const [];
  @override
  Future<void> setAfterCheckin(String formId, bool on) async {}
  @override
  Future<void> submit(String formId, {required Map<String, dynamic> answers, String? role}) async {
    submitted = answers;
  }
}

class FakeMyForms implements MyFormsService {
  FakeMyForms(this.forms, {this.templates = kGallery});
  List<MyForm> forms;
  final List<GalleryTemplate> templates;
  final List<String> calls = [];

  @override
  Future<List<MyForm>> myForms() async => forms;
  @override
  Future<List<GalleryTemplate>> gallery() async => templates;
  @override
  Future<String> create(
      {String? title, String? clubId, String? templateSlug, String lang = 'en'}) async {
    calls.add('create:$title:$clubId:$templateSlug:$lang');
    return 'new1';
  }

  @override
  Future<void> close(String formId) async => calls.add('close:$formId');
  @override
  Future<void> delete(String formId) async {
    calls.add('delete:$formId');
    forms = [for (final f in forms) if (f.id != formId) f];
  }

  @override
  Future<void> withdraw(String formId) async => calls.add('withdraw:$formId');
}

/// A small gallery: one template per category the tests look for.
const kGallery = [
  GalleryTemplate(
    slug: 'event_registration',
    name: 'Event registration',
    nameMs: 'Pendaftaran acara',
    description: 'Names, matric numbers and contacts of everyone joining.',
    descriptionMs: 'Nama, nombor matrik dan nombor telefon semua peserta.',
    category: 'events',
    questions: [
      TemplateQuestion(kind: 'short_text', label: 'Full name', labelMs: 'Nama penuh', required: true),
      TemplateQuestion(kind: 'student_id', label: 'Matric number', labelMs: 'Nombor matrik'),
      TemplateQuestion(
          kind: 'single_choice',
          label: 'Dietary needs',
          labelMs: 'Keperluan pemakanan',
          choices: ['None', 'Vegetarian'],
          choicesMs: ['Tiada', 'Vegetarian']),
    ],
  ),
  GalleryTemplate(
    slug: 'merch_order',
    name: 'T-shirt & merch order',
    nameMs: 'Tempahan baju & cenderamata',
    description: 'Sizes, quantities, collection and payment.',
    descriptionMs: 'Saiz, kuantiti, cara ambil dan bayaran.',
    category: 'orders',
    questions: [
      TemplateQuestion(kind: 'single_choice', label: 'Size', labelMs: 'Saiz', choices: ['S', 'M']),
      TemplateQuestion(kind: 'number', label: 'Quantity', labelMs: 'Kuantiti'),
    ],
  ),
  GalleryTemplate(
    slug: 'event_feedback',
    name: 'Event feedback',
    nameMs: 'Maklum balas acara',
    description: 'How did it go?',
    descriptionMs: 'Bagaimana acara itu?',
    category: 'feedback',
    questions: [
      TemplateQuestion(kind: 'rating', label: 'Overall', labelMs: 'Keseluruhan'),
      TemplateQuestion(kind: 'long_text', label: 'Suggestions', labelMs: 'Cadangan'),
    ],
  ),
];

const _fields = [
  FormFieldSpec(id: 'q1', kind: 'short_text', label: 'What did you lose?', required: true),
  FormFieldSpec(id: 'q2', kind: 'single_choice', label: 'Where', choices: ['Library', 'Cafe']),
];

FormDoc standalone({String status = 'open', bool canEdit = false, bool hidden = false,
        List<FormFieldSpec> fields = _fields}) =>
    FormDoc(
      id: 'f1',
      title: 'Lost & found survey',
      status: status,
      canEdit: canEdit,
      fields: fields,
      standalone: true,
      isHidden: hidden,
      ownerUsername: 'alice',
      ownerName: 'Alice',
    );

/// The app's providers, a router (so `context.push` works) and a theme.
Future<GoRouter> pump(WidgetTester tester, double width, Widget child,
    {bool dark = false}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => child),
    GoRoute(path: '/:rest(.*)', builder: (_, s) => Scaffold(body: Text('route ${s.uri}'))),
  ]);
  await tester.pumpWidget(BlocProvider(
    create: (_) => LanguageCubit(),
    child: MaterialApp.router(
      theme: ThemeData(useMaterial3: true),
      darkTheme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      routerConfig: router,
    ),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  tearDown(() {
    FormService.debugReset();
    MyFormsService.debugReset();
    ClubService.debugPostAsOptions = null;
  });

  // ------------------------------------------------------------ pure rules
  group('rules', () {
    test('blocked labels match the server list', () {
      for (final bad in ['Password', 'Kata laluan UiTM', 'OTP code', 'Your PIN', 'CVV',
                         'Credit card number', 'No. kad kredit']) {
        expect(formLabelBlocked(bad), isTrue, reason: bad);
      }
      for (final fine in ['Pinjam buku?', 'Opinion', 'Name', 'IC number']) {
        expect(formLabelBlocked(fine), isFalse, reason: fine);
      }
    });

    test('IC, bank and address only warn', () {
      for (final w in ['IC number', 'No. K/P', 'MyKad', 'Bank account', 'Alamat rumah', 'Address']) {
        expect(formLabelSensitive(w), isTrue, reason: w);
        expect(formLabelBlocked(w), isFalse, reason: w);
      }
      expect(formLabelSensitive('Nama penuh'), isFalse);
    });

    test('server errors map to codes', () {
      expect(formErrorCode(Exception('FORM:blocked_label')), 'blocked_label');
      expect(formErrorCode(Exception('FORM:required:abc')), 'required');
      expect(formErrorCode(Exception('MOD:rate_limited:form')), 'mod_rate_limited');
      expect(formErrorCode(Exception('VERIFY:required:form_create')), 'verify_required');
      expect(formErrorCode(Exception('boom')), isNull);
      expect(AppStrings.en.formServerError('too_many'), contains('10'));
      expect(AppStrings.ms.formServerError('blocked_label'), contains('kata laluan'));
    });

    test('/f/:id is an allowed in-app link and a guest page', () {
      expect(validateActionLink('Fill in form', '/f/abc'), isNull);
      expect(isKnownInternalRoute('/forms'), isTrue);
      expect(isKnownInternalRoute('/f/abc/responses'), isFalse);
      expect(isGuestPath('/f/abc'), isTrue);
      expect(isGuestPath('/f/abc/edit'), isFalse);
      expect(isGuestPath('/forms'), isFalse);
    });

    test('paths follow the kind of form', () {
      expect(standalone().answerPath, '/f/f1');
      expect(standalone().editPath, '/f/f1/edit');
      const ev = FormDoc(id: 'x', title: 't', status: 'open', eventId: 'e1');
      expect(ev.editPath, '/event/e1/form/edit?f=x');
    });

    test('Malay copy names the maker', () {
      expect(AppStrings.ms.formMadeBy('@alice'), 'Dibuat oleh @alice — bukan borang rasmi kolej.');
    });
  });

  // ------------------------------------------------------------ answer page
  for (final width in [375.0, 1280.0]) {
    for (final dark in [false, true]) {
      final mode = dark ? 'dark' : 'light';

      testWidgets('guest at $width ($mode) sees who made it and a sign-in bar', (tester) async {
        FormService.instance = FakeForms(FormView(doc: standalone(), reason: 'signed_out'));
        await pump(tester, width, const EventFormScreen(formId: 'f1'), dark: dark);

        expect(find.byKey(const ValueKey('made-by')), findsOneWidget);
        expect(find.textContaining('Made by @alice'), findsOneWidget);
        expect(find.textContaining('Sign in'), findsWidgets);
        // Guests cannot report or answer.
        expect(find.byIcon(Icons.more_vert), findsNothing);
        expect(tester.takeException(), isNull);
      });

      testWidgets('signed-in at $width ($mode) answers, reports, withdraws', (tester) async {
        final fake = FakeForms(FormView(doc: standalone(), canAnswer: true));
        FormService.instance = fake;
        final mine = FakeMyForms(const []);
        MyFormsService.instance = mine;
        await pump(tester, width, const EventFormScreen(formId: 'f1'), dark: dark);

        expect(find.textContaining('Made by @alice'), findsOneWidget);
        expect(find.byIcon(Icons.more_vert), findsOneWidget, reason: 'report menu');
        expect(find.text('Withdraw my answer'), findsNothing);

        await tester.enterText(find.byKey(const ValueKey('input-q1')), 'Wallet');
        await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
        await tester.pumpAndSettle();
        expect(fake.submitted?['q1'], 'Wallet');

        // Answered: the page offers to take it back.
        fake.view = FormView(
            doc: standalone(), canAnswer: true, mine: const {'answers': {'q1': 'Wallet'}});
        await pump(tester, width, const EventFormScreen(formId: 'f1'), dark: dark);
        await tester.scrollUntilVisible(find.text('Withdraw my answer'), 200,
            scrollable: find.byType(Scrollable).first);
        await tester.tap(find.text('Withdraw my answer'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Withdraw my answer'));
        await tester.pumpAndSettle();
        expect(mine.calls, ['withdraw:f1']);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('a removed form shows only the notice', (tester) async {
    FormService.instance = FakeForms(FormView(
        doc: standalone(hidden: true, fields: const []), reason: 'removed'));
    await pump(tester, 375, const EventFormScreen(formId: 'f1'));
    expect(find.text('This form was removed by the moderators.'), findsOneWidget);
    expect(find.byKey(const ValueKey('made-by')), findsNothing);
  });

  testWidgets('its maker gets edit, not report', (tester) async {
    FormService.instance = FakeForms(FormView(doc: standalone(canEdit: true), canAnswer: true));
    await pump(tester, 375, const EventFormScreen(formId: 'f1'));
    expect(find.byIcon(Icons.more_vert), findsNothing);
    await tester.tap(find.byTooltip('Edit form'));
    await tester.pumpAndSettle();
    expect(find.text('route /f/f1/edit'), findsOneWidget);
  });

  // ------------------------------------------------------------ editor
  for (final width in [375.0, 1280.0]) {
    testWidgets('editor at $width warns on personal data and blocks passwords', (tester) async {
      final fake = FakeForms(FormView(
        doc: standalone(status: 'draft', canEdit: true, fields: const [
          FormFieldSpec(id: 'a', kind: 'short_text', label: 'Name'),
          FormFieldSpec(id: 'b', kind: 'short_text', label: 'IC number'),
          FormFieldSpec(id: 'c', kind: 'short_text', label: 'Your password'),
        ]),
      ));
      FormService.instance = fake;
      await pump(tester, width, const FormEditorScreen(formId: 'f1'));

      expect(find.byKey(const ValueKey('form-safety')), findsOneWidget);
      expect(find.byKey(const ValueKey('sensitive-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('blocked-2')), findsOneWidget);
      // RSVP / check-in belong to events.
      expect(find.text(AppStrings.en.formRequireRsvp), findsNothing);

      await tester.tap(find.byTooltip('Save'));
      await tester.pumpAndSettle();
      expect(fake.saved, isEmpty, reason: 'a blocked label never reaches the server');
      expect(find.text(AppStrings.en.formBlockedLabel), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }

  // ------------------------------------------------------------ my forms
  const rows = [
    MyForm(id: 'f1', title: 'Lost & found survey', status: 'open', responses: 3),
    MyForm(id: 'f2', title: 'Robot sign-up', status: 'draft', clubId: 'c1', clubName: 'Robotics'),
    MyForm(id: 'f3', title: 'Old poll', status: 'closed', isHidden: true),
  ];

  for (final width in [375.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('My forms at $width (${dark ? 'dark' : 'light'}) lists forms', (tester) async {
        MyFormsService.instance = FakeMyForms(List.of(rows));
        await pump(tester, width, const MyFormsScreen(), dark: dark);
        expect(find.text('Lost & found survey'), findsOneWidget);
        expect(find.textContaining('3 responses'), findsOneWidget);
        expect(find.textContaining('Robotics'), findsOneWidget);
        expect(find.text('Removed by moderators'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('empty My forms invites a first form', (tester) async {
    MyFormsService.instance = FakeMyForms(const []);
    await pump(tester, 375, const MyFormsScreen());
    expect(find.text("You haven't made any forms yet."), findsOneWidget);
  });

  testWidgets('New form opens the template gallery', (tester) async {
    MyFormsService.instance = FakeMyForms(const []);
    await pump(tester, 1280, const MyFormsScreen());
    await tester.tap(find.text('New form').first);
    await tester.pumpAndSettle();
    expect(find.text('route /forms/new'), findsOneWidget);
  });

  testWidgets('delete asks first, then removes', (tester) async {
    final fake = FakeMyForms(List.of(rows));
    MyFormsService.instance = fake;
    await pump(tester, 375, const MyFormsScreen());
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete form'));
    await tester.pumpAndSettle();
    expect(find.textContaining('all 3 answers'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete form'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['delete:f1']);
    expect(find.text('Lost & found survey'), findsNothing);
  });

  // ------------------------------------------------------------ the gallery
  group('CSV import parsing', () {
    test('the sample reads cleanly', () {
      final p = parseQuestionCsv(kSampleQuestionCsv);
      expect(p.ok, isTrue, reason: '${p.problems.map((e) => e.code)}');
      expect(p.fields.map((f) => f.kind), [
        'short_text', 'student_id', 'single_choice', 'multi_choice', 'rating', 'long_text',
      ]);
      expect(p.fields[2].choices, ['Morning', 'Afternoon', 'Evening']);
      expect(p.fields[0].required, isTrue);
    });

    test('a plain list becomes short answers', () {
      final p = parseQuestionCsv('Name\nRoom number\n\nFavourite food');
      expect(p.ok, isTrue);
      expect(p.fields.map((f) => f.label), ['Name', 'Room number', 'Favourite food']);
      expect(p.fields.every((f) => f.kind == 'short_text'), isTrue);
    });

    test('Malay and Google Forms type names', () {
      final p = parseQuestionCsv('soalan,jenis,wajib,pilihan\n'
          'Nama,teks,ya,\nSesi,aneka pilihan,ya,Pagi;Petang\nNilai,linear scale,,1-10');
      expect(p.ok, isTrue);
      expect(p.fields.map((f) => f.kind), ['short_text', 'single_choice', 'rating']);
      expect(p.fields[1].choices, ['Pagi', 'Petang']);
      expect(p.fields[2].max, 10);
    });

    test('an unknown type names its line', () {
      final p = parseQuestionCsv('question,type\nName,text\nColour,rainbow');
      expect(p.ok, isFalse);
      expect(p.problemLines, [3]);
    });

    test("the editor's own format still works", () {
      final p = parseQuestionCsv('short_text,Nama penuh,yes\nrating,KI1,yes,1-5,ki_pre,1');
      expect(p.ok, isTrue);
      expect(p.fields[1].analysis, 'ki_pre');
    });

    test('search reaches both languages', () {
      expect(kGallery[1].matches('baju'), isTrue);
      expect(kGallery[1].matches('quantity'), isTrue);
      expect(kGallery[1].matches('dietary'), isFalse);
    });
  });

  for (final width in [375.0, 1280.0]) {
    for (final dark in [false, true]) {
      testWidgets('gallery at $width (${dark ? 'dark' : 'light'}) lays out', (tester) async {
        MyFormsService.instance = FakeMyForms(const []);
        ClubService.debugPostAsOptions = () async => const [PostAsOption.self('Just me')];
        await pump(tester, width, const FormGalleryScreen(), dark: dark);

        expect(find.byKey(const ValueKey('start-blank')), findsOneWidget);
        expect(find.byKey(const ValueKey('start-csv')), findsOneWidget);
        for (final t in kGallery) {
          expect(find.byKey(ValueKey('tpl-${t.slug}')), findsOneWidget);
        }
        // Phones get a chip row, desktops a rail: both carry every category.
        expect(find.byKey(const ValueKey('cat-orders')), findsOneWidget);
        // Descriptions only where there is room for them.
        expect(find.text('Sizes, quantities, collection and payment.'),
            width >= 900 ? findsOneWidget : findsNothing);
        // No owner picker without clubs.
        expect(find.byKey(const ValueKey('gallery-owner')), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('search and categories narrow the grid', (tester) async {
    MyFormsService.instance = FakeMyForms(const []);
    ClubService.debugPostAsOptions = () async => const [];
    await pump(tester, 375, const FormGalleryScreen());

    await tester.enterText(find.byKey(const ValueKey('gallery-search')), 'merch');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpl-merch_order')), findsOneWidget);
    expect(find.byKey(const ValueKey('tpl-event_registration')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('gallery-search')), 'zzz');
    await tester.pumpAndSettle();
    expect(find.textContaining('No templates match'), findsOneWidget);
    await tester.tap(find.text('Clear search').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpl-event_registration')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('cat-feedback')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('cat-feedback')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tpl-event_feedback')), findsOneWidget);
    expect(find.byKey(const ValueKey('tpl-merch_order')), findsNothing);
  });

  for (final width in [375.0, 1280.0]) {
    testWidgets('at $width a template previews, then makes a club form', (tester) async {
      final fake = FakeMyForms(const []);
      MyFormsService.instance = fake;
      ClubService.debugPostAsOptions = () async => const [
            PostAsOption.self('Just me'),
            PostAsOption.club(clubId: 'c1', label: 'Robotics', handle: 'robotics'),
          ];
      await pump(tester, width, const FormGalleryScreen());

      await tester.tap(find.byKey(const ValueKey('gallery-owner')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Robotics').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('tpl-event_registration')));
      await tester.pumpAndSettle();
      expect(find.text('Full name *'), findsOneWidget);
      expect(find.textContaining('None · Vegetarian'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('use-template')));
      await tester.pumpAndSettle();

      expect(fake.calls, ['create:null:c1:event_registration:en']);
      expect(find.text('route /f/new1/edit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('blank form starts at once', (tester) async {
    final fake = FakeMyForms(const []);
    MyFormsService.instance = fake;
    ClubService.debugPostAsOptions = () async => const [];
    await pump(tester, 375, const FormGalleryScreen());
    await tester.tap(find.byKey(const ValueKey('start-blank')));
    await tester.pumpAndSettle();
    expect(fake.calls, ['create:null:null:null:en']);
    expect(find.text('route /f/new1/edit'), findsOneWidget);
  });

  for (final width in [375.0, 1280.0]) {
    testWidgets('at $width a CSV import makes a form with its questions', (tester) async {
      final mine = FakeMyForms(const []);
      MyFormsService.instance = mine;
      final forms = FakeForms(FormView(doc: standalone(status: 'draft', canEdit: true, fields: const [])));
      FormService.instance = forms;
      ClubService.debugPostAsOptions = () async => const [];
      await pump(tester, width, const FormGalleryScreen());

      await tester.tap(find.byKey(const ValueKey('start-csv')));
      await tester.pumpAndSettle();
      final create = find.byKey(const ValueKey('csv-create'));
      expect(tester.widget<FilledButton>(create).onPressed, isNull, reason: 'nothing to import yet');

      await tester.enterText(find.byKey(const ValueKey('csv-text')), 'Name,text,yes\nColour,rainbow');
      await tester.pumpAndSettle();
      expect(find.textContaining('Check line 2'), findsOneWidget);
      expect(tester.widget<FilledButton>(create).onPressed, isNull);

      await tester.enterText(find.byKey(const ValueKey('csv-title')), 'Bake sale');
      await tester.enterText(find.byKey(const ValueKey('csv-text')),
          'question,type,required,options\nName,text,yes,\nCake,choice,yes,Chocolate|Pandan\nNotes,paragraph,,');
      await tester.pumpAndSettle();
      expect(find.text('3 questions ready'), findsOneWidget);
      await tester.tap(create);
      await tester.pumpAndSettle();

      expect(mine.calls, ['create:Bake sale:null:null:en']);
      expect(forms.saved.single.fields.map((f) => f.label), ['Name', 'Cake', 'Notes']);
      expect(forms.saved.single.fields[1].choices, ['Chocolate', 'Pandan']);
      expect(find.text('route /f/new1/edit'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  // ------------------------------------------------------------ linking
  testWidgets('the picker returns a form, closed and removed ones left out', (tester) async {
    MyFormsService.instance = FakeMyForms(List.of(rows));
    MyForm? picked;
    await pump(
      tester,
      375,
      Scaffold(body: Center(child: AttachFormButton(onPicked: (f) => picked = f))),
    );
    await tester.tap(find.byKey(const ValueKey('attach-form')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pick-f3')), findsNothing);
    expect(find.text(AppStrings.en.formAttachDraft), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pick-f1')));
    await tester.pumpAndSettle();
    expect(picked?.path, '/f/f1');
  });

  for (final dark in [false, true]) {
    testWidgets('a post shows its form button (${dark ? 'dark' : 'light'})', (tester) async {
      await pump(
        tester,
        375,
        const Scaffold(
          body: PostFormLinks(post: {
            'id': 'p1',
            'action_links': [
              {'label': 'Fill in form', 'url': '/f/f1'},
              {'label': 'Elsewhere', 'url': 'https://example.com'},
            ],
          }),
        ),
        dark: dark,
      );
      expect(find.text('Elsewhere'), findsNothing);
      await tester.tap(find.text('Fill in form'));
      await tester.pumpAndSettle();
      expect(find.text('route /f/f1'), findsOneWidget);
    });
  }

  testWidgets('announcements keep their own buttons', (tester) async {
    await pump(
      tester,
      375,
      const Scaffold(
        body: PostFormLinks(post: {
          'is_announcement': true,
          'action_links': [
            {'label': 'Fill in form', 'url': '/f/f1'},
          ],
        }),
      ),
    );
    expect(find.text('Fill in form'), findsNothing);
  });
}
