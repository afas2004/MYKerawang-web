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
import '../utils/guest_access.dart';
import '../utils/listing_status.dart';
import '../widgets/brand/brand.dart';
import '../widgets/embed_card.dart';
import '../widgets/error_state.dart';
import '../widgets/feed_composer.dart';
import '../widgets/hover_carousel.dart';
import '../widgets/shell_actions.dart';
import '../widgets/universal_card.dart';
import '../utils/announcement_rules.dart';
import '../widgets/announcement_view.dart';
import '../widgets/post_card.dart';
import '../widgets/profile_avatar_action.dart';
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
  // Announcements may opt out of Home (show_in_feed = false); scheduled
  // ones wait for publish_at (the view hides them too).
  final shown = posts.where((p) => showInHomeFeed(p)).toList();
  for (var i = 0; i < shown.length; i++) {
    out.add({...shown[i], 'type': 'post'});
    if (inject && (i + 1) % every == 0 && next < injectables.length) {
      out.add(injectables[next++]);
    }
  }
  return out;
}

/// Home's app bar actions: search, a refresh button only for mouse users
/// on desktop web (phones pull to refresh), notifications for signed-in
/// users, then the profile avatar (or "Sign in" for guests). Settings
/// live behind the avatar / in Profile.
///
/// [unreadBadge] false draws a plain bell (tests: the live count needs
/// Supabase).
List<Widget> homeAppBarActions(BuildContext context,
    {required VoidCallback onRefresh, bool unreadBadge = true}) {
  final s = context.l10n;
  final signedIn = ShellAuth.of(context);
  return [
    const ShellSearchButton(),
    const ShellClubsButton(),
    if (kIsWeb && Responsive.isDesktop(context))
      IconButton(
        tooltip: s.refresh,
        icon: const Icon(AppIcons.refresh),
        onPressed: onRefresh,
      ),
    if (signedIn)
      IconButton(
        tooltip: s.notifications,
        icon: unreadBadge
            ? const UnreadBadge(child: Icon(AppIcons.notifications))
            : const Icon(AppIcons.notifications),
        onPressed: () => context.goNotifications(),
      ),
    const ProfileAvatarAction(),
    const SizedBox(width: KSpace.s),
  ];
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
            .eq('is_hidden', false)
            .isFilter('cancelled_at', null)
            .gt('end_datetime', now)
            .order('start_datetime', ascending: true)
            .limit(20),
        _supabase.from('listings')
            .select()
            .or(kAvailableListingsFilter)
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
      .order('is_pinned', ascending: false) // active pins first (20261019004500)
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

  /// The editor is a route (/create/post); publishing lands on the new
  /// post and the feed refreshes through [onContentChanged].
  void _openComposer() {
    // Guests see the feed read-only; posting asks them to sign in.
    if (!requireLogin(context)) return;
    context.goCreatePost();
  }

  @override
  Widget build(BuildContext context) {
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
      // Search and notifications only. Settings live in Profile; refresh
      // is pull-to-refresh, with a button only for mouse users on desktop.
      actions: homeAppBarActions(context, onRefresh: _fetchFeedData),
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
  /// The first cards of the feed fade up in turn on load; the rest just
  /// appear.
  static Widget _enter(int index, Widget Function() build) =>
      index < 6 ? KEntrance(index: index, child: build()) : build();

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
    final railVisible = size.isLarge; // MainScaffold shows the rail here
    final items = buildFeedItems(posts, injectables, inject: !railVisible);
    final topPadding = MediaQuery.paddingOf(context).top + KBand.heightOf(context);

    return Scaffold(
      body: LinearRefresher(
        onRefresh: onRefresh,
        offset: topPadding,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // Kepala kain: Home's band is plum.
              KBand.sliverAppBar(
                context,
                tone: KBand.home,
                // Desktop: the sidebar carries the wordmark, so the page
                // header just names the page.
                title: size.isExpanded ? Text(s.navHome) : Text(
                  AppStrings.appName,
                  // 20 px so the wordmark fits beside four actions on a
                  // 360 px phone.
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: KBand.onBand),
                ),
                actions: actions,
              ),

              _column(SliverToBoxAdapter(child: FeedComposer(onTap: onCompose))),

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
                      cardWidth: 220,
                    ),
                  )),
                if (!railVisible && !isLoading && listings.isNotEmpty)
                  _column(SliverToBoxAdapter(
                    child: _FeedSection(
                      title: s.freshFinds,
                      onSeeAll: () => context.go('/market'),
                      items: listings,
                      onTap: (l) => context.goItem(l),
                      cardWidth: 160,
                    ),
                  )),
                if (isLoading)
                  _column(SliverToBoxAdapter(child: PostCardSkeleton.list(context)))
                else
                  _column(SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _enter(index, () {
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
                        if (item['is_announcement'] == true) {
                          return AnnouncementCard(
                            key: ValueKey(item['id']),
                            post: item,
                            onTap: () => context.goPost(item),
                          );
                        }
                        return PostCard(
                          key: ValueKey(item['id']),
                          post: item,
                          onTap: () => context.goPost(item),
                        );
                      }),
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
        padding: const EdgeInsets.symmetric(vertical: KSpace.l),
        child: Column(
          children: [
            Text(s.social.loadMoreFailed),
            TextButton.icon(
              onPressed: onLoadMore,
              icon: const Icon(AppIcons.refresh),
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
      padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.xl, KSpace.l, 96),
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
      padding: const EdgeInsets.only(top: KSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(
            title: title,
            onSeeAll: onSeeAll,
            padding: const EdgeInsets.fromLTRB(KSpace.l, 0, KSpace.s, KSpace.xs),
          ),
          // Compact strip: photo + two text lines.
          HoverCarousel(
            height: 196,
            itemCount: items.length,
            itemBuilder: (context, i) => Container(
              width: cardWidth,
              margin: const EdgeInsets.only(right: KSpace.m, bottom: KSpace.s),
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
        icon: AppIcons.compose,
        illo: AppIllo.emptyFeed,
        title: s.social.feedEmptyTitle,
        message: s.social.feedEmptyBody,
        actionLabel: s.social.createFirstPost,
        onAction: onCompose,
      ),
    );
  }
}
