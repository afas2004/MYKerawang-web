import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/attendance_rules.dart';

/// The attendance flow's pure bits: names on the door screen, the CSV, and the
/// organiser's contact buttons.
void main() {
  group('the name on the door screen', () {
    test('drops the father\'s name and title-cases', () {
      expect(shortAttendeeName('NURUL ARISSA BINTI AZIZ'), 'Nurul Arissa');
      expect(shortAttendeeName('AHMAD DANEIL BIN WARI'), 'Ahmad Daneil');
      expect(shortAttendeeName('SITI a/p MUTHU'), 'Siti');
    });

    test('keeps at most two words', () {
      expect(shortAttendeeName('MUHAMMAD AZIM BIN MOHD KHAIRI'), 'Muhammad Azim');
      expect(shortAttendeeName('Nur Iman Solehah'), 'Nur Iman');
    });

    test('no bin/binti at all still shortens', () {
      expect(shortAttendeeName('ILYA SYAHIRAH ADILAH JAAFAR'), 'Ilya Syahirah');
    });

    test('empty and odd input do not throw', () {
      expect(shortAttendeeName(''), '');
      expect(shortAttendeeName('   '), '');
      expect(shortAttendeeName('binti'), 'Binti');
    });
  });

  group('the attendance CSV', () {
    final rows = [
      {
        'display_name': 'Nurul Arissa Binti Aziz',
        'student_id': '2023837334',
        'verified': true,
        'checked_in_at': '2026-10-25T12:00:00Z',
      },
      {
        'username': 'azim',
        'student_id': null,
        'verified': false,
        'checked_in_at': '2026-10-25T12:05:00Z',
      },
    ];

    test('has the columns the merit export wants', () {
      final lines = attendanceCsv(rows).trimRight().split('\n');
      expect(lines.first, 'name,student_id,verified,checked_in_at');
      expect(lines[1], 'Nurul Arissa Binti Aziz,2023837334,yes,2026-10-25T12:00:00Z');
      // falls back to the username, and a missing id is an empty cell
      expect(lines[2], 'azim,,no,2026-10-25T12:05:00Z');
    });

    test('quotes a name with a comma', () {
      final csv = attendanceCsv([
        {'display_name': 'Ali, bin Abu', 'student_id': '1', 'verified': false},
      ]);
      expect(csv, contains('"Ali, bin Abu"'));
    });

    test('no rows is still a header', () {
      expect(attendanceCsv(const []), 'name,student_id,verified,checked_in_at\n');
    });
  });

  test('file names carry the event and the date', () {
    expect(
      flowFileName('attendance', 'Malam Ujian KI', now: DateTime(2026, 10, 25)),
      'attendance-malam-ujian-ki-20261025.csv',
    );
    expect(
      flowFileName('ki', '  ', now: DateTime(2026, 1, 2)),
      'ki-event-20260102.csv',
    );
  });

  group('contact links', () {
    test('each channel becomes a link', () {
      final links = contactLinks({
        'whatsapp': '012-345 6789',
        'telegram': '@kerawang',
        'instagram': 'kelab.ab',
        'email': 'kelab@uitm.edu.my',
        'link': 'https://example.com',
      });
      expect(links.map((l) => l.channel), ['whatsapp', 'telegram', 'instagram', 'email', 'link']);
      expect(links[0].url, 'https://wa.me/0123456789');
      expect(links[1].url, 'https://t.me/kerawang');
      expect(links[2].url, 'https://instagram.com/kelab.ab');
      expect(links[3].url, 'mailto:kelab@uitm.edu.my');
    });

    test('blank channels are skipped', () {
      expect(contactLinks({'whatsapp': '', 'email': '  '}), isEmpty);
      expect(contactLinks(const {}), isEmpty);
    });
  });
}
