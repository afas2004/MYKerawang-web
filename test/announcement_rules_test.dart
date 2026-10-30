import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/announcement_rules.dart';

void main() {
  group('action links', () {
    test('internal routes must exist in the app', () {
      expect(validateActionLink('Join', '/event/abc'), isNull);
      expect(validateActionLink('Clubs', '/clubs'), isNull);
      expect(validateActionLink('Hub', '/announcements?tab=kolej'), isNull);
      expect(validateActionLink('Nope', '/admin/secret'), ActionLinkIssue.unknownRoute);
      expect(validateActionLink('Nope', '/event'), ActionLinkIssue.unknownRoute);
    });

    test('external links must be https', () {
      expect(validateActionLink('Form', 'https://forms.gle/x'), isNull);
      expect(validateActionLink('Form', 'http://forms.gle/x'), ActionLinkIssue.notHttps);
      expect(validateActionLink('Form', 'javascript:alert(1)'), ActionLinkIssue.badUrl);
      expect(validateActionLink('Form', 'forms.gle/x'), ActionLinkIssue.badUrl);
    });

    test('label 1–24 chars, url required', () {
      expect(validateActionLink('  ', '/home'), ActionLinkIssue.emptyLabel);
      expect(validateActionLink('x' * 25, '/home'), ActionLinkIssue.labelTooLong);
      expect(validateActionLink('x' * 24, '/home'), isNull);
      expect(validateActionLink('Go', ' '), ActionLinkIssue.emptyUrl);
    });

    test('listFrom drops bad entries and keeps at most 2', () {
      final links = ActionLink.listFrom([
        {'label': 'A', 'url': '/home'},
        {'label': 'Bad', 'url': 'http://x.com'},
        {'label': 'B', 'url': 'https://x.com'},
        {'label': 'C', 'url': '/events'},
        'junk',
      ]);
      expect(links.map((l) => l.label), ['A', 'B']);
      expect(ActionLink.listFrom(null), isEmpty);
    });
  });

  group('draft validation', () {
    List<AnnouncementIssue> v({
      String title = 'Notis',
      String body = '',
      String? category = 'club',
      List<String> allowed = kClubAnnouncementCategories,
      int images = 0,
      List<ActionLink> actions = const [],
      DateTime? publishAt,
      DateTime? featureUntil,
    }) =>
        validateAnnouncement(
          title: title,
          body: body,
          category: category,
          allowedCategories: allowed,
          extraImages: images,
          actions: actions,
          publishAt: publishAt,
          featureUntil: featureUntil,
        );

    test('a minimal club announcement is fine', () => expect(v(), isEmpty));
    test('title is required', () => expect(v(title: '  '), [AnnouncementIssue.titleRequired]));
    test('clubs cannot use kolej/jpk', () {
      expect(v(category: 'kolej'), [AnnouncementIssue.categoryNotAllowed]);
      expect(v(category: 'kolej', allowed: kAnnouncementCategories), isEmpty);
      expect(v(category: null), [AnnouncementIssue.categoryNotAllowed]);
    });
    test('limits', () {
      expect(v(images: 5), [AnnouncementIssue.tooManyImages]);
      expect(v(actions: const [ActionLink('a', '/home'), ActionLink('b', '/home'), ActionLink('c', '/home')]),
          [AnnouncementIssue.tooManyActions]);
      expect(v(actions: const [ActionLink('a', 'http://x.com')]), [AnnouncementIssue.badAction]);
      expect(v(body: 'x' * 5001), [AnnouncementIssue.bodyTooLong]);
    });
    test('banner end must be after publishing', () {
      final at = DateTime(2026, 11, 1, 9);
      expect(v(publishAt: at, featureUntil: at), [AnnouncementIssue.featureBeforePublish]);
      expect(v(publishAt: at, featureUntil: at.add(const Duration(days: 1))), isEmpty);
    });
  });

  group('feed rules', () {
    final now = DateTime.utc(2026, 10, 23, 12);
    test('show_in_feed=false and future publish_at stay out of Home', () {
      expect(showInHomeFeed({'show_in_feed': false}, now: now), isFalse);
      expect(showInHomeFeed({'publish_at': '2026-10-24T00:00:00Z'}, now: now), isFalse);
      expect(showInHomeFeed({'publish_at': '2026-10-22T00:00:00Z'}, now: now), isTrue);
      expect(showInHomeFeed({}, now: now), isTrue); // columns not there yet
    });
    test('comments default on', () {
      expect(commentsEnabled({}), isTrue);
      expect(commentsEnabled({'comments_enabled': false}), isFalse);
    });
  });

  group('page title', () {
    String title(Map<String, dynamic> post) =>
        postPageTitle(post, thread: 'Thread', announcement: 'Announcement');

    test('names the kind of page, not the headline', () {
      expect(title({'title': 'Kelas tambahan'}), 'Thread');
      expect(title({'title': 'Kelas tambahan', 'is_announcement': true}),
          'Announcement');
      expect(title({}), 'Thread');
      expect(title({'is_announcement': true, 'title': '  '}), 'Announcement');
    });
  });

  group('light formatting', () {
    test('paragraphs and bullets', () {
      final blocks = parseBody('Hello kolej\nline two\n\n- one\n• two\n* three\n\nBye');
      expect(blocks.length, 3);
      expect((blocks[0] as ParagraphBlock).text, 'Hello kolej\nline two');
      expect((blocks[1] as BulletsBlock).items, ['one', 'two', 'three']);
      expect((blocks[2] as ParagraphBlock).text, 'Bye');
    });

    test('bold and https links, punctuation kept outside', () {
      expect(parseInline('Daftar **sekarang** di https://x.com/a.'), const [
        InlineSpan('Daftar '),
        InlineSpan('sekarang', bold: true),
        InlineSpan(' di '),
        InlineSpan('https://x.com/a', url: 'https://x.com/a'),
        InlineSpan('.'),
      ]);
      expect(parseInline('http://insecure.com'), const [InlineSpan('http://insecure.com')]);
    });
  });
}
