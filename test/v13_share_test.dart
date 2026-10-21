import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/widgets/brand/brand.dart';
import 'package:mykerawang/widgets/post_card.dart';

import 'helpers/feed_fixtures.dart';

/// v1.3 #4: sharing a post always carries that post's exact /post/<id>.
void main() {
  setUp(installFeedHooks);
  tearDown(() {
    resetFeedHooks();
    PostCard.debugShare = null;
  });

  test('postShareUrl is the absolute /post/<id> URL', () {
    expect(postSharePath('abc-123'), '/post/abc-123');
    final url = postShareUrl('abc-123');
    expect(url, endsWith('/post/abc-123'));
    expect(Uri.parse(url).hasScheme, isTrue);
  });

  testWidgets('Share hands the sheet the post route', (tester) async {
    String? title;
    PostCard.debugShare = (context, t, body, images, {String? link}) async {
      title = t;
      linkSeen = link;
    };
    linkSeen = null;
    await pumpAt(tester, kCompact,
        Scaffold(body: PostCard(post: samplePost(id: 'p42'))));
    await tester.tap(find.byTooltip('Share'));
    await tester.pump();
    expect(linkSeen, '/post/p42');
    expect(title, 'Lost wallet');
  });

  testWidgets('Copy link puts the post URL on the clipboard', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    await pumpAt(tester, kCompact,
        Scaffold(body: PostCard(post: samplePost(id: 'p7'))));
    await tester.pump();
    await tester.tap(find.byIcon(AppIcons.more));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pumpAndSettle();
    expect(copied, postShareUrl('p7'));
    expect(find.text('Link copied'), findsOneWidget);
  });
}

/// Set by the debugShare stub (its named `link` parameter shadows locals).
String? linkSeen;
