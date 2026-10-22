import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/home_screen.dart';
import 'package:mykerawang/widgets/announcement_view.dart';
import 'package:mykerawang/widgets/post_card.dart';

import 'announcement_view_test.dart' show sampleAnnouncement;
import 'helpers/feed_fixtures.dart';

/// v1.4 Home: announcements show as compact cards; show_in_feed=false
/// ones stay in Announcements only.
void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  test('buildFeedItems drops show_in_feed=false and future publish_at', () {
    final items = buildFeedItems([
      samplePost(id: 'a'),
      {...sampleAnnouncement(), 'id': 'hidden', 'show_in_feed': false},
      {...samplePost(id: 'later'), 'publish_at': DateTime.now().add(const Duration(days: 1)).toUtc().toIso8601String()},
      {...sampleAnnouncement(), 'id': 'shown'},
    ], const []);
    expect(items.map((p) => p['id']), ['a', 'shown']);
  });

  for (final size in [kCompact, kExpanded]) {
    testWidgets('announcement renders as the compact card at ${size.width.toInt()} px',
        (tester) async {
      await pumpAt(
        tester,
        size,
        FeedView(
          posts: [sampleAnnouncement(), samplePost(id: 'p2')],
          onRefresh: () async {},
          onLoadMore: () {},
          onCompose: () {},
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(AnnouncementCard), findsOneWidget);
      expect(find.byType(PostCard), findsOneWidget);
    });
  }
}
