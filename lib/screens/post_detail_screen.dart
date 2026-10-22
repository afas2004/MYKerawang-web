import 'package:flutter/material.dart';
import 'package:mykerawang/utils/app_nav.dart';
import 'package:mykerawang/widgets/mention_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/mention_service.dart';
import '../services/comment_pins.dart';
import '../services/moderation_service.dart';
import '../services/announcement_service.dart';
import '../services/post_service.dart';
import '../services/share_service.dart';
import '../utils/announcement_rules.dart';
import '../widgets/announcement_view.dart';
import '../l10n/announce_strings.dart';
import 'create_post_screen.dart';
import '../widgets/linear_refresher.dart';
import '../widgets/comment_tile.dart';
import '../widgets/owner_menu.dart';
import '../widgets/post_card.dart';
import '../l10n/app_strings.dart';
import '../l10n/feed_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../widgets/brand/brand.dart';
import '../utils/guest_access.dart';
import '../widgets/restriction_gate.dart';

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  /// Comments shown at first, and added by each "show earlier".
  static const _commentPage = 30;

  final _commentCtrl = TextEditingController();
  final _composerFocus = FocusNode();
  final _supabase = Supabase.instance.client;

  bool _isSending = false;
  bool _isAnon = false;
  bool _hasText = false;
  late Map<String, dynamic> _postData;

  // Comments: the newest [_commentLimit], oldest first on screen.
  List<Map<String, dynamic>> _comments = [];
  Set<String> _myCommentIds = {};
  bool _commentsLoaded = false;
  Object? _commentsError;
  int _commentLimit = _commentPage;
  bool _hasEarlier = false;
  bool _loadingEarlier = false;
  int _loadSeq = 0; // drops results of superseded loads
  RealtimeChannel? _channel;

  String get _postId => widget.post['id'];

  @override
  void initState() {
    super.initState();
    _postData = widget.post;
    _commentCtrl.addListener(_onTextChanged);
    _loadComments();
    _checkCanPin();
    _loadLinkedEvent();
    // Realtime only signals; rows are re-read from comments_public so
    // anonymous authors stay hidden.
    _channel = _supabase
        .channel('post-comments-$_postId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'comments',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'post_id',
            value: _postId,
          ),
          callback: (_) => _loadComments(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    final channel = _channel;
    if (channel != null) _supabase.removeChannel(channel);
    _commentCtrl.removeListener(_onTextChanged);
    _commentCtrl.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasText = _commentCtrl.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  /// Pull-to-refresh: the post (for counts) and its comments.
  Future<void> _refreshData() async {
    await Future.wait([_refreshPost(), _loadComments()]);
  }

  Future<void> _refreshPost() async {
    try {
      final freshPost = await _supabase
          .from('posts_public') // anonymity-safe view
          .select('*')
          .eq('id', _postData['id'])
          .single();
      if (mounted) setState(() => _postData = freshPost);
    } catch (e) {
      debugPrint("Refresh error: $e");
    }
  }

  /// Post author or admin may pin comments (the RPC re-checks).
  bool _canPinComments = false;

  /// The viewer wrote this post (anonymous ones included).
  bool _mine = false;

  /// The event an announcement links to (linked_event_id).
  Map<String, dynamic>? _linkedEvent;

  bool get _isAnnouncement => _postData['is_announcement'] == true;

  Future<void> _loadLinkedEvent() async {
    final id = _postData['linked_event_id'];
    if (id == null) return;
    final ev = await AnnouncementService.event('$id');
    if (mounted && ev != null) setState(() => _linkedEvent = ev);
  }

  Future<void> _deleteAnnouncement() async {
    final ps = context.postL10nRead;
    final ok = await confirmDelete(
      context,
      title: ps.deletePost,
      message: ps.deletePostConfirm,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.deletePost(_postData);
      messenger.showSnackBar(SnackBar(content: Text(ps.postDeleted)));
      notifyContentChanged();
      if (mounted) _leave();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(describeWriteError(context, e))),
        );
      }
    }
  }

  Future<void> _checkCanPin() async {
    final mine = await PostService.isMine(_postData);
    if (mounted && mine != _mine) setState(() => _mine = mine);
    final role = mine ? null : await ModerationService.myRole();
    final can = mine || role == 'admin' || role == 'owner';
    if (mounted && can != _canPinComments) {
      setState(() => _canPinComments = can);
    }
  }

  Future<void> _togglePin(Map<String, dynamic> c) async {
    final now = await CommentPins.toggle(context, c);
    if (now != null) await _loadComments();
  }

  /// Pinned comments of this post (always shown, above the paged list).
  /// Empty if the pins migration isn't applied yet.
  Future<List<Map<String, dynamic>>> _fetchPinned() async {
    try {
      final rows = await _supabase
          .from('comments_public')
          .select('*')
          .eq('post_id', _postId)
          .not('pinned_at', 'is', null)
          .order('pinned_at', ascending: true);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      debugPrint('Pinned comments unavailable: $e');
      return const [];
    }
  }

  Future<void> _loadComments() async {
    final seq = ++_loadSeq;
    final limit = _commentLimit;
    try {
      // Newest first so the limit keeps the latest; one extra row tells
      // whether there are earlier ones.
      final results = await Future.wait([
        _supabase
            .from('comments_public') // anonymity-safe view
            .select('*')
            .eq('post_id', _postId)
            .order('created_at', ascending: false)
            .limit(limit + 1),
        _fetchPinned(),
      ]);
      final rows = List<Map<String, dynamic>>.from(results[0]);
      final pinned = results[1];
      final hasEarlier = rows.length > limit;
      // Pinned first, then the newest page without repeating them.
      final pinnedIds = {for (final p in pinned) p['id']};
      final comments = pinnedFirst([
        ...pinned,
        ...rows
            .take(limit)
            .toList()
            .reversed
            .where((c) => !pinnedIds.contains(c['id'])),
      ]);

      // Anonymous comments arrive without user_id; only the author's own
      // ids come back from the RPC, so it reveals nobody else's.
      final myId = _supabase.auth.currentUser?.id;
      final mine = comments.any((c) => c['user_id'] == null)
          ? await PostService.myCommentIds(_postId)
          : <String>{};

      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _comments = comments;
        _hasEarlier = hasEarlier;
        _myCommentIds = {
          ...mine,
          for (final c in comments)
            if (myId != null && c['user_id'] == myId) c['id'] as String,
        };
        _commentsLoaded = true;
        _commentsError = null;
      });
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      setState(() => _commentsError = e);
    }
  }

  Future<void> _showEarlier() async {
    setState(() {
      _loadingEarlier = true;
      _commentLimit += _commentPage;
    });
    await _loadComments();
    if (mounted) setState(() => _loadingEarlier = false);
  }

  Future<void> _editComment(Map<String, dynamic> c) async {
    final s = context.l10nRead;
    final ps = context.postL10nRead;
    final ctrl = TextEditingController(text: c['body'] ?? '');
    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ps.editComment),
        content: SizedBox(
          width: 480,
          child: MentionInput(
            controller: ctrl,
            hintText: s.commentHint,
            isMultiLine: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(s.saveChanges),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (body == null || body.isEmpty || body == c['body'] || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.updateComment(c['id'], body);
      await MentionService.notify(
        text: body,
        postId: _postId,
        commentId: c['id'],
        anonymous: c['is_anonymous'] ?? false,
        alreadyNotified: MentionService.usernamesIn(c['body'] ?? ''),
      );
      messenger.showSnackBar(SnackBar(content: Text(ps.commentUpdated)));
      await _loadComments();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.errorWithDetail.fill([e]))),
      );
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> c) async {
    final s = context.l10nRead;
    final ps = context.postL10nRead;
    final ok = await confirmDelete(
      context,
      title: ps.deleteComment,
      message: ps.deleteCommentConfirm,
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.deleteComment(c['id']);
      messenger.showSnackBar(SnackBar(content: Text(ps.commentDeleted)));
      await _refreshData();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(s.errorWithDetail.fill([e]))),
      );
    }
  }

  /// A cold deep link has nothing underneath to pop back to.
  /// Back: to where the post was opened from; opened cold, to Home.
  void _leave() => appBack(context);

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    if (!requireLogin(context)) return;
    if (!await ensureCanWrite(context, ModScope.comment) || !mounted) return;
    final s = context.l10nRead;
    final ps = context.postL10nRead;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isSending = true);
    try {
      final newComment = await _supabase
          .from('comments')
          .insert({
            'post_id': _postId,
            'user_id': _supabase.auth.currentUser!.id,
            'body': text,
            'is_anonymous': _isAnon,
          })
          .select('id')
          .single();

      // Mentions (no author on anonymous comments); never throws.
      await MentionService.notify(
        text: text,
        postId: _postId,
        commentId: newComment['id'],
        anonymous: _isAnon,
      );

      // The text is only cleared once it is safely posted.
      _commentCtrl.clear();
      if (mounted) FocusScope.of(context).unfocus();
      messenger.showSnackBar(SnackBar(content: Text(ps.commentPosted)));
      await _refreshData();
    } catch (e) {
      debugPrint("Comment failed: $e");
      messenger.showSnackBar(
        SnackBar(
          content: Text(ps.commentFailed),
          action: SnackBarAction(
            label: s.tryAgain,
            onPressed: () {
              if (mounted) _submitComment();
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Widget _buildComments(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    final ps = context.postL10n;

    if (!_commentsLoaded) {
      if (_commentsError != null) {
        return Padding(
          padding: const EdgeInsets.all(KSpace.l),
          child: Column(
            children: [
              Text(
                s.connectionError,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              TextButton.icon(
                onPressed: _loadComments,
                icon: const Icon(AppIcons.refresh),
                label: Text(s.tryAgain),
              ),
            ],
          ),
        );
      }
      return const Padding(
        padding: EdgeInsets.all(KSpace.xxl),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_comments.isEmpty) {
      return BrandEmptyState(
        compact: true,
        icon: AppIcons.comment,
        title: s.beFirstToComment,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasEarlier)
          Padding(
            padding: const EdgeInsets.only(bottom: KSpace.xs),
            child: _loadingEarlier
                ? const Padding(
                    padding: EdgeInsets.all(KSpace.m),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : TextButton.icon(
                    onPressed: _showEarlier,
                    icon: const RotatedBox(
                      quarterTurns: 3,
                      child: Icon(AppIcons.chevronRight),
                    ),
                    label: Text(ps.showEarlierComments),
                  ),
          ),
        for (var i = 0; i < _comments.length; i++)
          CommentTile(
            key: ValueKey(_comments[i]['id']),
            comment: _comments[i],
            threadLine: i < _comments.length - 1,
            onEdit: _myCommentIds.contains(_comments[i]['id'])
                ? () => _editComment(_comments[i])
                : null,
            onDelete: _myCommentIds.contains(_comments[i]['id'])
                ? () => _deleteComment(_comments[i])
                : null,
            onTogglePin: _canPinComments
                ? () => _togglePin(_comments[i])
                : null,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final fs = context.feedL10n;
    final count =
        (_postData['comment_count'] as num?)?.toInt() ?? _comments.length;

    return Scaffold(
      appBar: appBarConstrained(
        context,
        maxWidth: Responsive.detailMaxWidth,
        leading: IconButton(
          tooltip: s.back,
          icon: const BackButtonIcon(),
          onPressed: _leave,
        ),
        title: Text(s.threadTitle),
      ),
      body: LinearRefresher(
        onRefresh: _refreshData,
        child: PostDetailLayout(
          // Announcements use their own template; posts use the card.
          post: _isAnnouncement
              ? AnnouncementDetailHead(
                  post: _postData,
                  linkedEvent: _linkedEvent,
                  canManage: _mine || _canPinComments,
                  onEdit: () => openPostEditor(context, _postData),
                  onDelete: _deleteAnnouncement,
                )
              : PostCard(
                  post: _postData,
                  onTap: null,
                  expanded: true,
                  onDeleted: _leave,
                  onCommentTap: _composerFocus.requestFocus,
                ),
          commentsHeader: Semantics(
            header: true,
            child: Text(
              count > 0 ? fs.commentCount.fill([count]) : s.comments,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          comments: _buildComments(context),
          // Comments can be turned off on announcements; guests read
          // and get a sign-in prompt instead of the composer.
          composer: !commentsEnabled(_postData)
              ? const CommentsOffNotice()
              : GuestableComposer(
                  loggedIn: isLoggedIn,
                  composer: CommentComposer(
                    controller: _commentCtrl,
                    focusNode: _composerFocus,
                    anonymous: _isAnon,
                    sending: _isSending,
                    canSend: _hasText && !_isSending,
                    onToggleAnonymous: () => setState(() => _isAnon = !_isAnon),
                    onSend: _submitComment,
                  ),
                ),
        ),
      ),
    );
  }
}

/// The comment box for members; for guests, a "Sign in to comment"
/// button in its place (posts stay readable).
class GuestableComposer extends StatelessWidget {
  final bool loggedIn;
  final Widget composer;

  const GuestableComposer({
    super.key,
    required this.loggedIn,
    required this.composer,
  });

  @override
  Widget build(BuildContext context) {
    if (loggedIn) return composer;
    return Padding(
      padding: const EdgeInsets.all(KSpace.m),
      child: SafeArea(
        top: false,
        child: GuestActionBar(label: context.feedL10n.signInToComment),
      ),
    );
  }
}

/// Thread layout on [AdaptiveScaffoldBody]: with ≥900 px of its own
/// width, the post on the left and the comments on the right with the
/// composer pinned under them; narrower, post then comments in one scroll
/// with the composer pinned to the bottom of the screen.
class PostDetailLayout extends StatelessWidget {
  final Widget post;
  final Widget commentsHeader;
  final Widget comments;
  final Widget composer;

  const PostDetailLayout({
    super.key,
    required this.post,
    required this.commentsHeader,
    required this.comments,
    required this.composer,
  });

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        KSpace.l,
        KSpace.l,
        KSpace.l,
        KSpace.xs,
      ),
      child: commentsHeader,
    );

    final stacked = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: KSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        KSpace.m,
                        KSpace.s,
                        KSpace.m,
                        0,
                      ),
                      child: SelectionArea(child: post),
                    ),
                    header,
                    Padding(
                      padding: const EdgeInsets.only(right: KSpace.xs),
                      child: comments,
                    ),
                  ],
                ),
              ),
            ),
            composer,
          ],
        ),
      ),
    );

    return AdaptiveScaffoldBody(
      compact: stacked,
      primary: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(top: KSpace.s, bottom: KSpace.xxl),
        child: SelectionArea(child: post),
      ),
      secondary: Column(
        children: [
          Align(alignment: Alignment.centerLeft, child: header),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(right: KSpace.s, bottom: KSpace.l),
              child: comments,
            ),
          ),
          composer,
        ],
      ),
    );
  }
}

