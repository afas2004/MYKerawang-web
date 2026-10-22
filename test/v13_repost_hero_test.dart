import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/widgets/embed_card.dart';
import 'package:mykerawang/widgets/post_card.dart';

import 'helpers/feed_fixtures.dart';

/// v1.3 #3: a post that shares an event/listing leads with it; the
/// post's own photos shrink to a thumbnail strip.
void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  Map<String, dynamic> repost({int photos = 0, bool event = true}) => {
        ...samplePost(id: 'r1', photos: photos),
        if (event) 'events': sampleEvent('e1') else 'listings': sampleListing('l1'),
      };

  for (final size in [kCompact, kMedium, kExpanded]) {
    testWidgets('shared event is the hero at ${size.width.toInt()} px', (tester) async {
      await pumpAt(tester, size,
          Scaffold(body: SingleChildScrollView(child: PostCard(post: repost(photos: 3)))));
      expect(tester.takeException(), isNull);
      expect(find.byType(SharedItemHero), findsOneWidget);
      expect(find.byType(PostPhotoStrip), findsOneWidget);
      expect(find.byType(PostPhotoLayout), findsNothing);
      expect(find.text('View event'), findsOneWidget); // the CTA
    });
  }

  testWidgets('hero sits directly under the text, above the strip', (tester) async {
    await pumpAt(tester, kCompact,
        Scaffold(body: SingleChildScrollView(child: PostCard(post: repost(photos: 2)))));
    final heroY = tester.getTopLeft(find.byType(SharedItemHero)).dy;
    final stripY = tester.getTopLeft(find.byType(PostPhotoStrip)).dy;
    final bodyY = tester.getTopLeft(find.textContaining('Brown', findRichText: true)).dy;
    expect(bodyY < heroY && heroY < stripY, isTrue);
  });

  testWidgets('no photos: hero only; listing shows its price', (tester) async {
    await pumpAt(tester, kCompact,
        Scaffold(body: SingleChildScrollView(child: PostCard(post: repost(event: false)))));
    expect(find.byType(SharedItemHero), findsOneWidget);
    expect(find.byType(PostPhotoStrip), findsNothing);
    expect(find.textContaining('RM 15'), findsOneWidget);
  });

  testWidgets('plain post keeps the full photo layout', (tester) async {
    await pumpAt(tester, kCompact,
        Scaffold(body: SingleChildScrollView(child: PostCard(post: samplePost(photos: 2)))));
    expect(find.byType(PostPhotoLayout), findsOneWidget);
    expect(find.byType(SharedItemHero), findsNothing);
  });
}
