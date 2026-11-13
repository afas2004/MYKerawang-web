/// Where a notification opens: the exact post comment, event, form answers
/// or profile it is about. Same rules as `link_for` in worker/push.py, so a
/// tap in the bell and a tap on the phone notification land on one page.
library;

Map _data(Map<String, dynamic> n) => n['data'] is Map ? n['data'] as Map : const {};

String? notificationPath(Map<String, dynamic> n) {
  final d = _data(n);
  final type = n['type'];
  final post = d['post_id'], event = d['event_id'], form = d['form_id'];
  final comment = d['comment_id'];
  final listing = d['listing_id'] ?? d['item_id'];
  final c = comment != null ? '?c=$comment' : '';

  if (type == 'form_answer' && form != null) {
    return event != null ? '/event/$event/form/responses?f=$form' : '/f/$form/responses';
  }
  if (post != null) return '/post/$post$c';
  if (event != null) return '/event/$event$c';
  if (listing != null) return '/item/$listing';
  if (type == 'follow' && n['actor_id'] != null) return '/u/${n['actor_id']}';
  final route = d['route'];
  if (route is String && route.startsWith('/')) return route;
  return null;
}

/// Bell filter a notification belongs to.
enum NotifFilter { all, social, events, forms, account }

NotifFilter notificationFilter(Map<String, dynamic> n) =>
    switch (n['category'] ?? '') {
      'comments' || 'mentions' || 'follows' => NotifFilter.social,
      'reminders' || 'event_changes' || 'event_joins' || 'new_events' => NotifFilter.events,
      'form_answers' => NotifFilter.forms,
      _ => switch (n['type']) {
          'mention' || 'follow' || 'comment' => NotifFilter.social,
          'event' => NotifFilter.events,
          _ => NotifFilter.account,
        },
    };
