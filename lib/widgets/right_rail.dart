import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../language_cubit.dart';
import '../utils/app_nav.dart';

/// Desktop-only right rail (Instagram/Facebook style): upcoming events
/// and fresh marketplace items, using the space next to the feed.
class RightRail extends StatefulWidget {
  const RightRail({super.key});

  @override
  State<RightRail> createState() => _RightRailState();
}

class _RightRailState extends State<RightRail> {
  List<dynamic> _events = [];
  List<dynamic> _items = [];
  bool _loading = true;
  bool _showingPastEvents = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final supabase = Supabase.instance.client;
      final now = DateTime.now().toIso8601String();
      // Prefer upcoming events; if there are none, show the most recent
      // past ones rather than leaving the rail empty.
      var events = await supabase
          .from('events')
          .select()
          .gt('end_datetime', now)
          .order('start_datetime', ascending: true)
          .limit(3);

      if (events.isEmpty) {
        events = await supabase
            .from('events')
            .select()
            .order('start_datetime', ascending: false)
            .limit(3);
        _showingPastEvents = events.isNotEmpty;
      }
      final items = await supabase
          .from('listings')
          .select()
          .eq('is_sold', false)
          .order('created_at', ascending: false)
          .limit(4);
      if (mounted) {
        setState(() {
          _events = events;
          _items = items;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) return const SizedBox(width: 300);

    return SizedBox(
      width: 300,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
        children: [
          if (_events.isNotEmpty) ...[
            _railCard(
              theme,
              // Don't call past events "this week" (H3)
              title: _showingPastEvents
                  ? context.l10n.pastEvents
                  : context.l10n.eventsThisWeek,
              icon: Icons.calendar_month,
              child: Column(
                children: _events.map((e) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.goEvent(e),
                    child: Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.only(left: 10, top: 2, bottom: 2),
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                              color: theme.colorScheme.primary, width: 3),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e['title'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(e['location'] ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_items.isNotEmpty)
            _railCard(
              theme,
              title: context.l10n.newInMarket,
              icon: Icons.auto_awesome,
              iconColor: theme.colorScheme.tertiary,
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: _items.map((item) {
                  return InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => context.goItem(item),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: item['image_url'] ?? '',
                            fit: BoxFit.cover,
                            memCacheWidth: 300,
                            errorWidget: (_, __, ___) => Container(
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: const Icon(Icons.storefront, size: 20)),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            child: Container(
                              color: Colors.black54,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              child: Text(
                                "RM ${(item['price'] as num?)?.toStringAsFixed(0) ?? '?'}",
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _railCard(ThemeData theme,
      {required String title,
      required IconData icon,
      Color? iconColor,
      required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon,
                  size: 18, color: iconColor ?? theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(title, style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
