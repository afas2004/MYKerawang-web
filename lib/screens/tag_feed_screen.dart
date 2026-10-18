import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/app_strings.dart';
import '../l10n/post_strings.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/responsive.dart';
import '../utils/tags.dart';
import '../widgets/error_state.dart';
import '../widgets/linear_refresher.dart';
import '../widgets/post_card.dart';
import '../widgets/post_card_skeleton.dart';

/// Opens the feed of posts carrying [tag] (pushed, not a route — no
/// deep link yet).
Future<void> openTagFeed(BuildContext context, String tag) =>
    Navigator.push(context,
        MaterialPageRoute(builder: (_) => TagFeedScreen(tag: tag)));

/// Posts with one hashtag, newest first, loaded a page at a time.
class TagFeedScreen extends StatefulWidget {
  final String tag;

  const TagFeedScreen({super.key, required this.tag});

  @override
  State<TagFeedScreen> createState() => _TagFeedScreenState();
}

class _TagFeedScreenState extends State<TagFeedScreen> {
  static const _pageSize = 20;

  final _scroll = ScrollController();
  final List<Map<String, dynamic>> _posts = [];
  bool _loading = false;
  bool _hasMore = true;
  Object? _error; // error of the last page load

  late final String _tag = normalizeTag(widget.tag);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.extentAfter < 600) _loadPage();
  }

  Future<void> _loadPage({bool reset = false}) async {
    if (_loading || (!_hasMore && !reset)) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final from = reset ? 0 : _posts.length;
    try {
      final rows = await Supabase.instance.client
          .from('posts_public') // anonymity-safe view
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

  Future<void> _refresh() => _loadPage(reset: true);

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final ps = context.postL10n;
    final title = displayTag(_tag);

    final Widget body;
    if (_posts.isEmpty && _loading) {
      body = ListView(children: [PostCardSkeleton.list(context)]);
    } else if (_posts.isEmpty && _error != null) {
      body = ErrorState(onRetry: _refresh);
    } else if (_posts.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text(ps.noTaggedPosts,
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
        ],
      );
    } else {
      body = ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _posts.length + 1,
        itemBuilder: (context, i) {
          if (i < _posts.length) {
            final post = _posts[i];
            return PostCard(
              post: post,
              onTap: () => context.goPost(post),
              onTagTap: (t) =>
                  normalizeTag(t) == _tag ? null : openTagFeed(context, t),
            );
          }
          // Footer: next page loading, failed (retry), or nothing more.
          if (_error != null) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(ps.loadMoreFailed),
                  TextButton.icon(
                    onPressed: _loadPage,
                    icon: const Icon(Icons.refresh),
                    label: Text(s.tryAgain),
                  ),
                ],
              ),
            );
          }
          if (_hasMore) {
            return const PostCardSkeleton();
          }
          return const SizedBox(height: 80);
        },
      );
    }

    return Scaffold(
      appBar: appBarConstrained(
        context,
        leading: IconButton(
          tooltip: s.back,
          icon: const BackButtonIcon(),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Semantics(
          label: ps.tagPostsLabel.fill([title]),
          child: ExcludeSemantics(child: Text(title)),
        ),
      ),
      body: PageBody(
        child: LinearRefresher(onRefresh: _refresh, child: body),
      ),
    );
  }
}
