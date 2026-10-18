import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/tag_feed_screen.dart';
import 'package:mykerawang/widgets/post_card.dart';
import 'package:mykerawang/widgets/post_card_skeleton.dart';

import 'helpers/feed_fixtures.dart';

void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  TagFeedView view({
    List<Map<String, dynamic>> posts = const [],
    bool loading = false,
    Object? error,
    int? count,
  }) =>
      TagFeedView(
        tag: 'lostfound',
        count: count,
        posts: posts,
        loading: loading,
        error: error,
        hasMore: false,
        onRefresh: () async {},
        onLoadMore: () {},
      );

  for (final size in [kCompact, kMedium, kExpanded]) {
    final w = size.width.toInt();
    testWidgets('tag feed at $w px: header, count, cards', (tester) async {
      await pumpAt(
        tester,
        size,
        view(
          count: 2,
          posts: [
            samplePost(id: 'a', tags: ['lostfound'], photos: 2),
            samplePost(id: 'b', anonymous: true, tags: ['lostfound']),
          ],
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('#lostfound'), findsWidgets);
      expect(find.text('2 posts'), findsOneWidget);
      expect(find.byType(PostCard), findsNWidgets(2));
    });
  }

  testWidgets('loading, empty and error states', (tester) async {
    await pumpAt(tester, kCompact, view(loading: true));
    expect(find.byType(PostCardSkeleton), findsWidgets);

    await pumpAt(tester, kCompact, view(count: 0));
    expect(find.text('No posts with this tag yet'), findsOneWidget);

    await pumpAt(tester, kCompact, view(error: 'offline'));
    expect(find.text('Try again'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
