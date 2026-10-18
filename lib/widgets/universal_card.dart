import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';
import '../utils/formatters.dart';
import 'tap_card.dart';

/// Small event / listing card for horizontal lists and grids: photo,
/// gold kind label, title, date range or price.
///
/// In a slot with a fixed height (carousels) the photo takes whatever the
/// text doesn't, so the card never overflows; unconstrained it uses a
/// 4:3 photo.
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
    final image = data['image_url'] as String?;
    final isEvent = data.containsKey('start_datetime');

    final start = isEvent ? parseLocal(data['start_datetime']) : null;
    final subtitle = isEvent
        ? (start == null
            ? ''
            : formatEventRange(start, parseLocal(data['end_datetime'])))
        : formatPrice(data['price']);

    final photo = image != null && image.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: image,
            memCacheWidth: 600,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, __) =>
                ColoredBox(color: scheme.surfaceContainerHighest),
            errorWidget: (_, __, ___) => ColoredBox(
              color: scheme.surfaceContainerHighest,
              child: Icon(Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant),
            ),
          )
        : ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: Icon(isEvent ? Icons.event : Icons.storefront,
                size: 36, color: scheme.onSurfaceVariant),
          );

    final text = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Gold kind label — specialness marker (spec §2)
          Text(
            "◆ ${(isEvent ? s.kindEvent : s.navMarket).toUpperCase()}",
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.tertiary,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: isEvent ? scheme.onSurfaceVariant : scheme.primary,
              fontWeight: isEvent ? FontWeight.w500 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );

    return TapCard(
      onTap: onTap,
      borderRadius: kerawangCut,
      color: theme.cardColor,
      border: BorderSide(color: scheme.outlineVariant),
      child: LayoutBuilder(
        builder: (context, box) {
          final bounded = box.hasBoundedHeight;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              if (bounded)
                Expanded(child: photo)
              else
                AspectRatio(aspectRatio: 4 / 3, child: photo),
              text,
            ],
          );
        },
      ),
    );
  }
}
