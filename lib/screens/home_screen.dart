import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/screens/create_event_screen.dart';
import 'package:mykerawang/screens/create_listing_screen.dart';
import 'package:mykerawang/widgets/linear_refresher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../l10n/social_strings.dart';
import '../services/unread_notifications.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../widgets/embed_card.dart';
import '../widgets/feed_composer.dart';
import '../widgets/hover_carousel.dart';
import '../widgets/universal_card.dart';
import '../widgets/post_card.dart';
import 'create_post_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  bool _hasError = false;
  List<dynamic> _socialFeed = []; // mobile: posts + injected embeds
  List<dynamic> _purePosts = []; // web: posts only (rail owns discovery)
  List<dynamic> _featuredEvents = [];
  List<dynamic> _freshMarketItems = [];

  // Paging: posts arrive [_pageSize] at a time as the user nears the end.
  static const _pageSize = 20;
  final List<Map<String, dynamic>> _posts = [];
  final Set<dynamic> _postIds = {};
  List<dynamic> _injectables = [];
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
        // 1. Events (For Carousel & Injection)
        _supabase.from('events')
            .select()
            .gt('end_datetime', now)
            .order('start_datetime', ascending: true)
            .limit(20), // Fetch more for injection

        // 2. Listings (For Horizontal & Injection)
        _supabase.from('listings')
            .select()
            .eq('is_sold', false)
            .order('created_at', ascending: false)
            .limit(20),

        // 3. First page of posts
        _postsPage(0),
      ]);
      final events = results[0];
      final listings = results[1];
      final posts = results[2];

      // Injectables: alternate event/listing, in their natural order.
      // Deterministic — same data always produces the same feed.
      final List<dynamic> injectables = [];
      for (int i = 0; i < events.length || i < listings.length; i++) {
        if (i < events.length) injectables.add({...events[i], 'type': 'event'});
        if (i < listings.length) {
          injectables.add({...listings[i], 'type': 'listing'});
        }
      }

      if (mounted) {
        setState(() {
          _featuredEvents = events.take(8).toList(); // Keep top 8 for carousel
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
          _rebuildFeeds();
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
  /// rows (joins are baked in), [_pageSize] at a time.
  Future<List<Map<String, dynamic>>> _postsPage(int from) => _supabase
      .from('posts_public')
      .select('*')
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
        _rebuildFeeds();
      });
    } catch (e) {
      debugPrint("Error loading more posts: $e");
      if (mounted) setState(() => _loadMoreError = true);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Derives both feeds from [_posts] (DESIGN_SPEC §4).
  void _rebuildFeeds() {
    final purePosts = _posts.map((p) => {...p, 'type': 'post'}).toList();

    // Mobile feed: exactly one embed after every 6th post.
    final List<dynamic> mixedFeed = [];
    int injectIndex = 0;
    for (int i = 0; i < purePosts.length; i++) {
      mixedFeed.add(purePosts[i]);
      if ((i + 1) % 6 == 0 && injectIndex < _injectables.length) {
        mixedFeed.add(_injectables[injectIndex++]);
      }
    }
    _socialFeed = mixedFeed;
    _purePosts = purePosts;
  }

  /// Fetch the next page when within ~a screen of the end.
  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis == Axis.vertical &&
        n.metrics.extentAfter < 800 &&
        !_loadMoreError) {
      _loadMore();
    }
    return false;
  }

  Future<void> _openComposer() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const CreatePostScreen()));
    if (mounted) _fetchFeedData();
  }

  @override
  Widget build(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top + kToolbarHeight;
    // Desktop: composer + pure posts; discovery lives in the right rail.
    // Mobile: carousels + deterministic embeds (DESIGN_SPEC §4).
    final bool isDesktop = isWide(context);
    final List<dynamic> feed = isDesktop ? _purePosts : _socialFeed;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: isDesktop
          ? null // sidebar "Jom post" + composer cover creation on desktop
          : FloatingActionButton(
              onPressed: () => _showCreateOptions(context),
              backgroundColor: Theme.of(context).colorScheme.primary,
              child: Icon(Icons.add,
                  color: Theme.of(context).colorScheme.onPrimary),
            ),
      body: LinearRefresher(
        onRefresh: _fetchFeedData,
        offset: topPadding,
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. APP BAR
            SliverAppBar(
              floating: true,
              snap: true,
              // On desktop the sidebar already carries the wordmark (F2.7)
              title: Text(
                isDesktop ? context.l10n.navHome : AppStrings.appName,
                style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.5),
              ),
              centerTitle: false,
              actions: [
                // Refresh button: pull-to-refresh has no mouse equivalent on web
                if (kIsWeb)
                  IconButton(
                    tooltip: context.l10n.refresh,
                    icon: const Icon(Icons.refresh),
                    onPressed: _fetchFeedData,
                  ),
                IconButton(
                  tooltip: context.l10n.notifications,
                  icon: const UnreadBadge(
                      child: Icon(Icons.notifications_outlined)),
                  onPressed: () => context.goNotifications(),
                ),
                IconButton(
                  tooltip: context.l10n.settings,
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.goSettings(),
                ),
                const SizedBox(width: 8),
              ],
            ),

            // COMPOSER (desktop web only) — posting without leaving the feed
            if (isDesktop && !_isLoading)
              SliverToBoxAdapter(
                child: FeedComposer(onPosted: _fetchFeedData),
              ),

            // ERROR STATE: network failed and we have nothing to show
            if (!_isLoading && _hasError && _socialFeed.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off,
                          size: 48,
                          color: Theme.of(context).colorScheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(context.l10n.connectionError),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _fetchFeedData,
                        icon: const Icon(Icons.refresh),
                        label: Text(context.l10n.tryAgain),
                      ),
                    ],
                  ),
                ),
              ),

            // 2. EVENTS CAROUSEL (Horizontal — mobile only; rail owns this on web)
            if (!isDesktop && !_isLoading && _featuredEvents.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(context.l10n.happeningSoon, () => context.go('/events')),
                    HoverCarousel(
                      height: 280,
                      itemCount: _featuredEvents.length,
                      itemBuilder: (context, index) {
                        return Container(
                          width: 260,
                          margin: const EdgeInsets.only(right: 12, bottom: 10),
                          child: UniversalCard(
                            data: _featuredEvents[index],
                            onTap: () => context.goEvent(_featuredEvents[index]),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),

            // 3. MARKETPLACE CAROUSEL (Horizontal — mobile only)
            if (!isDesktop && !_isLoading && _freshMarketItems.isNotEmpty)
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionHeader(context.l10n.freshFinds, () => context.go('/market')),
                    HoverCarousel(
                      height: 280,
                      itemCount: _freshMarketItems.length,
                      itemBuilder: (context, index) {
                        return Container(
                          width: 200,
                          margin: const EdgeInsets.only(right: 12, bottom: 10),
                          child: UniversalCard(
                            data: _freshMarketItems[index],
                            onTap: () => context.goItem(_freshMarketItems[index]),
                          ),
                        );
                      },
                    ),
                    const Divider(thickness: 8, height: 24), 
                  ],
                ),
              ),

            // 4. SOCIAL FEED (Vertical Mixed)
            _isLoading 
              ? const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
              : SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = feed[index];

                      // RENDER INJECTED EMBEDS (IG-style, DESIGN_SPEC §4)
                      if (item['type'] == 'event' || item['type'] == 'listing') {
                        final isEvent = item['type'] == 'event';
                        return EmbedCard(
                          data: item,
                          isEvent: isEvent,
                          onTap: () =>
                              isEvent ? context.goEvent(item) : context.goItem(item),
                        );
                      }

                      // RENDER POST
                      return PostCard(
                        post: item,
                        onTap: () => context.goPost(item),
                      );
                    },
                    childCount: feed.length,
                  ),
                ),

            // EMPTY STATE: loaded fine, but nobody has posted yet
            if (!_isLoading && !_hasError && _posts.isEmpty)
              SliverToBoxAdapter(child: _emptyFeed(context)),

            // PAGING FOOTER: spinner / retry / end
            if (!_isLoading && _posts.isNotEmpty)
              SliverToBoxAdapter(child: _pagingFooter(context)),
          ],
        ),
        ),
      )
    );
  }

  Widget _emptyFeed(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Icon(Icons.forum_outlined, size: 56, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(s.social.feedEmptyTitle,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(s.social.feedEmptyBody,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _openComposer,
            icon: const Icon(Icons.edit_outlined),
            label: Text(s.social.createFirstPost),
          ),
        ],
      ),
    );
  }

  Widget _pagingFooter(BuildContext context) {
    final s = context.l10n;
    if (_loadMoreError) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          children: [
            Text(s.social.loadMoreFailed),
            TextButton.icon(
              onPressed: _loadMore,
              icon: const Icon(Icons.refresh),
              label: Text(s.social.retry),
            ),
          ],
        ),
      );
    }
    if (_hasMore) {
      // Slivers build lazily, so the footer being built means it is near
      // the viewport — covers tall screens where nothing scrolls.
      if (!_loadingMore) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadMore();
        });
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return const SizedBox(height: 32);
  }

  Widget _sectionHeader(String title, VoidCallback onSeeAll) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          TextButton(onPressed: onSeeAll, child: Text(context.l10n.seeAll)),
        ],
      ),
    );
  }

  void _showCreateOptions(BuildContext context) {
    final s = context.l10nRead;
    showAdaptiveSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(s.createPostTitle),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CreatePostScreen()));
              }
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today),
              title: Text(s.createEvent),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateEventScreen()));
              }
            ),
            ListTile(
              leading: const Icon(Icons.storefront),
              title: Text(s.sellItem),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const CreateListingScreen()));
              }
            ),
          ],
        ),
      ),
    );
  }
}