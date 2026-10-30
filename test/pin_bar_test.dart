import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/home_screen.dart';
import 'package:mykerawang/services/pinned_posts.dart';
import 'package:mykerawang/widgets/pin_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/feed_fixtures.dart';

void main() {
  setUp(installFeedHooks);
  tearDown(() {
    resetFeedHooks();
    PinnedPosts.debugReset();
  });

  Map<String, dynamic> pin(String id, {bool mandatory = false}) => {
        ...samplePost(id: id, title: 'Pin $id', body: 'Body of $id', pinned: true),
        'pin_mandatory': mandatory,
      };

  Widget bar(List<Map<String, dynamic>> pins,
          {ValueChanged<Map<String, dynamic>>? onOpen}) =>
      Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: PinBar(
            pins: pins,
            onOpen: onOpen ?? (_) {},
            onDismiss: (_) {},
          ),
        ),
      );

  testWidgets('first tap expands, second opens the post', (t) async {
    Map<String, dynamic>? opened;
    await pumpAt(t, kCompact, bar([pin('a')], onOpen: (p) => opened = p));
    expect(find.text('Body of a'), findsNothing);

    await t.tap(find.text('Pin a'));
    await t.pumpAndSettle();
    expect(find.text('Body of a'), findsOneWidget);
    expect(opened, isNull);

    await t.tap(find.text('Pin a'));
    await t.pumpAndSettle();
    expect(opened?['id'], 'a');
    expect(t.takeException(), isNull);
  });

  testWidgets('swipe moves to the next pin and the counter follows', (t) async {
    await pumpAt(t, kCompact, bar([pin('a'), pin('b')]));
    expect(find.text('1/2'), findsOneWidget);
    await t.drag(find.byType(PageView), const Offset(-300, 0));
    await t.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('Pin b'), findsOneWidget);
  });

  testWidgets('a mandatory pin has no close button', (t) async {
    await pumpAt(t, kCompact, bar([pin('a', mandatory: true)]));
    expect(find.byType(IconButton), findsNothing);
    await pumpAt(t, kCompact, bar([pin('b')]));
    expect(find.byType(IconButton), findsOneWidget);
  });

  for (final size in [kCompact, kExpanded]) {
    testWidgets('feed at ${size.width}: pinned post leaves the list', (t) async {
      await pumpAt(
        t,
        size,
        FeedView(
          posts: [
            samplePost(id: 'a', title: 'Pin a'),
            samplePost(id: 'b', title: 'Plain post'),
          ],
          pins: [pin('a')],
          onRefresh: () async {},
          onLoadMore: () {},
          onCompose: () {},
        ),
      );
      await t.pump();
      expect(find.text('Pin a'), findsOneWidget); // the bar, not a card too
      expect(find.text('Plain post'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  test('mandatory first, closed pins stay closed, mandatory cannot close',
      () async {
    PinnedPosts.debugLoad =
        () async => [pin('a'), pin('b', mandatory: true)];
    await PinnedPosts.refresh();
    expect(PinnedPosts.pins.value.map((p) => p['id']), ['b', 'a']);

    await PinnedPosts.dismiss(pin('a'));
    await PinnedPosts.dismiss(pin('b', mandatory: true));
    expect(PinnedPosts.pins.value.map((p) => p['id']), ['b']);

    await PinnedPosts.refresh();
    expect(PinnedPosts.pins.value.map((p) => p['id']), ['b']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('dismissed_pins'), ['a']);
  });
}
