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
import 'events_screen.dart' show CountdownChip, DateBlock, eventCountdown, isOfficialProfile;
import '../widgets/mention_text.dart';
import '../widgets/status_badge.dart';
import '../widgets/brand/brand.dart';
import '../widgets/tap_card.dart';
import 'gallery_view_screen.dart';
import '../widgets/restriction_gate.dart';
import '../widgets/save_button.dart';

class EventDetailScreen extends StatefulWidget {
  final Map<String, dynamic> event;

  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen>
    with RefreshOnContentChange {
  late Map<String, dynamic> _event;
  Map<String, dynamic>? _organizer;
  bool _isLoading = true;
  int _currentImageIndex = 0;
  final _heroController = PageController();
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
  void dispose() {
    _heroController.dispose();
    _commentCtrl.dispose();
    super.dispose();
  }

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
          notifyContentChanged(); // lists drop the deleted event
          popOrHome(context);
        }
      } catch (e) {
        if (mounted) showErrorWithRetry(context, e, onRetry: _deleteEvent);
      }
    }
  }

  /// Edit is its own route; saving brings us back here and refreshes
  /// through [contentChanges].
  Future<void> _editEvent() async => context.goEditEvent(_event);

  @override
  void onContentChanged() => _fetchEventDetails();

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

  // ---------------------------------------------------------------------
  // Derived state
  // ---------------------------------------------------------------------

  bool get _isOwner {
    final me = Supabase.instance.client.auth.currentUser;
    return me != null && me.id == _event['organizer_id'];
  }

  DateTime get _start => parseLocal(_event['start_datetime']) ?? DateTime.now();
  DateTime? get _end => parseLocal(_event['end_datetime']);

  bool get _isPast {
    final end = _end;
    return end != null
        ? end.isBefore(DateTime.now())
        : _start.add(const Duration(hours: 4)).isBefore(DateTime.now());
  }

  /// Joining / registering is closed once an event is over or cancelled.
  bool get _isClosed => _isPast || _isCancelled;

  List<String> get _images => [
        if (_event['image_url'] != null) _event['image_url'],
        ...?(_event['gallery_urls'] as List?)?.whereType<String>(),
      ];

  /// Two columns (media + content left, sticky info card right) once the
  /// page is given this much width.
  static const double _wideFrom = Responsive.desktopBreakpoint;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final wide = constraints.maxWidth >= _wideFrom;
      return Scaffold(
        appBar: wide
            ? AppBar(
                leading: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back),
                  // A shared link opens this page cold, with nothing
                  // underneath to pop back to.
                  onPressed: () => popOrHome(context),
                ),
                actions: [..._actions(context, onPhoto: false), const SizedBox(width: 8)],
              )
            : null,
        body: AdaptiveScaffoldBody(
          primaryFlex: 3,
          secondaryFlex: 2,
          compact: _compactBody(context),
          // ---- left: media, title, about, comments ----
          primary: _primaryPane(context),
          // ---- right: info card, scrolling on its own (stays in view) ----
          secondary: SingleChildScrollView(
            padding: const EdgeInsets.only(top: KSpace.s, bottom: KSpace.xl),
            child: _infoCard(context),
          ),
        ),
        // Compact: the comment box is pinned to the bottom. Wide: it sits
        // under the comments instead.
        bottomSheet: wide ? null : bottomBarConstrained(context, _composerBar(context)),
      );
    });
  }

  // ---------------------------------------------------------------------
  // Layouts
  // ---------------------------------------------------------------------

  Widget _compactBody(BuildContext context) {
    return PageBody(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 320,
            pinned: true,
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            leading: Padding(
              padding: const EdgeInsets.all(8.0),
              child: CircleAvatar(
                backgroundColor: photoScrim(0.45),
                child: IconButton(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: const Icon(Icons.arrow_back, color: kOnPhoto),
                  onPressed: () => popOrHome(context),
                ),
              ),
            ),
            actions: _actions(context, onPhoto: true),
            flexibleSpace: FlexibleSpaceBar(
              background: ClipRRect(
                borderRadius: BorderRadius.only(
                  bottomLeft: KRadius.cut.bottomLeft,
                  bottomRight: KRadius.cut.bottomRight,
                ),
                child: _heroCarousel(context, withTitle: true),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isCancelled) ...[_cancelledBanner(context), const SizedBox(height: 16)],
                  _infoCard(context),
                  const SizedBox(height: 24),
                  _aboutSection(context),
                  const SizedBox(height: 24),
                  _commentsSection(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _primaryPane(BuildContext context) {
    final theme = Theme.of(context);
    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.only(top: KSpace.s, bottom: KSpace.xxl),
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: KRadius.cut,
              child: _heroCarousel(context, withTitle: false),
            ),
          ),
          if (_images.length > 1) ...[
            const SizedBox(height: KSpace.m),
            _thumbnails(context),
          ],
          const SizedBox(height: KSpace.xl),
          Text(_event['title'] ?? '',
              style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
          if (_isCancelled) ...[const SizedBox(height: KSpace.l), _cancelledBanner(context)],
          const SizedBox(height: KSpace.xl),
          _aboutSection(context),
          const SizedBox(height: KSpace.xxl),
          _commentsSection(context),
          const SizedBox(height: KSpace.l),
          _composerBar(context, inline: true),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Pieces
  // ---------------------------------------------------------------------

  /// Save, share, report (visitors) or the manage menu (organiser).
  /// [onPhoto]: drawn over the hero image, so they sit in scrim circles.
  List<Widget> _actions(BuildContext context, {required bool onPhoto}) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final fg = onPhoto ? kOnPhoto : scheme.onSurfaceVariant;

    Widget wrap(Widget child) => onPhoto
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
            child: CircleAvatar(backgroundColor: photoScrim(0.45), child: child),
          )
        : child;

    return [
      wrap(SaveButton(type: SavedType.event, id: _event['id'], color: fg)),
      wrap(IconButton(
        tooltip: s.share,
        icon: Icon(Icons.share, color: fg),
        onPressed: _share,
      )),
      if (_isOwner)
        wrap(_ownerMenu(context, fg))
      else
        wrap(GuardedReportButton(
          targetId: _event['id'],
          type: 'event',
          icon: Icon(Icons.more_vert, color: fg),
        )),
      if (onPhoto) const SizedBox(width: 6),
    ];
  }

  void _share() {
    ShareService.shareContent(
      context,
      _event['title'],
      [
        if (_event['location'] != null) "📍 ${_event['location']}",
        "🗓 ${formatEventRange(_start, _end)}",
        if (_event['description'] != null) "\n${_event['description']}",
      ].join('\n'),
      _images,
      // Deep link keeps the description intact — the Web Share API drops
      // text when files attach.
      link: '/event/${_event['id']}',
    );
  }

  /// Owner controls live in a menu so the bottom bar stays free for
  /// comments — organisers answer questions too.
  Widget _ownerMenu(BuildContext context, Color fg) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: s.manageEvent,
      icon: Icon(Icons.more_vert, color: fg),
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
          value: _isCancelled ? 'restore' : 'cancel',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(_isCancelled ? Icons.event_available : Icons.event_busy),
            title: Text(_isCancelled ? s.restoreEvent : s.cancelEvent),
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
    );
  }

  /// Photo carousel with the ENDED / CANCELLED stamp, a counter, and on
  /// compact the title over a gradient.
  Widget _heroCarousel(BuildContext context, {required bool withTitle}) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final images = _images;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (images.isEmpty)
          ColoredBox(
            color: scheme.primaryContainer,
            child: Center(
              child: Icon(Icons.event, size: 56, color: scheme.onPrimaryContainer),
            ),
          )
        else
          PageView.builder(
            controller: _heroController,
            itemCount: images.length,
            onPageChanged: (index) => setState(() => _currentImageIndex = index),
            itemBuilder: (context, index) => TapCard(
              borderRadius: BorderRadius.zero,
              semanticLabel: s.photoCount.fill([index + 1, images.length]),
              onTap: () => showGallery(context, items: images, initialIndex: index),
              child: Hero(
                tag: "gallery_$index",
                child: CachedNetworkImage(
                  imageUrl: images[index],
                  fit: BoxFit.cover,
                  placeholder: (_, __) => ColoredBox(color: scheme.surfaceContainerHighest),
                  errorWidget: (_, __, ___) => ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(Icons.event, color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          ),

        // Top scrim so the back / action buttons stay visible.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 100,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [photoScrim(0.5), photoScrim(0)],
                ),
              ),
            ),
          ),
        ),

        if (_isClosed)
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: photoScrim(0.35),
                child: Center(
                  child: StatusBadge.stamp(_isCancelled ? s.cancelled : s.ended),
                ),
              ),
            ),
          ),

        if (withTitle)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [photoScrim(0), photoScrim(0.75)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _event['title'] ?? '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(color: kOnPhoto, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatEventRange(_start, _end),
                      style: theme.textTheme.bodyMedium?.copyWith(color: kOnPhoto),
                    ),
                  ],
                ),
              ),
            ),
          ),

        if (images.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(top: withTitle ? 56 : 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: photoScrim(0.7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    "${_currentImageIndex + 1} / ${images.length}",
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: kOnPhoto, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Thumbnail strip under the hero on wide layouts.
  Widget _thumbnails(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final images = _images;
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final selected = i == _currentImageIndex;
          return TapCard(
            semanticLabel: s.photoCount.fill([i + 1, images.length]),
            borderRadius: BorderRadius.circular(8),
            border: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
            onTap: () {
              setState(() => _currentImageIndex = i);
              if (_heroController.hasClients) {
                _heroController.animateToPage(i,
                    duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
              }
            },
            child: SizedBox(
              width: 96,
              child: CachedNetworkImage(imageUrl: images[i], fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }

  Widget _cancelledBanner(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Container(
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
    );
  }

  /// Date, place, attendance + Join, calendar, registration, organiser and
  /// friends going. Sticky on the right on wide layouts.
  Widget _infoCard(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final location = (_event['location'] ?? '').toString().trim();
    final isOwner = _isOwner;

    return KCard(
      borderRadius: KRadius.cut,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ---- when ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DateBlock(date: _start, muted: _isClosed),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatEventRange(_start, _end),
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (!_isClosed && eventCountdown(s, _event) != null) ...[
                      const SizedBox(height: 6),
                      CountdownChip(eventCountdown(s, _event)!),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ---- where ----
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.location_on_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(location.isEmpty ? s.locationTba : location,
                        style: theme.textTheme.bodyLarge),
                    if (location.isNotEmpty)
                      TextButton.icon(
                        style: TextButton.styleFrom(
                            padding: EdgeInsets.zero, minimumSize: const Size(48, 40)),
                        onPressed: () => launchUrl(
                          Uri.https('www.google.com', '/maps/search/',
                              {'api': '1', 'query': location}),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.map_outlined, size: 18),
                        label: Text(s.openInMaps),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 24),

          // ---- attendance + join ----
          Row(
            children: [
              Icon(Icons.group_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.attendingCount.fill([_participantCount]),
                    style: theme.textTheme.titleSmall),
              ),
            ],
          ),
          if (_followingGoing > 0) ...[
            const SizedBox(height: 8),
            _followingGoingRow(context),
          ],
          if (!isOwner) ...[
            const SizedBox(height: 12),
            // Already-joined people can still leave a cancelled event;
            // nobody can newly join.
            _isJoined
                ? OutlinedButton.icon(
                    onPressed: _toggleJoin,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(s.joined),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  )
                : FilledButton.icon(
                    onPressed: _isClosed ? null : _toggleJoin,
                    icon: Icon(_isCancelled ? Icons.event_busy : Icons.add, size: 18),
                    label: Text(_isCancelled
                        ? s.cancelled
                        : (_isPast ? s.ended : s.join)),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  ),
          ],
          if (!_isClosed) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _savingCalendar ? null : _addToCalendar,
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: _savingCalendar
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.event_available, size: 18),
              label: Text(s.addToCalendar),
            ),
          ],
          if (_event['registration_link'] != null) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              icon: Icon(_isClosed ? Icons.event_busy : Icons.link),
              label: Text(_isClosed ? s.registrationClosed : s.registerOnline),
              onPressed: _isClosed ? null : () => _launchSafeUrl(_event['registration_link']),
            ),
          ],

          // ---- organiser ----
          if (_organizer != null) ...[
            const Divider(height: 24),
            _organiserRow(context),
          ],
        ],
      ),
    );
  }

  Widget _followingGoingRow(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
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
                    backgroundColor: scheme.surfaceContainer,
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
    );
  }

  Widget _organiserRow(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final o = _organizer!;
    final official = isOfficialProfile(o);
    return KCard(
      onTap: () => context.goUser(o['id']),
      official: official,
      semanticLabel: '${s.organizer}: ${o['display_name'] ?? ''}',
      padding: const EdgeInsets.all(KSpace.m),
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              backgroundImage:
                  o['avatar_url'] != null ? CachedNetworkImageProvider(o['avatar_url']) : null,
              child: o['avatar_url'] == null
                  ? Icon(Icons.person, color: scheme.onPrimaryContainer)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(o['display_name'] ?? s.organizer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                      if (official) ...[
                        const SizedBox(width: 4),
                        Tooltip(
                          message: s.officialAccount,
                          child: Icon(Icons.verified, size: 16, color: scheme.tertiary),
                        ),
                      ],
                    ],
                  ),
                  Text('${s.organizer} · ${roleLabel(s, o['role'])}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Widget _aboutSection(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final raw = (_event['description'] ?? '').toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(s.aboutEvent, style: theme.textTheme.titleLarge)),
            TextButton.icon(
              onPressed: () {
                if (!requireLogin(context)) return;
                context.goCreatePost(sharedEvent: _event);
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
            raw.trim().isEmpty ? s.noDetails : raw,
            style: theme.textTheme.bodyLarge?.copyWith(height: 1.5, color: scheme.onSurface),
          ),
        ),
      ],
    );
  }

  Widget _commentsSection(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(s.comments, style: theme.textTheme.titleLarge),
              ),
            ),
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
        const Divider(),
        StreamBuilder<List<Map<String, dynamic>>>(
          stream: _commentsStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(s.noComments, style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              );
            }
            return Column(
              children: [
                for (final c in snapshot.data!)
                  CommentTile(
                    comment: c,
                    highlightUserId: _event['organizer_id'],
                    highlightLabel: s.organiserBadge,
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  /// Comment box. Everyone comments, organisers included; guests get a
  /// login button. [inline] = inside the page (wide) instead of pinned.
  Widget _composerBar(BuildContext context, {bool inline = false}) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final field = !isLoggedIn
        ? GuestActionBar(label: s.loginToComment)
        : Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _postComment(),
                  decoration: InputDecoration(
                    hintText: s.askAboutEvent,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
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
          );
    if (inline) return field;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        boxShadow: [
          BoxShadow(
              color: scheme.shadow.withValues(alpha: 0.05),
              blurRadius: 5,
              offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(child: field),
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
