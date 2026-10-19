import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/widgets/brand/brand.dart';
import 'package:mykerawang/theme/app_icons.dart';
import 'package:mykerawang/widgets/post_card.dart';

import 'helpers/feed_fixtures.dart';

/// PostCard variants at every width: nothing overflows, photo layouts
/// pick the right arrangement, and the action row keeps 48 px targets.
void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  final variants = <String, Map<String, dynamic>>{
    'plain': samplePost(),
    'no title': samplePost(title: null),
    'anonymous': samplePost(anonymous: true),
    'verified + pinned': samplePost(verified: true, pinned: true),
    '1 photo': samplePost(photos: 1),
    '2 photos': samplePost(photos: 2),
    '3 photos': samplePost(photos: 3),
    '6 photos': samplePost(photos: 6, tags: ['question', 'lostfound', 'academic']),
    'long body': samplePost(body: 'Panjang gila cerita ni. ' * 40),
  };

  for (final size in [kCompact, kMedium, kExpanded]) {
    final w = size.width.toInt();
    for (final entry in variants.entries) {
      testWidgets('${entry.key} at $w px', (tester) async {
        await pumpAt(
          tester,
          size,
          Scaffold(
            body: SingleChildScrollView(
              child: PostCard(post: entry.value, onTap: () {}),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('photo tiles: one per photo up to 4, then +N', (tester) async {
    Future<void> pumpPhotos(int n) => pumpAt(
          tester,
          kCompact,
          Scaffold(
            body: SingleChildScrollView(
              child: PostCard(post: samplePost(id: 'n$n', photos: n)),
            ),
          ),
        );

    for (final n in [1, 2, 3, 4]) {
      await pumpPhotos(n);
      expect(find.bySemanticsLabel(RegExp('Post photo \\d of $n')),
          findsNWidgets(n), reason: '$n photos');
    }
    await pumpPhotos(6);
    expect(find.bySemanticsLabel(RegExp('Post photo \\d of 6')), findsNWidgets(4));
    expect(find.text('+2'), findsOneWidget);
  });

  testWidgets('pinned post is an official card labelled Pinned', (tester) async {
    await pumpAt(
      tester,
      kCompact,
      Scaffold(body: PostCard(post: samplePost(pinned: true))),
    );
    expect(find.text('Pinned'), findsOneWidget);
    expect(find.widgetWithIcon(KCard, AppIcons.pin), findsOneWidget);

    await pumpAt(tester, kCompact,
        Scaffold(body: PostCard(post: samplePost(id: 'plain'))));
    expect(find.text('Pinned'), findsNothing);
  });

  testWidgets('verified author shows the badge', (tester) async {
    await pumpAt(tester, kCompact,
        Scaffold(body: PostCard(post: samplePost(verified: true))));
    expect(find.byIcon(AppIcons.verified), findsOneWidget);
    expect(find.byTooltip('Verified'), findsOneWidget);
  });

  testWidgets('action row targets are at least 48 px', (tester) async {
    await pumpAt(tester, kCompact,
        Scaffold(body: PostCard(post: samplePost())));
    for (final f in [
      find.byTooltip('Share'),
      find.byTooltip('More'),
      find.ancestor(
          of: find.text('2'),
          matching: find.byWidgetPredicate((w) => w is TextButton)),
    ]) {
      final size = tester.getSize(f.first);
      expect(size.height, greaterThanOrEqualTo(48), reason: '$f');
      expect(size.width, greaterThanOrEqualTo(48), reason: '$f');
    }
  });
}
