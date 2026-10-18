import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mykerawang/services/share_service.dart';
import 'package:mykerawang/utils/report_helper.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import '../widgets/mention_text.dart';
import '../widgets/status_badge.dart';
import '../widgets/tap_card.dart';
import 'create_post_screen.dart'; 
import 'create_event_screen.dart';
import 'gallery_view_screen.dart';
import '../utils/responsive.dart';
import '../widgets/restriction_gate.dart';

class EventDetailScreen extends StatefulWidget {
  final Map<String, dynamic> event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  late Map<String, dynamic> _event;
  Map<String, dynamic>? _organizer;
  bool _isLoading = true;
  int _currentImageIndex = 0; 
  final _commentCtrl = TextEditingController();
  bool _isJoined = false;       // <--- NEW: Did I join?
  int _participantCount = 0;    // <--- NEW: Total count
  late Stream<List<Map<String, dynamic>>> _commentsStream;

  final List<String> _trustedDomains = [
    'uitm.edu.my', 
    'google.com', 'forms.gle', 'docs.google.com',
    'whatsapp.com', 'wa.me',
    'instagram.com', 'facebook.com', 'twitter.com', 'x.com',
    't.me', 'telegram.org',
    'linkedin.com'
  ];

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    _commentsStream = _fetchCommentsStream();
    _fetchEventDetails();
  }

  Future<void> _fetchEventDetails() async {
    final supabase = Supabase.instance.client;
    try {
      final freshEvent = await supabase.from('events').select().eq('id', _event['id']).single();
      final organizer = await supabase.from('profiles').select().eq('id', freshEvent['organizer_id']).maybeSingle();

      // 2. NEW: Fetch Participant Count
      final count = await supabase
          .from('event_participants')
          .count(CountOption.exact)
          .eq('event_id', _event['id']);
      
      // 3. NEW: Check if *I* already joined
      bool amIJoined = false;
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final myEntry = await supabase
            .from('event_participants')
            .select()
            .eq('event_id', _event['id'])
            .eq('user_id', userId)
            .maybeSingle();
        amIJoined = myEntry != null;
      }

      if (mounted) {
        setState(() {
          _event = freshEvent;
          _organizer = organizer;
          _participantCount = count; // <--- Update Count
          _isJoined = amIJoined;     // <--- Update My Status
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching details: $e");
    }
  }

  /// Realtime can only subscribe to a real table, and a raw `comments`
  /// stream carries `user_id` even for anonymous comments. So the stream is
  /// used purely as a change signal; the rows actually rendered come from
  /// `comments_public`, which blanks the author.
  Stream<List<Map<String, dynamic>>> _fetchCommentsStream() async* {
    yield await _fetchEventComments();

    final signal = Supabase.instance.client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('event_id', _event['id']);

    await for (final _ in signal) {
      yield await _fetchEventComments();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchEventComments() async {
    final rows = await Supabase.instance.client
        .from('comments_public')
        .select('*')
        .eq('event_id', _event['id'])
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _postComment() async {
    if (_commentCtrl.text.trim().isEmpty) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    if (!await ensureCanWrite(context, ModScope.comment) || !mounted) return;

    try {
      await Supabase.instance.client.from('comments').insert({
        'event_id': _event['id'],
        'user_id': user.id,
        'body': _commentCtrl.text.trim(),
      });
      _commentCtrl.clear();
      if (mounted) FocusScope.of(context).unfocus();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeWriteError(context, e))));
    }
  }

  // --- NEW: Delete Logic ---
  Future<void> _deleteEvent() async {
    final s = context.l10nRead;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.cancelEvent),
        content: Text(s.cancelEventConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.keepEvent)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.delete, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client.from('events').delete().eq('id', _event['id']);
        if (mounted) {
          Navigator.pop(context, true); // Return true to refresh profile/home
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.eventCancelled)));
        }
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.errorWithDetail.fill([e]))));
      }
    }
  }

  // --- 2. SAFETY: LINK CHECKER ---
  Future<void> _launchSafeUrl(String url) async {
    final uri = Uri.parse(url);
    final host = uri.host.toLowerCase().replaceFirst('www.', '');

    bool isTrusted = _trustedDomains.any((domain) => host.endsWith(domain));

    if (isTrusted) {
      // Safe -> Launch immediately
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      // Unknown -> Warning Dialog
      final s = context.l10nRead;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            Icon(Icons.warning_amber, color: Theme.of(ctx).colorScheme.error),
            const SizedBox(width: 8),
            Expanded(child: Text(s.leavingApp)),
          ]),
          content: Text(s.externalLinkWarning.fill([host])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                launchUrl(uri, mode: LaunchMode.externalApplication);
              },
              child: Text(s.openAnyway),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _toggleJoin() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10nRead.loginToJoin)));
      return;
    }
    if (!_isJoined && (!await ensureCanWrite(context, ModScope.events) || !mounted)) return;

    // 1. Instant UI Update (Makes it feel fast)
    setState(() {
      _isJoined = !_isJoined;
      _participantCount += _isJoined ? 1 : -1;
    });

    try {
      // 2. Update Database
      if (_isJoined) {
        await supabase.from('event_participants').insert({
          'event_id': _event['id'],
          'user_id': userId,
        });
      } else {
        await supabase.from('event_participants').delete().match({
          'event_id': _event['id'],
          'user_id': userId,
        });
      }
    } catch (e) {
      // 3. Revert if error
      if (mounted) {
        setState(() {
          _isJoined = !_isJoined;
          _participantCount += _isJoined ? 1 : -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeWriteError(context, e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = Supabase.instance.client.auth.currentUser;
    final isOwner = currentUser != null && currentUser.id == _event['organizer_id'];
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;

    final startDate = parseLocal(_event['start_datetime'])!;
    final DateTime? endDate = parseLocal(_event['end_datetime']);

    // 1. PREPARE THE DATA (Handle Empty Strings correctly)
    final String rawDesc = _event['description'] ?? '';
    final String descriptionText = rawDesc.trim().isEmpty
        ? s.noDetails
        : rawDesc;

    final List<String> allImages = [
      if (_event['image_url'] != null) _event['image_url'],
      ...?(_event['gallery_urls'] as List?)?.cast<String>(),
    ];

    final bool isPast = endDate != null 
        ? endDate.isBefore(DateTime.now()) 
        : startDate.add(const Duration(hours: 4)).isBefore(DateTime.now());

    return Scaffold(
      body: PageBody(child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 1. App Bar (Keep your existing code)
            SliverAppBar(
              expandedHeight: 300,
              pinned: true,
              leading: Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: photoScrim(0.45),
                  child: IconButton(
                    tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                    icon: const Icon(Icons.arrow_back, color: kOnPhoto),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
              backgroundColor: theme.scaffoldBackgroundColor,
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // 1. THE CAROUSEL
                    PageView.builder(
                      itemCount: allImages.length,
                      onPageChanged: (index) => setState(() => _currentImageIndex = index),
                      itemBuilder: (context, index) {
                        return TapCard(
                          borderRadius: BorderRadius.zero,
                          onTap: () => showGallery(context,
                              items: allImages, initialIndex: index),
                          child: Hero(
                            tag: "gallery_$index", // Unique tag for smooth animation
                            child: CachedNetworkImage(
                              imageUrl: allImages[index],
                              fit: BoxFit.cover,
                              placeholder: (_,__) => const Center(child: CircularProgressIndicator()),
                              errorWidget: (_,__,___) => Container(color: scheme.surfaceContainerHighest, child: Icon(Icons.event, color: scheme.onSurfaceVariant)),
                            ),
                          ),
                        );
                      },
                    ),

                    if (isPast)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: photoScrim(0.4),
                          child: Center(child: StatusBadge.stamp(s.ended)),
                        ),
                      ),
                    ),

                    // 2. THE BADGE (e.g. "1/5")
                    if (allImages.length > 1)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: photoScrim(0.7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.photo_library, color: kOnPhoto, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                "${_currentImageIndex + 1} / ${allImages.length}",
                                style: theme.textTheme.labelMedium?.copyWith(color: kOnPhoto, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      ),
                      
                    // 3. GRADIENT SHADOW (To make back button visible)
                    Positioned(
                      top: 0, left: 0, right: 0,
                      height: 100,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [photoScrim(0.6), photoScrim(0)],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 2. Body
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(_event['title'], style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold))),
                        // Body icons sit on the page, not on the photo, so
                        // they take scheme colours (the old black circles
                        // vanished on Songket Noir).
                        IconButton(
                          tooltip: s.share,
                          icon: Icon(Icons.share, color: scheme.onSurfaceVariant),
                          onPressed: () {
                            ShareService.shareContent(
                              context,
                              _event['title'],
                              [
                                if (_event['location'] != null) "📍 ${_event['location']}",
                                "🗓 ${formatEventRange(startDate, endDate)}",
                                if (_event['description'] != null) "\n${_event['description']}",
                              ].join('\n'),
                              allImages,
                            );
                          },
                        ),
                        ReportMenuButton(targetId: _event['id'], type: 'event'),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Date & Location Rows (Keep your existing logic)
                    _infoRow(Icons.calendar_today, formatEventRange(startDate, endDate), theme),
                    const SizedBox(height: 12),
                    _infoRow(Icons.location_on, _event['location'] ?? s.locationTba, theme),
                    
                    const SizedBox(height: 24),
                    const Divider(),

                                        
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                      ),
                      child: Row(
                        children: [
                          // 1. The Count
                          Icon(Icons.group, size: 20, color: scheme.primary),
                          const SizedBox(width: 8),
                          Text(s.attendingCount.fill([_participantCount]), style: const TextStyle(fontWeight: FontWeight.bold)),
                          
                          const Spacer(),

                          // 2. The Button (Only show if not owner)
                          if (Supabase.instance.client.auth.currentUser?.id != _event['organizer_id'])
                            SizedBox(
                              height: 36,
                              child: _isJoined
                                  ? OutlinedButton.icon(
                                      onPressed: _toggleJoin,
                                      icon: const Icon(Icons.check, size: 16),
                                      label: Text(s.joined),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: scheme.primary,
                                        side: BorderSide(color: scheme.primary),
                                      ),
                                    )
                                  : FilledButton.icon(
                                      onPressed: _toggleJoin,
                                      icon: const Icon(Icons.add, size: 16),
                                      label: Text(s.join),
                                    ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Organizer Tile (Keep existing)
                    if (_organizer != null)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundImage: _organizer!['avatar_url'] != null ? NetworkImage(_organizer!['avatar_url']) : null,
                          child: _organizer!['avatar_url'] == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(_organizer!['display_name'] ?? s.organizer, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text(roleLabel(s, _organizer!['role'])),
                        trailing: OutlinedButton(
                          onPressed: () => context.goUser(_organizer!['id']),
                          child: Text(s.viewProfile),
                        ),
                      ),

                    const Divider(),
                    const SizedBox(height: 16),

                   
                    // Description & Post Button (Keep existing)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(s.aboutEvent, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => CreatePostScreen(sharedEvent: _event)));
                          },
                          icon: const Icon(Icons.repeat, size: 16),
                          label: Text(s.repost),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    SizedBox(
                      width: double.infinity,
                      child: MentionText(
                        descriptionText,
                        style: theme.textTheme.bodyLarge?.copyWith(height: 1.5, color: scheme.onSurface),
                      ),
                    ),
                    const SizedBox(height: 32),
                    
                    // --- REGISTER BUTTON (VISIBLE TO EVERYONE HERE) ---
                    if (_event['registration_link'] != null)
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: Icon(isPast ? Icons.event_busy : Icons.link),
                        label: Text(isPast ? s.registrationClosed : s.registerOnline),
                        // Past = onPressed null, so the theme's disabled colours apply
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: isPast 
                          ? null // DISABLE CLICK
                          : () => _launchSafeUrl(_event['registration_link']), // USE SAFE LAUNCHER
                      ),
                    ),

                    const SizedBox(height: 32),
                    const Divider(thickness: 4),

                    // Discussion Header (Keep existing)
                    Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(s.comments, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        
                        // NEW REFRESH BUTTON HERE
                        IconButton(
                          icon: _isLoading 
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) 
                            : const Icon(Icons.refresh, size: 20),
                          onPressed: () {
                            setState(() {
                              _isLoading = true;
                              _commentsStream = _fetchCommentsStream();
                            });
                            _fetchEventDetails();
                          },
                          tooltip: s.refreshComments,
                        ),
                      ],
                    ),
                  ),

                    // Comments List (Keep existing)
                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _commentsStream,
                      builder: (context, snapshot) {
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return Center(child: Padding(padding: const EdgeInsets.all(16), child: Text(s.noComments, style: TextStyle(color: scheme.onSurfaceVariant))));
                        }
                        return ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            final c = snapshot.data![index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const CircleAvatar(radius: 14, child: Icon(Icons.person, size: 14)),
                              title: MentionText(c['body'] ?? ''),
                              subtitle: Text(formatRelative(context, DateTime.parse(c['created_at'])),
                                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                              trailing: ReportMenuButton(targetId: c['id'], type: 'comment', iconSize: 18),
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        )),
      
      // 3. BOTTOM SHEET LOGIC (This is where the magic happens)
      bottomSheet: bottomBarConstrained(context, Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, -2))],
        ),
        child: SafeArea(
          child: isOwner
              // A: OWNER CONTROLS (Edit / Delete)
              ? Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _deleteEvent,
                        style: OutlinedButton.styleFrom(foregroundColor: scheme.error, side: BorderSide(color: scheme.error)),
                        child: Text(s.cancelEvent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () async {
                          // Navigate to Edit Screen
                          final result = await Navigator.push(
                            context, 
                            MaterialPageRoute(builder: (_) => CreateEventScreen(eventToEdit: _event))
                          );
                          if (result == true) _fetchEventDetails();
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: scheme.primary, foregroundColor: scheme.onPrimary),
                        child: Text(s.edit),
                      ),
                    ),
                  ],
                )
              // B: VIEWER CONTROLS (Comment Input)
              : Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _commentCtrl,
                        decoration: InputDecoration(
                          hintText: s.askAboutEvent,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          filled: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                      ),
                    ),
                    IconButton(tooltip: s.post, icon: Icon(Icons.send, color: scheme.primary), onPressed: _postComment),
                  ],
                ),
        ),
      )),
    );
  }

  Widget _infoRow(IconData icon, String text, ThemeData theme) {
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: theme.textTheme.bodyLarge)),
      ],
    );
  }
}