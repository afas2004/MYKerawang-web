import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/widgets/linear_refresher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../l10n/feed_strings.dart';
import '../language_cubit.dart';
import '../l10n/social_strings.dart';
import '../services/unread_notifications.dart';
import '../utils/app_nav.dart';
import '../widgets/brand/brand.dart';
import '../widgets/embed_card.dart';
import '../widgets/error_state.dart';
import '../widgets/feed_composer.dart';
import '../widgets/hover_carousel.dart';
import '../widgets/shell_actions.dart';
import '../widgets/universal_card.dart';
import '../widgets/post_card.dart';
import 'create_post_screen.dart';
import '../widgets/post_card_skeleton.dart';

/// Posts with one discovery embed (alternating event / listing) after
/// every [every]th post — deterministic, so the same data always gives
/// the same feed (DESIGN_SPEC §4).
List<Map<String, dynamic>> buildFeedItems(
  List<Map<String, dynamic>> posts,
  List<Map<String, dynamic>> injectables, {
  bool inject = true,
  int every = 6,
}) {
  final out = <Map<String, dynamic>>[];
  var next = 0;
  for (var i = 0; i < posts.length; i++) {
    out.add({...posts[i], 'type': 'post'});
    if (inject && (i + 1) % every == 0 && next < injectables.length) {
      out.add(injectables[next++]);
    }
  }
  return out;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

/// Loads the feed; [FeedView] lays it out.
class _HomeScreenState extends State<HomeScreen>
    with RefreshOnContentChange {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _hasError = false;
  List<Map<String, dynamic>> _featuredEvents = [];
  List<Map<String, dynamic>> _freshMarketItems = [];

  // Paging: posts arrive [_pageSize] at a time as the user nears the end.
  static const _pageSize = 20;
  final List<Map<String, dynamic>> _posts = [];
  final Set<dynamic> _postIds = {};
  List<Map<String, dynamic>> _injectables = [];
  bool _hasMore = true;
  bool _loadingMore = false;
  bool _loadMoreError = false;

  @override
  void initState() {
    super.initState();
    _fetchFeedData();
  }

  Future<void> _fetchFeedData() async {
    if (mounted && _hasError) setState(() => _hasError = false);
    try {
      final now = DateTime.now().toUtc().toIso8601String();

      // All three run in parallel — one round trip on mobile, not three.
      final results = await Future.wait<List<Map<String, dynamic>>>([
        _supabase.from('events')
            .select()
            .gt('end_datetime', now)
            .order('start_datetime', ascending: true)
            .limit(20),
        _supabase.from('listings')
            .select()
            .eq('is_sold', false)
            .order('created_at', ascending: false)
            .limit(20),
        _postsPage(0),
      ]);
      final events = results[0];
      final listings = results[1];
      final posts = results[2];

      // Injectables: alternate event/listing, in their natural order.
      final injectables = <Map<String, dynamic>>[];
      for (int i = 0; i < events.length || i < listings.length; i++) {
        if (i < events.length) injectables.add({...events[i], 'type': 'event'});
        if (i < listings.length) {
          injectables.add({...listings[i], 'type': 'listing'});
        }
      }

      if (mounted) {
        setState(() {
          _featuredEvents = events.take(8).toList();
          _freshMarketItems = listings.take(8).toList();
          _injectables = injectables;
          _posts
            ..clear()
            ..addAll(posts);
          _postIds
            ..clear()
            ..addAll(posts.map((p) => p['id']));
          _hasMore = posts.length == _pageSize;
          _loadMoreError = false;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching feed: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  /// Posts from the view, which blanks user_id/profiles on anonymous
  /// rows (joins are baked in), [_pageSize] at a time. Active pins first.
  Future<List<Map<String, dynamic>>> _postsPage(int from) => _supabase
      .from('posts_public')
      .select('*')
      .order('is_pinned') // active pins first (20261019004500)
      .order('created_at', ascending: false)
      .range(from, from + _pageSize - 1);

  /// Next page, appended. Rows already shown (new posts shift the
  /// offsets) are skipped.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _isLoading) return;
    setState(() {
      _loadingMore = true;
      _loadMoreError = false;
    });
    try {
      final page = await _postsPage(_posts.length);
      if (!mounted) return;
      setState(() {
        for (final p in page) {
          if (_postIds.add(p['id'])) _posts.add(p);
        }
        _hasMore = page.length == _pageSize;
      });
    } catch (e) {
      debugPrint("Error loading more posts: $e");
      if (mounted) setState(() => _loadMoreError = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  // New / edited / deleted content elsewhere refreshes the feed.
  @override
  void onContentChanged() => _fetchFeedData();

  Future<void> _openComposer() async {
    if (await openPostComposer(context) && mounted) _fetchFeedData();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return FeedView(
      posts: _posts,
      injectables: _injectables,
      events: _featuredEvents,
      listings: _freshMarketItems,
      isLoading: _isLoading,
      hasError: _hasError,
      hasMore: _hasMore,
      loadingMore: _loadingMore,
      loadMoreError: _loadMoreError,
      onRefresh: _fetchFeedData,
      onLoadMore: _loadMore,
      onCompose: _openComposer,
      onPosted: _fetchFeedData,
      actions: [
        const ShellSearchButton(),
        // Pull-to-refresh has no mouse equivalent on web
        if (kIsWeb)
          IconButton(
            tooltip: s.refresh,
            icon: const Icon(Icons.refresh),
            onPressed: _fetchFeedData,
          ),
        IconButton(
          tooltip: s.notifications,
          icon: const UnreadBadge(child: Icon(Icons.notifications_outlined)),
          onPressed: () => context.goNotifications(),
        ),
        IconButton(
          tooltip: s.settings,
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => context.goSettings(),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

}

/// The home feed layout, fed with data — no Supabase, so it can be
/// tested at any width.
///
/// Every size: app bar, composer, then posts in one ≤680 px column
/// (pinned first, gold-framed by [PostCard]). Without the right rail
/// (< [Responsive.railBreakpoint]) discovery moves into the feed:
/// "Happening soon" and "Fresh finds" sections, plus one event/listing
/// embed after every 6th post.
class FeedView extends StatelessWidget {
  final List<Map<String, dynamic>> posts;
  final List<Map<String, dynamic>> injectables;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> listings;
  final bool isLoading;
  final bool hasError;
  final bool hasMore;
  final bool loadingMore;
  final bool loadMoreError;
  final Future<void> Function() onRefresh;
  final VoidCallback onLoadMore;
  final VoidCallback onCompose;
  final VoidCallback onPosted;
  final List<Widget> actions;

  const FeedView({
    super.key,
    required this.posts,
    this.injectables = const [],
    this.events = const [],
    this.listings = const [],
    this.isLoading = false,
    this.hasError = false,
    this.hasMore = false,
    this.loadingMore = false,
    this.loadMoreError = false,
    required this.onRefresh,
    required this.onLoadMore,
    required this.onCompose,
    required this.onPosted,
    this.actions = const [],
  });

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical &&
        n.metrics.extentAfter < 800 &&
        !loadMoreError) {
      onLoadMore();
    }
    return false;
  }

  /// Centres slivers in a column of at most [Responsive.feedMaxWidth].
  static Widget _column(Widget sliver) => SliverLayoutBuilder(
        builder: (context, c) {
          final side = ((c.crossAxisExtent - Responsive.feedMaxWidth) / 2)
              .clamp(0.0, double.infinity);
          return SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: side),
            sliver: sliver,
          );
        },
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = context.l10n;
    final width = MediaQuery.sizeOf(context).width;
    final size = Responsive.sizeFor(width);
    final desktop = size.isExpanded;
    final railVisible = size.isLarge; // MainScaffold shows the rail here
    final items = buildFeedItems(posts, injectables, inject: !railVisible);
    final topPadding = MediaQuery.paddingOf(context).top + kToolbarHeight;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: LinearRefresher(
        onRefresh: onRefresh,
        offset: topPadding,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                // On desktop the sidebar already carries the wordmark (F2.7)
                title: Text(
                  desktop ? s.navHome : AppStrings.appName,
                  style: theme.textTheme.titleLarge,
                ),
                centerTitle: false,
                actions: actions,
                bottom: LatticeBand.preferred(),
              ),

              _column(SliverToBoxAdapter(child: FeedComposer(onPosted: onPosted))),

              if (!isLoading && hasError && posts.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: ErrorState(onRetry: onRefresh),
                )
              else ...[
                if (!railVisible && !isLoading && events.isNotEmpty)
                  _column(SliverToBoxAdapter(
                    child: _FeedSection(
                      title: s.happeningSoon,
                      onSeeAll: () => context.go('/events'),
                      items: events,
                      onTap: (e) => context.goEvent(e),
                      cardWidth: 240,
                    ),
                  )),
                if (!railVisible && !isLoading && listings.isNotEmpty)
                  _column(SliverToBoxAdapter(
                    child: _FeedSection(
                      title: s.freshFinds,
                      onSeeAll: () => context.go('/market'),
                      items: listings,
                      onTap: (l) => context.goItem(l),
                      cardWidth: 180,
                    ),
                  )),
                if (isLoading)
                  _column(SliverToBoxAdapter(child: PostCardSkeleton.list(context)))
                else
                  _column(SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = items[index];
                        if (item['type'] == 'event' || item['type'] == 'listing') {
                          final isEvent = item['type'] == 'event';
                          return EmbedCard(
                            data: item,
                            isEvent: isEvent,
                            onTap: () => isEvent
                                ? context.goEvent(item)
                                : context.goItem(item),
                          );
                        }
                        return PostCard(
                          key: ValueKey(item['id']),
                          post: item,
                          onTap: () => context.goPost(item),
                        );
                      },
                      childCount: items.length,
                    ),
                  )),
                if (!isLoading && !hasError && posts.isEmpty)
                  _column(SliverToBoxAdapter(child: _EmptyFeed(onCompose: onCompose))),
                if (!isLoading && posts.isNotEmpty)
                  _column(SliverToBoxAdapter(child: _pagingFooter(context))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _pagingFooter(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    if (loadMoreError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(s.social.loadMoreFailed),
            TextButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(Icons.refresh),
              label: Text(s.social.retry),
            ),
          ],
        ),
      );
    }
    if (hasMore) {
      // Slivers build lazily, so the footer being built means it is near
      // the viewport — covers tall screens where nothing scrolls.
      if (!loadingMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) => onLoadMore());
      }
      return const PostCardSkeleton();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 96),
      child: Center(
        child: Text(context.feedL10n.feedEnd,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    );
  }
}

/// Section header (display-face title + "See all") over a horizontal list.
class _FeedSection extends StatelessWidget {
  final String title;
  final VoidCallback onSeeAll;
  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onTap;
  final double cardWidth;

  const _FeedSection({
    required this.title,
    required this.onSeeAll,
    required this.items,
    required this.onTap,
    required this.cardWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KSpace.m, bottom: KSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: title,
            onSeeAll: onSeeAll,
            padding: const EdgeInsets.fromLTRB(KSpace.l, 0, KSpace.s, KSpace.xs),
          ),
          HoverCarousel(
            height: 250,
            itemCount: items.length,
            itemBuilder: (context, i) => Container(
              width: cardWidth,
              margin: const EdgeInsets.only(right: 12, bottom: 8),
              child: UniversalCard(data: items[i], onTap: () => onTap(items[i])),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFeed extends StatelessWidget {
  final VoidCallback onCompose;

  const _EmptyFeed({required this.onCompose});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KSpace.xl),
      child: BrandEmptyState(
        icon: Icons.forum_outlined,
        title: s.social.feedEmptyTitle,
        message: s.social.feedEmptyBody,
        actionLabel: s.social.createFirstPost,
        onAction: onCompose,
      ),
    );
  }
}
