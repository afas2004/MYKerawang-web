import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/form_rules.dart';
import 'package:mykerawang/utils/google_form_import.dart';

/// Import from Google Form: the link rules and the parser, on saved forms.
///
/// Fixtures (test/fixtures/google_forms):
///   upi_recruitment.*  a real public form (its WhatsApp invite replaced)
///   every_type.json    made up: one of every Google Forms item type
///   sign_in.html       what a sign-in-only form gives instead of questions
///   broken.html        a page cut off half-way through the data

String _fixture(String name) => File('test/fixtures/google_forms/$name').readAsStringSync();
Object? _json(String name) => jsonDecode(_fixture(name));

void main() {
  group('links', () {
    test('short and long links are accepted and rebuilt from their id', () {
      expect(normaliseGoogleFormUrl('https://forms.gle/qphAyf6jEiWHK45o6'),
          'https://forms.gle/qphAyf6jEiWHK45o6');
      expect(normaliseGoogleFormUrl('forms.gle/qphAyf6jEiWHK45o6'),
          'https://forms.gle/qphAyf6jEiWHK45o6');
      expect(normaliseGoogleFormUrl('  http://forms.gle/qphAyf6jEiWHK45o6/  '),
          'https://forms.gle/qphAyf6jEiWHK45o6');
      expect(
          normaliseGoogleFormUrl(
              'https://docs.google.com/forms/d/e/1FAIpQLSfAUqIC-Dh9A/viewform?usp=send_form'),
          'https://docs.google.com/forms/d/e/1FAIpQLSfAUqIC-Dh9A/viewform');
      expect(normaliseGoogleFormUrl('https://docs.google.com/forms/u/1/d/1AbCdEfGhIjKlMn/edit'),
          'https://docs.google.com/forms/d/1AbCdEfGhIjKlMn/viewform');
    });

    test('anything else is refused (no fetching other addresses)', () {
      for (final bad in [
        '',
        'https://forms.gle',
        'https://evil.com/forms.gle/abcd',
        'https://forms.gle@evil.com/abcd',
        'https://forms.gle/abcd@evil.com',
        'https://forms.gle.evil.com/abcd',
        'https://docs.google.com.evil.com/forms/d/e/1FAIpQLSfAUqIC/viewform',
        'https://docs.google.com/document/d/1AbCdEfGhIjKlMn/edit',
        'https://docs.google.com/forms/d/e/1FAIpQLSfAUqIC/viewform/../../../x',
        'https://docs.google.com/forms/d/e/1FAIpQLSfAUqIC/viewform?x=<script>',
        'ftp://forms.gle/abcd',
        'javascript:alert(1)',
        'https://forms.gle/ab cd',
        'https://forms.gle/abcd\\x',
        'https://forms.gle/${'a' * 600}',
      ]) {
        expect(normaliseGoogleFormUrl(bad), isNull, reason: bad);
      }
    });

    test('a link is found inside a post', () {
      expect(findGoogleFormUrl('Daftar sini: https://forms.gle/qphAyf6jEiWHK45o6. Terima kasih!'),
          'https://forms.gle/qphAyf6jEiWHK45o6');
      expect(findGoogleFormUrl('Register (forms.gle/qphAyf6jEiWHK45o6)'),
          'https://forms.gle/qphAyf6jEiWHK45o6');
      expect(findGoogleFormUrl('No form here, just https://example.com'), isNull);
    });
  });

  group('extracting the data from a page', () {
    test('the saved page yields the same data as the saved JSON', () {
      final text = extractGoogleFormJson(_fixture('upi_recruitment.html'));
      expect(text, isNotNull);
      expect(jsonDecode(text!), _json('upi_recruitment.json'));
    });

    test('a sign-in page has no data', () {
      expect(extractGoogleFormJson(_fixture('sign_in.html')), isNull);
    });

    test('a cut-off page has no usable data', () {
      final text = extractGoogleFormJson(_fixture('broken.html'));
      expect(text, isNull);
    });

    test('data that is not a form is refused', () {
      for (final bad in <Object?>[null, 'x', 42, [], [null], [null, 'x'], [null, [null, 'x']]]) {
        expect(() => parseGoogleForm(bad), throwsA(isA<GoogleFormParseException>()),
            reason: '$bad');
      }
    });
  });

  group('the real form', () {
    final d = parseGoogleForm(_json('upi_recruitment.json'));

    test('keeps the title shown on the form', () {
      expect(d.title, 'PENCARIAN AJK PELAJAR UNIT PEMBANGUNAN ISLAM (UPI) UiTMCTKKT');
      expect(d.untitled, isFalse);
      expect(d.description, isNull);
    });

    test('maps every question', () {
      expect(d.fields.map((f) => f.kind).toList(),
          ['short_text', 'student_id', 'single_choice', 'heading']);
      expect(d.fields[0].label, 'NAMA PENUH');
      expect(d.fields[0].required, isTrue);
      expect(d.fields[1].label, 'NO MATRIK');
      expect(d.fields[1].required, isTrue);
      expect(d.fields[2].label, 'AJK YANG DIMOHON:');
      expect(d.fields[2].choices, ['AJK POSTER', 'AJK MAKANAN', 'AJK HEBAHAN', 'AJK MULTIMEDIA']);
      expect(d.fields[2].required, isTrue);
      expect(d.fields[3].required, isFalse);
      // The text block keeps its link.
      expect(d.fields[3].help, contains('https://chat.whatsapp.com/EXAMPLEinviteCODE000'));
      expect(d.notes, isEmpty);
      expect(d.questionCount, 3);
    });

    test('is valid for the server', () {
      expect(checkFields(d.fields), isEmpty);
    });

    test('with student features off, the matric question is plain text', () {
      final off = parseGoogleForm(_json('upi_recruitment.json'), studentIds: false);
      expect(off.fields[1].kind, 'short_text');
    });

    test('an untitled form asks for a title', () {
      final raw = _json('upi_recruitment.json') as List;
      (raw[1] as List)[8] = null;
      final u = parseGoogleForm(raw);
      expect(u.untitled, isTrue);
      expect(u.title, '');
    });
  });

  group('every item type', () {
    final d = parseGoogleForm(_json('every_type.json'));
    FormFieldSpec byLabel(String l) => d.fields.firstWhere((f) => f.label == l);

    test('title and description', () {
      expect(d.title, 'Every type test');
      expect(d.description, 'A form with every kind of question.');
    });

    test('short answers by what they ask', () {
      expect(byLabel('Full name').kind, 'short_text');
      expect(byLabel('No. Matrik').kind, 'student_id');
      expect(byLabel('No. Matrik').help, 'Example: 2024123456');
      expect(byLabel('Email address').kind, 'email');
      expect(byLabel('No. Telefon').kind, 'phone');
      expect(byLabel('Tell us about yourself').kind, 'long_text');
    });

    test('choices', () {
      final faculty = byLabel('Which faculty?');
      expect(faculty.kind, 'single_choice');
      expect(faculty.choices, ['FSKM', 'FPA', 'Other']);
      expect(faculty.required, isTrue);
      expect(d.notes, contains(const GoogleFormNote('other', 'Which faculty?')));

      final sem = byLabel('Semester'); // a dropdown, with a repeat
      expect(sem.kind, 'single_choice');
      expect(sem.choices, ['1', '2', '3']);

      final days = byLabel('Which days can you help?');
      expect(days.kind, 'multi_choice');
      expect(days.choices, ['Mon', 'Tue', 'Wed']);

      final agree = byLabel('I agree to the rules');
      expect(agree.kind, 'consent');
      expect(agree.required, isTrue);
      expect(d.notes, contains(const GoogleFormNote('one_choice', 'I agree to the rules')));
    });

    test('scales', () {
      final useful = byLabel('How useful was the talk?');
      expect(useful.kind, 'rating');
      expect([useful.min, useful.max], [1, 5]);
      expect(useful.help, '1 = Not useful · 5 = Very useful');

      final wide = byLabel('Rate from 0 to 10');
      expect(wide.kind, 'single_choice');
      expect(wide.choices.first, '0');
      expect(wide.choices.length, 11);
      expect(d.notes, contains(const GoogleFormNote('scale_as_choice', 'Rate from 0 to 10')));

      final stars = byLabel('Overall rating');
      expect(stars.kind, 'rating');
      expect([stars.min, stars.max], [1, 5]);
    });

    test('dates, times and headings', () {
      expect(byLabel('Date of birth').kind, 'date');
      expect(byLabel('Arrival time').kind, 'short_text');
      expect(d.notes, contains(const GoogleFormNote('time', 'Arrival time')));

      final about = byLabel('About the programme');
      expect(about.kind, 'heading');
      expect(about.help, contains('https://example.com/rules'));
      expect(byLabel('Part 2: Logistics').kind, 'heading');
      expect(byLabel('Part 2: Logistics').help, 'Transport and food');
    });

    test('what cannot come across is listed, not silently dropped', () {
      expect(d.skipped, [
        const GoogleFormNote('grid', 'Rate each session'),
        const GoogleFormNote('image', 'Poster'),
        const GoogleFormNote('video', 'Intro video'),
        const GoogleFormNote('file', 'Upload your resume'),
        const GoogleFormNote('blocked', 'Your bank PIN'),
        const GoogleFormNote('unknown', 'Mystery item'),
      ]);
      for (final label in ['Rate each session', 'Poster', 'Your bank PIN', 'Mystery item']) {
        expect(d.fields.where((f) => f.label == label), isEmpty, reason: label);
      }
    });

    test('an event form keeps a question a student form may not ask', () {
      final ev = parseGoogleForm(_json('every_type.json'), standalone: false);
      expect(ev.fields.where((f) => f.label == 'Your bank PIN'), hasLength(1));
      expect(ev.skipped.map((n) => n.code), isNot(contains('blocked')));
    });

    test('the result passes the editor and server rules', () {
      expect(checkFields(d.fields), isEmpty);
      for (final f in d.fields) {
        expect(f.label.length, lessThanOrEqualTo(kLabelMax));
        if (f.kind == 'heading') expect(f.required, isFalse);
        for (final c in f.choices) {
          expect(c.length, lessThanOrEqualTo(60));
        }
      }
    });
  });

  group('limits', () {
    List<Object?> form(List<Object?> items) => [
          null,
          [null, items, null, null, null, null, null, null, 'T'],
          '/forms',
          'T'
        ];

    test('over 40 questions: the rest are listed as not imported', () {
      final d = parseGoogleForm(form([
        for (var i = 0; i < 45; i++) [i, 'Q$i', null, 0, [[i, null, 0]]],
      ]));
      expect(d.fields, hasLength(kMaxFormFields));
      expect(d.skipped.where((n) => n.code == 'too_many'), hasLength(5));
      expect(d.skipped.first.label, 'Q40');
    });

    test('long labels and choices are shortened to what the server accepts', () {
      final d = parseGoogleForm(form([
        [1, 'L' * 300, null, 2, [[1, [['C' * 80, null, null, null, 0], ['B', null, null, null, 0]], 0]]],
      ]));
      final f = d.fields.single;
      expect(f.label.length, kLabelMax);
      expect(f.choices.first.length, 60);
      expect(d.changed.map((n) => n.code), contains('trimmed'));
      expect(checkFields(d.fields), isEmpty);
    });

    test('a choice question without options becomes short text', () {
      final d = parseGoogleForm(form([
        [1, 'Pick', null, 2, [[1, [], 1]]],
      ]));
      expect(d.fields.single.kind, 'short_text');
      expect(d.fields.single.required, isTrue);
    });

    test('a question without a title borrows its description; empty blocks vanish', () {
      final d = parseGoogleForm(form([
        [1, null, 'What is your name?', 0, [[1, null, 0]]],
        [2, '', '', 6, null],
      ]));
      expect(d.fields.single.label, 'What is your name?');
      expect(d.fields.single.help, isNull);
      expect(d.notes, isEmpty);
    });

    test('an empty form parses to no questions', () {
      final d = parseGoogleForm(form(const []));
      expect(d.fields, isEmpty);
      expect(d.questionCount, 0);
    });
  });
}
