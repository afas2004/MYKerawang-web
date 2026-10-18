import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../l10n/shell_strings.dart';
import '../l10n/social_strings.dart';
import '../language_cubit.dart';
import '../services/unread_notifications.dart';
import '../utils/formatters.dart';
import '../utils/adaptive.dart';
import '../utils/roles.dart';
import '../widgets/brand/brand.dart';

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
              builder: (context, unread, _) => TextButton.icon(
                onPressed: unread > 0 ? _markAllRead : null,
                icon: const Icon(Icons.done_all),
                label: Text(s.social.markAllRead),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: PageBody(child: _userId == null
        ? _NotifEmpty(
            title: s.loginToSeeNotifications,
            body: s.shell.notificationsEmptyBody,
          )
        : StreamBuilder<List<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _NotifEmpty(
                  icon: Icons.wifi_off,
                  title: s.connectionError,
                  body: '${snapshot.error}',
                );
              }
              if (!snapshot.hasData) return const _NotifSkeleton();

              final notifications = snapshot.data!;
              _resolve(notifications);
              if (notifications.isEmpty) {
                return _NotifEmpty(
                  title: s.shell.allCaughtUp,
                  body: s.shell.notificationsEmptyBody,
                );
              }

              // Today / This week / Earlier, newest first within each.
              final groups = <String, List<Map<String, dynamic>>>{};
              for (final n in notifications) {
                final when = parseLocal(n['created_at']) ?? DateTime(2000);
                final label = switch (notificationBucket(when, DateTime.now())) {
                  NotifBucket.today => s.shell.today,
                  NotifBucket.thisWeek => s.shell.thisWeek,
                  NotifBucket.earlier => s.shell.earlier,
                };
                (groups[label] ??= []).add(n);
              }

              return ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  for (final entry in groups.entries) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Semantics(
                        header: true,
                        child: Text(entry.key,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(color: scheme.onSurfaceVariant)),
                      ),
                    ),
                    for (final notif in entry.value) _tile(context, notif),
                  ],
                ],
              );
            },
          )),
    );
  }

  Widget _tile(BuildContext context, Map<String, dynamic> notif) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isRead = notif['is_read'] == true;
    final actor = _actorOf(notif);
    final avatar = actor?['avatar_url'] as String?;

    final leading = actor != null
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                child: avatar == null
                    ? Text(displayNameFor(s, actor).characters.first.toUpperCase())
                    : null,
              ),
              // Small type glyph on the avatar keeps the list scannable.
              Positioned(
                right: -4,
                bottom: -4,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: scheme.surface,
                  child: Icon(_iconFor(notif['type']), size: 12, color: scheme.primary),
                ),
              ),
            ],
          )
        // No (visible) actor: neutral type icon.
        : CircleAvatar(
            backgroundColor:
                isRead ? scheme.surfaceContainerHighest : scheme.primaryContainer,
            child: Icon(
              _iconFor(notif['type']),
              size: 20,
              color: isRead ? scheme.onSurfaceVariant : scheme.primary,
            ),
          );

    final tile = Material(
      color: isRead ? Colors.transparent : scheme.primaryContainer.withValues(alpha: 0.35),
      child: InkWell(
        onTap: () {
          // Mark as read, then open what it refers to (12.1)
          _markRead(notif);
          _openTarget(context, notif);
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: 64),
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          decoration: BoxDecoration(
            border: Border(
              // Unread rows carry a primary edge, not just a tint.
              left: BorderSide(
                color: isRead ? Colors.transparent : scheme.primary,
                width: 3,
              ),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(notif['title'] ?? s.notifications,
                        style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: isRead ? FontWeight.w500 : FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(_sentence(s, notif, actor),
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(
                      formatRelative(context, DateTime.parse(notif['created_at'])),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (!isRead)
                IconButton(
                  tooltip: s.shell.markRead,
                  icon: const Icon(Icons.mark_email_read_outlined),
                  onPressed: () => _markRead(notif),
                ),
            ],
          ),
        ),
      ),
    );

    if (isRead) return tile;
    // Swipe either way to mark read; the row stays (the stream updates it).
    return Dismissible(
      key: ValueKey('notif-${notif['id']}'),
      confirmDismiss: (_) async {
        await _markRead(notif);
        return false;
      },
      background: _swipeBackground(context, Alignment.centerLeft),
      secondaryBackground: _swipeBackground(context, Alignment.centerRight),
      child: tile,
    );
  }

  Widget _swipeBackground(BuildContext context, Alignment align) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.secondaryContainer,
      alignment: align,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.mark_email_read_outlined, color: scheme.onSecondaryContainer),
          const SizedBox(width: 8),
          Text(context.l10n.shell.markRead,
              style: TextStyle(color: scheme.onSecondaryContainer)),
        ],
      ),
    );
  }
}

enum NotifBucket { today, thisWeek, earlier }

/// Which date group a notification falls in, relative to [now].
NotifBucket notificationBucket(DateTime when, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(when.year, when.month, when.day);
  if (!day.isBefore(today)) return NotifBucket.today;
  if (today.difference(day).inDays < 7) return NotifBucket.thisWeek;
  return NotifBucket.earlier;
}

/// Empty / signed-out / error state.
class _NotifEmpty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  const _NotifEmpty({
    this.icon = Icons.notifications_none,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) =>
      BrandEmptyState(icon: icon, title: title, message: body.isEmpty ? null : body);
}

class _NotifSkeleton extends StatelessWidget {
  const _NotifSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 6,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const KSkeleton.circle(),
            const SizedBox(width: KSpace.l),
            Expanded(child: KSkeleton.lines(3)),
          ],
        ),
      ),
    );
  }
}
