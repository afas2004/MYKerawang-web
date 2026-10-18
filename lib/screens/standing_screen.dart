import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import '../utils/moderation_logic.dart';
import '../widgets/error_state.dart';
import '../widgets/kerawang_motif.dart';
import '../widgets/moderation_ui.dart';

/// /standing — the user's own account status. Calm and explanatory:
/// what is limited, why, until when, what still works, and an Appeal
/// button for each decision. Moderation notifications point here.
class StandingScreen extends StatefulWidget {
  const StandingScreen({super.key});

  @override
  State<StandingScreen> createState() => _StandingScreenState();
}

class _StandingScreenState extends State<StandingScreen> {
  late Future<ModerationStatus> _future = ModerationService.myStatus(force: true);

  void _reload() => setState(() => _future = ModerationService.myStatus(force: true));

  Future<void> _appeal({String? caseId, String? restrictionId}) async {
    final m = modStrings(context);
    final message = await askReason(
      context,
      title: m.appealTitle,
      confirmLabel: m.appealSend,
      label: m.appealHint,
      helper: m.appealLength,
      minLength: 10,
    );
    if (message == null || !mounted) return;
    try {
      await ModerationService.submitAppeal(caseId: caseId, restrictionId: restrictionId, message: message);
      if (!mounted) return;
      showModSnack(context, m.appealSent);
      _reload();
    } catch (e) {
      if (mounted) showModError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    return Scaffold(
      appBar: AppBar(title: Text(m.accountStatus)),
      body: FutureBuilder<ModerationStatus>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorState(onRetry: _reload);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: StandingView(
              status: snap.data!,
              onAppealRestriction: (id) => _appeal(restrictionId: id),
              onAppealCase: (id) => _appeal(caseId: id),
            ),
          );
        },
      ),
    );
  }
}

/// Presentational body of [StandingScreen] (testable without Supabase).
class StandingView extends StatelessWidget {
  final ModerationStatus status;
  final void Function(String restrictionId) onAppealRestriction;
  final void Function(String caseId) onAppealCase;

  const StandingView({
    super.key,
    required this.status,
    required this.onAppealRestriction,
    required this.onAppealCase,
  });

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final u = m.ui;
    final theme = Theme.of(context);
    final s = status;
    final restrictions = [...s.restrictions];
    final legacyBan = s.banned && !restrictions.any((r) => r.scope == ModScope.account);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Summary(clean: s.clean),
                if (!s.clean) ...[
                  const SizedBox(height: 24),
                  if (restrictions.isNotEmpty || legacyBan) ...[
                    Text(m.sectionRestrictions, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (legacyBan)
                      const _RestrictionCard(
                        r: Restriction(id: '', scope: ModScope.account, until: null, reason: ''),
                        onAppeal: null,
                      ),
                    for (final r in restrictions)
                      _RestrictionCard(
                        r: r,
                        onAppeal: r.appealStatus == null ? () => onAppealRestriction(r.id) : null,
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (s.cases.isNotEmpty) ...[
                    Text(u.historyTitle, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    for (final c in s.cases)
                      _HistoryItem(
                        c: c,
                        onAppeal: c['appeal_status'] == null && c['decision'] != 'restored'
                            ? () => onAppealCase('${c['id']}')
                            : null,
                      ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  final bool clean;
  const _Summary({required this.clean});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: clean ? scheme.secondaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(clean ? Icons.verified_user_outlined : Icons.shield_outlined,
              size: 40, color: clean ? scheme.onSecondaryContainer : scheme.primary),
          const SizedBox(height: 12),
          Text(
            clean ? m.goodStanding : m.accountStatus,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge
                ?.copyWith(color: clean ? scheme.onSecondaryContainer : scheme.onSurface),
          ),
          const SizedBox(height: 6),
          Text(
            clean ? m.goodStandingBody : m.ui.standingIntro,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: clean ? scheme.onSecondaryContainer : scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          const KerawangDivider(),
        ],
      ),
    );
  }
}

class _AppealFooter extends StatelessWidget {
  final String? status;
  final VoidCallback? onAppeal;
  const _AppealFooter({required this.status, required this.onAppeal});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    if (status != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ModChip(
          label: m.appealStatusLabel(status),
          icon: Icons.gavel,
          background: scheme.primaryContainer,
          foreground: scheme.onPrimaryContainer,
        ),
      );
    }
    if (onAppeal == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerRight,
      child: OutlinedButton.icon(
        onPressed: onAppeal,
        icon: const Icon(Icons.gavel, size: 18),
        label: Text(m.appeal),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      ),
    );
  }
}

/// Non-punitive tone: tertiary (not error) surface, what still works.
class _RestrictionCard extends StatelessWidget {
  final Restriction r;
  final VoidCallback? onAppeal;
  const _RestrictionCard({required this.r, required this.onAppeal});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = scheme.onTertiaryContainer;
    return Card(
      elevation: 0,
      color: scheme.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.pause_circle_outline, color: fg),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(m.cantTitle(r.scope.db),
                      style: theme.textTheme.titleSmall?.copyWith(color: fg)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (r.reason.trim().isNotEmpty)
              Text(m.restrictedReason.fill([r.reason]),
                  style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
            Text(
              r.until == null ? m.restrictedPermanent : m.restrictedUntil.fill([formatUntil(r.until!)]),
              style: theme.textTheme.bodyMedium?.copyWith(color: fg, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(m.ui.canStill, style: theme.textTheme.bodySmall?.copyWith(color: fg)),
            if (r.automatic)
              Text(m.restrictedAuto, style: theme.textTheme.bodySmall?.copyWith(color: fg)),
            const SizedBox(height: 8),
            _AppealFooter(status: r.appealStatus, onAppeal: onAppeal),
          ],
        ),
      ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final Map<String, dynamic> c;
  final VoidCallback? onAppeal;
  const _HistoryItem({required this.c, required this.onAppeal});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final preview = c['preview'] as Map<String, dynamic>?;
    final decision = c['decision'] as String?;
    final (label, icon) = c['status'] == 'hidden'
        ? (m.caseHiddenPending, Icons.hourglass_top)
        : switch (decision) {
            'removed' => (m.caseRemoved, Icons.visibility_off_outlined),
            'warned' => (m.caseWarned, Icons.info_outline),
            _ => (m.caseRestored, Icons.check_circle_outline),
          };
    final snippet = '${preview?['title'] ?? preview?['body'] ?? ''}'.trim();
    final categories = ((c['categories'] as List?) ?? const []).cast<String>();
    final reason = c['reason'] as String?;
    final when = DateTime.tryParse('${c['decided_at'] ?? c['hidden_at']}');

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${m.typeLabel(c['target_type'] as String?)} · $label',
                      style: theme.textTheme.titleSmall),
                ),
                if (when != null)
                  Text(formatUntil(when),
                      style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            Text(snippet.isEmpty ? m.contentGone : snippet,
                maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(m.reportedAs.fill([categories.map(m.categoryLabel).join(', ')]),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (reason != null && reason.isNotEmpty)
              Text(m.restrictedReason.fill([reason]),
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            _AppealFooter(status: c['appeal_status'] as String?, onAppeal: onAppeal),
          ],
        ),
      ),
    );
  }
}
