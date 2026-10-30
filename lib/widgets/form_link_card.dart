import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/form_strings.dart';
import '../language_cubit.dart';
import '../services/form_service.dart';
import 'brand/brand.dart';

/// A form linked from a post, shown the way Threads and X show a link: one
/// full-width card in the post's frame — a tile, the form's real title, who
/// made it and how long it is, where it stands for you, and one action.
///
/// The post only stores `{label, url: /f/:id}`; the card reads the rest from
/// `form_public()` and keeps it for a few minutes, so scrolling the feed back
/// and forth does not ask again. While it loads, the link's own label stands in
/// for the title.
class FormLinkCard extends StatefulWidget {
  final String formId;

  /// The action link's label, shown until the form's title arrives.
  final String label;

  const FormLinkCard({super.key, required this.formId, required this.label});

  /// `/f/:id` → `:id`, or null for any other link.
  static String? idFrom(String url) {
    final m = RegExp(r'^/f/([^/?#]+)/?$').firstMatch(url.split('?').first);
    return m?.group(1);
  }

  static final Map<String, (DateTime, Future<FormView>)> _cache = {};
  static const _ttl = Duration(minutes: 3);

  static Future<FormView> _load(String id) {
    final hit = _cache[id];
    if (hit != null && DateTime.now().difference(hit.$1) < _ttl) return hit.$2;
    final future = FormService.instance.load(id);
    _cache[id] = (DateTime.now(), future);
    // A failure is not remembered: the next build asks again.
    future.catchError((Object _) {
      _cache.remove(id);
      return FormView(doc: FormDoc(id: id, title: '', status: 'closed'));
    });
    return future;
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();

  @override
  State<FormLinkCard> createState() => _FormLinkCardState();
}

class _FormLinkCardState extends State<FormLinkCard> {
  late Future<FormView> _view = FormLinkCard._load(widget.formId);

  @override
  void didUpdateWidget(FormLinkCard old) {
    super.didUpdateWidget(old);
    if (old.formId != widget.formId) _view = FormLinkCard._load(widget.formId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FormView>(
      future: _view,
      builder: (context, snap) => _Card(
        label: widget.label,
        view: snap.data,
        failed: snap.hasError,
        onTap: () => context.push('/f/${widget.formId}'),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String label;
  final FormView? view;
  final bool failed;
  final VoidCallback onTap;

  const _Card({required this.label, required this.view, required this.failed, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final doc = view?.doc;

    // Gone or taken down: say so quietly instead of offering a dead button.
    final gone = failed || (view?.reason == 'removed');
    final title = gone ? s.formCardGone : ((doc?.title.isNotEmpty ?? false) ? doc!.title : label);

    final who = doc == null
        ? null
        : doc.clubName ?? (doc.ownerUsername != null ? '@${doc.ownerUsername}' : null);
    final questions = doc?.fields.where((f) => f.isAnswerable).length;

    final answered = view?.answered ?? false;
    final open = view != null && (view!.canAnswer || view!.reason == 'signed_out');
    final (statusText, statusColor, statusIcon) = gone
        ? (null, scheme.onSurfaceVariant, null)
        : view == null
            ? (null, scheme.onSurfaceVariant, null)
            : answered
                ? (s.formCardAnswered, scheme.primary, AppIcons.check)
                : open
                    ? (s.formCardOpen, scheme.primary, null)
                    : (s.formClosed, scheme.onSurfaceVariant, AppIcons.lock);

    final meta = [
      if (who != null) who,
      if (questions != null && !gone) s.galleryQuestions(questions),
    ].join(' · ');

    final action = gone
        ? null
        : (answered || !open)
            ? s.formCardView
            : s.formCardFill;

    return LayoutBuilder(
      builder: (context, c) {
        final roomy = c.maxWidth >= 420;
        return KCard(
          key: const ValueKey('form-link-card'),
          onTap: gone ? null : onTap,
          padding: const EdgeInsets.all(KSpace.m),
          color: scheme.surfaceContainerLow,
          semanticLabel: [s.formCardKind, title, meta, statusText ?? ''].where((e) => e.isNotEmpty).join(', '),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: gone ? scheme.surfaceContainerHighest : scheme.primaryContainer,
                  borderRadius: KRadius.small,
                ),
                child: Icon(
                  AppIcons.list,
                  size: 24,
                  color: gone ? scheme.onSurfaceVariant : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: KSpace.m),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.formCardKind.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: gone ? scheme.onSurfaceVariant : scheme.primary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: gone ? scheme.onSurfaceVariant : scheme.onSurface,
                      ),
                    ),
                    if (meta.isNotEmpty || statusText != null) ...[
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          if (meta.isNotEmpty) TextSpan(text: meta),
                          if (meta.isNotEmpty && statusText != null) const TextSpan(text: ' · '),
                          if (statusIcon != null)
                            WidgetSpan(
                              alignment: PlaceholderAlignment.middle,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 3),
                                child: Icon(statusIcon, size: 12, color: statusColor),
                              ),
                            ),
                          if (statusText != null)
                            TextSpan(
                              text: statusText,
                              style: TextStyle(color: statusColor, fontWeight: FontWeight.w700),
                            ),
                        ]),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (action != null) ...[
                const SizedBox(width: KSpace.s),
                // Room for a real button on wide cards; a phone gets the
                // chevron and the whole card as the target.
                if (roomy)
                  FilledButton.tonal(
                    key: const ValueKey('form-card-action'),
                    onPressed: onTap,
                    child: Text(action),
                  )
                else
                  Icon(AppIcons.chevronRight, size: 20, color: scheme.onSurfaceVariant),
              ],
            ],
          ),
        );
      },
    );
  }
}
