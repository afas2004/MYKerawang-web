import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import '../widgets/tap_card.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  
  String _query = '';
  List<Map<String, dynamic>> _results = [];
  bool _isLoading = false;
  String _activeFilter = 'All'; // Options: All, People, Events, Market, Posts
  
  // Pagination State
  int _searchLimit = 10;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // --- SEARCH LOGIC ---
  void _onSearchChanged(String query) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    
    // Wait 500ms before hitting the database (Optimization)
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (query.isNotEmpty) {
        setState(() {
          _query = query;
          _searchLimit = 10; // Reset limit on new search
        });
        _performSearch();
      } else {
        setState(() {
          _query = '';
          _results = [];
        });
      }
    });
  }

  Future<void> _loadMore() async {
    setState(() {
      _searchLimit += 10;
    });
    await _performSearch();
  }

  Future<void> _performSearch() async {
    if (_query.isEmpty) return;
    final s = context.l10nRead;
    setState(() => _isLoading = true);
    
    List<Map<String, dynamic>> tempResults = [];
    final q = "%$_query%";
    // Split limit across categories if "All" is selected to ensure variety
    final int limitPerCategory = _activeFilter == 'All' ? (_searchLimit ~/ 4) + 2 : _searchLimit;

    // Track IDs for Contextual Post Search
    List<String> foundEventIds = [];
    List<String> foundListingIds = [];

    try {
      // 1. Search PROFILES
      if (_activeFilter == 'All' || _activeFilter == 'People') {
        final people = await _supabase.from('profiles')
            .select('id, full_name, display_name, avatar_url, role')
            .or('full_name.ilike.$q, display_name.ilike.$q')
            .limit(limitPerCategory);
            
        for (var p in people) {
          tempResults.add({...p, 'type': 'person'});
        }
      }

      // 2. Search EVENTS
      if (_activeFilter == 'All' || _activeFilter == 'Events' || _activeFilter == 'Posts') {
        final nowStr = DateTime.now().toUtc().toIso8601String();
        final events = await _supabase.from('events')
            .select('id, title, start_datetime, image_url')
            .ilike('title', q)
            .gte('end_datetime', nowStr)
            .limit(limitPerCategory);
            
        for (var e in events) {
          if (_activeFilter != 'Posts') tempResults.add({...e, 'type': 'event'});
          foundEventIds.add(e['id']); 
        }
      }

      // 3. Search MARKETPLACE
      if (_activeFilter == 'All' || _activeFilter == 'Market' || _activeFilter == 'Posts') {
        final items = await _supabase.from('listings')
            .select('id, title, price, image_url, is_sold')
            .ilike('title', q)
            .eq('is_sold', false)
            .limit(limitPerCategory);
            
        for (var i in items) {
          if (_activeFilter != 'Posts') tempResults.add({...i, 'type': 'market'});
          foundListingIds.add(i['id']); 
        }
      }

      // 4. Search POSTS (Direct + Contextual)
      if (_activeFilter == 'All' || _activeFilter == 'Posts') {
        // Build robust filter: matches body OR matches related event/item
        String postFilter = 'title.ilike.$q, body.ilike.$q';
        
        if (foundEventIds.isNotEmpty) {
          postFilter += ', shared_event_id.in.(${foundEventIds.join(',')})';
        }
        if (foundListingIds.isNotEmpty) {
          postFilter += ', shared_listing_id.in.(${foundListingIds.join(',')})';
        }

        final posts = await _supabase.from('posts_public')
            // The view already embeds profiles/events/listings as JSON,
            // and blanks the author on anonymous rows.
            .select('*')
            .or(postFilter)
            .order('created_at', ascending: false)
            .limit(limitPerCategory);

        for (var p in posts) {
          // Smart Title Generation
          String displayTitle = p['title'] ?? s.kindPost;
          if ((p['title'] == null || p['title'].toString().trim().isEmpty)) {
            if (p['events'] != null) {
              displayTitle = s.replyTo.fill([p['events']['title']]);
            } else if (p['listings'] != null) {
              displayTitle = s.replyTo.fill([p['listings']['title']]);
            }
          }

          tempResults.add({
            ...p, 
            'type': 'post',
            'title': displayTitle,
          });
        }
      }

      // Shuffle for discovery feel if "All"
      if (_activeFilter == 'All') tempResults.shuffle();

      if (mounted) {
        setState(() {
          _results = tempResults;
          _isLoading = false; 
        });
      }
    } catch (e) {
      debugPrint("Search Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    // Filter keys stay stable (they drive the queries); labels are localized
    final filters = {
      'All': s.all,
      'Posts': s.posts,
      'People': s.people,
      'Events': s.navEvents,
      'Market': s.navMarket,
    };
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.searchHint,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            suffixIcon: _query.isNotEmpty 
              ? IconButton(
                  icon: const Icon(Icons.clear), 
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  }
                ) 
              : null,
          ),
          onChanged: _onSearchChanged,
        ),
      ),
      body: Column(
        children: [
          // --- FILTER CHIPS ---
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: filters.keys.map((filter) {
                final isSelected = _activeFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filters[filter]!),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() {
                        _activeFilter = filter;
                        // Reset pagination on filter change
                        _searchLimit = 10;
                        if (_query.isNotEmpty) _performSearch();
                      });
                    },
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
                    selectedColor: Theme.of(context).colorScheme.primaryContainer,
                    checkmarkColor: Theme.of(context).colorScheme.onPrimaryContainer,
                    labelStyle: TextStyle(
                      color: isSelected 
                        ? Theme.of(context).colorScheme.onPrimaryContainer 
                        : Theme.of(context).colorScheme.onSurface,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),

          // --- RESULTS LIST ---
          Expanded(
            child: _isLoading && _results.isEmpty 
              ? const Center(child: CircularProgressIndicator())
              : _results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search, size: 64, color: Theme.of(context).dividerColor),
                          const SizedBox(height: 16),
                          Text(
                            _query.isEmpty ? s.startTyping : s.noResults,
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _results.length + 1, // +1 for Show More button
                      separatorBuilder: (_,__) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        // --- SHOW MORE BUTTON (At the end) ---
                        if (index == _results.length) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: _isLoading 
                              ? const Center(child: CircularProgressIndicator())
                              : TextButton(
                                  onPressed: _loadMore,
                                  child: Text(s.showMore),
                                ),
                          );
                        }

                        final item = _results[index];
                        final type = item['type'];

                        if (type == 'person') return _buildPersonCard(item);
                        return _buildContentCard(item, type);
                      },
                    ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET: Person Card ---
  Widget _buildPersonCard(Map<String, dynamic> item) {
    final s = context.l10n;
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: item['avatar_url'] != null 
            ? CachedNetworkImageProvider(item['avatar_url']) 
            : null,
        child: item['avatar_url'] == null ? const Icon(Icons.person) : null,
      ),
      title: Text(displayNameFor(s, item), style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(roleLabel(s, item['role'])),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.goUser(item['id']),
    );
  }

  // --- WIDGET: Content Card (Event, Market, Post) ---
  Widget _buildContentCard(Map<String, dynamic> item, String type) {
    final isEvent = type == 'event';
    final isPost = type == 'post';
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;

    final title = item['title'] ?? s.untitled;
    final image = item['image_url'];
    
    String subtitle;
    String badgeLabel;
    Color badgeColor;
    IconData placeholderIcon;

    if (isEvent) {
      final start = parseLocal(item['start_datetime']);
      subtitle = start != null ? formatEventDate(start) : s.dateTba;
      badgeLabel = s.kindEvent;
      badgeColor = scheme.primary;
      placeholderIcon = Icons.event;
    } else if (isPost) {
      // For posts, show who posted it
      final author = item['profiles']?['display_name'] ?? s.anonymous;
      subtitle = s.postedBy.fill([author]);
      badgeLabel = s.kindPost;
      badgeColor = scheme.secondary;
      placeholderIcon = Icons.article;
    } else {
      // Market — gold label, same as the feed embed's "◆ MARKET".
      subtitle = formatPrice(item['price']);
      badgeLabel = s.navMarket;
      badgeColor = scheme.tertiary;
      placeholderIcon = Icons.store;
    }

    return TapCard(
      color: theme.cardColor,
      border: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
      onTap: () {
        if (isEvent) {
          context.goEvent(item);
        } else if (isPost) {
           _navigateToPost(item['id']);
        } else {
          context.goItem(item);
        }
      },
      child: SizedBox(
        height: 100,
        child: Row(
          children: [
            // Image Section
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
              child: SizedBox(
                width: 100,
                height: 100,
                child: image != null
                    ? CachedNetworkImage(
                        imageUrl: image, 
                        memCacheWidth: 300,
                        fit: BoxFit.cover,
                        placeholder: (_,__) => Container(color: scheme.surfaceContainerHighest),
                        errorWidget: (_,__,___) => Icon(Icons.broken_image, color: scheme.onSurfaceVariant),
                      )
                    : Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(placeholderIcon, color: scheme.onSurfaceVariant),
                      ),
              ),
            ),
            // Text Section
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        badgeLabel.toUpperCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _navigateToPost(String postId) async {
    try {
      final post = await _supabase.from('posts_public').select('*').eq('id', postId).single();
      if (mounted) {
         context.goPost(post);
      }
    } catch (e) {
      debugPrint("Error opening post: $e");
    }
  }
}