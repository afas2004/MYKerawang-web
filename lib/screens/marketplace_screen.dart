import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mykerawang/widgets/linear_refresher.dart';
import 'create_listing_screen.dart';
import '../l10n/access_strings.dart';
import '../utils/app_nav.dart';
import '../utils/categories.dart';
import '../utils/formatters.dart';
import '../utils/listing_status.dart';
import '../widgets/status_badge.dart';
import '../widgets/tap_card.dart';
import 'marketplace_cubit.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../utils/responsive.dart';
import '../widgets/error_state.dart';

class MarketplaceScreen extends StatelessWidget {
  const MarketplaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Provide the Cubit
    return BlocProvider(
      create: (_) => MarketplaceCubit(),
      child: const MarketplaceView(),
    );
  }
}

class MarketplaceView extends StatefulWidget {
  const MarketplaceView({super.key});

  @override
  State<MarketplaceView> createState() => _MarketplaceViewState();
}

class _MarketplaceViewState extends State<MarketplaceView> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCreate(BuildContext context) async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const CreateListingScreen()));
    if (result == true && context.mounted) {
      context.read<MarketplaceCubit>().loadData();
    }
  }

  Future<void> _openFilters(BuildContext context, MarketFilters current) async {
    final cubit = context.read<MarketplaceCubit>();
    final next = await showAdaptiveSheet<MarketFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: current),
    );
    if (next != null) cubit.applyFilters(next);
  }

  @override
  Widget build(BuildContext context) {
    // 2. Consume the State
    return BlocBuilder<MarketplaceCubit, MarketplaceState>(
      builder: (context, state) {
        final s = context.l10n;
        final scheme = Theme.of(context).colorScheme;
        final categories = <String?>[null, ...kListingCategories];
        final active = state.filters.activeCount;

        return Scaffold(
          appBar: AppBar(
            title: Text(s.marketplaceTitle),
            actions: [
              IconButton(
                tooltip: s.filters,
                onPressed: () => _openFilters(context, state.filters),
                icon: Badge(
                  isLabelVisible: active > 0,
                  label: Text('$active'),
                  child: const Icon(Icons.tune),
                ),
              ),
              // Desktop has no FAB, so creation lives here instead (H1.1).
              if (isWide(context))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: () => _openCreate(context),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(s.sellItem),
                  ),
                ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(50),
              child: SizedBox(
                height: 50,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: categories.length,
                  itemBuilder: (context, index) {
                    final category = categories[index];
                    final isSelected = state.filters.category == category;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(category ?? s.all),
                        selected: isSelected,
                        onSelected: (_) =>
                            context.read<MarketplaceCubit>().updateCategory(category),
                        backgroundColor: Theme.of(context).cardColor,
                        selectedColor: scheme.surfaceContainerHighest,
                        checkmarkColor: scheme.primary,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          body: LinearRefresher(
            offset: 0.0,
            onRefresh: () => context.read<MarketplaceCubit>().loadData(),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => context.read<MarketplaceCubit>().updateSearch(v),
                    decoration: InputDecoration(
                      hintText: s.searchItems,
                      prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
                      filled: true,
                      fillColor: scheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                    ),
                  ),
                ),
                Expanded(child: _results(context, state)),
              ],
            ),
          ),
          // See G5 — no floating corner button on desktop.
          floatingActionButton: isWide(context) ? null : FloatingActionButton(
            heroTag: 'market_fab',
            tooltip: s.sellItem,
            onPressed: () => _openCreate(context),
            backgroundColor: scheme.primary,
            child: Icon(Icons.add, color: scheme.onPrimary),
          ),
        );
      },
    );
  }

  Widget _results(BuildContext context, MarketplaceState state) {
    final s = context.l10n;
    final cubit = context.read<MarketplaceCubit>();

    if (state.isLoading && state.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.errorMessage != null && state.items.isEmpty) {
      return ErrorState(onRetry: cubit.loadData);
    }
    if (state.items.isEmpty) {
      final filtered = !state.filters.isDefault || state.searchQuery.isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(filtered ? s.noMatchingItems : s.noItemsFound, textAlign: TextAlign.center),
              if (!state.filters.isDefault) ...[
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => cubit.applyFilters(const MarketFilters()),
                  child: Text(s.resetFilters),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return LayoutBuilder(builder: (context, constraints) {
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                // 2 columns on phones, 3-4 on wider screens
                crossAxisCount: Responsive.gridColumns(constraints.maxWidth),
                childAspectRatio: 0.7,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
              ),
              itemCount: state.items.length,
              itemBuilder: (context, index) => _ListingTile(item: state.items[index]),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
              child: Center(child: _footer(context, state)),
            ),
          ),
        ],
      );
    });
  }

  Widget _footer(BuildContext context, MarketplaceState state) {
    final s = context.l10n;
    final cubit = context.read<MarketplaceCubit>();
    if (state.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: CircularProgressIndicator(),
      );
    }
    if (state.loadMoreFailed) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(s.somethingWentWrong, textAlign: TextAlign.center),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: cubit.loadMore,
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(s.retry),
          ),
        ],
      );
    }
    if (state.hasMore) {
      return OutlinedButton(onPressed: cubit.loadMore, child: Text(s.loadMore));
    }
    return const SizedBox.shrink();
  }
}

