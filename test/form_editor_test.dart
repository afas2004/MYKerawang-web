import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/events/form_editor_screen.dart';
import 'package:mykerawang/services/form_service.dart';
import 'package:mykerawang/utils/form_rules.dart';

import 'helpers/feed_fixtures.dart';

/// The editor against a fake service: starting points, editing, saving,
/// publishing and the paste path.
class FakeFormService implements FormService {
  FakeFormService({this.summaryValue, FormDoc? initial}) : doc = initial;

  FormSummary? summaryValue;
  FormDoc? doc;
  final List<FormDoc> saved = [];
  int blankCalls = 0;
  int templateCalls = 0;
  bool published = false;

  @override
  Future<List<FormTemplate>> templates() async => const [
        FormTemplate(slug: 'ki', name: 'KI response report', fieldCount: 2),
      ];

  @override
  Future<FormSummary?> summary(String eventId) async => summaryValue;

  @override
  Future<String> createBlank(String eventId, {String? title}) async {
    blankCalls++;
    doc = FormDoc(id: 'f1', title: title ?? 'Borang program', status: 'draft');
    return 'f1';
  }

  @override
  Future<String> createFromTemplate(String eventId, String slug) async {
    templateCalls++;
    doc = const FormDoc(
      id: 'f1',
      title: 'Laporan KI',
      status: 'draft',
      fields: [
        FormFieldSpec(
            kind: 'rating',
            label: 'KI1 Komunikasi',
            required: true,
            analysis: 'ki_pre',
            kiCode: 1),
        FormFieldSpec(kind: 'long_text', label: 'Cadangan'),
      ],
    );
    return 'f1';
  }

  @override
  Future<String?> openFormId(String eventId) async => doc?.id;

  @override
  Future<String?> myEmail() async => null;

  @override
  Future<FormView> load(String formId) async => FormView(doc: doc!, canAnswer: doc!.isOpen);

  @override
  Future<void> submit(String formId,
          {required Map<String, dynamic> answers, String? role}) async {}

  @override
  Future<FormAnalysis> analysis(String formId) async => const FormAnalysis();

  @override
  Future<List<FormResponse>> responses(String formId) async => const [];

  @override
  Future<void> setAfterCheckin(String formId, bool on) async {}

  @override
  Future<void> save(FormDoc doc) async {
    saved.add(doc);
    // The server assigns ids; emulate it so the reload after a save is honest.
    this.doc = doc.copyWith(fields: [
      for (var i = 0; i < doc.fields.length; i++)
        doc.fields[i].copyWith(id: doc.fields[i].id ?? 'new$i'),
    ]);
  }

  @override
  Future<void> publish(String formId) async {
    published = true;
    doc = doc?.copyWith(status: 'open');
  }
}

void main() {
  setUp(installFeedHooks);
  tearDown(() {
    resetFeedHooks();
    FormService.debugReset();
  });

  FormDoc draft({List<FormFieldSpec>? fields}) => FormDoc(
        id: 'f1',
        title: 'Laporan KI',
        status: 'draft',
        fields: fields ??
            const [
              FormFieldSpec(
                  kind: 'rating',
                  label: 'KI1 Komunikasi',
                  required: true,
                  analysis: 'ki_pre',
                  kiCode: 1),
            ],
      );

  testWidgets('the chooser starts the KI template', (tester) async {
    final fake = FakeFormService();
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const FormEditorScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('Start from'), findsOneWidget);
    await tester.tap(find.text('KI response report'));
    await tester.pumpAndSettle();

    expect(fake.templateCalls, 1);
    expect(find.text('KI1 Komunikasi'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Cadangan'), 220,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Cadangan'), findsOneWidget);
  });

  testWidgets('editing a question and saving sends the whole list', (tester) async {
    final fake = FakeFormService(
      summaryValue: const FormSummary(id: 'f1', title: 'Laporan KI', status: 'draft'),
      initial: draft(),
    );
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const FormEditorScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    // The question is edited on its own row: there is no dialog to open.
    await tester.enterText(find.text('KI1 Komunikasi'), 'KI1 Komunikasi (baharu)');
    await tester.pumpAndSettle();

    expect(find.text('KI1 Komunikasi (baharu)'), findsOneWidget);

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(fake.saved, hasLength(1));
    expect(fake.saved.single.fields.single.label, 'KI1 Komunikasi (baharu)');
    // the analysis tag survives a relabel
    expect(fake.saved.single.fields.single.analysis, 'ki_pre');
    expect(fake.saved.single.fields.single.kiCode, 1);
  });

  testWidgets('a question with no label is not saved', (tester) async {
    final fake = FakeFormService(
      summaryValue: const FormSummary(id: 'f1', title: 'Laporan KI', status: 'draft'),
      initial: draft(),
    );
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const FormEditorScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Add question'), 220,
        scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Add question'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add question'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Save'));
    await tester.pumpAndSettle();

    expect(fake.saved, isEmpty);
    expect(find.textContaining('needs a label'), findsWidgets);
  });

  testWidgets('publishing asks first, then opens the form', (tester) async {
    final fake = FakeFormService(
      summaryValue: const FormSummary(id: 'f1', title: 'Laporan KI', status: 'draft'),
      initial: draft(),
    );
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const FormEditorScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Publish'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Publish'));
    await tester.pumpAndSettle();

    expect(fake.published, isTrue);
    expect(find.text('OPEN'), findsOneWidget);
  });

  testWidgets('a pasted list fills the editor', (tester) async {
    final fake = FakeFormService();
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const FormEditorScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Paste a question list'));
    await tester.pumpAndSettle();

    final box = find
        .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
        .first;
    await tester.enterText(
        box, 'short_text,Nama penuh,yes,,,\nrating,KI2 Pemikiran kritis,yes,1-5,ki_post,2\n');
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();

    expect(fake.blankCalls, 1);
    expect(find.text('Nama penuh'), findsOneWidget);
    // The list scrolls: bring the pasted second question into view.
    await tester.scrollUntilVisible(find.text('KI2 Pemikiran kritis'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('KI2 Pemikiran kritis'), findsOneWidget);
    expect(find.textContaining('KI2'), findsWidgets);
  });

  testWidgets('a read-only (closed) form cannot be edited', (tester) async {
    final fake = FakeFormService(initial: draft().copyWith(status: 'closed'));
    FormService.instance = fake;

    await pumpAt(tester, kCompact, const FormEditorScreen(eventId: 'e1', formId: 'f1'));
    await tester.pumpAndSettle();

    expect(find.text('CLOSED'), findsOneWidget);
    expect(find.text('Add question'), findsNothing);
    expect(find.byTooltip('Save'), findsNothing);
  });
}
