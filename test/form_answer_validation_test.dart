import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/form_rules.dart';

/// Per-field answer validation: the same call backs blur, change-after-error
/// and submit.
void main() {
  const name = FormFieldSpec(id: 'f1', kind: 'short_text', label: 'Nama', required: true);
  const note = FormFieldSpec(id: 'f2', kind: 'long_text', label: 'Nota');
  const rating = FormFieldSpec(
      id: 'f3', kind: 'rating', label: 'KI1', required: true, analysis: 'ki_pre', kiCode: 1);
  const role = FormFieldSpec(
      id: 'f4', kind: 'single_choice', label: 'Peranan', required: true, choices: ['Peserta', 'Penganjur']);
  const consent = FormFieldSpec(id: 'f5', kind: 'consent', label: 'Setuju', required: true);
  const matric = FormFieldSpec(id: 'f6', kind: 'student_id', label: 'Matrik', required: true);
  const heading = FormFieldSpec(id: 'f7', kind: 'heading', label: 'Bahagian');

  test('required and empty is the only complaint about an empty field', () {
    expect(validateAnswer(name, null), AnswerIssue.required);
    expect(validateAnswer(name, '   '), AnswerIssue.required);
    expect(validateAnswer(note, null), isNull, reason: 'optional fields stay quiet');
    expect(validateAnswer(heading, null), isNull);
  });

  test('a rating must be a whole number inside the scale', () {
    expect(validateAnswer(rating, 4), isNull);
    expect(validateAnswer(rating, 0), AnswerIssue.rating);
    expect(validateAnswer(rating, 6), AnswerIssue.rating);
    expect(validateAnswer(rating, 3.5), AnswerIssue.rating);
    expect(validateAnswer(rating, '4'), isNull, reason: 'the server sends numbers as strings sometimes');
  });

  test('a choice must be one of the options', () {
    expect(validateAnswer(role, 'Peserta'), isNull);
    expect(validateAnswer(role, 'Bukan'), AnswerIssue.choice);
    expect(validateAnswer(role, null), AnswerIssue.required);
  });

  test('consent has to be actually ticked', () {
    expect(validateAnswer(consent, true), isNull);
    expect(validateAnswer(consent, false), AnswerIssue.required);
    expect(validateAnswer(consent, null), AnswerIssue.required);
  });

  test('a matric is digits, 6 to 12', () {
    expect(validateAnswer(matric, '2023837334'), isNull);
    expect(validateAnswer(matric, '20238'), AnswerIssue.matric);
    expect(validateAnswer(matric, '20A3837334'), AnswerIssue.matric);
  });

  test('an optional multi choice may be left alone', () {
    const tags = FormFieldSpec(
        id: 'f8', kind: 'multi_choice', label: 'Makanan', choices: ['Halal', 'Veg']);
    expect(validateAnswer(tags, const <String>[]), isNull);
    expect(validateAnswer(tags, ['Halal']), isNull);
    expect(validateAnswer(tags, ['Halal', 'Pork']), AnswerIssue.choice);
  });

  group('progress', () {
    test('counts acceptable answers, not just non-empty ones', () {
      final fields = [heading, name, rating, note];
      expect(answerProgress(fields, {}), (0, 3));
      expect(answerProgress(fields, {'f1': 'Ali', 'f3': 9}), (1, 3),
          reason: 'an out-of-range rating is not an answer');
      expect(answerProgress(fields, {'f1': 'Ali', 'f3': 5}), (2, 3));
    });

    test('invalidAnswers lists the ids that still need work', () {
      expect(invalidAnswers([name, rating, note], {'f1': 'Ali'}), ['f3']);
      expect(invalidAnswers([name, note], {'f1': 'Ali'}), isEmpty);
    });
  });
}
