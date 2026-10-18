import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:mykerawang/widgets/linear_refresher.dart';
import 'create_event_screen.dart';
import 'events_cubit.dart'; // Ensure this matches your file structure
import '../language_cubit.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/categories.dart';
import '../widgets/error_state.dart';

class EventsScreen extends StatelessWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Provide the Cubit
    return BlocProvider(
      create: (_) => EventsCubit(),
      child: const EventsView(),
    );
  }
}

class EventsView extends StatefulWidget {
  const EventsView({super.key});

  @override
  State<EventsView> createState() => _EventsViewState();
}

class _EventsViewState extends State<EventsView> {
  final TextEditingController _searchCtrl = TextEditingController();
  final List<String> _tags = ['All', ...kEventTags];

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 2. Consume the State
    return BlocBuilder<EventsCubit, EventsState>(
      builder: (context, state) {
        return Scaffold(
          appBar: AppBar(
            title: Text(context.l10n.navEvents),
            // Desktop has no FAB, so creation lives here instead (H1.1).
            actions: [
              if (isWide(context))
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilledButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const CreateEventScreen()));
                      if (result == true && context.mounted) {
                        context.read<EventsCubit>().loadData();
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(context.l10n.createEvent),
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
                  itemCount: _tags.length,
                  itemBuilder: (context, index) {
                    final tag = _tags[index];
                    // Read selection from State
                    final isSelected = state.selectedTag == tag;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(tag),
                        selected: isSelected,
                        // Call Cubit
                        onSelected: (v) => context.read<EventsCubit>().updateTag(tag),
                        backgroundColor: Theme.of(context).colorScheme.surface,
                        selectedColor: Theme.of(context).colorScheme.secondaryContainer,
                        checkmarkColor: Theme.of(context).colorScheme.onSecondaryContainer,
                        labelStyle: TextStyle(
                        color: isSelected 
                            ? Theme.of(context).colorScheme.onSecondaryContainer 
                            : Theme.of(context).colorScheme.onSurface,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      )
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
              await context.read<EventsCubit>().loadData();
            },
            child: state.isLoading
                ? const Center(child: CircularProgressIndicator())
                : (state.errorMessage != null && state.allEvents.isEmpty)
                ? ErrorState(
                    onRetry: () => context.read<EventsCubit>().loadData())
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: TextField(
                          controller: _searchCtrl,
                          // Call Cubit
                          onChanged: (v) => context.read<EventsCubit>().updateSearch(v),
                          decoration: InputDecoration(
                            hintText: context.l10n.searchEvents,
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
                        child: state.displayedEvents.isEmpty
                            ? const Center(child: Text("No events found"))
                            : ListView.separated(
                                padding: const EdgeInsets.all(16),
                                itemCount: state.displayedEvents.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 16),
                                itemBuilder: (context, index) {
                                  final event = state.displayedEvents[index];
                                  // Parse date exactly as before
                                  final date = DateTime.parse(event['start_datetime']).toLocal();
                                  final ended = isEventEnded(event);

                                  return Opacity(
                                    // Ended events stay visible but recede (spec §6)
                                    opacity: ended ? 0.55 : 1,
                                    child: GestureDetector(
                                    onTap: () => context.goEvent(event),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainer,
                                        borderRadius: kerawangCut,
                                        border: Border.all(
                                          color: Theme.of(context).colorScheme.outlineVariant,
                                          width: 1,
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Stack(
                                            children: [
                                          CachedNetworkImage(
                                              imageUrl: event['image_url'] ?? '',
                                              memCacheWidth: 900, // decode at card size, not camera size
                                              fadeInDuration: Duration.zero,
                                              fadeOutDuration: Duration.zero,
                                              height: 180,
                                              width: double.infinity,
                                              fit: BoxFit.cover,
                                              placeholder: (context, url) => Container(
                                                height: 180, 
                                                color: Theme.of(context).colorScheme.surfaceContainerHighest, 
                                                child: const Center(child: CircularProgressIndicator())
                                              ),
                                              errorWidget: (context, url, error) => Container(
                                                height: 180,
                                                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                                child: Center(
                                                  child: Icon(Icons.event_busy, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 40),
                                                ),
                                              ),
                                            ),
                                            if (ended)
                                              Positioned(
                                                top: 10,
                                                left: 10,
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(
                                                      horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withValues(alpha: 0.7),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: const Text(
                                                    "TAMAT",
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                      letterSpacing: 1,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          Padding(
                                            padding: const EdgeInsets.all(16),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                // Tags Row
                                                Row(
                                                  children: ((event['tags'] as List?) ?? [])
                                                  .take(3)
                                                  .map<Widget>((t) => Padding(
                                                    padding: const EdgeInsets.only(right: 8),
                                                    child: Text(
                                                      "#$t",
                                                      style: TextStyle(
                                                        color: Theme.of(context).colorScheme.primary,
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  )).toList(),
                                                ),
                                                const SizedBox(height: 8),
                                                // Title
                                                Text(event['title'],
                                                    style: const TextStyle(
                                                        fontSize: 18,
                                                        fontWeight: FontWeight.bold)),
                                                const SizedBox(height: 8),
                                                // Date
                                                Row(
                                                  children: [
                                                    Icon(Icons.calendar_today,
                                                        size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                        DateFormat('dd MMM, hh:mm a').format(date),
                                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                                  ],
                                                ),
                                                const SizedBox(height: 4),
                                                // Location
                                                Row(
                                                  children: [
                                                    Icon(Icons.location_on,
                                                        size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                                    const SizedBox(width: 8),
                                                    Text(event['location'] ?? 'TBA',
                                                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          )
                                        ],
                                      ),
                                    ),
                                  ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
          // Desktop creates from the sidebar / header — a FAB floating in
          // the far corner of a wide window is a phone pattern (G5).
          floatingActionButton: isWide(context) ? null : FloatingActionButton(
            heroTag: 'events_fab',
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CreateEventScreen())),
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
          ),
        );
      },
    );
  }
}