/// Club mentions in user-written text: `@[handle]`.
///
/// A club has a handle but no profile, and club handles and usernames are
/// not one namespace, so `@kerawang` could ping a person called kerawang.
/// The brackets keep a club mention out of `@username` parsing (`[` is not
/// a word character) and still read sensibly as plain text.
final clubMentionPattern = RegExp(r'@\[([A-Za-z0-9_.\-]+)\]');

/// What the composer inserts for [handle].
String clubMentionToken(String handle) => '@[$handle]';

/// Handles mentioned in [text], in order, without duplicates.
List<String> clubHandlesIn(String text) => [
      ...{for (final m in clubMentionPattern.allMatches(text)) m.group(1)!},
    ];

/// [text] for places that show it unformatted (excerpts, previews): each
/// club mention becomes the club's name, or `@handle` while it is unknown.
String plainClubMentions(String text, [Map<String, String> names = const {}]) =>
    text.replaceAllMapped(clubMentionPattern, (m) {
      final h = m.group(1)!;
      return names[h.toLowerCase()] ?? '@$h';
    });
