import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/l10n/app_strings.dart';
import 'package:mykerawang/l10n/social_strings.dart';
import 'package:mykerawang/screens/home_screen.dart';
import 'package:mykerawang/widgets/brand/brand.dart';
import 'package:mykerawang/widgets/embed_card.dart';
import 'package:mykerawang/widgets/feed_composer.dart';
import 'package:mykerawang/widgets/post_card.dart';
import 'package:mykerawang/widgets/post_card_skeleton.dart';

import 'helpers/feed_fixtures.dart';

/// FeedView at phone / tablet / desktop widths: no overflow, composer on
/// every size, discovery in the feed only when there's no right rail.
void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  final posts = [
    samplePost(id: 'pin', pinned: true, verified: true),
    samplePost(id: 'anon', anonymous: true, title: null),
    samplePost(id: 'p1', photos: 1, tags: ['question', 'lostfound']),
    samplePost(id: 'p2', photos: 2),
    samplePost(id: 'p3', photos: 3),
    samplePost(id: 'p4', photos: 6),
    samplePost(id: 'p5'),
  ];

  Widget feed({bool loading = false, List<Map<String, dynamic>>? p}) => FeedView(
        posts: p ?? posts,
        injectables: [sampleEvent('e1'), sampleListing('l1')],
        events: [sampleEvent('e1'), sampleEvent('e2')],
        listings: [sampleListing('l1')],
        isLoading: loading,
        onRefresh: () async {},
        onLoadMore: () {},
        onCompose: () {},
        onPosted: () {},
        onCreateMenu: () {},
      );

  for (final size in [kCompact, kMedium, kExpanded]) {
    final w = size.width.toInt();

    testWidgets('feed at $w px: no overflow, composer present', (tester) async {
      await pumpAt(tester, size, feed());
      expect(tester.takeException(), isNull);
      expect(find.byType(FeedComposer), findsOneWidget);
      expect(find.byType(PostCard), findsWidgets);

      // Scroll through the whole feed; every card must lay out cleanly.
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await tester.pump();
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('loading at $w px shows skeletons', (tester) async {
      await pumpAt(tester, size, feed(loading: true));
      expect(tester.takeException(), isNull);
      expect(find.byType(PostCardSkeleton), findsWidgets);
    });

    testWidgets('empty feed at $w px offers to post', (tester) async {
      await pumpAt(tester, size, feed(p: []));
      expect(tester.takeException(), isNull);
      expect(find.byType(BrandEmptyState), findsOneWidget);
      expect(find.widgetWithText(FilledButton, AppStrings.en.social.createFirstPost),
          findsOneWidget);
    });
  }

  testWidgets('discovery sections only without the rail', (tester) async {
    await pumpAt(tester, kCompact, feed());
    expect(find.text('Happening Soon'), findsOneWidget);

    await pumpAt(tester, kExpanded, feed());
    expect(find.text('Happening Soon'), findsNothing);
  });

  test('buildFeedItems: one embed after every 6th post', () {
    final many = [for (var i = 0; i < 13; i++) samplePost(id: 'p$i')];
    final inj = [sampleEvent('e'), sampleListing('l')];
    final items = buildFeedItems(many, inj);
    expect(items.length, 15);
    expect(items[6]['type'], 'event');
    expect(items[13]['type'], 'listing');
    expect(buildFeedItems(many, inj, inject: false).length, 13);
  });

  testWidgets('embeds render in the compact feed', (tester) async {
    final many = [for (var i = 0; i < 7; i++) samplePost(id: 'p$i')];
    await pumpAt(tester, kCompact, feed(p: many));
    await tester.scrollUntilVisible(find.byType(EmbedCard), 400,
        scrollable: find.descendant(
            of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);
    expect(tester.takeException(), isNull);
  });
}
