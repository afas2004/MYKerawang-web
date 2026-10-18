import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:mykerawang/utils/report_helper.dart';
import 'package:mykerawang/widgets/mention_input.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/linear_refresher.dart';
import '../widgets/mention_text.dart';
import '../widgets/post_card.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import '../utils/adaptive.dart';
import '../utils/responsive.dart';
import '../widgets/restriction_gate.dart';

class PostDetailScreen extends StatefulWidget {
  final Map<String, dynamic> post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final _commentCtrl = TextEditingController();
  final _supabase = Supabase.instance.client;
  
  // STATE VARIABLES
  bool _isLoading = false;
  bool _isAnon = false;
  late Map<String, dynamic> _postData; // <--- NEW: Dynamic Post Data
  late Stream<List<Map<String, dynamic>>> _commentsStream;

  @override
  void initState() {
    super.initState();
    _postData = widget.post; // Initialize with passed data
    _commentsStream = _fetchCommentsStream();
  }

  // 1. REFRESH FUNCTION (Updates Post Counts)
  Future<void> _refreshData() async {
    try {
      // Fetch the specific post again to get new 'comment_count'
      final freshPost = await _supabase
          .from('posts_public') // anonymity-safe view
          .select('*')
          .eq('id', _postData['id'])
          .single();
      
      if (mounted) {
        setState(() {
          _postData = freshPost; // Update UI with new numbers
        });
      }
    } catch (e) {
      debugPrint("Refresh error: $e");
    }
  }

  Stream<List<Map<String, dynamic>>> _fetchCommentsStream() async* {
    yield await _fetchComments();
    final stream = _supabase
        .from('comments')
        .stream(primaryKey: ['id'])
        .eq('post_id', widget.post['id'])
        .order('created_at', ascending: true);

    await for (final _ in stream) {
      yield await _fetchComments();
    }
  }

  Future<List<Map<String, dynamic>>> _fetchComments() async {
    final response = await _supabase
        .from('comments_public') // anonymity-safe view
        .select('*')
        .eq('post_id', widget.post['id'])
        .order('created_at', ascending: true);
    return List<Map<String, dynamic>>.from(response);
  }

  // PASTE THIS INSIDE _PostDetailScreenState class
  Future<void> _processMentions(String text, String postId, {String? commentId}) async {
    final regex = RegExp(r"\@(\w+)");
    final matches = regex.allMatches(text);
    final usernames = matches.map((m) => m.group(1)).toSet().toList();

    if (usernames.isEmpty) return;

    final myId = _supabase.auth.currentUser!.id;
    // Read by the recipient, so written in the canonical language.
    const n = AppStrings.en;

    final users = await _supabase
        .from('profiles')
        .select('id, username')
        .inFilter('username', usernames);

    for (var user in users) {
      if (user['id'] == myId) continue;

      await _supabase.from('notifications').insert({
        'user_id': user['id'],
        'actor_id': myId,
        'type': 'mention',
        'title': n.notifMentionCommentTitle,
        'body': n.notifMentionCommentBody.fill([text]),
        'data': {'post_id': postId, 'comment_id': commentId},
      });
    }
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    
    // ... (Your existing login check) ...
    if (!await ensureCanWrite(context, ModScope.comment) || !mounted) return;

    setState(() => _isLoading = true);

    try {
      // 1. Send to Database AND Select the ID back
      final newComment = await _supabase.from('comments').insert({
        'post_id': widget.post['id'],
        'user_id': _supabase.auth.currentUser!.id,
        'body': text,
        'is_anonymous': _isAnon,
      }).select().single(); // <--- ADD .select().single()

      // 2. PROCESS MENTIONS (This was missing!)
      await _processMentions(text, widget.post['id'], commentId: newComment['id']);

      // 3. Clear Input & Refresh
      _commentCtrl.clear();
      if (mounted) FocusScope.of(context).unfocus();
      await _refreshData();
      if (!mounted) return;
      setState(() {
        _commentsStream = _fetchCommentsStream(); 
      });
      
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeWriteError(context, e))));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    return Scaffold(
      appBar: appBarConstrained(context, title: Text(s.threadTitle)),
      body: PageBody(child: Column(
        children: [
          Expanded(
            child: LinearRefresher(
              onRefresh: _refreshData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(), // Ensures pull-to-refresh works even if list is short
                child: Column(
                  children: [
                    // USE DYNAMIC _postData HERE
                    PostCard(post: _postData, onTap: null),
                    
                    const Divider(thickness: 4), 
                    
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      color: scheme.surface,
                      child: Text(s.comments, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),

                    StreamBuilder<List<Map<String, dynamic>>>(
                      stream: _commentsStream,
                      builder: (context, snapshot) {
                        if (snapshot.hasError) return Padding(padding: const EdgeInsets.all(16), child: Text(s.errorWithDetail.fill([snapshot.error])));
                        if (!snapshot.hasData) return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
                        
                        final comments = snapshot.data!;
                        if (comments.isEmpty) {
                           return Padding(
                             padding: const EdgeInsets.all(32.0),
                             child: Text(s.beFirstToComment, style: TextStyle(color: scheme.onSurfaceVariant)),
                           );
                        }

                        return ListView.separated(
                          shrinkWrap: true, 
                          physics: const NeverScrollableScrollPhysics(), 
                          itemCount: comments.length,
                          separatorBuilder: (_,__) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final c = comments[index];
                            final isAnon = c['is_anonymous'] ?? false;
                            
                            final profile = c['profiles'];
                            final displayName = displayNameFor(s, profile, anonymous: isAnon);
                            final avatarUrl = isAnon ? null : profile?['avatar_url'];
                            final username = isAnon ? null : profile?['username'];

                            return ListTile(
                              leading: Tooltip(
                                // Explain what the crossed-eye icon means
                                message: isAnon
                                    ? s.postedAnonymously
                                    : displayName,
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
                                  Text(displayName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  if (!isAnon && username != null) ...[
                                    const SizedBox(width: 4),
                                    Text("@$username", style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                  ],
                                  const SizedBox(width: 8),
                                  Text(formatRelative(context, DateTime.parse(c['created_at'])), style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                                ],
                              ),

                              subtitle: MentionText(c['body'] ?? ''),
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
          ),
          
          // INPUT BAR (Same as before)
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
                    tooltip: s.postAnonymously,
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
                    onPressed: _isLoading ? null : _submitComment,
                    icon: _isLoading 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                      : Icon(Icons.send, color: scheme.primary),
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