class _ListingTile extends StatelessWidget {
  final Map<String, dynamic> item;
  const _ListingTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ListingStatus.of(item);
    final isSold = status == ListingStatus.sold;
    final badge = status.badge(s);

    // TapCard (not GestureDetector) so desktop gets a pointer cursor +
    // hover ripple (G6)
    return TapCard(
      onTap: () => context.goItem(item),
      child: Opacity(
        opacity: isSold ? 0.6 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: item['image_url'] ?? '',
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        memCacheWidth: 500,
                        placeholder: (context, url) => Container(
                          color: scheme.surfaceContainerHighest,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: scheme.surfaceContainerHighest,
                          child: Center(
                            child: Icon(Icons.store_mall_directory_outlined,
                                color: scheme.onSurfaceVariant, size: 30),
                          ),
                        ),
                      ),
                      // RESERVED / SOLD badge (4.7)
                      if (badge != null)
                        Positioned(top: 8, left: 8, child: StatusBadge(badge)),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item['title'] ?? '',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(formatPrice(item['price'] as num?),
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: isSold ? scheme.onSurfaceVariant : scheme.primary,
                            decoration: isSold ? TextDecoration.lineThrough : null,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Category, price range, status and sort. Returns the new filters, or
/// null if dismissed.
class _FilterSheet extends StatefulWidget {
  final MarketFilters initial;
  const _FilterSheet({required this.initial});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _category = widget.initial.category;
  late Set<ListingStatus> _statuses = {...widget.initial.statuses};
  late MarketSort _sort = widget.initial.sort;
  late final _minCtrl = TextEditingController(text: _fmt(widget.initial.minPrice));
  late final _maxCtrl = TextEditingController(text: _fmt(widget.initial.maxPrice));

  static String _fmt(double? v) =>
      v == null ? '' : (v == v.roundToDouble() ? v.toInt().toString() : v.toString());

  @override
  void dispose() {
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  MarketFilters _result() {
    var min = double.tryParse(_minCtrl.text.trim());
    var max = double.tryParse(_maxCtrl.text.trim());
    if (min != null && max != null && min > max) (min, max) = (max, min);
    return MarketFilters(
      category: _category,
      minPrice: min,
      maxPrice: max,
      // Showing nothing is never what someone means.
      statuses: _statuses.isEmpty ? MarketFilters.defaultStatuses : _statuses,
      sort: _sort,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(text,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        );

    final priceInput = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            24, 16, 24, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.filters,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),

            heading(s.sortBy),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (sort, label) in [
                  (MarketSort.newest, s.sortNewest),
                  (MarketSort.cheapest, s.sortCheapest),
                  (MarketSort.priciest, s.sortPriciest),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _sort == sort,
                    onSelected: (_) => setState(() => _sort = sort),
                  ),
              ],
            ),

            heading(s.category),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in <String?>[null, ...kListingCategories])
                  ChoiceChip(
                    label: Text(c ?? s.all),
                    selected: _category == c,
                    onSelected: (_) => setState(() => _category = c),
                  ),
              ],
            ),

            heading(s.priceRange),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: priceInput,
                    decoration: InputDecoration(labelText: s.minPrice, prefixText: 'RM '),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('–'),
                ),
                Expanded(
                  child: TextField(
                    controller: _maxCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: priceInput,
                    decoration: InputDecoration(labelText: s.maxPrice, prefixText: 'RM '),
                  ),
                ),
              ],
            ),

            heading(s.listingStatus),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final st in ListingStatus.values)
                  FilterChip(
                    label: Text(st.label(s)),
                    selected: _statuses.contains(st),
                    onSelected: (on) => setState(() {
                      _statuses = {..._statuses};
                      on ? _statuses.add(st) : _statuses.remove(st);
                    }),
                  ),
              ],
            ),

            const SizedBox(height: 24),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, const MarketFilters()),
                  child: Text(s.resetFilters),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, _result()),
                  child: Text(s.showResults),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
