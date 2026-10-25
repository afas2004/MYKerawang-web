import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/text_rules.dart';

/// The client half of the form text contract: what the inputs enforce while
/// typing, and what a save sends after cleaning.
void main() {
  group('cleanLine', () {
    test('trims and collapses whitespace', () {
      expect(cleanLine('  KI1   Komunikasi  '), 'KI1 Komunikasi');
      expect(cleanLine('a\t\tb'), 'a b');
    });

    test('a newline cannot become a three-line label', () {
      expect(cleanLine('Nama\npenuh\n\n'), 'Nama penuh');
      expect(cleanLine('Nama\r\npenuh'), 'Nama penuh');
    });

    test('drops control characters but keeps normal text', () {
      expect(cleanLine('Nama\u0000 penuh\u0007'), 'Nama penuh');
      expect(cleanLine('Cadangan — baik'), 'Cadangan — baik');
      // Arabic is text, not a control character.
      expect(cleanLine('بسم الله'), 'بسم الله');
    });

    test('empty stays empty', () {
      expect(cleanLine('   '), '');
      expect(cleanLine('\n\t'), '');
    });
  });

  group('cleanBlock', () {
    test('keeps paragraphs, normalises line endings, trims ends', () {
      expect(cleanBlock('\r\nOne\r\n\r\nTwo\r\n'), 'One\n\nTwo');
    });
  });

  group('cleanChoices', () {
    test('drops blanks and duplicates, keeps order', () {
      expect(cleanChoices(['Peserta', '  ', 'Penganjur', 'peserta']),
          ['Peserta', 'Penganjur']);
    });

    test('caps each choice at kChoiceMax', () {
      final long = 'x' * 120;
      expect(cleanChoices([long]).single.length, kChoiceMax);
    });

    test('caps the number of choices at kChoiceCountMax', () {
      final many = [for (var i = 0; i < 60; i++) 'Option $i'];
      expect(cleanChoices(many), hasLength(kChoiceCountMax));
    });

    test('what the server would refuse becomes what it accepts', () {
      // A blank option and a duplicate are both accepted by the RPC's length
      // check, but they read as a broken form; cleaning them is the client's
      // job.
      expect(cleanChoices(['', '', '']), isEmpty);
    });
  });

  test('the caps match the server contract', () {
    expect(kFormLabelMax, 200); // form_check_field
    expect(kShortAnswerMax, 200); // submit_form_response
    expect(kLongAnswerMax, 2000); // submit_form_response
  });

  group('csvSafe', () {
    test('neutralises a formula but keeps a number', () {
      expect(csvSafe('=1+1'), "'=1+1");
      expect(csvSafe('+SUM(A1)'), "'+SUM(A1)");
      expect(csvSafe('-2+3'), "'-2+3");
      expect(csvSafe('@SUM(A1)'), "'@SUM(A1)");
      expect(csvSafe('-5'), '-5');
      expect(csvSafe('+60123456789'), '+60123456789');
      expect(csvSafe('2023837334'), '2023837334');
    });

    test('leaves ordinary text alone', () {
      expect(csvSafe('AHMAD'), 'AHMAD');
      expect(csvSafe('Cadangan — baik'), 'Cadangan — baik');
      expect(csvSafe(''), '');
    });

    test('a TSV cell cannot carry a tab or a newline into the columns', () {
      expect(tsvCell('a\tb'), 'a b');
      expect(tsvCell('a\nb'), 'a b');
      expect(tsvCell('  =1+1  '), "'=1+1");
    });
  });
}
