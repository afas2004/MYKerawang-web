import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/formatters.dart';
import '../utils/adaptive.dart';
import '../utils/responsive.dart';

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

class NotificationScreen extends StatelessWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final userId = Supabase.instance.client.auth.currentUser?.id;

    return Scaffold(
      appBar: appBarConstrained(context,
          title: Text(context.l10n.notificationsTitle)),
      body: PageBody(child: userId == null 
        ? Center(child: Text(context.l10n.loginToSeeNotifications))
        : StreamBuilder(
            stream: Supabase.instance.client
                .from('notifications')
                .stream(primaryKey: ['id'])
                .eq('user_id', userId)
                .order('created_at', ascending: false)
                .limit(100),
            builder: (context, snapshot) {
              if (snapshot.hasError) return Center(child: Text(context.l10n.errorWithDetail.fill([snapshot.error])));
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              
              final notifications = snapshot.data!;
              if (notifications.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none,
                          size: 64,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(context.l10n.noNotifications),
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
                  
                  return ListTile(
                    tileColor: isRead
                        ? null
                        : Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
                    leading: CircleAvatar(
                      backgroundColor: isRead
                          ? Theme.of(context).colorScheme.surfaceContainerHighest
                          : Theme.of(context).colorScheme.primaryContainer,
                      child: Icon(
                        _iconFor(notif['type']),
                        size: 20,
                        color: isRead
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(notif['title'], style: TextStyle(fontWeight: isRead ? FontWeight.normal : FontWeight.bold)),
                    subtitle: Text(notif['body'] ?? notif['message'] ?? ''),
                    trailing: Text(
                      formatRelative(context, DateTime.parse(notif['created_at'])),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    onTap: () {
                      // Mark as read, then open what it refers to (12.1)
                      Supabase.instance.client
                          .from('notifications')
                          .update({'is_read': true}).eq('id', notif['id']);
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