import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/social_strings.dart';
import '../language_cubit.dart';
import '../services/saved_items.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import 'save_button.dart';

/// The own-profile "Saved" tab: bookmarks grouped by type (posts, Market,
/// events), newest first within each group.
class SavedItemsView extends StatefulWidget {
  /// Fires when the page around this tab is refreshed (pull-to-refresh).
  final Listenable? reloadSignal;

  const SavedItemsView({super.key, this.reloadSignal});

  @override
  State<SavedItemsView> createState() => _SavedItemsViewState();
}

class _SavedItemsViewState extends State<SavedItemsView> {
  late Future<List<SavedEntry>> _future = SavedItems.instance.fetchAll();

  void _reload() =>
      setState(() => _future = SavedItems.instance.fetchAll());

  @override
  void initState() {
    super.initState();
    widget.reloadSignal?.addListener(_reload);
  }

  @override
  void didUpdateWidget(SavedItemsView old) {
    super.didUpdateWidget(old);
    if (old.reloadSignal != widget.reloadSignal) {
      old.reloadSignal?.removeListener(_reload);
      widget.reloadSignal?.addListener(_reload);
    }
  }

  @override
  void dispose() {
    widget.reloadSignal?.removeListener(_reload);
    super.dispose();
  }

  /// Fills the tab and can be dragged, so pull-to-refresh works even when
  /// there is no list (loading, error, nothing saved).
  Widget _pullable(Widget child) => LayoutBuilder(
        builder: (context, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: c.maxHeight),
            child: Center(child: child),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return FutureBuilder<List<SavedEntry>>(
      future: _future,
      builder: (context, snap) {
        // On a reload keep the old list up; the spinner is first load only.
        if (snap.connectionState != ConnectionState.done && !snap.hasData) {
          return _pullable(const CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _pullable(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.errorWithDetail.fill([snap.error])),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _reload,
                  icon: const Icon(Icons.refresh),
                  label: Text(s.social.retry),
                ),
              ],
            ),
          );
        }

        // Re-filter against the live key set, so un-saving here removes
        // the row immediately.
        return ValueListenableBuilder<Set<String>>(
          valueListenable: SavedItems.instance.keys,
          builder: (context, keys, _) {
            final entries = snap.data!
                .where((e) => keys.contains(SavedItems.keyOf(e.type, e.id)))
                .toList();
            if (entries.isEmpty) {
              return _pullable(
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bookmark_border,
                          size: 48, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      Text(s.social.nothingSaved,
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(s.social.nothingSavedSub,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              );
            }

            final groups = [
              (SavedType.post, s.posts),
              (SavedType.listing, s.navMarket),
              (SavedType.event, s.navEvents),
            ];
            // No own RefreshIndicator: the profile page's refresher
            // already wraps this tab.
            return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final (type, label) in groups)
                    if (entries.any((e) => e.type == type)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(label,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                      ),
                      for (final e in entries.where((e) => e.type == type))
                        _tile(context, s, e),
                    ],
                ],
            );
          },
        );
      },
    );
  }

  Widget _tile(BuildContext context, AppStrings s, SavedEntry e) {
    final scheme = Theme.of(context).colorScheme;
    final item = e.item;
    final trailing = SaveButton(type: e.type, id: e.id);

    if (item == null) {
      return ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest,
          child: Icon(Icons.block, color: scheme.onSurfaceVariant),
        ),
        title: Text(s.social.savedNoLongerAvailable,
            style: TextStyle(color: scheme.onSurfaceVariant)),
        trailing: trailing,
      );
    }

    final image = item['image_url'] as String?;
    final (String title, String subtitle, IconData icon) = switch (e.type) {
      SavedType.post => (
          _postTitle(s, item),
          s.postedBy.fill([item['profiles']?['display_name'] ?? s.anonymous]),
          Icons.article,
        ),
      SavedType.listing => (
          item['title'] ?? s.untitled,
          item['is_sold'] == true ? s.sold : formatPrice(item['price']),
          Icons.storefront,
        ),
      SavedType.event => (
          item['title'] ?? s.untitled,
          switch (parseLocal(item['start_datetime'])) {
            final start? => formatEventDate(start),
            null => s.dateTba,
          },
          Icons.event,
        ),
    };

    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 48,
          height: 48,
          child: image != null
              ? CachedNetworkImage(
                  imageUrl: image,
                  memCacheWidth: 150,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Icon(icon, color: scheme.onSurfaceVariant),
                )
              : Container(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(icon, color: scheme.onSurfaceVariant),
                ),
        ),
      ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: trailing,
      onTap: () => switch (e.type) {
        SavedType.post => context.goPost(item),
        SavedType.listing => context.goItem(item),
        SavedType.event => context.goEvent(item),
      },
    );
  }

  /// Post titles are optional: title → first body line → "Post".
  String _postTitle(AppStrings s, Map<String, dynamic> post) {
    final title = '${post['title'] ?? ''}'.trim();
    if (title.isNotEmpty) return title;
    final line = '${post['body'] ?? ''}'.trim().split('\n').first.trim();
    return line.isNotEmpty ? line : s.kindPost;
  }
}
