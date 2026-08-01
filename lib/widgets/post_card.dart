import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_parsed_text/flutter_parsed_text.dart';
import 'package:mykerawang/utils/app_nav.dart';
import 'package:mykerawang/utils/report_helper.dart';
import 'package:mykerawang/widgets/embed_card.dart';
import 'package:mykerawang/theme/app_themes.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class PostCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback? onTap;
  final bool showProfileHeader;

  const PostCard({super.key, required this.post, this.onTap, this.showProfileHeader = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAnon = post['is_anonymous'] ?? false;
    
    // Safety check for date
    final createdVal = post['created_at'];
    final date = createdVal != null ? DateTime.parse(createdVal) : DateTime.now();

    // Data parsing
    final rawProfile = post['profiles'];
    final Map<String, dynamic>? profile = (rawProfile is List && rawProfile.isNotEmpty) 
        ? rawProfile.first 
        : (rawProfile is Map<String, dynamic> ? rawProfile : null);

    final String displayName = isAnon 
        ? "Anonymous Student" 
        : (profile?['display_name'] ?? "UiTM Student");
    final String? avatarUrl = isAnon ? null : profile?['avatar_url'];
    final String? username = isAnon ? null : profile?['username'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      elevation: 0,
      // Signature kerawang cut — DESIGN_SPEC §2
      shape: RoundedRectangleBorder(
        borderRadius: kerawangCut,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      color: theme.cardColor,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              
              // 1. HEADER (User + PFP)
              if (showProfileHeader)
                Row(
                  children: [
                    GestureDetector(
                      onTap: (isAnon || profile == null) 
                          ? null 
                        : () => context.goUser(profile['id']),
                    child: CircleAvatar(
                      radius: 16, // Slightly larger for better visibility
                      backgroundColor: isAnon ? Colors.grey : theme.colorScheme.primaryContainer,
                      backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                      child: (avatarUrl == null) 
                          ? Icon(isAnon ? Icons.visibility_off : Icons.person, size: 16, color: isAnon ? Colors.white : theme.colorScheme.onPrimaryContainer)
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  
                  // Name & Time Column
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: theme.colorScheme.onSurface),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (!isAnon && username != null) ...[
                              const SizedBox(width: 4),
                              Text(
                                "@$username",
                                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                              ),
                            ]
                          ],
                        ),
                        Text(
                          timeago.format(date, locale: 'en_short'),
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  
                  
                ],
              ),
              const SizedBox(height: 12),

              // Tag
                  if (post['tags'] != null && (post['tags'] as List).isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "#${post['tags'][0]}",
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                      ),
                    ),
                
                const SizedBox(height: 12),

              // 2. TITLE
              Text(
                post['title'] ?? 'No Title',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, height: 1.3),
              ),
              const SizedBox(height: 6),

              // 3. BODY PREVIEW
              if (post['body'] != null)
                ParsedText(
                  text: post['body'] ?? '',
                  style: TextStyle(color: theme.colorScheme.onSurface), // Your default style
                  parse: [
                    MatchText(
                      pattern: r"\@(\w+)", // Regex to find @username
                      style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                      onTap: (username) async {
                        final cleanName = username.substring(1); // Remove '@'
                        
                        // Find the user ID based on the username
                        final user = await Supabase.instance.client
                            .from('profiles')
                            .select('id')
                            .eq('username', cleanName)
                            .maybeSingle();

                        if (user != null && context.mounted) {
                          // Navigate to their profile
                          context.goUser(user['id']);
                        } else if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("User not found")));
                        }
                      },
                    ),
                  ],
                ),
              
              // 4. SHARED CONTENT (Event OR Listing) — same embed language
              // as the feed, compact so it supports rather than dominates.
              if (post['events'] != null)
                EmbedCard(
                  data: post['events'],
                  isEvent: true,
                  compact: true,
                  onTap: () => context.goEvent(post['events']),
                )
              else if (post['listings'] != null)
                EmbedCard(
                  data: post['listings'],
                  isEvent: false,
                  compact: true,
                  onTap: () => context.goItem(post['listings']),
                ),

              const SizedBox(height: 16),

              // 5. FOOTER (Just Replies & Share)
              Row(
                children: [
                  // Comment Count
                  Icon(Icons.chat_bubble_outline, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Builder(builder: (context) {
                    final count = post['comment_count'] ?? 0;
                    return Text(
                      "$count ${count == 1 ? 'Reply' : 'Replies'}",
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  }),
                  
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Colors.grey),
                    onSelected: (value) {
                      if (value == 'report') {
                        // Call the helper we just made
                        showReportDialog(context, post['id'], 'post');
                      }
                      // You can add 'delete' here later for the owner
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(Icons.flag, color: Colors.red, size: 20),
                            SizedBox(width: 8),
                            Text("Report", style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

}