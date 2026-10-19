import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../l10n/feed_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../utils/app_nav.dart';
import '../widgets/brand/brand.dart';
import '../utils/tags.dart';
import '../widgets/error_state.dart';
import '../widgets/linear_refresher.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card_skeleton.dart';

/// Opens the feed of posts carrying [tag] at `/tag/:tag` (linkable).
Future<void> openTagFeed(BuildContext context, String tag) async =>
    context.goTag(tag);

/// Posts with one hashtag, newest first, loaded a page at a time.
class TagFeedScreen extends StatefulWidget {
  final String tag;

  const TagFeedScreen({super.key, required this.tag});

  @override
  State<TagFeedScreen> createState() => _TagFeedScreenState();
}

class _TagFeedScreenState extends State<TagFeedScreen> {
  static const _pageSize = 20;

  final List<Map<String, dynamic>> _posts = [];
  bool _loading = false;
  bool _hasMore = true;
  int? _count;
  Object? _error; // error of the last page load

  late final String _tag = normalizeTag(widget.tag);

  SupabaseQueryBuilder get _view =>
      Supabase.instance.client.from('posts_public'); // anonymity-safe view

  @override
  void initState() {
    super.initState();
    _loadPage();
    _loadCount();
  }

  Future<void> _loadCount() async {
    try {
      final res = await _view
          .select('id')
          .overlaps('tags', tagAliases(_tag))
          .count(CountOption.exact);
      if (mounted) setState(() => _count = res.count);
    } catch (e) {
      debugPrint("Tag count failed: $e"); // header just omits the count
    }
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading || (!_hasMore && !reset)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final from = reset ? 0 : _posts.length;
    try {
      final rows = await _view
          .select('*')
          .overlaps('tags', tagAliases(_tag))
          .order('created_at', ascending: false)
          .range(from, from + _pageSize - 1);
      if (!mounted) return;
      setState(() {
        if (reset) _posts.clear();
        _posts.addAll(List<Map<String, dynamic>>.from(rows));
        _hasMore = rows.length == _pageSize;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refresh() async {
    await Future.wait([_loadPage(reset: true), _loadCount()]);
  }

  @override
  Widget build(BuildContext context) {
    return TagFeedView(
      tag: _tag,
      count: _count,
      posts: _posts,
      loading: _loading,
      error: _error,
      hasMore: _hasMore,
      onRefresh: _refresh,
      onLoadMore: _loadPage,
    );
  }
}

/// Tag feed layout from data: header (tag in the display face + post
/// count), then the same cards as the home feed in one ≤680 px column.
class TagFeedView extends StatelessWidget {
  final String tag;
  final int? count;
  final List<Map<String, dynamic>> posts;
  final bool loading;
  final Object? error;
  final bool hasMore;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;

  const TagFeedView({
    super.key,
    required this.tag,
    required this.count,
    required this.posts,
    required this.loading,
    required this.error,
    required this.hasMore,
    required this.onRefresh,
    required this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final ps = context.postL10n;
    final fs = context.feedL10n;
    final title = displayTag(tag);

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            label: ps.tagPostsLabel.fill([title]),
            excludeSemantics: true,
            child: Text(title, style: theme.textTheme.headlineSmall),
          ),
          if (count != null)
            Text(
              count == 1 ? fs.tagPostCountOne : fs.tagPostCount.fill([count]),
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );

    final Widget body;
    if (posts.isEmpty && loading) {
      body = ListView(children: [header, PostCardSkeleton.list(context)]);
    } else if (posts.isEmpty && error != null) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [header, ErrorState(onRetry: onRefresh)],
      );
    } else if (posts.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          header,
          BrandEmptyState(
            icon: Icons.tag,
            title: ps.noTaggedPosts,
            compact: true,
          ),
        ],
      );
    } else {
      body = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.metrics.extentAfter < 600 && error == null) onLoadMore();
          return false;
        },
        child: ListView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: posts.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) return header;
            if (i <= posts.length) {
              final post = posts[i - 1];
              return PostCard(
                key: ValueKey(post['id']),
                post: post,
                onTap: () => context.goPost(post),
                onTagTap: (t) =>
                    normalizeTag(t) == tag ? null : openTagFeed(context, t),
              );
            }
            // Footer: next page loading, failed (retry), or the end.
            if (error != null) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(ps.loadMoreFailed),
                    TextButton.icon(
                      onPressed: onLoadMore,
                      icon: const Icon(Icons.refresh),
                      label: Text(s.tryAgain),
                    ),
                  ],
                ),
              );
            }
            if (hasMore) return const PostCardSkeleton();
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Text(fs.feedEnd,
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: s.back,
          icon: const BackButtonIcon(),
          onPressed: () => appBack(context),
        ),
        bottom: LatticeBand.preferred(),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
          child: LinearRefresher(onRefresh: onRefresh, child: body),
        ),
      ),
    );
  }
}
