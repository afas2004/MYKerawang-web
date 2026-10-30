import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../utils/tags.dart';
import '../utils/filter_rules.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../l10n/shell_strings.dart';
import '../language_cubit.dart';
import '../utils/app_nav.dart';
import '../utils/event_live.dart';
import '../utils/formatters.dart';
import '../utils/roles.dart';
import '../widgets/after_fonts_load.dart';
import '../widgets/brand/brand.dart';
import '../widgets/status_badge.dart';

/// Extra result source for "All" searches (e.g. clubs). Returns rows that
/// [SearchScreen] renders like people: `title`, optional `subtitle`,
/// `avatar_url`, and the `route` to push on tap.
typedef SearchSource = Future<List<Map<String, dynamic>>> Function(
    String term, int limit);

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  /// Hook for the clubs feature: set at startup to include clubs in
  /// results (shown as a "Clubs" section). Null = no clubs section.
  static SearchSource? clubSource;

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

  /// The query as a safe PostgREST filter value (see [filterSafe]); a leading
  /// @ (handle search) is dropped so "@ali" and "ali" match the same people.
  static String _filterSafe(String raw) =>
      filterSafe(raw).replaceFirst(RegExp(r'^@+'), '');

  /// "#futsal" → "futsal"; null when the query isn't a hashtag.
  static String? hashtagOf(String query) {
    final q = query.trim();
    if (!q.startsWith('#') || q.contains(' ')) return null;
    final tag = normalizeTag(q.substring(1));
    return tag.isEmpty ? null : tag;
  }

  Future<void> _performSearch() async {
    if (_query.isEmpty) return;
    if (hashtagOf(_query) != null) {
      // Tags have their own feed; the body shows a row that opens it.
      setState(() {
        _results = [];
        _isLoading = false;
        _error = false;
      });
      return;
    }
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
        // profiles_public for everyone: guests can't read profiles, and the
        // view exposes only public columns (no full_name to match on).
        final people = await _supabase.from('profiles_public')
            .select('id, username, display_name, avatar_url, role, is_verified')
            .or('display_name.ilike.$q,username.ilike.$q')
            .limit(limitPerCategory);
            
        for (var p in people) {
          tempResults.add({...p, 'type': 'person'});
        }
      }

      // 1b. Clubs, when the clubs feature registered a source.
      final clubs = SearchScreen.clubSource;
      if (clubs != null && _activeFilter == 'All') {
        try {
          for (final c in await clubs(term, limitPerCategory)) {
            tempResults.add({...c, 'type': 'club'});
          }
        } catch (e) {
          debugPrint("Club search error: $e");
        }
      }

      // 2. Search EVENTS
      if (_activeFilter == 'All' || _activeFilter == 'Events' || _activeFilter == 'Posts') {
        // Ended and cancelled events stay findable (greyed, with a badge);
        // upcoming ones sort first.
        final events = await _supabase.from('events')
            .select('id, title, start_datetime, end_datetime, image_url, cancelled_at')
            .ilike('title', q)
            .order('start_datetime', ascending: false)
            .limit(limitPerCategory);
        for (var e in events..sort(compareForBrowse)) {
          if (_activeFilter != 'Posts') tempResults.add({...e, 'type': 'event'});
          foundEventIds.add(e['id']); 
        }
      }

      // 3. Search MARKETPLACE
      if (_activeFilter == 'All' || _activeFilter == 'Market' || _activeFilter == 'Posts') {
        final items = await _supabase.from('listings')
            .select('id, title, price, image_url, is_sold, status')
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

    // Search field lives in the app bar; filter chips sit right under it.
    return Scaffold(
      appBar: AppBar(
        // Desktop: the field sits in the page-header row, level with the
        // other tabs' titles, on the page's own ground.
        toolbarHeight: Responsive.isDesktop(context) ? KBand.desktopHeight : 64,
        backgroundColor: Responsive.isDesktop(context) ? Colors.transparent : null,
        titleSpacing: KSpace.l,
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: s.searchHint,
            prefixIcon: const Icon(AppIcons.search, size: 20),
            filled: true,
            fillColor: scheme.surfaceContainerHigh,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: KSpace.m),
            border: const OutlineInputBorder(
              borderRadius: KRadius.pill,
              borderSide: BorderSide.none,
            ),
            enabledBorder: const OutlineInputBorder(
              borderRadius: KRadius.pill,
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: KRadius.pill,
              borderSide: BorderSide(color: scheme.primary, width: 2),
            ),
            suffixIcon: _searchCtrl.text.isNotEmpty
                ? IconButton(
                    tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                    icon: const Icon(AppIcons.close, size: 20),
                    onPressed: () {
                      _searchCtrl.clear();
                      _onSearchChanged('');
                      setState(() {});
                    },
                  )
                : null,
          ),
          onChanged: (v) {
            setState(() {}); // clear button
            _onSearchChanged(v);
          },
          onSubmitted: (v) {
            final tag = hashtagOf(v);
            if (tag != null) {
              _rememberQuery(v.trim());
              context.goTag(tag);
              return;
            }
            if (v.trim().isNotEmpty) _useRecent(v.trim());
          },
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          // Rebuilt once the web fonts load (labels otherwise keep the
          // fallback width and lose their last letter).
          child: AfterFontsLoad(child: SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.xs, KSpace.l, KSpace.s),
              children: [
                for (final f in filters.entries)
                  Padding(
                    padding: const EdgeInsets.only(right: KSpace.s),
                    child: ChoiceChip(
                      label: Text(f.value),
                      selected: _activeFilter == f.key,
                      showCheckmark: false,
                      onSelected: (_) => _setFilter(f.key),
                    ),
                  ),
              ],
            ),
          )),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
          child: _body(context),
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
          icon: AppIcons.search,
          title: s.shell.searchPromptTitle,
          body: s.shell.searchPromptBody,
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: KSpace.s),
        children: [
          _SectionTitle(
            title: s.shell.recentSearches,
            action: s.shell.clearRecent,
            onAction: () => _saveRecent([]),
          ),
          for (final r in _recent)
            ListTile(
              leading: const Icon(AppIcons.history),
              title: Text(r),
              onTap: () => _useRecent(r),
              trailing: IconButton(
                tooltip: s.shell.removeRecent,
                icon: const Icon(AppIcons.close),
                onPressed: () =>
                    _saveRecent(_recent.where((x) => x != r).toList()),
              ),
            ),
        ],
      );
    }

    final tag = hashtagOf(_query);
    if (tag != null) {
      return ListView(
        padding: const EdgeInsets.symmetric(vertical: KSpace.s),
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: scheme.primaryContainer,
              child: Icon(AppIcons.hashtag, color: scheme.onPrimaryContainer),
            ),
            title: Text(displayTag(tag)),
            subtitle: Text(s.shell.seePostsTagged.fill([displayTag(tag)])),
            trailing: const Icon(AppIcons.chevronRight),
            onTap: () {
              _rememberQuery(_query.trim());
              context.goTag(tag);
            },
          ),
        ],
      );
    }

    if (_isLoading && _results.isEmpty) return const _SearchSkeleton();

    if (_error && _results.isEmpty) {
      return _SearchMessage(
        icon: AppIcons.error,
        illo: AppIllo.offline,
        title: s.connectionError,
        body: '',
        actionLabel: s.tryAgain,
        onAction: _performSearch,
      );
    }

    if (_results.isEmpty) {
      return _SearchMessage(
        icon: AppIcons.search,
        illo: AppIllo.noResults,
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
        ('club', s.shell.clubs, null),
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
          if (label.isNotEmpty && filter == null)
            SectionHeader(title: label, padding: const EdgeInsets.fromLTRB(0, KSpace.m, 0, KSpace.s))
          else if (label.isNotEmpty)
            _SectionTitle(
              title: label,
              action: s.seeAll,
              onAction: () => _setFilter(filter!),
              padding: const EdgeInsets.fromLTRB(0, 12, 0, 8),
            ),
          for (final item in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: switch (item['type']) {
                'person' => _buildPersonCard(item),
                'club' => _buildClubCard(item),
                _ => _buildContentCard(item, item['type']),
              },
            ),
        ],
        // --- SHOW MORE (end of list) ---
        Padding(
          padding: const EdgeInsets.symmetric(vertical: KSpace.s),
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
        child: item['avatar_url'] == null ? const Icon(AppIcons.person) : null,
      ),
      title: Text(displayNameFor(s, item), style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text([
        if (item['username'] != null) '@${item['username']}',
        roleLabel(s, item['role']),
      ].join(' · ')),
      trailing: const Icon(AppIcons.chevronRight),
      onTap: () => context.goUser(item['id']),
    );
  }

  /// Row from [SearchScreen.clubSource]: title, subtitle, avatar, route.
  Widget _buildClubCard(Map<String, dynamic> item) {
    final avatar = item['avatar_url'] as String?;
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
        child: avatar == null ? const Icon(AppIcons.people) : null,
      ),
      title: Text('${item['title'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: item['subtitle'] == null ? null : Text('${item['subtitle']}'),
      trailing: const Icon(AppIcons.chevronRight),
      onTap: item['route'] == null ? null : () => context.push('${item['route']}'),
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
    final closed = isEvent && isEventClosed(item);
    final status =
        isPost ? null : statusLabelFor(item, s, isEvent: isEvent);
    
    String subtitle;
    String badgeLabel;
    Color badgeColor;
    IconData placeholderIcon;

    if (isEvent) {
      final start = parseLocal(item['start_datetime']);
      subtitle = start != null ? formatEventDate(start) : s.dateTba;
      badgeLabel = s.kindEvent;
      badgeColor = scheme.primary;
      placeholderIcon = AppIcons.events;
    } else if (isPost) {
      // For posts, show who posted it
      final author = item['profiles']?['display_name'] ?? s.anonymous;
      subtitle = s.postedBy.fill([author]);
      badgeLabel = s.kindPost;
      badgeColor = scheme.secondary;
      placeholderIcon = AppIcons.comment;
    } else {
      // Market — gold label, same as the feed embed's "◆ MARKET".
      subtitle = formatPrice(item['price']);
      badgeLabel = s.navMarket;
      badgeColor = scheme.tertiary;
      placeholderIcon = AppIcons.market;
    }

    final card = KCard(
      padding: EdgeInsets.zero,
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
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(KRadius.cardValue)),
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
                        errorWidget: (_,__,___) => Icon(AppIcons.photo, color: scheme.onSurfaceVariant),
                      )
                    : Container(
                        color: scheme.surfaceContainerHighest,
                        child: Icon(placeholderIcon, color: scheme.onSurfaceVariant),
                      ),
                if (status != null)
                  Center(child: StatusBadge(status)),
                  ],
                ),
              ),
            ),
            // Text Section
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: KSpace.m, vertical: KSpace.s),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: KSpace.s, vertical: 2),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.12),
                        borderRadius: KRadius.pill,
                      ),
                      child: Text(
                        badgeLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: badgeColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: KSpace.xs),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return _greyIfEnded(card, closed);
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
  final EdgeInsetsGeometry padding;

  const _SectionTitle({
    required this.title,
    required this.action,
    required this.onAction,
    this.padding = const EdgeInsets.fromLTRB(KSpace.l, KSpace.xs, KSpace.s, KSpace.xs),
  });

  @override
  Widget build(BuildContext context) => SectionHeader(
        title: title,
        seeAllLabel: action,
        onSeeAll: onAction,
        padding: padding,
      );
}

/// Prompt / no-results / error message.
class _SearchMessage extends StatelessWidget {
  final IconData icon;
  final AppIllo? illo;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SearchMessage({
    required this.icon,
    this.illo,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) => BrandEmptyState(
        icon: icon,
        illo: illo,
        title: title,
        message: body.isEmpty ? null : body,
        actionLabel: actionLabel,
        onAction: onAction,
      );
}

class _SearchSkeleton extends StatelessWidget {
  const _SearchSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(KSpace.l),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.only(bottom: KSpace.m),
        child: KSkeleton(height: 100, borderRadius: KRadius.card),
      ),
    );
  }
}
