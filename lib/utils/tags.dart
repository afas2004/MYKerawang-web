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

/// Stored spellings to match when listing posts for [tag] — rows saved
/// before normalisation may still hold `lost&found`.
List<String> tagAliases(String tag) {
  final t = normalizeTag(tag);
  return t == kLostFoundTag ? const [kLostFoundTag, 'lost&found'] : [t];
}
