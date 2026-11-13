import '../l10n/app_strings.dart';
import '../l10n/notification_strings.dart';
import '../utils/formatters.dart';

/// Title and line for the kinds that carry structured data, in the
/// reader's language. Null for older rows and moderation/club notices,
/// which keep their stored text.
(String, String)? notificationHeadline(
  AppStrings s,
  Map<String, dynamic> n,
  String? actorName,
) {
  final d = n['data'] is Map ? n['data'] as Map : const {};
  final count = (n['count'] as num?)?.toInt() ?? 1;
  final who =
      actorName ??
      (n['type'] == 'form_answer' && '${d['who'] ?? ''}'.isNotEmpty
          ? '${d['who']}'
          : s.nSomeone);
  final evTitle = '${d['event_title'] ?? ''}';
  String when(dynamic raw) {
    final t = parseLocal(raw);
    return t == null ? '' : formatEventDate(t);
  }

  String join(List<String> parts) =>
      parts.where((p) => p.isNotEmpty).join(' · ');
  final snippet = '${d['snippet'] ?? n['body'] ?? ''}';

  return switch (n['type']) {
    'comment' => (
      d['post_id'] == null && d['event_id'] != null
          ? s.nCommentEvent(who, count)
          : s.nCommentPost(who, count),
      snippet,
    ),
    'also_commented' => (s.nAlsoCommented(who, count), snippet),
    'form_answer' => (
      s.nFormAnswer(count),
      join([
        '${d['form_title'] ?? ''}',
        if (count > 1 && who != s.nSomeone) s.nLatestFrom(who),
      ]),
    ),
    'event_join' => (s.nEventJoin(who, count), evTitle),
    'event_reminder' => (
      s.nStartingSoon,
      join([evTitle, s.nStartsAt(when(d['start'])), '${d['location'] ?? ''}']),
    ),
    'new_event' => (
      s.nNewEvent,
      join([evTitle, when(d['start']), '${d['location'] ?? ''}']),
    ),
    'event_changed' => (
      s.nEventChanged,
      join([
        evTitle,
        if (d['start'] != d['old_start']) s.nNowAt(when(d['start'])),
        if (d['location'] != d['old_location'] && d['location'] != null)
          s.nNowPlace('${d['location']}'),
      ]),
    ),
    'event_cancelled' => (s.nEventCancelled, evTitle),
    'follow' when actorName != null => (s.nFollow(who), ''),
    _ => null,
  };
}
