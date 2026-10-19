import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/post_detail_screen.dart';
import 'package:mykerawang/widgets/comment_tile.dart';
import 'package:mykerawang/widgets/post_card.dart';

import 'helpers/feed_fixtures.dart';

/// Thread layout at phone / tablet / desktop: no overflow; two columns
/// (post | comments + composer) only from 900 px.
void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  Map<String, dynamic> comment(String id, {bool anon = false}) => {
        'id': id,
        'post_id': 'p1',
        'body': 'Setuju! @amir jom pergi sekali. ' * 3,
        'is_anonymous': anon,
        'user_id': anon ? null : 'u$id',
        'profiles': anon
            ? null
            : {
                'id': 'u$id',
                'username': 'siti_kolej_kerawang_panjang',
                'display_name': 'Siti Nurhaliza binti Ahmad',
                'avatar_url': null,
              },
        'created_at': DateTime.now().toIso8601String(),
      };

  Widget layout({bool anonymous = false}) {
    final ctrl = TextEditingController();
    final comments = [comment('c1'), comment('c2', anon: true), comment('c3')];
    return Scaffold(
      body: PostDetailLayout(
        post: PostCard(post: samplePost(photos: 3, tags: ['rant']), expanded: true),
        commentsHeader: const Text('3 comments'),
        comments: Column(
          children: [
            for (var i = 0; i < comments.length; i++)
              CommentTile(comment: comments[i], threadLine: i < comments.length - 1),
          ],
        ),
        composer: CommentComposer(
          controller: ctrl,
          anonymous: anonymous,
          sending: false,
          canSend: false,
          onToggleAnonymous: () {},
          onSend: () {},
        ),
      ),
    );
  }

  for (final size in [kCompact, kMedium, kExpanded]) {
    final w = size.width.toInt();
    testWidgets('thread at $w px: no overflow', (tester) async {
      await pumpAt(tester, size, layout());
      expect(tester.takeException(), isNull);
      expect(find.byType(CommentTile), findsNWidgets(3));
      // Split = the comments header sits to the right of the post.
      final postX = tester.getTopLeft(find.byType(PostCard)).dx;
      final headerX = tester.getTopLeft(find.text('3 comments')).dx;
      expect(headerX > postX + 200, size.width >= 900);
    });
  }

  testWidgets('anonymous toggle is labelled in words', (tester) async {
    await pumpAt(tester, kCompact, layout());
    expect(find.text('Comment anonymously'), findsOneWidget);

    await pumpAt(tester, kCompact, layout(anonymous: true));
    expect(find.text('Anonymous — your name is hidden'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('anonymous comment shows no name or handle', (tester) async {
    await pumpAt(tester, kCompact, layout());
    expect(find.textContaining('Name hidden'), findsOneWidget);
    expect(find.text('Anonymous'), findsOneWidget);
  });
}
