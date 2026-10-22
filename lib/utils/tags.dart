/// Post hashtags. Stored lowercase without `#`; shown as `#tag`.
///
/// Lost & Found is a reserved tag (DESIGN_SPEC): every spelling
/// (Lost&Found, lost-found, lost_found, #LostFound…) becomes `lostfound`.
const kLostFoundTag = 'lostfound';

final _tagPattern = RegExp(r'#?([\w&-]+)');
final _separators = RegExp(r'[&_\-\s]');

/// One tag in its stored form, or '' if nothing is left.
String normalizeTag(String raw) {
  final t = raw.trim().toLowerCase().replaceFirst(RegExp(r'^#+'), '');
  if (t.replaceAll(_separators, '') == kLostFoundTag) return kLostFoundTag;
  return t;
}

/// Unique normalised tags typed into a free-text field, in order.
List<String> parseTags(String text) => _tagPattern
    .allMatches(text)
    .map((m) => normalizeTag(m.group(1)!))
    .where((t) => t.isNotEmpty)
    .toSet()
    .toList();

/// How a stored tag is shown.
String displayTag(String stored) => '#${normalizeTag(stored)}';

/// Spellings to match when listing posts for [tag].
///
/// Migration 20261022003100 normalises stored tags (and a trigger keeps
/// them normalised), but until it runs older rows still hold what the
/// first editors saved: "Rant", "#rant", "Lost&Found". Matching those
/// too keeps the tag feed and its count right either way.
List<String> tagAliases(String tag) {
  final t = normalizeTag(tag);
  if (t.isEmpty) return const [];
  String cap(String s) => s[0].toUpperCase() + s.substring(1);
  final forms = <String>{t, '#$t', cap(t), t.toUpperCase()};
  if (t == kLostFoundTag) {
    // No spaces: they'd need quoting inside PostgREST's {a,b} list.
    forms.addAll(const ['lost&found', 'Lost&Found', 'LostFound', 'lost-found']);
  }
  return forms.toList();
}

/// Whether a posts row carries [tag], however it was stored.
bool postHasTag(Map<String, dynamic> post, String tag) {
  final want = normalizeTag(tag);
  return List<String>.from(post['tags'] ?? const [])
      .any((stored) => normalizeTag(stored) == want);
}

/// Stored form of a whole tag list: normalised, no blanks, no repeats,
/// first spelling's position kept (mirrors SQL normalize_tags()).
List<String> normalizeTags(Iterable<String> raw) =>
    raw.map(normalizeTag).where((t) => t.isNotEmpty).toSet().toList();
