import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mykerawang/widgets/linear_refresher';
import 'create_listing_screen.dart';
import '../utils/app_nav.dart';
import '../utils/categories.dart';
import 'marketplace_cubit.dart'; // Ensure this matches your file name
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
  final List<String> _filters = ['All', ...kListingCategories];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2. Consume the State
    return BlocBuilder<MarketplaceCubit, MarketplaceState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.marketplaceTitle),
            // Desktop has no FAB, so creation lives here instead (H1.1).
            actions: [
              if (isWide(context))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const CreateListingScreen()));
                      if (result == true && context.mounted) {
                        context.read<MarketplaceCubit>().loadData();
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.l10n.sellItem),
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
                  itemCount: _filters.length,
                  itemBuilder: (context, index) {
                    final filter = _filters[index];
                    // Read state for selection
                    final isSelected = state.selectedFilter == filter;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(filter),
                        selected: isSelected,
                        // Call Cubit
                        onSelected: (v) => context.read<MarketplaceCubit>().updateFilter(filter),
                        backgroundColor: Theme.of(context).cardColor,
                        selectedColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        checkmarkColor: Theme.of( context).colorScheme.primary,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          body: LinearRefresher(
            offset: 0.0,
            onRefresh: () async {
              // Now calling the PUBLIC method
              await context.read<MarketplaceCubit>().loadData();
            },
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : (state.errorMessage != null && state.allItems.isEmpty)
                ? ErrorState(
                    onRetry: () => context.read<MarketplaceCubit>().loadData())
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _searchCtrl,
                          // Call Cubit on change
                          onChanged: (v) => context.read<MarketplaceCubit>().updateSearch(v),
                          decoration: InputDecoration(
                            hintText: context.l10n.searchItems,
                            prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            filled: true,
                            fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none),
                          ),
                        ),
                      ),
                      Expanded(
                        // Use state.displayedItems from Cubit
                        child: state.displayedItems.isEmpty
                            ? Center(child: Text(context.l10n.noItemsFound))
                            : LayoutBuilder(builder: (context, constraints) {
                                return GridView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  // 2 columns on phones, 3-4 on wider screens
                                  crossAxisCount: Responsive.gridColumns(constraints.maxWidth),
                                  childAspectRatio: 0.7,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                                itemCount: state.displayedItems.length,
                                itemBuilder: (context, index) {
                                  final item = state.displayedItems[index];
                                  final isSold = item['is_sold'] == true;
                                  // InkWell (not GestureDetector) so desktop
                                  // gets a pointer cursor + hover ripple (G6)
                                  return InkWell(
                                    onTap: () => context.goItem(item),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Opacity(
                                      opacity: isSold ? 0.6 : 1,
                                      child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).cardColor,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
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
                                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                  child: const Center(child: CircularProgressIndicator())
                                                ),
                                                errorWidget: (context, url, error) => Container(
                                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                  child: const Center(
                                                    child: Icon(Icons.store_mall_directory_outlined, color: Colors.grey, size: 30)
                                                  ),
                                                ),
                                              ),
                                              // SOLD badge (4.7)
                                              if (isSold)
                                                Positioned(
                                                  top: 8,
                                                  left: 8,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(
                                                        horizontal: 10, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withValues(alpha: 0.75),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: const Text("SOLD",
                                                        style: TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.w700,
                                                            letterSpacing: 1)),
                                                  ),
                                                ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(10),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(item['title'],
                                                    maxLines: 2,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: Theme.of(context).textTheme.titleSmall
                                                        ?.copyWith(fontWeight: FontWeight.w600)),
                                                const SizedBox(height: 4),
                                                Text(
                                                    "RM ${(item['price'] as num).toStringAsFixed(2)}",
                                                    style: TextStyle(
                                                        color: isSold
                                                            ? Theme.of(context).colorScheme.onSurfaceVariant
                                                            : Theme.of(context).colorScheme.primary,
                                                        decoration: isSold
                                                            ? TextDecoration.lineThrough
                                                            : null,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16)),
                                              ],
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                    ),
                                  );
                                },
                              );
                              }),
                      ),
                    ],
                  ),
          ),
          // See G5 — no floating corner button on desktop.
          floatingActionButton: isWide(context) ? null : FloatingActionButton(
            heroTag: 'market_fab',
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CreateListingScreen())),
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
          ),
        );
      },
    );
  }
}