import 'package:flutter_test/flutter_test.dart';
import 'package:mykerawang/utils/club_posts.dart';

/// The club page shows pinned posts in their own slot. The bug this covers: a
/// club post pinned months ago used to fall outside the newest-30 window, so the
/// page silently lost it.
void main() {
  Map<String, dynamic> post(String id, {bool pinned = false}) => {
        'id': id,
        'title': 'Post $id',
        'is_club_pinned': pinned,
        'created_at': '2026-10-01T00:00:00Z',
      };

  test('a pinned post older than 30 others still gets its own slot', () {
    final rows = [
      for (var i = 0; i < 30; i++) post('new-$i'),
      post('old-pin', pinned: true),
    ];
    final sections = splitClubPosts(rows);

    expect(sections.pinned.map((p) => p['id']), ['old-pin']);
    expect(sections.rest.length, 30);
    // The service returns pinned first; the split preserves that order.
    expect(rows.firstWhere((r) => r['id'] == 'old-pin'), isNotNull);
  });

  test('the page no longer depends on where the pinned row sits in the list', () {
    final pinnedLast = [post('a'), post('b', pinned: true)];
    final pinnedFirst = [post('b', pinned: true), post('a')];

    expect(splitClubPosts(pinnedLast).pinned.map((p) => p['id']), ['b']);
    expect(splitClubPosts(pinnedFirst).pinned.map((p) => p['id']), ['b']);
    expect(splitClubPosts(pinnedFirst).rest.map((p) => p['id']), ['a']);
  });

  test('several pins keep their query order', () {
    final sections = splitClubPosts([
      post('p1', pinned: true),
      post('n1'),
      post('p2', pinned: true),
    ]);
    expect(sections.pinned.map((p) => p['id']), ['p1', 'p2']);
    expect(sections.rest.map((p) => p['id']), ['n1']);
  });

  test('nothing pinned, or nothing at all, is not an error', () {
    expect(splitClubPosts(const []).isEmpty, isTrue);

    final onlyRest = splitClubPosts([post('a'), post('b')]);
    expect(onlyRest.pinned, isEmpty);
    expect(onlyRest.rest.length, 2);
    expect(onlyRest.isEmpty, isFalse);

    final onlyPinned = splitClubPosts([post('a', pinned: true)]);
    expect(onlyPinned.rest, isEmpty);
    expect(onlyPinned.pinned.length, 1);
  });

  test('a missing flag counts as unpinned', () {
    final sections = splitClubPosts([
      {'id': 'x', 'title': 'No flag'},
    ]);
    expect(sections.pinned, isEmpty);
    expect(sections.rest.length, 1);
  });
}
