/// User-typed text as a PostgREST filter value.
///
/// `supabase-dart` sends `.or('a.ilike.%x%,b.ilike.%x%')` as a *filter
/// string*, not as a parameter: inside it `,` separates conditions, `()` group
/// them, `.` separates column/operator/value, `"` and `\` quote, and `:`
/// casts. A search box must not be able to add conditions, so those
/// characters become spaces before the string is built.
///
/// `%` and `_` are LIKE wildcards, not structure — they are left alone (a
/// user searching "50%" may match more, not break the query).
library;

final RegExp _structure = RegExp(r'[,()"\\:]');

/// [raw] with filter syntax removed, whitespace collapsed, trimmed.
String filterSafe(String raw) =>
    raw.replaceAll(_structure, ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
