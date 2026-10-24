import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../language_cubit.dart';
import '../../services/club_service.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/error_state.dart';
import 'club_strings.dart';
import 'club_widgets.dart';

/// /clubs — search and browse active clubs; entry to registration and to
/// the clubs you run.
class ClubDirectoryScreen extends StatefulWidget {
  const ClubDirectoryScreen({super.key});

  @override
  State<ClubDirectoryScreen> createState() => _ClubDirectoryScreenState();
}

class _ClubDirectoryScreenState extends State<ClubDirectoryScreen> {
  String _search = '';
  String? _category;
  Timer? _debounce;
  late Future<_DirData> _future = _load();
  late final Future<List<Map<String, dynamic>>> _mine =
      ClubService.myClubs().catchError((_) => <Map<String, dynamic>>[]);

  Future<_DirData> _load() async {
    final clubs = await ClubService.directory(search: _search, category: _category);
    final counts = await ClubService.followerCounts([for (final c in clubs) c.id]);
    return _DirData(clubs, counts);
  }

  void _reload() => setState(() {
        _future = _load();
      });

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    return Scaffold(
      appBar: AppBar(title: Text(c.directoryTitle)),
      body: FutureBuilder<_DirData>(
        future: _future,
        builder: (context, snap) {
          return FutureBuilder<List<Map<String, dynamic>>>(
            future: _mine,
            builder: (context, mine) => ClubDirectoryView(
              clubs: snap.data?.clubs,
              followerCounts: snap.data?.counts ?? const {},
              myClubs: mine.data ?? const [],
              loading: snap.connectionState != ConnectionState.done,
              error: snap.hasError ? snap.error : null,
              search: _search,
              category: _category,
              signedIn: ClubService.currentUserId != null,
              onSearch: (v) {
                _search = v;
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _reload);
              },
              onCategory: (v) {
                _category = v;
                _reload();
              },
              onRetry: _reload,
              onOpen: (handle) => context.push('/c/$handle'),
              onRegister: () => context.push('/clubs/register'),
            ),
          );
        },
      ),
    );
  }
}

class _DirData {
  final List<Club> clubs;
  final Map<String, int> counts;
  const _DirData(this.clubs, this.counts);
}

/// Presentational directory: search, category chips, "My clubs" strip,
/// responsive grid of club cards.
class ClubDirectoryView extends StatelessWidget {
  final List<Club>? clubs; // null while loading
  final Map<String, int> followerCounts;
  final List<Map<String, dynamic>> myClubs;
  final bool loading;
  final Object? error;
  final String search;
  final String? category;
  final bool signedIn;
  final ValueChanged<String> onSearch;
  final ValueChanged<String?> onCategory;
  final VoidCallback onRetry;
  final ValueChanged<String> onOpen;
  final VoidCallback onRegister;

  const ClubDirectoryView({
    super.key,
    required this.clubs,
    required this.followerCounts,
    required this.myClubs,
    required this.loading,
    required this.error,
    required this.search,
    required this.category,
    required this.signedIn,
    required this.onSearch,
    required this.onCategory,
    required this.onRetry,
    required this.onOpen,
    required this.onRegister,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100),
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(c.directorySub,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    const SizedBox(height: KSpace.m),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: onSearch,
                            decoration: InputDecoration(
                              prefixIcon: const Icon(AppIcons.search),
                              hintText: c.searchClubs,
                            ),
                          ),
                        ),
                        if (signedIn) ...[
                          const SizedBox(width: KSpace.s),
                          FilledButton.icon(
                            onPressed: onRegister,
                            icon: const Icon(AppIcons.create, size: 18),
                            label: Text(c.registerClub),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: KSpace.m),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final k in [null, ...ClubStrings.categories]) ...[
                            ChoiceChip(
                              label: Text(k == null ? c.allCategories : c.categoryLabel(k)),
                              selected: category == k,
                              onSelected: (_) => onCategory(k),
                            ),
                            const SizedBox(width: KSpace.s),
                          ],
                        ],
                      ),
                    ),
                    if (myClubs.isNotEmpty) ...[
                      const SizedBox(height: KSpace.l),
                      Text(c.myClubs, style: theme.textTheme.titleSmall),
                      const SizedBox(height: KSpace.s),
                      Wrap(
                        spacing: KSpace.s,
                        runSpacing: KSpace.s,
                        children: [
                          for (final m in myClubs)
                            ActionChip(
                              avatar: ClubLogo(url: m['logo_url'] as String?, name: '${m['name']}', size: 24),
                              label: Text(m['status'] == 'active'
                                  ? '${m['name']}'
                                  : '${m['name']} · ${c.statusLabel(m['status'] as String?)}'),
                              onPressed: () => onOpen('${m['handle']}'),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: KSpace.l),
                  ],
                ),
              ),
            ),
            ..._results(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _results(BuildContext context) {
    final c = context.l10n.club;
    if (loading) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: KSpace.l),
          sliver: SliverToBoxAdapter(child: KSkeleton.lines(4)),
        ),
      ];
    }
    if (error != null) {
      return [SliverFillRemaining(hasScrollBody: false, child: ErrorState(onRetry: onRetry))];
    }
    final list = clubs ?? const [];
    if (list.isEmpty) {
      final filtered = search.trim().isNotEmpty || category != null;
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: BrandEmptyState(
            illo: filtered ? AppIllo.noResults : AppIllo.emptyFeed,
            title: filtered ? c.noMatch : c.noClubs,
            message: filtered ? null : c.noClubsBody,
            actionLabel: !filtered && signedIn ? c.registerClub : null,
            onAction: !filtered && signedIn ? onRegister : null,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(KSpace.l, 0, KSpace.l, KSpace.xl),
        sliver: SliverLayoutBuilder(builder: (context, constraints) {
          final w = constraints.crossAxisExtent;
          final cols = w >= 900 ? 3 : (w >= 560 ? 2 : 1);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: KSpace.m,
              crossAxisSpacing: KSpace.m,
              mainAxisExtent: 132,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, i) => ClubCard(
                club: list[i],
                followers: followerCounts[list[i].id] ?? 0,
                onTap: () => onOpen(list[i].handle),
              ),
              childCount: list.length,
            ),
          );
        }),
      ),
    ];
  }
}

/// Directory tile: logo, name + verified, @handle, category, followers.
class ClubCard extends StatelessWidget {
  final Club club;
  final int followers;
  final VoidCallback onTap;
  const ClubCard({super.key, required this.club, required this.followers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.l10n.club;
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return KCard(
      onTap: onTap,
      semanticLabel: club.name,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClubLogo(url: club.logoUrl, name: club.name, size: 56),
          const SizedBox(width: KSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClubNameLine(name: club.name, verified: club.isVerified, style: theme.textTheme.titleMedium),
                Text('@${club.handle}', maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                const SizedBox(height: KSpace.xs),
                if ((club.description ?? '').isNotEmpty)
                  Text(club.description!, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(
                  [
                    if ((club.category ?? '').isNotEmpty) c.categoryLabel(club.category),
                    c.followerLabel(followers),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
