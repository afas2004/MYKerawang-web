import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/utils/report_helper.dart';
import 'package:mykerawang/widgets/mention_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/mention_service.dart';
import '../services/post_service.dart';
import '../widgets/linear_refresher.dart';
import '../widgets/mention_text.dart';
import '../widgets/owner_menu.dart';
import '../widgets/post_card.dart';
import '../l10n/app_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import '../utils/adaptive.dart';
import '../utils/responsive.dart';

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

  Future<void> _loadComments() async {
    final seq = ++_loadSeq;
    final limit = _commentLimit;
    try {
      // Newest first so the limit keeps the latest; one extra row tells
      // whether there are earlier ones.
      final response = await _supabase
          .from('comments_public') // anonymity-safe view
          .select('*')
          .eq('post_id', _postId)
          .order('created_at', ascending: false)
          .limit(limit + 1);
      final rows = List<Map<String, dynamic>>.from(response);
      final hasEarlier = rows.length > limit;
      final comments = rows.take(limit).toList().reversed.toList();

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
              onPressed: () => Navigator.pop(ctx), child: Text(s.cancel)),
          TextButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: Text(s.saveChanges)),
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
      messenger.showSnackBar(SnackBar(content: Text(s.errorWithDetail.fill([e]))));
    }
  }

  Future<void> _deleteComment(Map<String, dynamic> c) async {
    final s = context.l10nRead;
    final ps = context.postL10nRead;
    final ok = await confirmDelete(context,
        title: ps.deleteComment, message: ps.deleteCommentConfirm);
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await PostService.deleteComment(c['id']);
      messenger.showSnackBar(SnackBar(content: Text(ps.commentDeleted)));
      await _refreshData();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.errorWithDetail.fill([e]))));
    }
  }

  /// A cold deep link has nothing underneath to pop back to.
  void _leave() => context.canPop() ? context.pop() : context.go('/home');

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty || _isSending) return;
    final s = context.l10nRead;
    final ps = context.postL10nRead;
    final messenger = ScaffoldMessenger.of(context);

    setState(() => _isSending = true);
    try {
      final newComment = await _supabase.from('comments').insert({
        'post_id': _postId,
        'user_id': _supabase.auth.currentUser!.id,
        'body': text,
        'is_anonymous': _isAnon,
      }).select('id').single();

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
      messenger.showSnackBar(SnackBar(
        content: Text(ps.commentFailed),
        action: SnackBarAction(
          label: s.tryAgain,
          onPressed: () {
            if (mounted) _submitComment();
          },
        ),
      ));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Widget _buildComments(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final ps = context.postL10n;

    if (!_commentsLoaded) {
      if (_commentsError != null) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(s.connectionError,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant)),
              TextButton.icon(
                onPressed: _loadComments,
                icon: const Icon(Icons.refresh),
                label: Text(s.tryAgain),
              ),
            ],
          ),
        );
      }
      return const Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()));
    }

    if (_comments.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32.0),
        child: Text(s.beFirstToComment, style: TextStyle(color: scheme.onSurfaceVariant)),
      );
    }

    return Column(
      children: [
        if (_hasEarlier)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _loadingEarlier
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton.icon(
                    onPressed: _showEarlier,
                    icon: const Icon(Icons.expand_less),
                    label: Text(ps.showEarlierComments),
                  ),
          ),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _comments.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final c = _comments[index];
            final isAnon = c['is_anonymous'] ?? false;

            final profile = c['profiles'];
            final displayName = displayNameFor(s, profile, anonymous: isAnon);
            final avatarUrl = isAnon ? null : profile?['avatar_url'];
            final username = isAnon ? null : profile?['username'];

            return ListTile(
              leading: Tooltip(
                // Explain what the crossed-eye icon means
                message: isAnon ? s.postedAnonymously : displayName,
                child: CircleAvatar(
                  radius: 16,
                  backgroundColor: isAnon
                      ? scheme.surfaceContainerHighest
                      : scheme.primaryContainer,
                  backgroundImage: avatarUrl != null ? CachedNetworkImageProvider(avatarUrl) : null,
                  child: (avatarUrl == null)
                      ? Icon(isAnon ? Icons.visibility_off : Icons.person,
                          size: 16,
                          color: isAnon
                              ? scheme.onSurfaceVariant
                              : scheme.onPrimaryContainer)
                      : null,
                ),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(displayName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                  if (!isAnon && username != null) ...[
                    const SizedBox(width: 4),
                    Text("@$username", style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                  const SizedBox(width: 8),
                  Text(formatRelative(context, DateTime.parse(c['created_at'])), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ),
              subtitle: MentionText(c['body'] ?? ''),
              trailing: _myCommentIds.contains(c['id'])
                  ? OwnerMenuButton(
                      iconSize: 18,
                      tooltip: ps.commentOptions,
                      onEdit: () => _editComment(c),
                      onDelete: () => _deleteComment(c),
                    )
                  : ReportMenuButton(targetId: c['id'], type: 'comment', iconSize: 18),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final ps = context.postL10n;
    final canSend = _hasText && !_isSending;
    return Scaffold(
      appBar: appBarConstrained(
        context,
        leading: IconButton(
          tooltip: s.back,
          icon: const BackButtonIcon(),
          onPressed: _leave,
        ),
        title: Text(s.threadTitle),
      ),
      body: PageBody(child: Column(
        children: [
          Expanded(
            child: LinearRefresher(
              onRefresh: _refreshData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // Ensures pull-to-refresh works even if list is short
                child: Column(
                  children: [
                    PostCard(post: _postData, onTap: null, onDeleted: _leave),

                    const Divider(thickness: 4),

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: scheme.surface,
                      child: Semantics(
                        header: true,
                        child: Text(s.comments, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),

                    _buildComments(context),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ),

          // INPUT BAR
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              boxShadow: [BoxShadow(color: scheme.shadow.withValues(alpha: 0.05), blurRadius: 5, offset: const Offset(0, -2))],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  IconButton(
                    tooltip: _isAnon ? ps.commentAnonOn : ps.commentAnonOff,
                    isSelected: _isAnon,
                    icon: Icon(
                      _isAnon ? Icons.visibility_off : Icons.visibility,
                      color: _isAnon ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    onPressed: () => setState(() => _isAnon = !_isAnon),
                  ),
                  Expanded(
                    child: MentionInput(
                      controller: _commentCtrl,
                      hintText: s.commentHint,
                      isMultiLine: true,
                      reverseDirection: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: ps.sendComment,
                    onPressed: canSend ? _submitComment : null,
                    icon: _isSending
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.send,
                            color: canSend ? scheme.primary : scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ],
      )),
    );
  }
}
