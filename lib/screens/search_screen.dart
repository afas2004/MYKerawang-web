import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../l10n/shell_strings.dart';
import '../language_cubit.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import '../widgets/status_badge.dart';
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
  bool _error = false;

  /// Bumped per search so a slow, stale response can't overwrite a newer one.
  int _requestId = 0;
  String _activeFilter = 'All'; // Options: All, People, Events, Market, Posts
  
  // Pagination State
  int _searchLimit = 10;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

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

  /// The query as a safe PostgREST filter value. `,` `(` `)` split or
  /// group `.or()` terms, `"` `\` quote, `:` casts — none mean anything
  /// to a user, so they become spaces. A leading @ (handle search) is
  /// dropped so "@ali" and "ali" match the same people.
  static String _filterSafe(String raw) => raw
      .replaceAll(RegExp(r'[,()"\\:]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceFirst(RegExp(r'^@+'), '');

  bool _hasEnded(Map<String, dynamic> event) {
    final end = parseLocal(event['end_datetime']) ??
        parseLocal(event['start_datetime']);
    return end != null && end.isBefore(DateTime.now());
  }

  Future<void> _performSearch() async {
    if (_query.isEmpty) return;
    final term = _filterSafe(_query);
    if (term.isEmpty) {
      setState(() => _results = []);
      return;
    }
    final s = context.l10nRead;
    final request = ++_requestId;
    setState(() {
      _isLoading = true;
      _error = false;
    });
    
    List<Map<String, dynamic>> tempResults = [];
    final q = "%$term%";
    // Split limit across categories if "All" is selected to ensure variety
    final int limitPerCategory = _activeFilter == 'All' ? (_searchLimit ~/ 4) + 2 : _searchLimit;

    // Track IDs for Contextual Post Search
    List<String> foundEventIds = [];
    List<String> foundListingIds = [];

    try {
      // 1. Search PROFILES
      if (_activeFilter == 'All' || _activeFilter == 'People') {
        final people = await _supabase.from('profiles')
            .select('id, full_name, display_name, username, avatar_url, role')
            .or('full_name.ilike.$q,display_name.ilike.$q,username.ilike.$q')
            .limit(limitPerCategory);
            
        for (var p in people) {
          tempResults.add({...p, 'type': 'person'});
        }
      }

      // 2. Search EVENTS
      if (_activeFilter == 'All' || _activeFilter == 'Events' || _activeFilter == 'Posts') {
        // Ended events stay findable (shown greyed with the Ended badge);
        // upcoming ones sort first, then most recently ended.
        final events = await _supabase.from('events')
            .select('id, title, start_datetime, end_datetime, image_url')
            .ilike('title', q)
            .order('start_datetime', ascending: false)
            .limit(limitPerCategory);
        final upcoming = events.where((e) => !_hasEnded(e)).toList().reversed;
        final ended = events.where(_hasEnded);

        for (var e in [...upcoming, ...ended]) {
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
        String postFilter = 'title.ilike.$q,body.ilike.$q';
        
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
          // Titles are optional: fall back to the shared item, then the
          // first line of the body, then the generic "Post".
          final rawTitle = '${p['title'] ?? ''}'.trim();
          final firstLine = '${p['body'] ?? ''}'.trim().split('\n').first.trim();
          final String displayTitle;
          if (rawTitle.isNotEmpty) {
            displayTitle = rawTitle;
          } else if (p['events']?['title'] != null) {
            displayTitle = s.replyTo.fill([p['events']['title']]);
          } else if (p['listings']?['title'] != null) {
            displayTitle = s.replyTo.fill([p['listings']['title']]);
          } else if (firstLine.isNotEmpty) {
            displayTitle = firstLine;
          } else {
            displayTitle = s.kindPost;
          }

          tempResults.add({
            ...p, 
            'type': 'post',
            'title': displayTitle,
          });
        }
      }

      // "All" is grouped into sections by the UI, so no shuffle.
      if (!mounted || request != _requestId) return;
      setState(() {
        _results = tempResults;
        _isLoading = false;
      });
      if (tempResults.isNotEmpty) _rememberQuery(_query);
    } catch (e) {
      debugPrint("Search Error: $e");
      if (mounted && request == _requestId) {
        setState(() {
          _isLoading = false;
          _error = true;
        });
      }
    }
  }

  // --- RECENT SEARCHES (this device only) ---
  static const _recentKey = 'recentSearches';
  static const _recentMax = 8;
  List<String> _recent = [];

  Future<void> _loadRecent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_recentKey) ?? const [];
      if (mounted) setState(() => _recent = list);
    } catch (_) {}
  }

  Future<void> _saveRecent(List<String> list) async {
    setState(() => _recent = list);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_recentKey, list);
    } catch (_) {}
  }

  void _rememberQuery(String q) {
    final t = q.trim();
    if (t.length < 2) return;
    _saveRecent([
      t,
      ..._recent.where((r) => r.toLowerCase() != t.toLowerCase()),
    ].take(_recentMax).toList());
  }

  void _useRecent(String q) {
    _searchCtrl.text = q;
    _searchCtrl.selection = TextSelection.collapsed(offset: q.length);
    _debounce?.cancel();
    setState(() {
      _query = q;
      _searchLimit = 10;
    });
    _performSearch();
  }

  void _setFilter(String filter) {
    setState(() {
      _activeFilter = filter;
      _searchLimit = 10; // Reset pagination on filter change
    });
    if (_query.isNotEmpty) _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Filter keys stay stable (they drive the queries); labels are localized
    final filters = {
      'All': s.all,
      'Posts': s.posts,
      'People': s.people,
      'Events': s.navEvents,
      'Market': s.navMarket,
    };

    return Scaffold(
      appBar: AppBar(title: Text(s.navSearch)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // --- SEARCH BAR ---
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: s.searchHint,
                    prefixIcon: const Icon(Icons.search),
                    filled: true,
                    fillColor: scheme.surfaceContainerHigh,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(28),
                      borderSide: BorderSide(color: scheme.primary, width: 2),
                    ),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                  ),
                  onChanged: (v) {
                    setState(() {}); // clear button
                    _onSearchChanged(v);
                  },
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) _useRecent(v.trim());
                  },
                ),
              ),

              // --- SEGMENTED FILTERS ---
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    for (final f in filters.entries)
                      ButtonSegment(value: f.key, label: Text(f.value)),
                  ],
                  selected: {_activeFilter},
                  onSelectionChanged: (sel) => _setFilter(sel.first),
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),

              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (_query.isEmpty) {
      if (_recent.isEmpty) {
        return _SearchMessage(
          icon: Icons.travel_explore,
          title: s.shell.searchPromptTitle,
          body: s.shell.searchPromptBody,
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionTitle(
            title: s.shell.recentSearches,
            action: s.shell.clearRecent,
            onAction: () => _saveRecent([]),
          ),
          for (final r in _recent)
            ListTile(
              leading: const Icon(Icons.history),
              title: Text(r),
              onTap: () => _useRecent(r),
              trailing: IconButton(
                tooltip: s.shell.removeRecent,
                icon: const Icon(Icons.close),
                onPressed: () =>
                    _saveRecent(_recent.where((x) => x != r).toList()),
              ),
            ),
        ],
      );
    }

    if (_isLoading && _results.isEmpty) return const _SearchSkeleton();

    if (_error && _results.isEmpty) {
      return _SearchMessage(
        icon: Icons.wifi_off,
        title: s.connectionError,
        body: '',
        action: FilledButton.icon(
          onPressed: _performSearch,
          icon: const Icon(Icons.refresh),
          label: Text(s.tryAgain),
        ),
      );
    }

    if (_results.isEmpty) {
      return _SearchMessage(
        icon: Icons.search_off,
        title: s.shell.noResultsFor.fill([_query]),
        body: s.shell.tryDifferent,
      );
    }

    // "All": one section per type, each with See all → that filter.
    // A single filter: one flat list.
    final sections = <(String, String?, List<Map<String, dynamic>>)>[];
    if (_activeFilter == 'All') {
      for (final (type, label, filter) in [
        ('person', s.people, 'People'),
        ('post', s.posts, 'Posts'),
        ('event', s.navEvents, 'Events'),
        ('market', s.navMarket, 'Market'),
      ]) {
        final rows = _results.where((r) => r['type'] == type).toList();
        if (rows.isNotEmpty) sections.add((label, filter, rows));
      }
    } else {
      sections.add(('', null, _results));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        for (final (label, filter, rows) in sections) ...[
          if (label.isNotEmpty)
            _SectionTitle(
              title: label,
              action: s.seeAll,
              onAction: () => _setFilter(filter!),
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            ),
          for (final item in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: item['type'] == 'person'
                  ? _buildPersonCard(item)
                  : _buildContentCard(item, item['type']),
            ),
        ],
        // --- SHOW MORE (end of list) ---
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size(160, 48)),
                    onPressed: _loadMore,
                    child: Text(s.showMore),
                  ),
                ),
        ),
        if (_error)
          Text(s.connectionError,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
      ],
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
      subtitle: Text([
        if (item['username'] != null) '@${item['username']}',
        roleLabel(s, item['role']),
      ].join(' · ')),
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
    final ended = isEvent && _hasEnded(item);
    
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

    final card = TapCard(
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                image != null
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
                if (ended)
                  Center(child: StatusBadge(s.ended)),
                  ],
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
    return _greyIfEnded(card, ended);
  }

  /// Past events stay tappable but read as inactive.
  Widget _greyIfEnded(Widget card, bool ended) =>
      ended ? Opacity(opacity: 0.6, child: card) : card;

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

class _SectionTitle extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onAction;
  final EdgeInsets padding;

  const _SectionTitle({
    required this.title,
    required this.action,
    required this.onAction,
    this.padding = const EdgeInsets.fromLTRB(16, 4, 8, 4),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(title, style: Theme.of(context).textTheme.titleMedium),
            ),
          ),
          TextButton(onPressed: onAction, child: Text(action)),
        ],
      ),
    );
  }
}

/// Prompt / no-results / error message. Swap for BrandEmptyState.
class _SearchMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final Widget? action;

  const _SearchMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.surfaceContainerHighest;
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, __) => Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
