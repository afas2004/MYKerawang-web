import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../language_cubit.dart';
import '../utils/formatters.dart';
import 'brand/brand.dart';

/// An event or listing inside the feed, styled like the market / event
/// cards: 16:10 photo, title, then the price or the date · place line.
///
/// [compact] is the horizontal variant used inside a post that shares an
/// event or listing, so it supports the post rather than dominating it.
class EmbedCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isEvent;
  final VoidCallback onTap;
  final bool compact;

  const EmbedCard({
    super.key,
    required this.data,
    required this.isEvent,
    required this.onTap,
    this.compact = false,
  });

  /// Price for items; "date · location" for events.
  String _meta() {
    if (isEvent) {
      final start = parseLocal(data['start_datetime']);
      final date = start != null ? formatDate(start) : '';
      final location = (data['location'] ?? '').toString();
      return [date, location].where((e) => e.isNotEmpty).join(' · ');
    }
    final price = data['price'];
    return price is num ? formatPrice(price) : '';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = (data['title'] ?? '').toString();
    final imageUrl = data['image_url'] as String?;
    final meta = _meta();
    final kindIcon = isEvent ? AppIcons.events : AppIcons.market;

    final metaStyle = isEvent
        ? theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)
        : theme.textTheme.titleSmall?.copyWith(
            color: scheme.tertiary, fontWeight: FontWeight.w700);

    Widget photo(int cacheWidth) => (imageUrl != null && imageUrl.isNotEmpty)
        ? CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            memCacheWidth: cacheWidth,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, __) =>
                ColoredBox(color: scheme.surfaceContainerHighest),
            errorWidget: (_, __, ___) => _Placeholder(icon: kindIcon),
          )
        : _Placeholder(icon: kindIcon);

    final metaRow = meta.isEmpty
        ? null
        : Row(
            children: [
              if (isEvent) ...[
                Icon(AppIcons.calendar, size: 14, color: scheme.onSurfaceVariant),
                const SizedBox(width: KSpace.xs),
              ],
              Expanded(
                child: Text(meta,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: metaStyle),
              ),
            ],
          );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(top: KSpace.m),
        child: KCard(
          onTap: onTap,
          padding: const EdgeInsets.all(KSpace.s),
          color: scheme.surfaceContainerLow,
          semanticLabel: [title, meta].where((e) => e.isNotEmpty).join(', '),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: KRadius.small,
                child: SizedBox(width: 64, height: 64, child: photo(200)),
              ),
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    if (metaRow != null) ...[
                      const SizedBox(height: 2),
                      metaRow,
                    ],
                  ],
                ),
              ),
              Icon(AppIcons.chevronRight, size: 20, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: KSpace.gutter, vertical: KSpace.m / 2),
      child: KCard(
        onTap: onTap,
        padding: EdgeInsets.zero,
        semanticLabel: [title, meta].where((e) => e.isNotEmpty).join(', '),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(aspectRatio: 16 / 10, child: photo(1000)),
            Padding(
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.l),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (metaRow != null) ...[
                    const SizedBox(height: KSpace.xs),
                    metaRow,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  final IconData icon;
  const _Placeholder({required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(icon, color: scheme.onSurfaceVariant)),
    );
  }
}

/// A shared event or listing as the hero of a post: 16:9 photo, type
/// label, title, date or price, and a call to action.
class SharedItemHero extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isEvent;
  final VoidCallback onTap;

  const SharedItemHero({
    super.key,
    required this.data,
    required this.isEvent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final title = (data['title'] ?? '').toString();
    final imageUrl = data['image_url'] as String?;
    final meta = EmbedCard(data: data, isEvent: isEvent, onTap: onTap)._meta();
    final icon = isEvent ? AppIcons.events : AppIcons.market;

    return KCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      semanticLabel: [title, meta].where((e) => e.isNotEmpty).join(', '),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: (imageUrl != null && imageUrl.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 1000,
                    placeholder: (_, __) =>
                        ColoredBox(color: scheme.surfaceContainerHighest),
                    errorWidget: (_, __, ___) => _Placeholder(icon: icon),
                  )
                : _Placeholder(icon: icon),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, KSpace.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(icon, size: 14, color: scheme.primary),
                  const SizedBox(width: KSpace.xs),
                  Text(isEvent ? s.kindEvent : s.navMarket,
                      style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.primary, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(height: KSpace.xs),
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: isEvent
                          ? theme.textTheme.bodyMedium
                              ?.copyWith(color: scheme.onSurfaceVariant)
                          : theme.textTheme.titleSmall?.copyWith(
                              color: scheme.tertiary, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: KSpace.m),
                FilledButton.tonal(
                  onPressed: onTap,
                  child: Text(isEvent ? s.viewEvent : s.viewItem),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

