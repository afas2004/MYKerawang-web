import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/announce_strings.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';
import '../screens/gallery_view_screen.dart';
import '../utils/announcement_rules.dart';
import '../utils/formatters.dart';
import '../utils/local_image.dart';
import 'brand/brand.dart';
import 'embed_card.dart';

// ---------------------------------------------------------------- links

/// Opens an announcement link: app routes ("/event/…") in-app via
/// go_router; https links only after the "leaving the app" check.
Future<void> openAnnouncementLink(BuildContext context, String url) async {
  if (url.startsWith('/')) {
    if (isKnownInternalRoute(url)) context.push(url);
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') return;
  final s = context.l10nRead;
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(AppIcons.externalLink, color: Theme.of(ctx).colorScheme.primary),
        const SizedBox(width: KSpace.s),
        Expanded(child: Text(s.leavingApp)),
      ]),
      content: Text(s.externalLinkWarning.fill([uri.host])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.cancel)),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(s.openAnyway)),
      ],
    ),
  );
  if (go == true) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

// ---------------------------------------------------------------- body

/// Light-formatted body: paragraphs, bullets, **bold**, tappable https
/// links (through [openAnnouncementLink]).
class FormattedBody extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const FormattedBody(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = style ??
        theme.textTheme.bodyLarge?.copyWith(height: 1.5, color: theme.colorScheme.onSurface);

    Widget rich(String line) => Text.rich(TextSpan(
          style: base,
          children: [
            for (final span in parseInline(line))
              if (span.url != null)
                TextSpan(
                  text: span.text,
                  style: TextStyle(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => openAnnouncementLink(context, span.url!),
                )
              else
                TextSpan(
                    text: span.text,
                    style: span.bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
          ],
        ));

    final blocks = parseBody(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: KSpace.m),
          switch (blocks[i]) {
            ParagraphBlock(:final text) => rich(text),
            BulletsBlock(:final items) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final item in items)
                    Padding(
                      padding: const EdgeInsets.only(bottom: KSpace.xs),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 9, right: KSpace.s, left: KSpace.xs),
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                  color: theme.colorScheme.primary, shape: BoxShape.circle),
                            ),
                          ),
                          Expanded(child: rich(item)),
                        ],
                      ),
                    ),
                ],
              ),
          },
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- image

/// A URL or a just-picked LocalImage (preview before upload).
class AnnouncementImage extends StatelessWidget {
  final dynamic source;
  final BoxFit fit;

  const AnnouncementImage(this.source, {super.key, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(child: Icon(AppIcons.announcement, color: scheme.onSurfaceVariant)),
    );
    final src = source;
    if (src is LocalImage) return Image.memory(src.bytes, fit: fit);
    if (src is String && src.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: src,
        fit: fit,
        memCacheWidth: 1400,
        placeholder: (_, __) => ColoredBox(color: scheme.surfaceContainerHighest),
        errorWidget: (_, __, ___) => fallback,
      );
    }
    return fallback;
  }
}

// ---------------------------------------------------------------- data

/// What the template shows; built from a posts row or a composer draft.
class AnnouncementData {
  final String title;
  final String body;
  final String? category;
  final String authorName;
  final String? authorAvatar;
  final dynamic cover;
  final List<dynamic> images;

  /// `16:9` (banner) or `1:1` (square). Chosen by the author.
  final String coverAspect;
  final List<ActionLink> actions;
  final Map<String, dynamic>? linkedEvent;
  final DateTime? publishAt;
  final DateTime? createdAt;

  const AnnouncementData({
    required this.title,
    required this.body,
    required this.category,
    required this.authorName,
    this.authorAvatar,
    this.cover,
    this.images = const [],
    this.coverAspect = '16:9',
    this.actions = const [],
    this.linkedEvent,
    this.publishAt,
    this.createdAt,
  });

  /// From a posts_public row (club or author profile as the speaker).
  factory AnnouncementData.fromPost(Map<String, dynamic> p,
      {Map<String, dynamic>? linkedEvent, String fallbackAuthor = ''}) {
    final club = p['club'] is Map ? p['club'] as Map : null;
    final profile = p['profiles'] is Map ? p['profiles'] as Map : null;
    return AnnouncementData(
      title: (p['title'] as String?) ?? '',
      body: (p['body'] as String?) ?? '',
      category: p['announcement_category'] as String?,
      authorName: '${club?['name'] ?? profile?['display_name'] ?? fallbackAuthor}',
      authorAvatar: (club?['logo_url'] ?? profile?['avatar_url']) as String?,
      cover: p['cover_url'] ?? p['image_url'],
      coverAspect: p['cover_aspect'] == '1:1' ? '1:1' : '16:9',
      images: List<String>.from(p['gallery_urls'] ?? const []),
      actions: ActionLink.listFrom(p['action_links']),
      linkedEvent: linkedEvent,
      publishAt: DateTime.tryParse('${p['publish_at'] ?? ''}')?.toLocal(),
      createdAt: DateTime.tryParse('${p['created_at'] ?? ''}')?.toLocal(),
    );
  }

  DateTime? get when => publishAt ?? createdAt;
  bool get scheduled => publishAt != null && publishAt!.isAfter(DateTime.now());
}

