import 'package:flutter/material.dart';

import '../l10n/app_strings.dart';
import '../l10n/moderation_strings.dart';
import '../language_cubit.dart';
import '../services/moderation_service.dart';
import '../utils/moderation_logic.dart';
import '../widgets/error_state.dart';
import '../widgets/moderation_ui.dart';

/// /standing — what is restricted, why, until when, and decisions about
/// the user's own content, each with an Appeal button (one per decision).
/// Moderation notifications point here (data.route).
class StandingScreen extends StatefulWidget {
  const StandingScreen({super.key});

  @override
  State<StandingScreen> createState() => _StandingScreenState();
}

class _StandingScreenState extends State<StandingScreen> {
  late Future<ModerationStatus> _future = ModerationService.myStatus(force: true);

  void _reload() =>
      setState(() => _future = ModerationService.myStatus(force: true));

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
      await ModerationService.submitAppeal(
          caseId: caseId, restrictionId: restrictionId, message: message);
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
          final s = snap.data!;
          if (s.clean) {
            return ModEmptyState(
                icon: Icons.verified_user_outlined,
                title: m.goodStanding,
                body: m.goodStandingBody);
          }
          final restrictions = [...s.restrictions];
          final legacyBan = s.banned && !restrictions.any((r) => r.scope == ModScope.account);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (restrictions.isNotEmpty || legacyBan) ...[
                  _SectionTitle(m.sectionRestrictions),
                  if (legacyBan)
                    _RestrictionCard(
                      r: const Restriction(
                          id: '', scope: ModScope.account, until: null, reason: ''),
                      onAppeal: null,
                    ),
                  for (final r in restrictions)
                    _RestrictionCard(
                      r: r,
                      onAppeal: r.appealStatus == null
                          ? () => _appeal(restrictionId: r.id)
                          : null,
                    ),
                  const SizedBox(height: 16),
                ],
                if (s.cases.isNotEmpty) ...[
                  _SectionTitle(m.sectionDecisions),
                  for (final c in s.cases)
                    _CaseCard(
                      c: c,
                      onAppeal: c['appeal_status'] == null && c['decision'] != 'restored'
                          ? () => _appeal(caseId: '${c['id']}')
                          : null,
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
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
      ),
    );
  }
}

class _RestrictionCard extends StatelessWidget {
  final Restriction r;
  final VoidCallback? onAppeal;
  const _RestrictionCard({required this.r, required this.onAppeal});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: scheme.errorContainer,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.block, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(m.cantTitle(r.scope.db),
                      style: TextStyle(
                          fontWeight: FontWeight.w700, color: scheme.onErrorContainer)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (r.reason.trim().isNotEmpty)
              Text(m.restrictedReason.fill([r.reason]),
                  style: TextStyle(color: scheme.onErrorContainer)),
            Text(
              r.until == null
                  ? m.restrictedPermanent
                  : m.restrictedUntil.fill([formatUntil(r.until!)]),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
            if (r.automatic)
              Text(m.restrictedAuto,
                  style: TextStyle(fontSize: 12, color: scheme.onErrorContainer)),
            const SizedBox(height: 8),
            _AppealFooter(status: r.appealStatus, onAppeal: onAppeal),
          ],
        ),
      ),
    );
  }
}

class _CaseCard extends StatelessWidget {
  final Map<String, dynamic> c;
  final VoidCallback? onAppeal;
  const _CaseCard({required this.c, required this.onAppeal});

  @override
  Widget build(BuildContext context) {
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    final preview = c['preview'] as Map<String, dynamic>?;
    final decision = c['decision'] as String?;
    final label = c['status'] == 'hidden'
        ? m.caseHiddenPending
        : switch (decision) {
            'removed' => m.caseRemoved,
            'warned' => m.caseWarned,
            _ => m.caseRestored,
          };
    final snippet = '${preview?['title'] ?? preview?['body'] ?? ''}'.trim();
    final categories = ((c['categories'] as List?) ?? const []).cast<String>();
    final reason = c['reason'] as String?;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${m.typeLabel(c['target_type'] as String?)} · $label',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(snippet.isEmpty ? m.contentGone : snippet,
                maxLines: 3, overflow: TextOverflow.ellipsis),
            if (categories.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(m.reportedAs.fill([categories.map(m.categoryLabel).join(', ')]),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ],
            if (reason != null && reason.isNotEmpty)
              Text(m.restrictedReason.fill([reason]),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            _AppealFooter(status: c['appeal_status'] as String?, onAppeal: onAppeal),
          ],
        ),
      ),
    );
  }
}
