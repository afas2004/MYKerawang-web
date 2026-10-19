import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mykerawang/widgets/linear_refresher.dart';
import '../l10n/access_strings.dart';
import '../utils/app_nav.dart';
import '../widgets/shell_actions.dart';
import '../utils/categories.dart';
import '../utils/formatters.dart';
import '../utils/listing_status.dart';
import '../widgets/status_badge.dart';
import '../widgets/brand/brand.dart';
import 'marketplace_cubit.dart';
import '../language_cubit.dart';
import '../utils/adaptive.dart';
import '../widgets/error_state.dart';

/// Filters become a side panel once the market is given this much width.
const double _kSidePanelFrom = 900;
const double _kSidePanelWidth = 280;


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

class _MarketplaceViewState extends State<MarketplaceView>
    with RefreshOnContentChange {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Used by the empty state only; the one general Create entry is the
  /// shell's (centre button / rail / sidebar).
  void _openCreate(BuildContext context) => context.goCreateListing();

  // Lists refresh after something is published, edited or deleted.
  @override
  void onContentChanged() => context.read<MarketplaceCubit>().loadData();


  Future<void> _openFilterSheet(BuildContext context, MarketFilters current) async {
    final cubit = context.read<MarketplaceCubit>();
    final next = await showAdaptiveSheet<MarketFilters>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: MarketFilterForm(
          initial: current,
          onApply: (f) => Navigator.pop(sheetContext, f),
        ),
      ),
    );
    if (next != null) cubit.applyFilters(next);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MarketplaceCubit, MarketplaceState>(
      builder: (context, state) {
        final s = context.l10n;
        final cubit = context.read<MarketplaceCubit>();
        final active = state.filters.activeCount;

        return LayoutBuilder(builder: (context, constraints) {
          final sidePanel = constraints.maxWidth >= _kSidePanelFrom;
          return Scaffold(
            appBar: AppBar(
              title: Text(s.marketplaceTitle),
              actions: [
                const ShellSearchButton(),
                if (!sidePanel)
                  IconButton(
                    tooltip: s.filters,
                    onPressed: () => _openFilterSheet(context, state.filters),
                    icon: Badge(
                      isLabelVisible: active > 0,
                      label: Text('$active'),
                      child: const Icon(Icons.tune),
                    ),
                  ),
              ],
              // Quick category chips; on wide layouts the side panel has them.
              bottom: sidePanel
                  ? LatticeBand.preferred()
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(52 + 9),
                      child: Column(
                        children: [
                          _CategoryChipRow(selected: state.filters.category),
                          const LatticeBand(),
                        ],
                      ),
                    ),
            ),
            body: LinearRefresher(
              offset: 0.0,
              onRefresh: () => cubit.loadData(),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (sidePanel) ...[
                    SizedBox(
                      width: _kSidePanelWidth,
                      // The form scrolls itself.
                      child: MarketFilterForm(
                        // Rebuilt whenever the applied filters change
                        // (e.g. Reset from the empty state).
                        key: ObjectKey(state.filters),
                        initial: state.filters,
                        onApply: cubit.applyFilters,
                        panel: true,
                      ),
                    ),
                    const VerticalDivider(width: 1),
                  ],
                  Expanded(
                    child: Column(
                      children: [
                        // Outside the scroll view, so it stays put (sticky).
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                          child: _searchField(context),
                        ),
                        Expanded(child: _results(context, state)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  Widget _searchField(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      onChanged: (v) {
        context.read<MarketplaceCubit>().updateSearch(v);
        setState(() {}); // show / hide the clear button
      },
      decoration: InputDecoration(
        hintText: s.searchItems,
        prefixIcon: Icon(Icons.search, color: scheme.onSurfaceVariant),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                tooltip: s.clearSearch,
                icon: const Icon(Icons.close),
                onPressed: () {
                  _searchCtrl.clear();
                  context.read<MarketplaceCubit>().updateSearch('');
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }

  Widget _results(BuildContext context, MarketplaceState state) {
    final cubit = context.read<MarketplaceCubit>();

    return LayoutBuilder(builder: (context, constraints) {
      final columns = Responsive.gridColumnsFor(constraints.maxWidth);

      if (state.isLoading && state.items.isEmpty) {
        return _MarketGridSkeleton(columns: columns);
      }
      if (state.errorMessage != null && state.items.isEmpty) {
        return ErrorState(onRetry: cubit.loadData);
      }
      if (state.items.isEmpty) {
        return _EmptyMarket(
          filtered: !state.filters.isDefault || state.searchQuery.isNotEmpty,
          onReset: state.filters.isDefault
              ? null
              : () => cubit.applyFilters(const MarketFilters()),
          onSell: () => _openCreate(context),
        );
      }

      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: MarketCard.aspectRatio,
                crossAxisSpacing: KSpace.m,
                mainAxisSpacing: KSpace.m,
              ),
              itemCount: state.items.length,
              itemBuilder: (context, index) {
                final item = state.items[index];
                return MarketCard(item: item, onTap: () => context.goItem(item));
              },
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

// ---------------------------------------------------------------------------
// Market card
// ---------------------------------------------------------------------------

/// Grid tile for a listing: square photo with the RESERVED / SOLD badge,
/// title, and the price in gold. Lifts on hover / focus on web.
class MarketCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback? onTap;

  const MarketCard({super.key, required this.item, this.onTap});

  /// Width / height of a tile (photo square + two text lines).
  static const double aspectRatio = 0.68;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = ListingStatus.of(item);
    final isSold = status == ListingStatus.sold;
    final badge = status.badge(s);
    final title = (item['title'] ?? '').toString();
    final price = formatPrice(item['price'] as num?);

    return Opacity(
      opacity: isSold ? 0.6 : 1,
      child: KCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        semanticLabel: '$title, $price${badge != null ? ', $badge' : ''}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: item['image_url'] ?? '',
                    fadeInDuration: Duration.zero,
                    fadeOutDuration: Duration.zero,
                    fit: BoxFit.cover,
                    memCacheWidth: 500,
                    // Sold photos are desaturated, not tinted.
                    color: isSold ? scheme.outline : null,
                    colorBlendMode: isSold ? BlendMode.saturation : null,
                    placeholder: (_, __) => ColoredBox(color: scheme.surfaceContainerHighest),
                    errorWidget: (_, __, ___) => ColoredBox(
                      color: scheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(Icons.storefront_outlined,
                            color: scheme.onSurfaceVariant, size: 30),
                      ),
                    ),
                  ),
                  if (badge != null) Positioned(top: 8, left: 8, child: StatusBadge(badge)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.s, KSpace.m, KSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(price,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                          // Gold is for prices (design direction).
                          color: isSold ? scheme.onSurfaceVariant : scheme.tertiary,
                          decoration: isSold ? TextDecoration.lineThrough : null,
                          fontWeight: FontWeight.w800)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filters
// ---------------------------------------------------------------------------

class _CategoryChipRow extends StatelessWidget {
  final String? selected;
  const _CategoryChipRow({required this.selected});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final categories = <String?>[null, ...kListingCategories];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final c = categories[i];
          return FilterChip(
            label: Text(c ?? s.all),
            selected: selected == c,
            onSelected: (_) => context.read<MarketplaceCubit>().updateCategory(c),
            selectedColor: scheme.secondaryContainer,
            checkmarkColor: scheme.onSecondaryContainer,
          );
        },
      ),
    );
  }
}

/// Sort, category, price range and status. A bottom sheet / dialog on
/// compact layouts, a side panel ([panel]) on wide ones.
class MarketFilterForm extends StatefulWidget {
  final MarketFilters initial;
  final ValueChanged<MarketFilters> onApply;
  final bool panel;

  const MarketFilterForm({
    super.key,
    required this.initial,
    required this.onApply,
    this.panel = false,
  });

  @override
  State<MarketFilterForm> createState() => _MarketFilterFormState();
}

class _MarketFilterFormState extends State<MarketFilterForm> {
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

  /// The side panel applies chip changes straight away; the sheet waits
  /// for "Show results".
  void _changed() {
    if (widget.panel) widget.onApply(_result());
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
    Widget priceField(TextEditingController c, String label) => TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: priceInput,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _changed(),
          decoration: InputDecoration(labelText: label, prefixText: 'RM '),
        );

    return Padding(
      padding: EdgeInsets.fromLTRB(
          widget.panel ? 16 : 24, 16, widget.panel ? 16 : 24,
          16 + (widget.panel ? 0 : MediaQuery.viewInsetsOf(context).bottom)),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.filters, style: theme.textTheme.titleLarge),

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
                    onSelected: (_) {
                      setState(() => _sort = sort);
                      _changed();
                    },
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
                    onSelected: (_) {
                      setState(() => _category = c);
                      _changed();
                    },
                  ),
              ],
            ),

            heading(s.priceRange),
            Row(
              children: [
                Expanded(child: priceField(_minCtrl, s.minPrice)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('–'),
                ),
                Expanded(child: priceField(_maxCtrl, s.maxPrice)),
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
                    onSelected: (on) {
                      setState(() {
                        _statuses = {..._statuses};
                        on ? _statuses.add(st) : _statuses.remove(st);
                      });
                      _changed();
                    },
                  ),
              ],
            ),

            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => widget.onApply(const MarketFilters()),
                  child: Text(s.resetFilters),
                ),
                FilledButton(
                  onPressed: () => widget.onApply(_result()),
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

// ---------------------------------------------------------------------------
// Empty and loading states
// ---------------------------------------------------------------------------

class _EmptyMarket extends StatelessWidget {
  final bool filtered;
  final VoidCallback? onReset;
  final VoidCallback onSell;

  const _EmptyMarket({required this.filtered, required this.onReset, required this.onSell});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    return BrandEmptyState(
      icon: Icons.storefront_outlined,
      title: filtered ? s.noMatchingItems : s.noItemsFound,
      message: filtered ? null : s.noItemsYetHint,
      actionLabel: onReset != null ? s.resetFilters : (filtered ? null : s.sellItem),
      onAction: onReset ?? (filtered ? null : onSell),
    );
  }
}

class _MarketGridSkeleton extends StatelessWidget {
  final int columns;
  const _MarketGridSkeleton({required this.columns});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(KSpace.l, 0, KSpace.l, KSpace.l),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          childAspectRatio: MarketCard.aspectRatio,
          crossAxisSpacing: KSpace.m,
          mainAxisSpacing: KSpace.m,
        ),
        itemCount: columns * 2,
        itemBuilder: (_, __) => const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: KSkeleton(height: double.infinity, borderRadius: KRadius.card)),
            SizedBox(height: KSpace.s),
            KSkeleton(height: 14),
            SizedBox(height: KSpace.xs),
            KSkeleton(width: 72, height: 16),
          ],
        ),
      ),
    );
  }
}
