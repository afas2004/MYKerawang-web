import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/form_rules.dart';

/// The editor's rules, and the paste format that fills it.
void main() {
  group('field checks', () {
    test('an empty form is refused', () {
      expect(checkFields(const []).single.code, FormIssue.emptyForm);
    });

    test('a label is required, and headings cannot be required', () {
      final problems = checkFields([
        const FormFieldSpec(kind: 'short_text', label: '  '),
        const FormFieldSpec(kind: 'heading', label: 'Bahagian', required: true),
      ]);
      expect(problems.map((p) => p.code), contains(FormIssue.labelRequired));
      expect(problems.map((p) => p.code), contains(FormIssue.headingRequired));
    });

    test('choices need two options; a rating needs a sane scale', () {
      final problems = checkFields([
        const FormFieldSpec(kind: 'single_choice', label: 'Kelas', choices: ['TAC401']),
        const FormFieldSpec(kind: 'rating', label: 'KI1', min: 5, max: 5),
      ]);
      expect(problems.map((p) => p.code), contains(FormIssue.choicesNeeded));
      expect(problems.map((p) => p.code), contains(FormIssue.badScale));
    });

    test('an analysis tag needs a rating, and a KI tag needs a code', () {
      final problems = checkFields([
        const FormFieldSpec(
            kind: 'short_text', label: 'Nama', analysis: 'ki_pre', kiCode: 1),
        const FormFieldSpec(kind: 'rating', label: 'KI2', analysis: 'ki_post'),
        const FormFieldSpec(kind: 'rating', label: 'Food', analysis: 'feedback'),
      ]);
      expect(problems.map((p) => p.code), contains(FormIssue.analysisNeedsRating));
      expect(problems.map((p) => p.code), contains(FormIssue.kiCodeNeeded));
    });

    test('at most seven KI questions per phase', () {
      final fields = [
        for (var i = 1; i <= 7; i++)
          FormFieldSpec(
              kind: 'rating',
              label: 'KI$i',
              analysis: 'ki_pre',
              kiCode: i),
        const FormFieldSpec(kind: 'rating', label: 'extra', analysis: 'ki_pre', kiCode: 1),
      ];
      expect(checkFields(fields).map((p) => p.code), contains(FormIssue.tooManyKi));
    });

    test('a real KI form passes', () {
      final fields = [
        for (var i = 1; i <= 7; i++)
          FormFieldSpec(kind: 'rating', label: 'KI$i', analysis: 'ki_pre', kiCode: i),
        for (var i = 1; i <= 7; i++)
          FormFieldSpec(kind: 'rating', label: 'KI$i', analysis: 'ki_post', kiCode: i),
        const FormFieldSpec(kind: 'rating', label: 'Pengisian', analysis: 'feedback'),
        const FormFieldSpec(kind: 'long_text', label: 'Cadangan'),
      ];
      expect(checkFields(fields), isEmpty);
    });
  });

  group('rpc shape', () {
    test('options travel with the kind that uses them', () {
      final choice = const FormFieldSpec(
          kind: 'single_choice', label: 'Peranan', choices: ['Peserta', 'Penganjur']);
      expect(choice.toRpc()['options'], {'choices': ['Peserta', 'Penganjur']});

      final rating = const FormFieldSpec(kind: 'rating', label: 'KI1', max: 10);
      expect(rating.toRpc()['options'], {'min': 1, 'max': 10});

      // a text field carries no options at all
      expect(const FormFieldSpec(kind: 'long_text', label: 'Nota').toRpc().containsKey('options'),
          isFalse);
    });

    test('a saved field sends its id; a new one does not', () {
      expect(const FormFieldSpec(kind: 'short_text', label: 'A').toRpc().containsKey('id'),
          isFalse);
      expect(const FormFieldSpec(id: 'abc', kind: 'short_text', label: 'A').toRpc()['id'], 'abc');
    });

    test('fromRpc reads what the server returns', () {
      final f = FormFieldSpec.fromRpc({
        'id': 'f1',
        'kind': 'rating',
        'label': 'KI3',
        'required': true,
        'options': {'min': 1, 'max': 5},
        'analysis': 'ki_post',
        'ki_code': 3,
      });
      expect(f.id, 'f1');
      expect(f.isRating, isTrue);
      expect(f.required, isTrue);
      expect(f.analysis, 'ki_post');
      expect(f.kiCode, 3);
      expect(f.toRpc()['options'], {'min': 1, 'max': 5});
    });
  });

  group('pasting a question list', () {
    test('header is optional; comma separated', () {
      final paste = parseFieldPaste(
          'kind,label,required,options,analysis,ki_code\n'
          'short_text,Nama penuh,yes,,,\n'
          'rating,KI1 Komunikasi,yes,1-5,ki_pre,1\n');
      expect(paste.fields.length, 2);
      expect(paste.ok, isTrue, reason: '${paste.problems}');
      expect(paste.fields[0].kind, 'short_text');
      expect(paste.fields[0].required, isTrue);
      expect(paste.fields[1].analysis, 'ki_pre');
      expect(paste.fields[1].kiCode, 1);
      expect(paste.fields[1].min, 1);
      expect(paste.fields[1].max, 5);
    });

    test('quoted labels keep their commas', () {
      final paste = parseFieldPaste(
          'heading,"Bahagian 1, Maklumat",no,,,\n'
          'short_text,"Nama, penuh",yes,,,\n');
      expect(paste.fields.first.label, 'Bahagian 1, Maklumat');
      expect(paste.fields.last.label, 'Nama, penuh');
    });

    test('tabs work, and choices are pipe separated', () {
      final paste = parseFieldPaste('single_choice\tPeranan\tyes\tPeserta|Penganjur\t\t\n');
      expect(paste.fields.single.choices, ['Peserta', 'Penganjur']);
      expect(paste.ok, isTrue, reason: '${paste.problems}');
    });

    test('an unknown kind is reported rather than dropped silently', () {
      final paste = parseFieldPaste('slider,Betapa puas hati,hmm,,,\n');
      expect(paste.fields, isEmpty);
      expect(paste.problems.single.code, 'unknown_kind');
    });

    test('a pasted list is still checked by the normal rules', () {
      final paste = parseFieldPaste('single_choice,Satu pilihan sahaja,no,TAC401,,\n');
      expect(paste.fields.length, 1);
      expect(paste.problems.map((p) => p.code), contains(FormIssue.choicesNeeded));
      expect(paste.ok, isFalse);
    });

    test('blank lines are ignored', () {
      final paste = parseFieldPaste('\n\nshort_text,Nama,yes,,,\n\n');
      expect(paste.fields.length, 1);
    });
  });
}