/// Comment box: an anonymity toggle that says what it does in words, the
/// text field, and send (disabled while empty, spinner while sending).
class CommentComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool anonymous;
  final bool sending;
  final bool canSend;
  final VoidCallback onToggleAnonymous;
  final VoidCallback onSend;

  const CommentComposer({
    super.key,
    required this.controller,
    this.focusNode,
    required this.anonymous,
    required this.sending,
    required this.canSend,
    required this.onToggleAnonymous,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final ps = context.postL10n;
    final fs = context.feedL10n;

    return Material(
      color: theme.scaffoldBackgroundColor,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(
          KSpace.m,
          KSpace.s,
          KSpace.s,
          KSpace.s,
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilterChip(
                avatar: Icon(
                  anonymous ? AppIcons.anonymous : AppIcons.visible,
                  size: 18,
                ),
                label: Text(anonymous ? fs.anonToggleOn : fs.anonToggle),
                selected: anonymous,
                showCheckmark: false,
                tooltip: anonymous ? ps.commentAnonOn : ps.commentAnonOff,
                onSelected: (_) => onToggleAnonymous(),
              ),
              const SizedBox(height: KSpace.s),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: KSpace.l,
                        vertical: KSpace.m - 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        // Stadium field, like the app's buttons.
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: MentionInput(
                        controller: controller,
                        focusNode: focusNode,
                        hintText: s.commentHint,
                        isMultiLine: true,
                        reverseDirection: true,
                        maxLines: 5,
                      ),
                    ),
                  ),
                  const SizedBox(width: KSpace.xs),
                  IconButton(
                    tooltip: ps.sendComment,
                    onPressed: canSend ? onSend : null,
                    icon: sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            AppIcons.send,
                            size: 20,
                            color: canSend
                                ? scheme.primary
                                : scheme.onSurfaceVariant,
                          ),
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

/// Shown in place of the comment box when an announcement has comments off.
class CommentsOffNotice extends StatelessWidget {
  const CommentsOffNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(KSpace.l),
        child: Row(
          children: [
            Icon(AppIcons.lock, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: KSpace.s),
            Expanded(
              child: Text(
                context.announceL10n.commentsOff,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Top of an announcement's page: the reader template plus Share and,
/// for the author / club officers / admins, Edit and Delete.
class AnnouncementDetailHead extends StatelessWidget {
  final Map<String, dynamic> post;
  final Map<String, dynamic>? linkedEvent;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const AnnouncementDetailHead({
    super.key,
    required this.post,
    required this.linkedEvent,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final fs = context.feedL10n;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnnouncementView(
            data: AnnouncementData.fromPost(post, linkedEvent: linkedEvent),
          ),
          const SizedBox(height: KSpace.s),
          Row(
            children: [
              IconButton(
                tooltip: fs.shareAction,
                icon: const Icon(AppIcons.share, size: 20),
                onPressed: () => ShareService.shareContent(
                  context,
                  (post['title'] as String?) ?? AppStrings.appName,
                  (post['body'] as String?) ?? '',
                  [if (post['cover_url'] != null) post['cover_url']],
                  link: postSharePath(post['id']),
                ),
              ),
              const Spacer(),
              if (canManage) ...[
                TextButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(AppIcons.edit, size: 18),
                  label: Text(s.edit),
                ),
                IconButton(
                  tooltip: s.delete,
                  icon: Icon(
                    AppIcons.delete,
                    size: 20,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: onDelete,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
