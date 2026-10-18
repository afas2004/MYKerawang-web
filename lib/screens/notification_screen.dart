import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../l10n/social_strings.dart';
import '../language_cubit.dart';
import '../services/unread_notifications.dart';
import '../utils/formatters.dart';
import '../utils/adaptive.dart';
import '../utils/responsive.dart';
import '../utils/roles.dart';

/// Icon per notification type so the list is scannable.
IconData _iconFor(String? type) => switch (type) {
      'mention' => Icons.alternate_email,
      'follow' => Icons.person_add_alt,
      'comment' => Icons.chat_bubble_outline,
      'event' => Icons.event_available,
      'listing' => Icons.storefront,
      _ => Icons.notifications,
    };

/// Opens whatever the notification refers to (UI_UX_AUDIT 12.1).
/// Payload lives in the `data` json column.
void _openTarget(BuildContext context, Map<String, dynamic> notif) {
  final data = notif['data'];
  if (data is! Map) return;

  final postId = data['post_id'];
  final eventId = data['event_id'];
  final listingId = data['listing_id'] ?? data['item_id'];
  final actorId = notif['actor_id'];

  if (postId != null) {
    context.push('/post/$postId');
  } else if (eventId != null) {
    context.push('/event/$eventId');
  } else if (listingId != null) {
    context.push('/item/$listingId');
  } else if (notif['type'] == 'follow' && actorId != null) {
    context.push('/u/$actorId');
  }
}

