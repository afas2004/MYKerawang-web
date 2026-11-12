import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/whats_new_strings.dart';
import '../../language_cubit.dart';
import '../../services/feature_flags.dart';
import '../../services/post_service.dart';
import '../../services/share_service.dart' show kAppBaseUrl;
import '../../services/whats_new_notes.dart';
import '../../utils/app_nav.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/moderation_ui.dart';
import '../../widgets/pin_controls.dart';

/// A ready-to-publish post for [r]: English lines, then Malay, then a
/// link to the full list. Lines behind a switched-off area are left out.
({String title, String body, List<String> tags}) releasePost(ReleaseNote r) {
  final lines = r.visibleLines;
  String list(AppStrings s) => lines.map((l) => '• ${l.of(s)}').join('\n');
  return (
    title: "What's new in ${r.version} · Apa yang baharu",
    body: '${list(AppStrings.en)}\n\n${list(AppStrings.ms)}\n\n'
        'All updates · Semua kemas kini: $kAppBaseUrl/settings/whats-new',
    tags: const ['update'],
  );
}

/// Owner only: share a release's notes with everyone, as a post or as a
/// pinned post, in one tap.
class WhatsNewAdminTab extends StatelessWidget {
  const WhatsNewAdminTab({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return ValueListenableBuilder(
      valueListenable: FeatureFlags.listenable,
      builder: (context, _, __) {
        final releases = [for (final r in kReleaseNotes) if (r.visibleLines.isNotEmpty) r];
        return ListView(
          padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.l, KSpace.l, 96),
          children: [
            Text(s.whatsNewAdminHint,
                style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.5, color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: KSpace.m),
            for (final r in releases)
              Card(
                margin: const EdgeInsets.only(bottom: KSpace.m),
                child: Padding(
                  padding: const EdgeInsets.all(KSpace.m),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${r.version} · ${formatDate(r.date)}',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: KSpace.xs),
                    for (final l in r.visibleLines)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('• ${l.of(s)}', style: theme.textTheme.bodyMedium),
                      ),
                    const SizedBox(height: KSpace.s),
                    Wrap(spacing: KSpace.s, runSpacing: KSpace.xs, children: [
                      OutlinedButton.icon(
                        icon: const Icon(AppIcons.compose, size: 18),
                        label: Text(s.whatsNewAdminPost),
                        onPressed: () => _openComposer(context, r),
                      ),
                      FilledButton.icon(
                        icon: const Icon(AppIcons.pin, size: 18),
                        label: Text(s.whatsNewAdminPin),
                        onPressed: () => _postAndPin(context, r),
                      ),
                    ]),
                  ]),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Opens the normal post editor, filled in; the owner reviews and posts.
  void _openComposer(BuildContext context, ReleaseNote r) {
    final p = releasePost(r);
    context.push('/create/post', extra: {'title': p.title, 'body': p.body, 'tags': p.tags});
  }

  /// Posts as the owner, then pins (the usual pin questions follow).
  Future<void> _postAndPin(BuildContext context, ReleaseNote r) async {
    final s = context.l10nRead;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(s.whatsNewAdminConfirm(r.version)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.whatsNewAdminPin),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final p = releasePost(r);
      final db = Supabase.instance.client;
      final row = await db
          .from('posts')
          .insert({
            'user_id': db.auth.currentUser!.id,
            'title': p.title,
            'body': p.body,
            'tags': p.tags,
            'is_anonymous': false,
          })
          .select('id')
          .single();
      final id = '${row['id']}';
      PostService.rememberMine(id);
      notifyContentChanged();
      if (!context.mounted) return;
      showToast(s.whatsNewAdminPosted);
      await PinActions.toggle(context, {'id': id}, pinned: false);
    } catch (e) {
      if (context.mounted) showModError(context, e);
    }
  }
}
