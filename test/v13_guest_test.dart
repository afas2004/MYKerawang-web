import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/post_detail_screen.dart';

import 'helpers/feed_fixtures.dart';

/// v1.3 #5: guests can read a post but get a sign-in prompt instead of
/// the comment box.
void main() {
  setUp(installFeedHooks);
  tearDown(resetFeedHooks);

  Widget box(bool loggedIn) => Scaffold(
        body: GuestableComposer(
          loggedIn: loggedIn,
          composer: CommentComposer(
            controller: TextEditingController(),
            anonymous: false,
            sending: false,
            canSend: false,
            onToggleAnonymous: () {},
            onSend: () {},
          ),
        ),
      );

  for (final size in [kCompact, kMedium, kExpanded]) {
    testWidgets('guest at ${size.width.toInt()} px: "Sign in to comment"', (tester) async {
      await pumpAt(tester, size, box(false));
      expect(tester.takeException(), isNull);
      expect(find.byType(CommentComposer), findsNothing);
      expect(find.text('Sign in to comment'), findsOneWidget);
    });
  }

  testWidgets('member: the comment box', (tester) async {
    await pumpAt(tester, kCompact, box(true));
    expect(find.byType(CommentComposer), findsOneWidget);
    expect(find.text('Sign in to comment'), findsNothing);
  });
}
