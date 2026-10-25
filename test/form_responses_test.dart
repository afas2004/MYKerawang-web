import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/events/form_responses_screen.dart';
import 'package:mykerawang/services/form_service.dart';
import 'package:mykerawang/utils/form_rules.dart';

import 'helpers/feed_fixtures.dart';

/// The analysis screen: S1/S2/S3 render with their n, the free-text answers are
/// listed, and the empty/no-form states say something useful.
class FakeResponsesService implements FormService {
  FakeResponsesService({
    FormAnalysis? analysis,
    List<FormResponse> responses = const [],
    FormSummary? summary = const FormSummary(id: 'f1', title: 'Laporan KI', status: 'open'),
  })  : analysisValue = analysis ?? const FormAnalysis(),
        responsesValue = responses,
        summaryValue = summary;

  final FormAnalysis analysisValue;
  final List<FormResponse> responsesValue;
  final FormSummary? summaryValue;

  @override
  Future<List<FormTemplate>> templates() async => const [];

  @override
  Future<FormSummary?> summary(String eventId) async => summaryValue;

  @override
  Future<String?> openFormId(String eventId) async => summaryValue?.id;

  @override
  Future<String?> myEmail() async => null;

  @override
  Future<String> createBlank(String eventId, {String? title}) =>
      throw UnimplementedError();

  @override
  Future<String> createFromTemplate(String eventId, String slug) =>
      throw UnimplementedError();

  @override
  Future<FormView> load(String formId) async => FormView(
        doc: const FormDoc(
          id: 'f1',
          title: 'Laporan KI',
          status: 'open',
          fields: [
            FormFieldSpec(id: 'f7', kind: 'long_text', label: 'Cadangan'),
          ],
        ),
        canAnswer: true,
      );

  @override
  Future<void> save(FormDoc doc) => throw UnimplementedError();

  @override
  Future<void> publish(String formId) => throw UnimplementedError();

  @override
  Future<void> submit(String formId,
      {required Map<String, dynamic> answers, String? role}) async {}

  @override
  Future<FormAnalysis> analysis(String formId) async => analysisValue;

  @override
  Future<List<FormResponse>> responses(String formId) async => responsesValue;

  @override
  Future<void> setAfterCheckin(String formId, bool on) async {}
}

void main() {
  setUp(installFeedHooks);
  tearDown(() {
    resetFeedHooks();
    FormService.debugReset();
  });

  const analysis = FormAnalysis(
    peserta: 2,
    penganjur: 1,
    s1: [
      KiMean(
          kiCode: 1,
          label: 'KI1 Kemahiran Berkomunikasi',
          nBefore: 2,
          meanBefore: 4.5,
          nAfter: 2,
          meanAfter: 4.75,
          delta: 0.25),
    ],
    s2: [
      KiMean(kiCode: 1, label: 'KI1 Kemahiran Berkomunikasi', nAfter: 1, meanAfter: 3.0),
    ],
    s3: [
      FeedbackMean(fieldId: 'f9', label: 'Mutu makanan', n: 2, mean: 3.62),
    ],
  );

  final responses = [
    FormResponse(
      userId: 'u1',
      displayName: 'AHMAD DANEIL',
      studentId: '2023837334',
      role: 'peserta',
      submittedAt: DateTime.utc(2026, 10, 25),
      answers: const {'f7': 'Tambah lagi soalan'},
    ),
  ];

  testWidgets('S1, S2 and S3 render with their n and the change', (tester) async {
    FormService.instance = FakeResponsesService(analysis: analysis, responses: responses);

    await pumpAt(tester, kCompact, const FormResponsesScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('Participant 2 · Organiser 1'), findsOneWidget);
    expect(find.text('S1 — Participants, KI before and after'), findsOneWidget);
    expect(find.text('S2 — Organisers, KI after the programme'), findsOneWidget);
    expect(find.text('S3 — Programme feedback'), findsOneWidget);

    // the means carry their n, and the change is signed
    expect(find.text('4.50 (2)'), findsOneWidget);
    expect(find.text('4.75 (2)'), findsOneWidget);
    expect(find.text('+0.25'), findsOneWidget);
    expect(find.text('3.62 (2)'), findsOneWidget);

    // one copy button per table
    expect(find.byTooltip('Copy table'), findsNWidgets(3));
  });

  testWidgets('free-text answers are listed with who wrote them', (tester) async {
    FormService.instance = FakeResponsesService(analysis: analysis, responses: responses);

    await pumpAt(tester, kCompact, const FormResponsesScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('Suggestions and comments'), findsOneWidget);
    expect(find.text('Tambah lagi soalan'), findsOneWidget);
    expect(find.text('Who answered'), findsOneWidget);
    expect(find.text('AHMAD DANEIL'), findsWidgets);
  });

  testWidgets('no answers yet says so', (tester) async {
    FormService.instance = FakeResponsesService();

    await pumpAt(tester, kCompact, const FormResponsesScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No answers yet'), findsOneWidget);
  });

  testWidgets('an event with no form says so', (tester) async {
    FormService.instance = FakeResponsesService(summary: null);

    await pumpAt(tester, kCompact, const FormResponsesScreen(eventId: 'e1'));
    await tester.pumpAndSettle();

    expect(find.text('This event has no form yet.'), findsOneWidget);
  });
}
