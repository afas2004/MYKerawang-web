import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../l10n/moderation_strings.dart';
import '../../language_cubit.dart';
import '../../services/moderation_service.dart';
import '../../utils/formatters.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_screen.dart';

/// Appeals against a case decision or a restriction. Accepting reverses
/// the decision; both outcomes notify the user with the admin's note.
class AppealsTab extends StatefulWidget {
  const AppealsTab({super.key});

  @override
  State<AppealsTab> createState() => _AppealsTabState();
}

class _AppealsTabState extends State<AppealsTab> with AutomaticKeepAliveClientMixin {
  bool _pendingOnly = true;
  late Future<List<Map<String, dynamic>>> _future = ModerationService.appeals();
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  void _reload() =>
      setState(() => _future = ModerationService.appeals(pendingOnly: _pendingOnly));

  Future<void> _handle(Map<String, dynamic> a, bool accept) async {
    final m = modStrings(context);
    final note = await askReason(
      context,
      title: accept ? m.acceptTitle : m.rejectAppealTitle,
      body: accept ? m.acceptBody : m.rejectAppealBody,
      confirmLabel: accept ? m.accept : m.reject,
      label: m.noteLabel,
      destructive: !accept,
    );
    if (note == null || !mounted) return;
    final id = '${a['id']}';
    setState(() => _busy.add(id));
    try {
      await ModerationService.handleAppeal(id, accept, note);
      if (!mounted) return;
      showModSnack(context, accept ? m.appealAcceptedDone : m.appealRejectedDone);
      _reload();
    } catch (e) {
      if (mounted) showModError(context, e);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final m = context.l10n.mod;
    final scheme = Theme.of(context).colorScheme;
    return AdminAsyncList<Map<String, dynamic>>(
      future: _future,
      onRetry: _reload,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            FilterChip(
              label: Text(m.pendingOnly),
              selected: _pendingOnly,
              onSelected: (v) {
                _pendingOnly = v;
                _reload();
              },
            ),
          ],
        ),
      ),
      empty: ModEmptyState(icon: Icons.gavel_outlined, title: m.noAppeals),
      itemBuilder: (context, a) {
        final busy = _busy.contains('${a['id']}');
        final caseInfo = a['case_info'] as Map<String, dynamic>?;
        final restriction = a['restriction_info'] as Map<String, dynamic>?;
        final preview = caseInfo?['preview'] as Map<String, dynamic>?;
        final created = DateTime.tryParse('${a['created_at']}');
        final pending = a['status'] == 'pending';

        String about;
        if (caseInfo != null) {
          final what = m.typeLabel(caseInfo['target_type'] as String?);
          final decision = caseInfo['decision'] == null
              ? m.statusLabel(caseInfo['status'] as String?)
              : m.decisionLabel(caseInfo['decision'] as String?);
          final snippet = '${preview?['title'] ?? preview?['body'] ?? ''}'.trim();
          about = '$what · $decision${snippet.isEmpty ? '' : ' · “$snippet”'}';
        } else if (restriction != null) {
          final until = DateTime.tryParse('${restriction['until']}');
          about = '${m.scopeLabel(restriction['scope'] as String?)} · '
              '${until == null ? m.permanent : m.untilDate.fill([formatUntil(until)])}';
        } else {
          about = m.contentGone;
        }
        final decisionReason =
            (caseInfo?['decision_reason'] ?? restriction?['reason']) as String?;

        return Card(
          elevation: 0,
          margin: const EdgeInsets.symmetric(vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (busy) const LinearProgressIndicator(minHeight: 2),
                AdminUserLine(
                  profile: a['profile'] as Map<String, dynamic>?,
                  anonymous: a['anonymous_source'] == true,
                  trailing: created == null ? null : formatRelative(context, created),
                ),
                const SizedBox(height: 8),
                Text('${m.appealAbout}: $about',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                if (decisionReason != null && decisionReason.isNotEmpty)
                  Text(m.restrictedReason.fill([decisionReason]),
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${a['message'] ?? ''}'),
                ),
                const SizedBox(height: 8),
                if (pending)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: busy ? null : () => _handle(a, false),
                        child: Text(m.reject),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: busy ? null : () => _handle(a, true),
                        child: Text(m.accept),
                      ),
                    ],
                  )
                else
                  Text(
                    '${m.appealStatusLabel(a['status'] as String?)}'
                    '${(a['resolution_note'] as String?)?.isNotEmpty == true ? ' — ${a['resolution_note']}' : ''}',
                    style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
