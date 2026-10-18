import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mykerawang/services/share_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/access_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/feedback.dart';
import '../utils/guest_access.dart';
import '../utils/ics.dart';
import '../utils/roles.dart';
import '../widgets/comment_tile.dart';
import '../widgets/mention_text.dart';
import '../widgets/status_badge.dart';
import '../widgets/tap_card.dart';
import 'create_post_screen.dart'; 
import 'create_event_screen.dart';
import 'gallery_view_screen.dart';
import '../utils/responsive.dart';
import '../widgets/restriction_gate.dart';
import '../services/saved_items.dart';
import '../widgets/save_button.dart';

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
  bool _joining = false;
  bool _postingComment = false;
  bool _savingCalendar = false;

  /// People I follow who joined: total, plus up to 3 for avatars.
  int _followingGoing = 0;
  List<Map<String, dynamic>> _followingGoingFaces = const [];
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
      // Only what the organiser tile shows. Guests can't read the profiles
      // table (it holds phone numbers), so they go through the safe view.
      final organizer = await supabase
          .from(isLoggedIn ? 'profiles' : 'profiles_public')
          .select('id, username, display_name, avatar_url, role, is_verified')
          .eq('id', freshEvent['organizer_id'])
          .maybeSingle();

      // 2. Participant count (guests see the number, not who)
      final int count;
      if (isLoggedIn) {
        count = await supabase
            .from('event_participants')
            .count(CountOption.exact)
            .eq('event_id', _event['id']);
      } else {
        final row = await supabase
            .from('event_participant_counts')
            .select('participant_count')
            .eq('event_id', _event['id'])
            .maybeSingle();
        count = (row?['participant_count'] as num?)?.toInt() ?? 0;
      }

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
      if (userId != null) _fetchFollowingGoing(userId);
    } catch (e) {
      debugPrint("Error fetching details: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// "N people you follow are going". Best-effort: a failure just hides
  /// the line.
  Future<void> _fetchFollowingGoing(String myId) async {
    final db = Supabase.instance.client;
    try {
      final follows = await db
          .from('followers')
          .select('following_id')
          .eq('follower_id', myId);
      final ids = [for (final f in follows) f['following_id'] as String];
      if (ids.isEmpty) return;

      final going = await db
          .from('event_participants')
          .select('user_id')
          .eq('event_id', _event['id'])
          .inFilter('user_id', ids);
      final goingIds = [for (final g in going) g['user_id'] as String];
      if (goingIds.isEmpty) {
        if (mounted) setState(() => _followingGoing = 0);
        return;
      }

      final faces = await db
          .from('profiles')
          .select('id, display_name, avatar_url')
          .inFilter('id', goingIds.take(3).toList());
      if (!mounted) return;
      setState(() {
        _followingGoing = goingIds.length;
        _followingGoingFaces = List<Map<String, dynamic>>.from(faces);
      });
    } catch (e) {
      debugPrint("Following-going lookup failed: $e");
    }
  }

  Future<void> _addToCalendar() async {
    if (_savingCalendar) return;
    final s = context.l10nRead;
    setState(() => _savingCalendar = true);
    try {
      final ics = buildEventIcs(_event,
          url: ShareService.absoluteUrl('/event/${_event['id']}'));
      await saveIcs(ics, icsFileName(_event['title']));
      // Mobile shows the share sheet, which is its own confirmation.
      if (mounted && kIsWeb) showSuccess(context, s.calendarFileSaved);
    } catch (e) {
      if (mounted) showErrorWithRetry(context, e, onRetry: _addToCalendar);
    } finally {
      if (mounted) setState(() => _savingCalendar = false);
    }
  }

  /// Realtime can only subscribe to a real table,and a raw `comments`
  /// stream carries `user_id` even for anonymous comments. So the stream is
  /// used purely as a change signal; the rows actually rendered come from
  /// `comments_public`, which blanks the author.
  Stream<List<Map<String, dynamic>>> _fetchCommentsStream() async* {
    yield await _fetchEventComments();

    final signal = Supabase.instance.client
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('event_id', _event['id']);

    // If realtime is unavailable (e.g. a guest's anon session), keep the
    // comments already shown rather than surfacing a stream error.
    try {
      await for (final _ in signal) {
        yield await _fetchEventComments();
      }
    } catch (e) {
      debugPrint("Comment stream ended: $e");
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
    if (!requireLogin(context)) return;
    if (_commentCtrl.text.trim().isEmpty || _postingComment) return;
    if (!await ensureCanWrite(context, ModScope.comment) || !mounted) return;
    final user = Supabase.instance.client.auth.currentUser!;
    final s = context.l10nRead;

    setState(() => _postingComment = true);
    try {
      await Supabase.instance.client.from('comments').insert({
        'event_id': _event['id'],
        'user_id': user.id,
        'body': _commentCtrl.text.trim(),
      });
      // Text is kept until the insert succeeds, so Retry resends it.
      _commentCtrl.clear();
      if (!mounted) return;
      FocusScope.of(context).unfocus();
      showSuccess(context, s.commentPosted);
    } catch (e) {
      if (mounted) showErrorWithRetry(context, e, onRetry: _postComment);
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  bool get _isCancelled => _event['cancelled_at'] != null;

  /// Soft cancel: the event stays visible, marked cancelled, and a
  /// database trigger notifies everyone who joined.
  Future<void> _cancelEvent() async {
    final s = context.l10nRead;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.cancelEvent),
        content: Text(s.cancelEventSoftConfirm),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.keepEvent)),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            child: Text(s.cancelEvent),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _setCancelled(DateTime.now().toUtc().toIso8601String(), s.eventCancelled);
    }
  }

  Future<void> _restoreEvent() =>
      _setCancelled(null, context.l10nRead.eventRestored);

  Future<void> _setCancelled(String? cancelledAt, String doneMessage) async {
    try {
      await Supabase.instance.client
          .from('events')
          .update({'cancelled_at': cancelledAt})
          .eq('id', _event['id']);
      if (!mounted) return;
      setState(() => _event = {..._event, 'cancelled_at': cancelledAt});
      showSuccess(context, doneMessage);
    } catch (e) {
      if (mounted) {
        showErrorWithRetry(context, e,
            onRetry: () => _setCancelled(cancelledAt, doneMessage));
      }
    }
  }

  /// Permanent delete — comments and participants go with it, so the
  /// owner has to type the title to confirm.
  Future<void> _deleteEvent() async {
    final s = context.l10nRead;
    final title = (_event['title'] ?? '').toString().trim();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => _TypeToConfirmDialog(
        title: s.deleteEvent,
        message: s.deleteEventConfirm,
        expected: title,
        cancelLabel: s.cancel,
        confirmLabel: s.deletePermanently,
      ),
    );

    if (confirm == true) {
      try {
        await Supabase.instance.client.from('events').delete().eq('id', _event['id']);
        if (mounted) {
          showSuccess(context, s.eventDeleted);
          popOrHome(context, true); // true = refresh profile/home
        }
      } catch (e) {
        if (mounted) showErrorWithRetry(context, e, onRetry: _deleteEvent);
      }
    }
  }

  Future<void> _editEvent() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateEventScreen(eventToEdit: _event)),
    );
    if (result == true) _fetchEventDetails();
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
    if (!requireLogin(context)) return;
    final userId = supabase.auth.currentUser!.id;
    if (_isCancelled && !_isJoined) return;
    if (_joining) return;
    if (!_isJoined && (!await ensureCanWrite(context, ModScope.events) || !mounted)) return;
    _joining = true;

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
        showErrorWithRetry(context, e, onRetry: _toggleJoin);
      }
    } finally {
      _joining = false;
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
    final bool isCancelled = _isCancelled;
    // Joining / registering is closed once an event is over or cancelled.
    final bool isClosed = isPast || isCancelled;

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
                    // A shared link opens this page cold, with nothing
                    // underneath to pop back to.
                    onPressed: () => popOrHome(context),
                  ),
                ),
              ),
              // Owner controls live here so the bottom bar stays free for
              // comments — organisers answer questions too.
              actions: [
                if (isOwner)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: CircleAvatar(
                      backgroundColor: photoScrim(0.45),
                      child: PopupMenuButton<String>(
                        tooltip: s.manageEvent,
                        icon: const Icon(Icons.more_vert, color: kOnPhoto),
                        onSelected: (v) => switch (v) {
                          'edit' => _editEvent(),
                          'cancel' => _cancelEvent(),
                          'restore' => _restoreEvent(),
                          'delete' => _deleteEvent(),
                          _ => null,
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.edit_outlined),
                              title: Text(s.edit),
                            ),
                          ),
                          PopupMenuItem(
                            value: isCancelled ? 'restore' : 'cancel',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(isCancelled ? Icons.event_available : Icons.event_busy),
                              title: Text(isCancelled ? s.restoreEvent : s.cancelEvent),
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem(
                            value: 'delete',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(Icons.delete_forever, color: scheme.error),
                              title: Text(s.deleteEvent, style: TextStyle(color: scheme.error)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
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

                    if (isClosed)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          color: photoScrim(0.4),
                          child: Center(child: StatusBadge.stamp(isCancelled ? s.cancelled : s.ended)),
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
                        SaveButton(type: SavedType.event, id: _event['id'], color: scheme.onSurfaceVariant),
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
                              // Deep link keeps the description intact — the
                              // Web Share API drops text when files attach.
                              link: '/event/${_event['id']}',
                            );
                          },
                        ),
                        if (!isOwner)
                          GuardedReportButton(targetId: _event['id'], type: 'event'),
                      ],
                    ),
                    if (isCancelled) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.errorContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.event_busy, color: scheme.onErrorContainer),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(s.eventCancelledBanner,
                                  style: TextStyle(color: scheme.onErrorContainer, fontWeight: FontWeight.w600)),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // Date & Location Rows(Keep your existing logic)
                    _infoRow(Icons.calendar_today, formatEventRange(startDate, endDate), theme),
                    const SizedBox(height: 12),
                    _infoRow(Icons.location_on, _event['location'] ?? s.locationTba, theme),
                    if (!isClosed) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _savingCalendar ? null : _addToCalendar,
                          icon: _savingCalendar
                              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.event_available, size: 18),
                          label: Text(s.addToCalendar),
                        ),
                      ),
                    ],

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
                          if (!isOwner)
                            SizedBox(
                              height: 36,
                              // Already-joined people can still leave a
                              // cancelled event; nobody can newly join.
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
                                      onPressed: isClosed ? null : _toggleJoin,
                                      icon: Icon(isCancelled ? Icons.event_busy : Icons.add, size: 16),
                                      label: Text(isCancelled ? s.cancelled : s.join),
                                    ),
                            ),
                        ],
                      ),
                    ),
                    if (_followingGoing > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          SizedBox(
                            width: 20.0 * _followingGoingFaces.length + 12,
                            height: 32,
                            child: Stack(
                              children: [
                                for (var i = 0; i < _followingGoingFaces.length; i++)
                                  Positioned(
                                    left: 20.0 * i,
                                    child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: theme.scaffoldBackgroundColor,
                                      child: CircleAvatar(
                                        radius: 14,
                                        backgroundColor: scheme.primaryContainer,
                                        backgroundImage: _followingGoingFaces[i]['avatar_url'] != null
                                            ? CachedNetworkImageProvider(_followingGoingFaces[i]['avatar_url'])
                                            : null,
                                        child: _followingGoingFaces[i]['avatar_url'] == null
                                            ? Icon(Icons.person, size: 14, color: scheme.onPrimaryContainer)
                                            : null,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _followingGoing == 1
                                  ? s.followingGoingOne
                                  : s.followingGoingMany.fill([_followingGoing]),
                              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ],
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
                            if (!requireLogin(context)) return;
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
                        icon: Icon(isClosed ? Icons.event_busy : Icons.link),
                        label: Text(isClosed ? s.registrationClosed : s.registerOnline),
                        // Past = onPressed null, so the theme's disabled colours apply
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed: isClosed
                          ? null// DISABLE CLICK
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
                          itemBuilder: (context, index) =>
                              CommentTile(comment: snapshot.data![index]),
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
          // Everyone comments here, organisers included (owner controls
          // are in the app bar menu). Guests get a login button instead.
          child: !isLoggedIn
              ? GuestActionBar(label: s.loginToComment)
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
                    IconButton(
                      tooltip: s.post,
                      onPressed: _postingComment ? null : _postComment,
                      icon: _postingComment
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.send, color: scheme.primary),
                    ),
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
/// Destructive confirmation that only enables once [expected] is typed —
/// harder to hit by accident than a Yes/No dialog.
class _TypeToConfirmDialog extends StatefulWidget {
  final String title;
  final String message;
  final String expected;
  final String cancelLabel;
  final String confirmLabel;

  const _TypeToConfirmDialog({
    required this.title,
    required this.message,
    required this.expected,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  @override
  State<_TypeToConfirmDialog> createState() => _TypeToConfirmDialogState();
}

class _TypeToConfirmDialogState extends State<_TypeToConfirmDialog> {
  final _ctrl = TextEditingController();

  bool get _matches =>
      _ctrl.text.trim().toLowerCase() == widget.expected.toLowerCase();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(Icons.warning_amber, color: scheme.error),
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 8),
          Text(widget.expected, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          TextField(
            controller: _ctrl,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: widget.expected),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _matches ? () => Navigator.pop(context, true) : null,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
