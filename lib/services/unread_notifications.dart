import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Live count of the signed-in user's unread notifications (is_read =
/// false), for the bell and the sidebar entry.
///
/// A realtime channel on the user's rows triggers a cheap head count, so
/// the number is always exact rather than derived from a capped stream.
/// Started/stopped by SessionWatcher (main.dart) as the session changes.
class UnreadNotifications {
  UnreadNotifications._();
  static final instance = UnreadNotifications._();

  final count = ValueNotifier<int>(0);

  final _supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  String? _userId;
  Timer? _coalesce;

  void start(String userId) {
    if (_userId == userId && _channel != null) return;
    stop();
    _userId = userId;
    _channel = _supabase
        .channel('unread-notifications-$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _scheduleRefresh(),
        )
        .subscribe();
    refresh();
  }

  void stop() {
    _coalesce?.cancel();
    final ch = _channel;
    if (ch != null) _supabase.removeChannel(ch);
    _channel = null;
    _userId = null;
    count.value = 0;
  }

  /// "Mark all as read" fires one event per row — count once.
  void _scheduleRefresh() {
    _coalesce?.cancel();
    _coalesce = Timer(const Duration(milliseconds: 300), refresh);
  }

  Future<void> refresh() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final n = await _supabase
          .from('notifications')
          .count(CountOption.exact)
          .eq('user_id', uid)
          .eq('is_read', false);
      if (_userId == uid) count.value = n;
    } catch (e) {
      debugPrint('Unread count error: $e');
    }
  }

  /// Marks every unread notification of the current user as read.
  Future<void> markAllRead() async {
    final uid = _userId ?? _supabase.auth.currentUser?.id;
    if (uid == null) return;
    count.value = 0; // optimistic
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', uid)
        .eq('is_read', false);
    await refresh();
  }
}

/// [child] with the live unread count as a badge (hidden at zero).
class UnreadBadge extends StatelessWidget {
  final Widget child;
  const UnreadBadge({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: UnreadNotifications.instance.count,
      builder: (context, n, _) => Badge(
        isLabelVisible: n > 0,
        label: Text(n > 99 ? '99+' : '$n'),
        child: child,
      ),
    );
  }
}