Map _dataOf(Map<String, dynamic> notif) =>
    notif['data'] is Map ? notif['data'] as Map : const {};

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final _supabase = Supabase.instance.client;
  late final String? _userId = _supabase.auth.currentUser?.id;
  late final Stream<List<Map<String, dynamic>>>? _stream = _userId == null
      ? null
      : _supabase
          .from('notifications')
          .stream(primaryKey: ['id'])
          .eq('user_id', _userId)
          .order('created_at', ascending: false)
          .limit(100);

  /// Actor profiles by id, fetched once per id.
  final Map<String, Map<String, dynamic>> _actors = {};

  /// Notification ids whose actor must stay hidden: mentions made from an
  /// anonymous (or no longer visible) post or comment.
  final Set<dynamic> _anonymous = {};

  /// Notification ids already checked, so each row is resolved once.
  final Set<dynamic> _resolved = {};

  /// Fetches actor profiles and anonymity for rows not seen before.
  Future<void> _resolve(List<Map<String, dynamic>> rows) async {
    final fresh = rows.where((n) => !_resolved.contains(n['id'])).toList();
    if (fresh.isEmpty) return;
    _resolved.addAll(fresh.map((n) => n['id']));

    final commentIds = <String>{};
    final postIds = <String>{};
    for (final n in fresh) {
      if (n['type'] != 'mention') continue;
      final d = _dataOf(n);
      if (d['comment_id'] != null) {
        commentIds.add('${d['comment_id']}');
      } else if (d['post_id'] != null) {
        postIds.add('${d['post_id']}');
      }
    }

    try {
      // Anonymous comments are filtered out by RLS for everyone but the
      // author, so "not returned" counts as anonymous too.
      final publicComments = <String>{};
      if (commentIds.isNotEmpty) {
        final rows = await _supabase
            .from('comments')
            .select('id, is_anonymous')
            .inFilter('id', commentIds.toList());
        for (final c in rows) {
          if (c['is_anonymous'] != true) publicComments.add('${c['id']}');
        }
      }
      final publicPosts = <String>{};
      if (postIds.isNotEmpty) {
        final rows = await _supabase
            .from('posts_public')
            .select('id, is_anonymous')
            .inFilter('id', postIds.toList());
        for (final p in rows) {
          if (p['is_anonymous'] != true) publicPosts.add('${p['id']}');
        }
      }
      for (final n in fresh) {
        if (n['type'] != 'mention') continue;
        final d = _dataOf(n);
        final hidden = d['comment_id'] != null
            ? !publicComments.contains('${d['comment_id']}')
            : d['post_id'] != null && !publicPosts.contains('${d['post_id']}');
        if (hidden) _anonymous.add(n['id']);
      }

      final actorIds = fresh
          .where((n) => !_anonymous.contains(n['id']))
          .map((n) => n['actor_id'])
          .whereType<String>()
          .where((id) => !_actors.containsKey(id))
          .toSet();
      if (actorIds.isNotEmpty) {
        final profiles = await _supabase
            .from('profiles')
            .select('id, display_name, username, avatar_url')
            .inFilter('id', actorIds.toList());
        for (final p in profiles) {
          _actors[p['id'] as String] = p;
        }
      }
    } catch (e) {
      // Fail closed: without the check, don't reveal who mentioned them.
      debugPrint('Notification actor lookup failed: $e');
      for (final n in fresh) {
        if (n['type'] == 'mention') _anonymous.add(n['id']);
      }
    }
    if (mounted) setState(() {});
  }

  Map<String, dynamic>? _actorOf(Map<String, dynamic> notif) {
    if (_anonymous.contains(notif['id'])) return null;
    final id = notif['actor_id'];
    return id is String ? _actors[id] : null;
  }

  /// Rows store a fragment for some types ("mentioned you in a post");
  /// put the actor (or "Someone") in front so it reads as a sentence.
  String _sentence(AppStrings s, Map<String, dynamic> notif,
      Map<String, dynamic>? actor) {
    var body = '${notif['body'] ?? notif['message'] ?? ''}'.trim();
    if (body.isEmpty) return body;
    final first = body[0];
    final isFragment = first != first.toUpperCase() &&
        first == first.toLowerCase(); // starts lowercase (Latin scripts)
    if (isFragment) {
      final who = actor != null ? displayNameFor(s, actor) : s.social.someone;
      body = '$who $body';
    }
    if (RegExp(r'[A-Za-z0-9]$').hasMatch(body)) body = '$body.';
    return body;
  }

  Future<void> _markRead(Map<String, dynamic> notif) async {
    if (notif['is_read'] == true) return;
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true}).eq('id', notif['id']);
      UnreadNotifications.instance.refresh();
    } catch (e) {
      debugPrint('Mark read failed: $e');
    }
  }

  Future<void> _markAllRead() async {
    final s = context.l10nRead;
    try {
      await UnreadNotifications.instance.markAllRead();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.errorWithDetail.fill([e]))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: appBarConstrained(
        context,
        title: Text(s.notificationsTitle),
        actions: [
          if (_userId != null)
            ValueListenableBuilder<int>(
              valueListenable: UnreadNotifications.instance.count,
              builder: (context, unread, _) => IconButton(
                tooltip: s.social.markAllRead,
                icon: const Icon(Icons.done_all),
                onPressed: unread > 0 ? _markAllRead : null,
              ),
            ),
        ],
      ),
      body: PageBody(child: _userId == null
        ? Center(child: Text(s.loginToSeeNotifications))
        : StreamBuilder<List<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text(s.errorWithDetail.fill([snapshot.error])));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

              final notifications = snapshot.data!;
              _resolve(notifications);
              if (notifications.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 64, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(s.noNotifications),
                    ],
                  ),
                );
              }

              return ListView.separated(
                itemCount: notifications.length,
                separatorBuilder: (_,__) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final notif = notifications[index];
                  final isRead = notif['is_read'] ?? false;
                  final actor = _actorOf(notif);
                  final avatar = actor?['avatar_url'] as String?;

                  return ListTile(
                    tileColor: isRead
                        ? null
                        : scheme.primary.withValues(alpha: 0.05),
                    leading: actor != null
                        ? CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            backgroundImage:
                                avatar != null ? NetworkImage(avatar) : null,
                            child: avatar == null
                                ? Text(displayNameFor(s, actor).characters.first.toUpperCase())
                                : null,
                          )
                        // No (visible) actor: neutral type icon.
                        : CircleAvatar(
                            backgroundColor: isRead
                                ? scheme.surfaceContainerHighest
                                : scheme.primaryContainer,
                            child: Icon(
                              _iconFor(notif['type']),
                              size: 20,
                              color: isRead
                                  ? scheme.onSurfaceVariant
                                  : scheme.primary,
                            ),
                          ),
                    title: Text(notif['title'] ?? s.notifications,
                        style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                    subtitle: Text(_sentence(s, notif, actor)),
                    trailing: Text(
                      formatRelative(context, DateTime.parse(notif['created_at'])),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant),
                    ),
                    onTap: () {
                      // Mark as read, then open what it refers to (12.1)
                      _markRead(notif);
                      _openTarget(context, notif);
                    },
                  );
                },
              );
            },
          )),
    );
  }
}
