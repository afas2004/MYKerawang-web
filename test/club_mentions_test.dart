import 'package:flutter/material.dart' hide InlineSpan;
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/club_service.dart';
import 'package:mykerawang/services/mention_service.dart';
import 'package:mykerawang/utils/announcement_rules.dart';
import 'package:mykerawang/utils/club_mentions.dart';
import 'package:mykerawang/widgets/announcement_view.dart';
import 'package:mykerawang/widgets/club_mention_chip.dart';
import 'package:mykerawang/widgets/mention_input.dart';

void main() {
  group('club mention token', () {
    test('round-trips and is found in text', () {
      expect(clubMentionToken('kelab.foto'), '@[kelab.foto]');
      expect(clubHandlesIn('Bersama @[kelab.foto] dan @[jpk] dan @[jpk]'),
          ['kelab.foto', 'jpk']);
    });

    test('never reads as a person mention', () {
      // A club handle can equal someone's username; the brackets keep the
      // club out of the people who get notified.
      expect(MentionService.usernamesIn('Bersama @[ali] dan @siti'), {'siti'});
    });

    test('plain text shows the name, or @handle while unknown', () {
      const text = 'Anjuran @[foto] dan @[jpk].';
      expect(plainClubMentions(text, {'foto': 'Kelab Fotografi'}),
          'Anjuran Kelab Fotografi dan @jpk.');
    });

    test('the body parser marks it', () {
      expect(parseInline('Oleh @[foto], **hari ini**'), const [
        InlineSpan('Oleh '),
        InlineSpan('@[foto]', club: 'foto'),
        InlineSpan(', '),
        InlineSpan('hari ini', bold: true),
      ]);
    });
  });

  testWidgets('a page shows a club mention as a chip with the club name',
      (tester) async {
    ClubMentionDirectory.debugSet(const [
      Club(id: '1', handle: 'Foto', name: 'Kelab Fotografi', category: 'arts'),
    ]);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: FormattedBody('Anjuran @[foto] minggu ini')),
    ));
    expect(find.byType(ClubMentionChip), findsOneWidget);
    expect(find.text('Kelab Fotografi'), findsOneWidget);
  });

  testWidgets('the composer highlights mentions without changing the text',
      (tester) async {
    final c = MentionEditingController(text: 'Hi @ali, with @[foto]');
    late TextSpan span;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        span = c.buildTextSpan(context: context, withComposing: false);
        return const SizedBox();
      }),
    ));
    expect(span.toPlainText(), c.text);
    final runs = span.children!.cast<TextSpan>();
    expect(runs.where((r) => r.style != null).map((r) => r.text),
        ['@ali', '@[foto]']);
  });
}
