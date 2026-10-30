import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/form_service.dart';
import 'package:mykerawang/utils/form_csv.dart';
import 'package:mykerawang/utils/form_rules.dart';

/// The two artefacts the club hands over: the response CSV and the copied
/// S1/S2/S3 tables.
void main() {
  const fields = [
    FormFieldSpec(id: 'h', kind: 'heading', label: 'Maklumat peserta'),
    FormFieldSpec(id: 'f1', kind: 'short_text', label: 'Nama penuh'),
    FormFieldSpec(id: 'f2', kind: 'student_id', label: 'Nombor matrik'),
    FormFieldSpec(id: 'f3', kind: 'rating', label: 'KI1 Komunikasi', analysis: 'ki_pre', kiCode: 1),
    FormFieldSpec(
        id: 'f4', kind: 'single_choice', label: 'Peranan', choices: ['Peserta', 'Penganjur']),
    FormFieldSpec(id: 'f5', kind: 'multi_choice', label: 'Makanan', choices: ['Halal', 'Vegetarian']),
    FormFieldSpec(id: 'f6', kind: 'consent', label: 'Setuju'),
    FormFieldSpec(id: 'f7', kind: 'long_text', label: 'Cadangan'),
  ];

  FormResponse person({
    String name = 'AHMAD',
    String? matric = '2023837334',
    String role = 'peserta',
    Map<String, dynamic> answers = const {
      'f1': 'AHMAD',
      'f2': '2023837334',
      'f3': 4,
      'f4': 'Peserta',
      'f5': ['Halal', 'Vegetarian'],
      'f6': true,
      'f7': 'Tambah lagi soalan',
    },
  }) =>
      FormResponse(
        userId: 'u1',
        displayName: name,
        studentId: matric,
        role: role,
        submittedAt: DateTime.utc(2026, 10, 25, 12),
        answers: answers,
      );

  test('columns: identity then questions, headings skipped', () {
    expect(responseColumns(fields), [
      'display_name',
      'student_id',
      'role',
      'submitted_at',
      'Nama penuh',
      'Nombor matrik',
      'KI1 Komunikasi',
      'Peranan',
      'Makanan',
      'Setuju',
      'Cadangan',
    ]);
  });

  test('a row renders each kind the way a spreadsheet wants it', () {
    final rows = responseRows(fields, [person()]);
    expect(rows.single, [
      'AHMAD',
      '2023837334',
      'peserta',
      '2026-10-25T12:00:00.000Z',
      'AHMAD',
      '2023837334',
      '4',
      'Peserta',
      'Halal; Vegetarian',
      'yes',
      'Tambah lagi soalan',
    ]);
  });

  test('a missing answer is an empty cell, not "null"', () {
    final rows = responseRows(fields, [person(answers: const {'f1': 'AHMAD'})]);
    expect(rows.single[6], '');
    expect(rows.single[9], '');
  });

  test('the CSV quotes what needs quoting', () {
    final csv = responsesCsv(fields, [
      person(answers: const {'f1': 'AHMAD, bin Wari', 'f7': 'Line one\nLine two'}),
    ]);
    expect(csv.split('\n').first, startsWith('display_name,student_id,role,submitted_at'));
    expect(csv, contains('"AHMAD, bin Wari"'));
    expect(csv, contains('"Line one\nLine two"'));
  });

  test('two people are two rows, oldest first as the server sends them', () {
    final csv = responsesCsv(fields, [
      person(name: 'A'),
      person(name: 'B', matric: null),
    ]);
    final lines = csv.trimRight().split('\n');
    expect(lines.length, 3);
    expect(lines[1], startsWith('A,'));
    expect(lines[2], startsWith('B,,'));
  });

  test('an answer that looks like a formula cannot run in a spreadsheet', () {
    final csv = responsesCsv(fields, [
      person(answers: const {
        'f1': '=HYPERLINK("http://example.invalid","click")',
        'f7': '@SUM(1+1)',
      }),
    ]);
    expect(csv, contains("'=HYPERLINK"));
    expect(csv, contains("'@SUM(1+1)"));
    // and a plain negative number is still a number
    final numbers = responsesCsv(fields, [person(answers: const {'f7': '-5'})]);
    expect(numbers, contains(',-5'));
    expect(numbers, isNot(contains("'-5")));
  });

  group('the copied tables', () {
    const ki = [
      KiMean(kiCode: 1, label: 'KI1 Komunikasi', nBefore: 8, meanBefore: 4.5, nAfter: 8, meanAfter: 4.75, delta: 0.25),
      KiMean(kiCode: 2, label: 'KI2 Pemikiran', nBefore: 8, meanBefore: 4.0, nAfter: 0, meanAfter: null),
    ];

    test('S1 is tab separated with the n beside every mean', () {
      final tsv = s1Tsv(ki);
      final lines = tsv.split('\n');
      expect(lines.first, 'KI\tn_before\tmean_before\tn_after\tmean_after\tdelta');
      expect(lines[1], 'KI1\t8\t4.50\t8\t4.75\t0.25');
      // no answers after → an empty cell rather than a made-up 0.00
      expect(lines[2], 'KI2\t8\t4.00\t0\t\t');
    });

    test('S2 carries the after-state only', () {
      expect(s2Tsv(ki).split('\n').first, 'KI\tn_after\tmean_after');
    });

    test('S3 uses the item labels', () {
      final tsv = s3Tsv(const [FeedbackMean(fieldId: 'x', label: 'Mutu makanan', n: 13, mean: 3.62)]);
      expect(tsv.split('\n').last, 'Mutu makanan\t13\t3.62');
    });
  });
}
