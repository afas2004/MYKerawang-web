/// The club page's two post sections, as a pure rule.
///
/// The page lifts club-pinned posts into their own slot above the list, so
/// "which posts are pinned" is a decision worth testing on its own — the bug it
/// guards against is a pinned post that never appears because it was older than
/// the page's 30-post window.
library;

/// Pinned posts first (in the order they arrived), then everything else
/// (newest first, as the query returned it).
class ClubPostSections {
  final List<Map<String, dynamic>> pinned;
  final List<Map<String, dynamic>> rest;

  const ClubPostSections(this.pinned, this.rest);

  bool get isEmpty => pinned.isEmpty && rest.isEmpty;
}

ClubPostSections splitClubPosts(List<Map<String, dynamic>> posts) {
  final pinned = <Map<String, dynamic>>[];
  final rest = <Map<String, dynamic>>[];
  for (final p in posts) {
    if (p['is_club_pinned'] == true) {
      pinned.add(p);
    } else {
      rest.add(p);
    }
  }
  return ClubPostSections(pinned, rest);
}
