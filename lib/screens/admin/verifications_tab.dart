import 'package:flutter/material.dart';

import '../../l10n/access_strings.dart';
import '../../l10n/app_strings.dart';
import '../../language_cubit.dart';
import '../../services/student_verification.dart';
import '../../utils/formatters.dart';
import '../../widgets/brand/brand.dart';
import '../../widgets/moderation_ui.dart';
import 'admin_screen.dart';

/// Pending student-verification requests.
///
/// There is no code-by-email yet, so this is the whole verification
/// process: a student submits a UiTM address, an admin looks at it and
/// approves or rejects. Only shown while the owner has the switch on.
class VerificationsTab extends StatefulWidget {
  final Future<List<Map<String, dynamic>>> Function()? load;
  final Future<void> Function(String userId, String email)? approve;
  final Future<void> Function(String userId)? reject;

  const VerificationsTab({super.key, this.load, this.approve, this.reject});

  @override
  State<VerificationsTab> createState() => _VerificationsTabState();
}

class _VerificationsTabState extends State<VerificationsTab>
    with AutomaticKeepAliveClientMixin {
  late Future<List<Map<String, dynamic>>> _future = _fetch();
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  Future<List<Map<String, dynamic>>> _fetch() =>
      (widget.load ?? StudentVerificationService.queue)();

  void _reload() => setState(() => _future = _fetch());

  Future<void> _decide(Map<String, dynamic> r, bool approve) async {
    final s = context.l10n;
    final id = '${r['user_id']}';
    final email = '${r['email'] ?? ''}';
    setState(() => _busy.add(id));
    try {
      if (approve) {
        await (widget.approve ?? StudentVerificationService.approve)(id, email);
      } else {
        await (widget.reject ?? StudentVerificationService.reject)(id);
      }
      if (!mounted) return;
      showModSnack(context, approve ? s.verifyApproved : s.verifyRejectedDone);
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
    final s = context.l10n;
    return AdminAsyncList<Map<String, dynamic>>(
      future: _future,
      onRetry: _reload,
      empty: ModEmptyState(icon: ModIcons.verified, title: s.verifyQueueEmpty),
      itemBuilder: (context, r) {
        final id = '${r['user_id']}';
        final busy = _busy.contains(id);
        final name = '${r['display_name'] ?? r['username'] ?? ''}'.trim();
        final submitted = DateTime.tryParse('${r['created_at'] ?? ''}');
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Card(
          margin: const EdgeInsets.symmetric(vertical: KSpace.xs + 2),
          child: Padding(
            padding: const EdgeInsets.all(KSpace.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? '${r['email'] ?? ''}' : name,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text('${r['email'] ?? ''}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                if (submitted != null)
                  Text(
                    s.verifySubmittedAt.fill([formatDate(submitted)]),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                const SizedBox(height: KSpace.s),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: busy ? null : () => _decide(r, false),
                      style: TextButton.styleFrom(foregroundColor: scheme.error),
                      child: Text(s.verifyReject),
                    ),
                    const SizedBox(width: KSpace.xs),
                    FilledButton.tonal(
                      onPressed: busy ? null : () => _decide(r, true),
                      child: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(s.verifyApprove),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
