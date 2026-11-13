import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/share_service.dart';

/// Our link must be the FIRST link in a shared message: WhatsApp and most
/// chat apps build the preview card from the first link they see.
void main() {
  const ours = 'https://kerawang.my/event/abc123';
  const footer = 'Check this out on MYKerawang!';

  /// What the share pop-up starts with (see ShareService.shareContent).
  String sheetText(String title, String body) => '$title\n\n$body\n\n$footer';

  List<String> lines(String s) => s.split('\n');

  test('description with an external link: ours comes first', () {
    final msg = composeShareMessage(
      sheetText(
        'Malam Ujian KI',
        '📍 Dewan Kolej\n🗓 Sat 15 Nov · 8:00–10:00pm\n\n'
            'Register: https://forms.gle/xyz\nIG: https://instagram.com/kerawang',
      ),
      ours,
    );
    expect(
      msg,
      '*Malam Ujian KI*\n'
      '$ours\n'
      '\n'
      '📍 Dewan Kolej\n'
      '🗓 Sat 15 Nov · 8:00–10:00pm\n'
      '\n'
      'Register: https://forms.gle/xyz\n'
      'IG: https://instagram.com/kerawang\n'
      '\n'
      '$footer',
    );
    expect(msg.indexOf(ours), lessThan(msg.indexOf('https://forms.gle')));
  });

  test('empty text sends just the link', () {
    expect(composeShareMessage('', ours), ours);
    expect(composeShareMessage('  \n\n ', ours), ours);
  });

  test('link already in the text is not duplicated and moves to line 2', () {
    final msg = composeShareMessage('Title\n\nBody\n\n$ours', ours);
    expect(msg, '*Title*\n$ours\n\nBody');
    expect(ours.allMatches(msg).length, 1);

    // Already in the right place: unchanged apart from bold.
    expect(composeShareMessage('Title\n$ours\n\nBody', ours),
        '*Title*\n$ours\n\nBody');

    // Only the text was our link.
    expect(composeShareMessage(ours, ours), ours);
  });

  test('a longer URL that merely starts with ours is kept', () {
    const longer = 'https://kerawang.my/event/abc1234';
    final msg = composeShareMessage('Title\nSee $longer', ours);
    expect(msg, '*Title*\n$ours\n\nSee $longer');
  });

  test('multi-line title: link goes after its first line', () {
    final msg = composeShareMessage(sheetText('Malam\nUjian KI', 'Body'), ours);
    expect(lines(msg).take(3), ['*Malam*', ours, '']);
    expect(msg, contains('Ujian KI'));
  });

  test('sharer edited the text: their first line is the title', () {
    final msg = composeShareMessage('\n  Jom datang!  \nSee you there', ours);
    expect(msg, '*Jom datang!*\n$ours\n\nSee you there');
  });

  test('a title with * is not bolded', () {
    expect(composeShareMessage('2*3 Maths\nBody', ours),
        '2*3 Maths\n$ours\n\nBody');
    expect(composeShareMessage('*Already bold*\nBody', ours),
        '*Already bold*\n$ours\n\nBody');
  });

  test('no link: text unchanged', () {
    expect(composeShareMessage('Title\n\nBody', null), 'Title\n\nBody');
    expect(composeShareMessage('Title\n\nBody', ''), 'Title\n\nBody');
  });

  group('our link is on the second line for every share type', () {
    // Mirrors the text each caller builds.
    final cases = <String, String>{
      'event': sheetText(
        'Malam Ujian KI',
        '📍 Dewan Kolej\n🗓 Sat 15 Nov · 8:00–10:00pm\n\nForm: https://forms.gle/xyz',
      ),
      'market listing': sheetText(
        'Rice cooker',
        'Price: RM 30.00\nBarely used. Pics: https://instagram.com/p/1',
      ),
      'post': sheetText('Lost key', 'Found near the cafe. https://wa.me/601'),
      'post with no title (app name)': sheetText('MYKerawang', 'Hello'),
      'announcement with empty body': sheetText('Notice', ''),
    };
    cases.forEach((name, text) {
      test(name, () {
        final msg = composeShareMessage(text, ours);
        expect(lines(msg)[1], ours);
        expect(RegExp(r'https?://').firstMatch(msg)!.start, msg.indexOf(ours));
      });
    });

    test('WhatsApp the seller (withPageLink)', () {
      final msg = ShareService.withPageLink(
        'Hi! I\'m interested in your listing "Rice cooker" (RM 30.00) on MYKerawang.',
        '/item/abc',
      );
      expect(lines(msg)[1], '$kAppBaseUrl/item/abc');
      expect(lines(msg)[0], startsWith('Hi!')); // personal message: no bold
    });
  });
}
