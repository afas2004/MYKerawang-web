import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../language_cubit.dart';
import '../utils/formatters.dart';
import 'tap_card.dart';

class UniversalCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const UniversalCard({super.key, required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final title = data['title'] ?? s.untitled;
    final image = data['image_url'];
    
    // Determine subtitle based on type (Event date vs Price)
    String subtitle = '';
    bool isEvent = data.containsKey('start_datetime');
    
    if (isEvent) {
      subtitle = formatEventRange(parseLocal(data['start_datetime'])!,
          parseLocal(data['end_datetime']));
    } else {
      // Marketplace item
      subtitle = formatPrice(data['price']);
    }

    return TapCard(
      onTap: onTap,
      color: theme.cardColor,
      border: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min, // <--- CRITICAL: Shrink-wraps the card
          children: [
            // 1. IMAGE SECTION
            // FIX: Replaced 'Expanded' with 'AspectRatio' or 'SizedBox'
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: SizedBox(
                height: 150, // <--- FIXED HEIGHT for Image
                width: double.infinity,
                child: image != null
                    ? CachedNetworkImage(
                        imageUrl: image,
                        memCacheWidth: 600,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(color: theme.colorScheme.surfaceContainerHighest),
                        errorWidget: (context, url, error) => Container(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: Icon(Icons.broken_image, color: scheme.onSurfaceVariant),
                        ),
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          isEvent ? Icons.event : Icons.store, 
                          size: 40, 
                          color: theme.colorScheme.onSurfaceVariant
                        ),
                      ),
              ),
            ),

            // 2. TEXT SECTION
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge (Event/Market)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isEvent
                          ? scheme.primaryContainer
                          : scheme.tertiary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      (isEvent ? s.kindEvent : s.navMarket).toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isEvent
                            ? scheme.onPrimaryContainer
                            : scheme.tertiary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),

                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
    );
  }
}