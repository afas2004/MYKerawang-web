import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/services/comment_pins.dart';
import 'package:mykerawang/widgets/brand/brand.dart';
import 'package:mykerawang/widgets/comment_tile.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'helpers/feed_fixtures.dart';

/// v1.3 #2: up to 3 pinned comments per post / event, shown first.
void main() {
  setUp(installFeedHooks);
  tearDown(() {
    resetFeedHooks();
    CommentPins.debugRpc = null;
  });

  Map<String, dynamic> comment(String id, {String? pinnedAt}) => {
        'id': id,
        'body': 'comment $id',
        'is_anonymous': false,
        'user_id': 'u$id',
        'profiles': {'id': 'u$id', 'username': 'user$id', 'display_name': 'User $id'},
        'created_at': DateTime.now().toIso8601String(),
        'pinned_at': pinnedAt,
      };

  test('pinnedFirst: pinned in pin order, then the rest unchanged', () {
    final rows = [
      comment('a'),
      comment('b', pinnedAt: '2026-10-22T10:00:00Z'),
      comment('c'),
      comment('d', pinnedAt: '2026-10-22T09:00:00Z'),
    ];
    expect(pinnedFirst(rows).map((c) => c['id']), ['d', 'b', 'a', 'c']);
  });

  testWidgets('pinned comment shows the Pinned label', (tester) async {
    await pumpAt(tester, kCompact,
        Scaffold(body: CommentTile(comment: comment('x', pinnedAt: '2026-10-22T10:00:00Z'))));
    expect(find.text('Pinned'), findsOneWidget);
    await pumpAt(tester, kCompact, Scaffold(body: CommentTile(comment: comment('y'))));
    expect(find.text('Pinned'), findsNothing);
  });

  Future<List<String>> menu(WidgetTester tester, CommentTile tile) async {
    await pumpAt(tester, kCompact, Scaffold(body: tile));
    await tester.tap(find.byIcon(AppIcons.more));
    await tester.pumpAndSettle();
    final shown = [
      for (final t in ['Pin comment', 'Unpin comment', 'Edit', 'Delete', 'Report'])
        if (find.text(t).evaluate().isNotEmpty) t
    ];
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    return shown;
  }

  testWidgets('menu offers pin only when allowed', (tester) async {
    expect(await menu(tester, CommentTile(comment: comment('a'))), ['Report']);
    expect(await menu(tester, CommentTile(comment: comment('a'), onTogglePin: () {})),
        ['Pin comment', 'Report']);
    expect(
        await menu(tester,
            CommentTile(comment: comment('a', pinnedAt: 'x'), onTogglePin: () {})),
        ['Unpin comment', 'Report']);
  });

  Future<bool?> toggle(WidgetTester tester, Map<String, dynamic> c) async {
    bool? result;
    await pumpAt(
      tester,
      kCompact,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await CommentPins.toggle(context, c),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('pinning calls the RPC and confirms', (tester) async {
    final calls = <(String, bool)>[];
    CommentPins.debugRpc = (id, pin) async {
      calls.add((id, pin));
      return null;
    };
    expect(await toggle(tester, comment('a')), isTrue);
    expect(calls, [('a', true)]);
    expect(find.text('Comment pinned'), findsOneWidget);
  });

  testWidgets('at the limit: "Unpin one first"', (tester) async {
    CommentPins.debugRpc = (id, pin) async => throw const PostgrestException(
          message: 'MOD:comment_pin_limit',
          code: 'P0001',
          details: '{"max": 3}',
        );
    expect(await toggle(tester, comment('a')), isNull);
    expect(find.text('You can pin up to 3 comments. Unpin one first.'), findsOneWidget);
  });
}
