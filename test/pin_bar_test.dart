import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/screens/admin/pins_tab.dart';
import 'package:mykerawang/screens/home_screen.dart';
import 'package:mykerawang/services/pinned_posts.dart';
import 'package:mykerawang/widgets/pin_bar.dart';
import 'package:mykerawang/widgets/pin_restore_row.dart';
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

  testWidgets('the chevron folds the preview back', (t) async {
    await pumpAt(t, kCompact, bar([pin('a', mandatory: true)]));
    await t.tap(find.byTooltip('Show more'));
    await t.pumpAndSettle();
    expect(find.text('Body of a'), findsOneWidget);
    await t.tap(find.byTooltip('Show less'));
    await t.pumpAndSettle();
    expect(find.text('Body of a'), findsNothing);
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

  testWidgets('Next shows only when unfolded, keeps the preview open and wraps', (t) async {
    await pumpAt(t, kCompact, bar([pin('a'), pin('b')]));
    expect(find.text('Next'), findsNothing);

    await t.tap(find.text('Pin a'));
    await t.pumpAndSettle();
    expect(find.text('Next'), findsOneWidget);

    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('2/2'), findsOneWidget);
    expect(find.text('Body of b'), findsOneWidget); // still unfolded

    await t.tap(find.text('Next'));
    await t.pumpAndSettle();
    expect(find.text('1/2'), findsOneWidget);
    expect(find.text('Body of a'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('a single pin has no Next button', (t) async {
    await pumpAt(t, kCompact, bar([pin('a')]));
    await t.tap(find.text('Pin a'));
    await t.pumpAndSettle();
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('a mandatory pin has no close button', (t) async {
    await pumpAt(t, kCompact, bar([pin('a', mandatory: true)]));
    expect(find.byTooltip('Close pin'), findsNothing);
    await pumpAt(t, kCompact, bar([pin('b')]));
    expect(find.byTooltip('Close pin'), findsOneWidget);
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

  // ---- closed pins, brought back ----

  testWidgets('the restore row counts closed pins and nothing at zero',
      (t) async {
    var restored = 0;
    await pumpAt(t, kCompact,
        Scaffold(body: PinRestoreRow(count: 0, onRestore: () => restored++)));
    expect(find.text('Show'), findsNothing);

    await pumpAt(t, kCompact,
        Scaffold(body: PinRestoreRow(count: 1, onRestore: () => restored++)));
    expect(find.text('1 closed pin'), findsOneWidget);

    await pumpAt(t, kCompact,
        Scaffold(body: PinRestoreRow(count: 3, onRestore: () => restored++)));
    expect(find.text('3 closed pins'), findsOneWidget);

    await t.tap(find.text('Show'));
    await t.pumpAndSettle();
    expect(restored, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('the feed offers closed pins back once the bar is empty',
      (t) async {
    Widget feed({required int closed}) => FeedView(
          posts: [samplePost(id: 'b', title: 'Plain post')],
          pins: const [],
          closedPins: closed,
          onRestorePins: () {},
          onRefresh: () async {},
          onLoadMore: () {},
          onCompose: () {},
        );

    await pumpAt(t, kCompact, feed(closed: 0));
    await t.pump();
    expect(find.text('Show'), findsNothing);

    await pumpAt(t, kCompact, feed(closed: 2));
    await t.pump();
    expect(find.text('2 closed pins'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  test('restore clears the closed list and the count follows', () async {
    PinnedPosts.debugLoad = () async => [pin('a'), pin('b')];
    await PinnedPosts.refresh();
    expect(PinnedPosts.closedCount.value, 0);

    await PinnedPosts.dismiss(pin('a'));
    expect(PinnedPosts.closedCount.value, 1);
    expect(PinnedPosts.pins.value.map((p) => p['id']), ['b']);

    await PinnedPosts.restore();
    expect(PinnedPosts.closedCount.value, 0);
    expect(PinnedPosts.pins.value.map((p) => p['id']), ['a', 'b']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList('dismissed_pins'), isNull);

    // A reload must not bring the closed pin back by itself.
    await PinnedPosts.dismiss(pin('a'));
    await PinnedPosts.refresh();
    expect(PinnedPosts.closedCount.value, 1);
  });

  test('a mandatory pin is never counted as closed', () async {
    PinnedPosts.debugLoad = () async => [pin('a', mandatory: true)];
    await PinnedPosts.refresh();
    await PinnedPosts.dismiss(pin('a', mandatory: true));
    expect(PinnedPosts.closedCount.value, 0);
  });

  // ---- admin console: the Pins tab ----

  testWidgets('the admin Pins tab lists every pin, closed ones included',
      (t) async {
    PinnedPosts.debugAdminLoad = () async => [
          {...pin('a'), 'pinned_until': '2026-12-31T00:00:00Z'},
          pin('b', mandatory: true),
        ];
    // Closed on this device: the tab must show it all the same.
    await PinnedPosts.dismiss(pin('a'));

    await pumpAt(t, kExpanded, const Scaffold(body: PinsTab()));
    await t.pumpAndSettle();
    expect(find.text('Pin a'), findsOneWidget);
    expect(find.text('Pin b'), findsOneWidget);
    expect(find.text('Until 31 Dec 2026'), findsOneWidget);
    expect(find.text('Mandatory pin'), findsOneWidget);
    // Unpin on both rows; the mandatory one offers "Make normal".
    expect(find.text('Make normal'), findsOneWidget);
    expect(find.text('Make mandatory'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('the admin Pins tab says so when nothing is pinned', (t) async {
    PinnedPosts.debugAdminLoad = () async => [];
    await pumpAt(t, kExpanded, const Scaffold(body: PinsTab()));
    await t.pumpAndSettle();
    expect(find.text('Nothing is pinned'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

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
