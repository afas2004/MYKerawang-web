import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Typed navigation helpers so every screen links the same way and every
/// piece of content gets a real, shareable URL.
///
/// The loaded row is passed as `extra` for an instant push; the route can
/// still rebuild it from the id alone when someone opens the link cold.
extension AppNav on BuildContext {
  void goItem(Map<String, dynamic> item) =>
      push('/item/${item['id']}', extra: item);

  void goEvent(Map<String, dynamic> event) =>
      push('/event/${event['id']}', extra: event);

  void goPost(Map<String, dynamic> post) =>
      push('/post/${post['id']}', extra: post);

  void goUser(String userId) => push('/u/$userId');

  void goSettings() => push('/settings');

  void goNotifications() => push('/notifications');
}
