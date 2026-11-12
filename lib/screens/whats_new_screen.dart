import 'package:flutter/material.dart';

import '../l10n/whats_new_strings.dart';
import '../language_cubit.dart';
import '../services/feature_flags.dart';
import '../services/update_service.dart';
import '../services/whats_new_notes.dart';
import '../utils/adaptive.dart';
import '../utils/app_nav.dart';
import '../utils/formatters.dart';
import '../widgets/brand/brand.dart';

/// Settings › What's new: every release with notes, newest first.
/// Open to guests too (/settings/whats-new), so a post can link to it.
class WhatsNewScreen extends StatelessWidget {
  /// Tests: notes other than [kReleaseNotes].
  final List<ReleaseNote>? notes;
  const WhatsNewScreen({super.key, this.notes});

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: appBarConstrained(context,
          leading: const AppBackButton(), title: Text(s.whatsNewTitle)),
      body: PageBody(
        // Lines behind a switch come and go with it.
        child: ValueListenableBuilder(
          valueListenable: FeatureFlags.listenable,
          builder: (context, _, __) {
            final releases = [
              for (final r in notes ?? kReleaseNotes)
                if (r.visibleLines.isNotEmpty) r,
            ];
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(KSpace.l, KSpace.m, KSpace.l, 96),
              itemCount: releases.length,
              separatorBuilder: (_, __) => const Divider(height: KSpace.l * 2),
              itemBuilder: (context, i) {
                final r = releases[i];
                final current = r.version == UpdateService.appVersion;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: KSpace.s,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(r.version,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                        Text(formatDate(r.date),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
                        if (current)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(s.whatsNewCurrent),
                          ),
                      ],
                    ),
                    const SizedBox(height: KSpace.xs),
                    for (final l in r.visibleLines)
                      Padding(
                        padding: const EdgeInsets.only(top: KSpace.xs),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2, right: KSpace.s),
                            child: Icon(AppIcons.sparkle, size: 16,
                                color: KPalette.onTheme(KPalette.plum, theme.brightness)),
                          ),
                          Expanded(
                            child: Text(l.of(s),
                                style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
                          ),
                        ]),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
