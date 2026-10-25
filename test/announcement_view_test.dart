import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/widgets/announcement_view.dart';

import 'helpers/feed_fixtures.dart';

Map<String, dynamic> sampleAnnouncement({bool comments = true}) => {
      ...samplePost(id: 'a1', title: 'Pendaftaran Minggu Kolej dibuka'),
      'is_announcement': true,
      'announcement_category': 'kolej',
      'body': 'Assalamualaikum semua.\n\n- Daftar sebelum **Jumaat**\n- Bawa kad matrik\n\nInfo: https://forms.gle/abc.',
      'cover_url': 'https://example.invalid/cover.jpg',
      'gallery_urls': ['https://example.invalid/1.jpg', 'https://example.invalid/2.jpg'],
      'action_links': [
        {'label': 'Daftar sekarang', 'url': 'https://forms.gle/abc'},
        {'label': 'Lihat acara', 'url': '/events'},
      ],
      'comments_enabled': comments,
      'club': {'id': 'c1', 'name': 'Jawatankuasa Perwakilan Kolej', 'handle': 'jpk'},
    };

void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  for (final size in [kCompact, kExpanded]) {
    final w = size.width.toInt();
    testWidgets('template at $w px', (tester) async {
      await pumpAt(
        tester,
        size,
        Scaffold(
          body: SingleChildScrollView(
            child: AnnouncementView(
              data: AnnouncementData.fromPost(sampleAnnouncement(),
                  linkedEvent: sampleEvent('e1')),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Pendaftaran Minggu Kolej dibuka'), findsOneWidget);
      expect(find.text('Kolej'), findsOneWidget);
      // A club announces as itself; the app's Official badge is only for
      // official accounts (verified profile), not for every club post.
      expect(find.text('Official'), findsNothing);
      expect(find.text('Daftar sekarang'), findsOneWidget);
      expect(find.text('Lihat acara'), findsOneWidget);
      expect(find.textContaining('Jawatankuasa'), findsOneWidget);
      expect(find.textContaining('Malam Kebudayaan'), findsOneWidget); // linked event
    });

    testWidgets('feed card at $w px', (tester) async {
      await pumpAt(tester, size,
          Scaffold(body: AnnouncementCard(post: sampleAnnouncement(), onTap: () {})));
      expect(tester.takeException(), isNull);
      expect(find.text('Kolej · Official'), findsNothing);
      expect(find.text('Kolej'), findsOneWidget);
    });
  }

  testWidgets('an official account keeps the badge', (tester) async {
    final post = {
      ...samplePost(id: 'a2', title: 'Notis kolej'),
      'is_announcement': true,
      'announcement_category': 'kolej',
      'body': 'Notis rasmi.',
      'profiles': {'id': 'p1', 'username': 'jpk', 'display_name': 'JPK', 'is_verified': true},
    };
    await pumpAt(
      tester,
      kCompact,
      Scaffold(
        body: SingleChildScrollView(
          child: AnnouncementView(data: AnnouncementData.fromPost(post)),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Official'), findsOneWidget);
  });

  testWidgets('external action asks before leaving the app', (tester) async {
    await pumpAt(
      tester,
      kCompact,
      Scaffold(
        body: SingleChildScrollView(
          child: AnnouncementView(data: AnnouncementData.fromPost(sampleAnnouncement())),
        ),
      ),
    );
    await tester.tap(find.text('Daftar sekarang'));
    await tester.pumpAndSettle();
    expect(find.textContaining('forms.gle'), findsWidgets);
    expect(find.byType(AlertDialog), findsOneWidget);
  });
}
