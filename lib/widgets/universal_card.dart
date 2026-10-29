import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../language_cubit.dart';
import '../utils/formatters.dart';
import 'brand/brand.dart';

/// Small event / listing card for horizontal lists: photo, title, and the
/// date range or price — the same style as the market and event cards.
///
/// In a slot with a fixed height (carousels) the photo takes whatever the
/// text doesn't, so the card never overflows; unconstrained it uses a
/// 16:10 photo.
class UniversalCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;

  const UniversalCard({super.key, required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final title = (data['title'] ?? s.untitled).toString();
    final image = data['image_url'] as String?;
    final isEvent = data.containsKey('start_datetime');

    final start = isEvent ? parseLocal(data['start_datetime']) : null;
    final subtitle = isEvent
        ? (start == null
            ? ''
            : formatEventRange(start, parseLocal(data['end_datetime'])))
        : formatPrice(data['price']);

    // No photo: a soft wash of the item's colour with one Fluent icon (never
    // an empty grey box), and the date stub on events.
    final seed = '${data['id'] ?? title}';
    final generated = KTintCover(
      seed: seed,
      color: KPalette.forKey(seed),
      icons: isEvent ? KTintCover.eventIcons : KTintCover.listingIcons,
      child: isEvent && start != null
          ? Align(
              alignment: Alignment.bottomLeft,
              child: Padding(
                padding: const EdgeInsets.all(KSpace.s),
                child: _MiniStub(date: start),
              ),
            )
          : null,
    );
    final photo = image != null && image.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: image,
            memCacheWidth: 600,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 200),
            placeholder: (_, __) =>
                ColoredBox(color: scheme.surfaceContainerHighest),
            errorWidget: (_, __, ___) => generated,
          )
        : generated;

    final text = Padding(
      padding: const EdgeInsets.fromLTRB(KSpace.m, KSpace.s, KSpace.m, KSpace.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: isEvent
                ? theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)
                : theme.textTheme.titleSmall?.copyWith(
                    color: scheme.tertiary, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );

    return KCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      semanticLabel: '$title, $subtitle',
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
                AspectRatio(aspectRatio: 16 / 10, child: photo),
              text,
            ],
          );
        },
      ),
    );
  }
}

/// Month over day, white on plum, for an event cover with no photo.
class _MiniStub extends StatelessWidget {
  final DateTime date;
  const _MiniStub({required this.date});

  static const _months = ['JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', 'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.primary,
        borderRadius: KRadius.small,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: KSpace.s, vertical: KSpace.xs),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_months[date.month - 1],
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onPrimary, height: 1.1)),
            Text('${date.day}',
                style: theme.textTheme.titleLarge
                    ?.copyWith(color: theme.colorScheme.onPrimary, height: 1.05)),
          ],
        ),
      ),
    );
  }
}
