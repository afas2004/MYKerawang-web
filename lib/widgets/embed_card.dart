import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';

/// IG-style feed embed for injected marketplace items and events
/// (DESIGN_SPEC.md §4). Same width as posts, visually louder:
/// full-bleed image (kerawang cut), gold category label, title,
/// one line of context, single CTA.
class EmbedCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isEvent;
  final VoidCallback onTap;

  /// Compact horizontal variant, used for content cross-posted inside a
  /// post so the embed supports the post rather than dominating it.
  final bool compact;

  const EmbedCard({
    super.key,
    required this.data,
    required this.isEvent,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;

    final label = (isEvent ? s.navEvents : s.navMarket).toUpperCase();
    final title = data['title'] ?? '';
    final imageUrl = data['image_url'] as String?;

    // Context line: price for items, date + location for events
    String contextLine;
    if (isEvent) {
      final start = DateTime.tryParse(data['start_datetime'] ?? '');
      final date = start != null ? DateFormat('d MMM').format(start.toLocal()) : '';
      final location = data['location'] ?? '';
      contextLine = [date, location].where((e) => e.isNotEmpty).join(' · ');
    } else {
      final price = data['price'];
      contextLine = price is num ? "RM ${price.toStringAsFixed(2)}" : '';
    }

    if (compact) {
      return Padding(
        padding: const EdgeInsets.only(top: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: kerawangCut,
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: kerawangCut,
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: (imageUrl != null && imageUrl.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 260,
                          placeholder: (_, __) =>
                              Container(color: scheme.surfaceContainerHighest),
                          errorWidget: (_, __, ___) => Container(
                            color: scheme.surfaceContainerHighest,
                            child: Icon(
                                isEvent ? Icons.event : Icons.storefront,
                                color: scheme.onSurfaceVariant),
                          ),
                        )
                      : Container(
                          color: scheme.surfaceContainerHighest,
                          child: Icon(isEvent ? Icons.event : Icons.storefront,
                              color: scheme.onSurfaceVariant),
                        ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "◆ $label",
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.tertiary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (contextLine.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            contextLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: isEvent
                                  ? scheme.onSurfaceVariant
                                  : scheme.primary,
                              fontWeight: isEvent ? null : FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(Icons.arrow_forward_ios,
                      size: 14, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: kerawangCut,
        child: Container(
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: kerawangCut,
            border: Border.all(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    memCacheWidth: 1000,
                    fadeInDuration: const Duration(milliseconds: 200),
                    placeholder: (_, __) =>
                        Container(color: scheme.surfaceContainerHighest),
                    errorWidget: (_, __, ___) => Container(
                      color: scheme.surfaceContainerHighest,
                      child: Icon(
                        isEvent ? Icons.event : Icons.storefront,
                        size: 40,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gold category label — specialness marker (spec §2)
                    Text(
                      "◆ $label",
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (contextLine.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        contextLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isEvent
                              ? scheme.onSurfaceVariant
                              : scheme.primary,
                          fontWeight: isEvent ? null : FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onTap,
                        child: Text(isEvent ? s.viewEvent : s.viewItem),
                      ),
                    ),
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
