import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/safe_link_strings.dart';
import 'package:mykerawang/language_cubit.dart';
import 'package:mykerawang/screens/admin/allowed_links_tab.dart';
import 'package:mykerawang/services/allowed_links.dart';
import 'package:mykerawang/utils/safe_links.dart';
import 'package:mykerawang/widgets/mention_text.dart';
import 'package:mykerawang/widgets/post_card.dart';

/// The spans MentionText drew, flattened.
List<TextSpan> _spans(WidgetTester tester) {
  final rich = tester.widget<RichText>(find.descendant(
      of: find.byType(MentionText), matching: find.byType(RichText)).first);
  final out = <TextSpan>[];
  rich.text.visitChildren((s) {
    if (s is TextSpan && s.text != null) out.add(s);
    return true;
  });
  return out;
}

TextSpan _span(WidgetTester tester, String text) =>
    _spans(tester).firstWhere((s) => s.text == text);

void main() {
  setUp(AllowedLinks.debugReset);
  tearDown(AllowedLinks.debugReset);

  Future<void> pump(WidgetTester tester, Widget child,
      {double width = 360}) async {
    await tester.pumpWidget(
      BlocProvider(
        create: (_) => LanguageCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: width, child: child)),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('MentionText.parse', () {
    test('allowed link, plain link, mention, punctuation', () {
      final parts = MentionText.parse(
          'Join https://chat.whatsapp.com/AbC. Not https://evil.com/@x, ask @amir',
          kSeedAllowedDomains);
      expect(parts.map((p) => p.runtimeType.toString()).toList(),
          ['PlainPart', 'LinkPart', 'PlainPart', 'UserMentionPart']);
      expect((parts[1] as LinkPart).text, 'https://chat.whatsapp.com/AbC');
      // The link that isn't allowed stays in the plain text, unchanged,
      // and the @x inside it isn't a mention.
      expect((parts[2] as PlainPart).text, '. Not https://evil.com/@x, ask ');
    });

    test('displayText shortens only allowed long links', () {
      const long = 'https://docs.google.com/forms/d/e/1FAIpQLSexample/viewform';
      const evil = 'https://example.com/a/very/long/path/that/is/not/allowed';
      expect(MentionText.displayText('$long $evil', kSeedAllowedDomains),
          '${linkLabel(long)} $evil');
    });
  });

  group('MentionText links', () {
    testWidgets('allowed link: link colour, underlined, tappable',
        (tester) async {
      await pump(tester, const MentionText('Form: https://forms.gle/abc.'));
      final link = _span(tester, 'https://forms.gle/abc');
      final scheme = Theme.of(tester.element(find.byType(MentionText))).colorScheme;
      expect(link.style?.color, scheme.primary);
      expect(link.style?.decoration, TextDecoration.underline);
      expect(link.recognizer, isA<TapGestureRecognizer>());
      // The full stop stays plain.
      expect(_spans(tester).last.text, '.');
      expect(_spans(tester).last.recognizer, isNull);
    });

    testWidgets('not allowed: plain text, unchanged, not tappable',
        (tester) async {
      const text = 'Win! https://evil-forms.gle.com/login and www.example.com';
      await pump(tester, const MentionText(text));
      final spans = _spans(tester);
      expect(spans.map((s) => s.text).join(), text);
      expect(spans.every((s) => s.recognizer == null), isTrue);
      expect(spans.every((s) => s.style?.decoration == null), isTrue);
    });

    testWidgets('bare www and uppercase links work', (tester) async {
      await pump(tester, const MentionText('www.uitm.edu.my or HTTPS://WA.ME/601'));
      expect(_span(tester, 'www.uitm.edu.my').recognizer, isNotNull);
      expect(_span(tester, 'HTTPS://WA.ME/601').recognizer, isNotNull);
    });

    testWidgets('long link shows ~40 characters with …', (tester) async {
      const long = 'https://docs.google.com/forms/d/e/1FAIpQLSexample/viewform';
      await pump(tester, const MentionText('Register $long'));
      final link = _spans(tester).firstWhere((s) => s.recognizer != null);
      expect(link.text, linkLabel(long));
      expect(link.text!.length, kLinkDisplayMax);
      expect(link.semanticsLabel, long);
    });

    testWidgets('the list can change: a removed site stops being tappable',
        (tester) async {
      await pump(tester, const MentionText('https://t.me/club'));
      expect(_span(tester, 'https://t.me/club').recognizer, isNotNull);
      AllowedLinks.debugSet(kSeedAllowedDomains.where((d) => d != 't.me'));
      await tester.pump();
      expect(_span(tester, 'https://t.me/club').recognizer, isNull);
    });

    testWidgets('mentions still work next to links', (tester) async {
      await pump(tester, const MentionText('@amir shared https://youtu.be/x'));
      final mention = _span(tester, '@amir');
      expect(mention.style?.fontWeight, FontWeight.bold);
      expect(mention.recognizer, isNotNull);
    });
  });

  group('feed card', () {
    testWidgets('still capped at 5 lines with long links', (tester) async {
      final body = List.generate(
          12,
          (i) => 'Line $i https://docs.google.com/forms/d/e/1FAIpQLSexample$i/viewform '
              'and https://example.com/not/allowed/$i').join('\n');
      const style = TextStyle(fontSize: 14, height: 1.4);
      await pump(tester, PostBodyPreview(body: body, style: style, onReadMore: () {}));
      final rich = tester.widget<RichText>(find.descendant(
          of: find.byType(MentionText), matching: find.byType(RichText)).first);
      expect(rich.maxLines, PostBodyPreview.maxLines);
      expect(rich.overflow, TextOverflow.ellipsis);
      final box = tester.getSize(find.byType(MentionText));
      // Fewer than 6 lines tall (the test font rounds line heights).
      expect(box.height, lessThan(6 * 14 * 1.4));
      expect(box.height, greaterThan(4 * 14 * 1.4));
      expect(find.text('Read more'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a short post with one long link has no Read more',
        (tester) async {
      await pump(
          tester,
          PostBodyPreview(
              body: 'Form: https://docs.google.com/forms/d/e/1FAIpQLSexample/viewform',
              style: const TextStyle(fontSize: 14),
              onReadMore: () {}));
      expect(find.text('Read more'), findsNothing);
    });
  });

  group('admin: add dialog', () {
    Future<List<String>> open(WidgetTester tester, String input) async {
      final saved = <String>[];
      await pump(
          tester,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showDialog<String>(
                context: context,
                builder: (_) => AddAllowedDomainDialog(
                  existing: const {'forms.gle'},
                  save: (d, n) async => saved.add(d),
                ),
              ),
              child: const Text('open'),
            ),
          ),
          width: 800);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('allowed-domain-field')), input);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('allowed-save')));
      await tester.pumpAndSettle();
      return saved;
    }

    testWidgets('a pasted link is cleaned to its host', (tester) async {
      expect(await open(tester, 'https://www.Instagram.com/kerawang/'),
          ['instagram.com']);
    });

    testWidgets('a duplicate is refused', (tester) async {
      expect(await open(tester, 'https://forms.gle/abc'), isEmpty);
      expect(find.text(AppStrings.en.slDuplicate('forms.gle')), findsOneWidget);
    });

    testWidgets('junk is refused', (tester) async {
      expect(await open(tester, 'not a site'), isEmpty);
      expect(find.text(AppStrings.en.slInvalid), findsOneWidget);
    });
  });

  group('admin: list', () {
    testWidgets('shows the sites with their notes, on a phone', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(BlocProvider(
        create: (_) => LanguageCubit(),
        child: MaterialApp(
          home: Scaffold(
            body: AllowedLinksTab(
              load: () async => const [
                AllowedDomain('forms.gle', note: 'Google Forms short links'),
                AllowedDomain('wa.me'),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('forms.gle'), findsOneWidget);
      expect(find.text('Google Forms short links'), findsOneWidget);
      expect(find.byKey(const ValueKey('allowed-remove-wa.me')), findsOneWidget);
      expect(find.text(AppStrings.en.slAdd), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
