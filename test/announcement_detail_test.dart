import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/post_detail_screen.dart';
import 'package:mykerawang/utils/announcement_rules.dart';
import 'package:mykerawang/widgets/announcement_view.dart';
import 'package:mykerawang/widgets/comment_tile.dart';

import 'announcement_view_test.dart' show sampleAnnouncement;
import 'helpers/feed_fixtures.dart';

/// Announcement detail: reader template on top, comments respect
/// comments_enabled ("Comments are off" instead of the box).
void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  Widget page(Map<String, dynamic> post, {bool mine = false}) => Scaffold(
        body: PostDetailLayout(
          post: AnnouncementDetailHead(
            post: post,
            linkedEvent: sampleEvent('e1'),
            mine: mine,
            onEdit: () {},
            onDelete: () {},
          ),
          commentsHeader: const Text('Comments'),
          comments: const Column(children: []),
          composer: commentsEnabled(post) ? const SizedBox(height: 48, child: Text('composer')) : const CommentsOffNotice(),
        ),
      );

  for (final size in [kCompact, kExpanded]) {
    testWidgets('announcement detail at ${size.width.toInt()} px', (tester) async {
      await pumpAt(tester, size, page(sampleAnnouncement(comments: false), mine: true));
      expect(tester.takeException(), isNull);
      expect(find.byType(AnnouncementView), findsOneWidget);
      expect(find.text('Comments are off for this announcement'), findsOneWidget);
      expect(find.text('composer'), findsNothing);
      expect(find.text('Edit'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsOneWidget);
      expect(find.byType(CommentTile), findsNothing);
    });
  }

  testWidgets('comments on: the composer is there; readers get no Edit', (tester) async {
    await pumpAt(tester, kCompact, page(sampleAnnouncement()));
    expect(find.text('composer'), findsOneWidget);
    expect(find.text('Comments are off for this announcement'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  // Regression: an officer or an admin who didn't write the announcement
  // used to get Edit here, and the RPC refused it. Someone else's
  // announcement is share-only.
  testWidgets('someone else\'s announcement offers Share but not Edit/Delete',
      (tester) async {
    await pumpAt(tester, kCompact, page(sampleAnnouncement(), mine: false));
    expect(find.text('Edit'), findsNothing);
    expect(find.byTooltip('Delete'), findsNothing);
    expect(find.byTooltip('Share'), findsOneWidget);
  });
}
