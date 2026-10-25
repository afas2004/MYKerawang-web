import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/events/event_form_screen.dart';
import 'package:mykerawang/services/form_service.dart';
import 'package:mykerawang/utils/form_rules.dart';

import 'helpers/feed_fixtures.dart';

/// The answer page against a fake service: rendering by kind, the required
/// check, the submit payload, the answered state and the blocked reasons.
class FakeAnswerService implements FormService {
  FakeAnswerService({required this.view, this.email, this.openId = 'f1'});

  FormView view;
  String? email;
  String? openId;
  Map<String, dynamic>? submitted;
  String? submittedRole;
  int loads = 0;

  @override
  Future<List<FormTemplate>> templates() async => const [];

  @override
  Future<FormSummary?> summary(String eventId) async => null;

  @override
  Future<String?> openFormId(String eventId) async => openId;

  @override
  Future<String?> myEmail() async => email;

  @override
  Future<String> createBlank(String eventId, {String? title}) =>
      throw UnimplementedError();

  @override
  Future<String> createFromTemplate(String eventId, String slug) =>
      throw UnimplementedError();

  @override
  Future<FormView> load(String formId) async {
    loads++;
    return view;
  }

  @override
  Future<void> save(FormDoc doc) => throw UnimplementedError();

  @override
  Future<void> publish(String formId) => throw UnimplementedError();

  @override
  Future<FormAnalysis> analysis(String formId) async => const FormAnalysis();

  @override
  Future<List<FormResponse>> responses(String formId) async => const [];

  @override
  Future<void> setAfterCheckin(String formId, bool on) async {}

  @override
  Future<void> submit(String formId,
      {required Map<String, dynamic> answers, String? role}) async {
    submitted = answers;
    submittedRole = role;
    view = FormView(
      doc: view.doc,
      canAnswer: true,
      mine: {'answers': answers, 'role': role},
      myRole: role,
    );
  }
}

/// heading, a required name, a required KI rating, a role choice, a note.
List<FormFieldSpec> kiFields() => const [
      FormFieldSpec(id: 'h1', kind: 'heading', label: 'Maklumat peserta'),
      FormFieldSpec(id: 'f1', kind: 'short_text', label: 'Nama penuh', required: true),
      FormFieldSpec(
          id: 'f2',
          kind: 'rating',
          label: 'KI1 Komunikasi',
          required: true,
          analysis: 'ki_pre',
          kiCode: 1),
      FormFieldSpec(
          id: 'f3',
          kind: 'single_choice',
          label: 'Saya menyertai sebagai',
          required: true,
          choices: ['Peserta', 'Penganjur']),
      FormFieldSpec(id: 'f4', kind: 'long_text', label: 'Cadangan'),
      FormFieldSpec(id: 'f5', kind: 'student_id', label: 'Nombor matrik'),
    ];

FormView openView({Map<String, dynamic>? mine}) => FormView(
      doc: FormDoc(id: 'f1', title: 'Laporan KI', status: 'open', fields: kiFields()),
      canAnswer: true,
      mine: mine,
    );

void main() {
  setUp(installFeedHooks);
  tearDown(() {
    resetFeedHooks();
    FormService.debugReset();
  });

  testWidgets('every kind renders and a submit sends the answers', (tester) async {
    final fake = FakeAnswerService(view: openView());
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const EventFormScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('Maklumat peserta'), findsOneWidget);
    expect(find.text('KI1 Komunikasi *'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('input-f1')), 'AHMAD DANEIL');
    await tester.tap(find.byKey(const ValueKey('rate-f2-4')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('choice-f3-Penganjur')));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(fake.submitted?['f1'], 'AHMAD DANEIL');
    expect(fake.submitted?['f2'], 4);
    expect(fake.submitted?['f3'], 'Penganjur');
    // The role comes from the choice, so S1/S2 split correctly.
    expect(fake.submittedRole, 'penganjur');
  });

  testWidgets('a required question blocks the submit', (tester) async {
    final fake = FakeAnswerService(view: openView());
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const EventFormScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Submit'));
    await tester.pumpAndSettle();

    expect(fake.submitted, isNull);
    expect(find.textContaining('required'), findsWidgets);
  });

  testWidgets('an existing answer is shown with an Update button', (tester) async {
    final fake = FakeAnswerService(
      view: openView(mine: {
        'answers': {'f1': 'NURUL IZZAH', 'f2': 5, 'f3': 'Peserta'},
        'role': 'peserta',
      }),
    );
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const EventFormScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('NURUL IZZAH'), findsOneWidget);
    expect(find.textContaining('You have answered'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Update answers'), findsOneWidget);
  });

  testWidgets('the matric is pre-filled from a student address', (tester) async {
    final fake = FakeAnswerService(
      view: openView(),
      email: '2023837334@student.uitm.edu.my',
    );
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const EventFormScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('2023837334'), findsOneWidget);
  });

  testWidgets('a guest gets the sign-in bar', (tester) async {
    final fake = FakeAnswerService(
      view: FormView(
        doc: FormDoc(id: 'f1', title: 'Laporan KI', status: 'open', fields: kiFields()),
        canAnswer: false,
        reason: 'signed_out',
      ),
    );
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const EventFormScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('Sign in to answer'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Submit'), findsNothing);
  });

  testWidgets('a closed form says so', (tester) async {
    final fake = FakeAnswerService(
      view: FormView(
        doc: FormDoc(id: 'f1', title: 'Laporan KI', status: 'closed', fields: kiFields()),
        canAnswer: false,
        reason: 'closed',
      ),
    );
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const EventFormScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('This form is closed.'), findsOneWidget);
  });

  testWidgets('an event with no form says so', (tester) async {
    final fake = FakeAnswerService(view: openView(), openId: null);
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const EventFormScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('This event has no form yet.'), findsOneWidget);
  });
}
