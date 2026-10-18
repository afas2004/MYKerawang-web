import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mykerawang/screens/create_event_screen.dart';
import 'package:mykerawang/screens/create_listing_screen.dart';
import 'package:mykerawang/widgets/linear_refresher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
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

        // 3. Posts — from the view, which blanks user_id/profiles on
        //    anonymous rows. Joins are baked into the view.
        _supabase.from('posts_public')
            .select('*')
            .order('is_pinned') // active pins first (20261019004500)
            .order('created_at', ascending: false)
            .limit(50), // Fetch enough posts
      ]);
      final events = results[0];
      final listings = results[1];
      final posts = results[2];

      // 4. PREPARE FEEDS (DESIGN_SPEC §4)
      final purePosts = posts.map((p) => {...p, 'type': 'post'}).toList();

      // Injectables: alternate event/listing, in their natural order.
      // Deterministic — same data always produces the same feed.
      final List<dynamic> injectables = [];
      for (int i = 0; i < events.length || i < listings.length; i++) {
        if (i < events.length) injectables.add({...events[i], 'type': 'event'});
        if (i < listings.length) {
          injectables.add({...listings[i], 'type': 'listing'});
        }
      }

      // Mobile feed: exactly one embed after every 6th post.
      final List<dynamic> mixedFeed = [];
      int injectIndex = 0;
      for (int i = 0; i < purePosts.length; i++) {
        mixedFeed.add(purePosts[i]);
        if ((i + 1) % 6 == 0 && injectIndex < injectables.length) {
          mixedFeed.add(injectables[injectIndex++]);
        }
      }

      if (mounted) {
        setState(() {
          _featuredEvents = events.take(8).toList(); // Keep top 8 for carousel
          _freshMarketItems = listings.take(8).toList();
          _socialFeed = mixedFeed;
          _purePosts = purePosts;
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
                  icon: const Icon(Icons.notifications_outlined),
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
          ],
        ),
      )
    );
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