// ---------------------------------------------------------------- template

/// The announcement page: 16:9 cover, category + Official badge, title,
/// speaker · time, formatted body, extra photos, action buttons and the
/// linked event. Used by post detail and the composer's preview.
class AnnouncementView extends StatelessWidget {
  final AnnouncementData data;

  /// Preview: buttons and links don't navigate.
  final bool preview;

  const AnnouncementView({super.key, required this.data, this.preview = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = context.announceL10n;
    final d = data;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.cover != null && !(d.cover is String && (d.cover as String).isEmpty))
          ClipRRect(
            borderRadius: KRadius.card,
            child: AspectRatio(
                aspectRatio: d.coverAspect == '1:1' ? 1.0 : 16 / 9,
                child: AnnouncementImage(d.cover)),
          ),
        const SizedBox(height: KSpace.l),
        Wrap(
          spacing: KSpace.s,
          runSpacing: KSpace.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _Badge(icon: AppIcons.announcement, label: a.categoryLabel(d.category), color: scheme.primary),
            _Badge(icon: AppIcons.official, label: a.official, color: scheme.tertiary),
            if (d.scheduled)
              _Badge(
                  icon: AppIcons.clock,
                  label: a.scheduledFor.fill([formatDate(d.publishAt!)]),
                  color: scheme.onSurfaceVariant),
          ],
        ),
        const SizedBox(height: KSpace.s),
        Text(d.title,
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.25)),
        const SizedBox(height: KSpace.s),
        Row(children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: scheme.primaryContainer,
            backgroundImage:
                d.authorAvatar != null ? CachedNetworkImageProvider(d.authorAvatar!) : null,
            child: d.authorAvatar == null
                ? Icon(AppIcons.official, size: 14, color: scheme.onPrimaryContainer)
                : null,
          ),
          const SizedBox(width: KSpace.s),
          Expanded(
            child: Text(
              [d.authorName, if (d.when != null) formatRelative(context, d.when!)]
                  .where((e) => e.isNotEmpty)
                  .join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ]),
        if (d.body.trim().isNotEmpty) ...[
          const SizedBox(height: KSpace.l),
          FormattedBody(d.body),
        ],
        if (d.images.isNotEmpty) ...[
          const SizedBox(height: KSpace.l),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: d.images.length,
              separatorBuilder: (_, __) => const SizedBox(width: KSpace.s),
              itemBuilder: (context, i) => ClipRRect(
                borderRadius: KRadius.small,
                child: SizedBox.square(
                  dimension: 96,
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(
                      onTap: preview ? null : () => showGallery(context, items: d.images, initialIndex: i),
                      child: AnnouncementImage(d.images[i]),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (d.actions.isNotEmpty) ...[
          const SizedBox(height: KSpace.l),
          Wrap(
            spacing: KSpace.s,
            runSpacing: KSpace.s,
            children: [
              for (var i = 0; i < d.actions.length; i++)
                (i == 0 ? FilledButton.icon : OutlinedButton.icon)(
                  onPressed: preview ? null : () => openAnnouncementLink(context, d.actions[i].url),
                  icon: Icon(d.actions[i].isInternal ? AppIcons.forward : AppIcons.externalLink, size: 18),
                  label: Text(d.actions[i].label),
                ),
            ],
          ),
        ],
        if (d.linkedEvent != null && d.linkedEvent!['title'] != null)
          EmbedCard(
            data: d.linkedEvent!,
            isEvent: true,
            compact: true,
            onTap: preview ? () {} : () => context.push('/event/${d.linkedEvent!['id']}', extra: d.linkedEvent),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.s, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: KRadius.small,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: KSpace.xs),
        Text(label,
            style: theme.textTheme.labelMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ---------------------------------------------------------------- feed card

/// Compact announcement card for the Home feed: cover thumbnail,
/// category · Official, title, speaker · time.
class AnnouncementCard extends StatelessWidget {
  final Map<String, dynamic> post;
  final VoidCallback onTap;

  const AnnouncementCard({super.key, required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final a = context.announceL10n;
    final d = AnnouncementData.fromPost(post);
    final hasCover = d.cover is String && (d.cover as String).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KSpace.gutter, vertical: KSpace.m / 2),
      child: KCard(
        onTap: onTap,
        official: true,
        padding: const EdgeInsets.all(KSpace.m),
        semanticLabel: '${a.categoryLabel(d.category)}, ${d.title}',
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: KRadius.small,
              child: SizedBox(
                width: 96,
                height: 54, // 16:9
                child: hasCover
                    ? AnnouncementImage(d.cover)
                    : ColoredBox(
                        color: scheme.primaryContainer,
                        child: Icon(AppIcons.announcement, color: scheme.onPrimaryContainer),
                      ),
              ),
            ),
            const SizedBox(width: KSpace.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(AppIcons.announcement, size: 14, color: scheme.primary),
                    const SizedBox(width: KSpace.xs),
                    Flexible(
                      child: Text(
                        '${a.categoryLabel(d.category)} · ${a.official}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 2),
                  Text(d.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    [d.authorName, if (d.when != null) formatRelative(context, d.when!)]
                        .where((e) => e.isNotEmpty)
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
