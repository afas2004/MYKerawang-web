import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../l10n/app_strings.dart';
import '../language_cubit.dart';

/// Report reasons. The key is what gets stored in `reports.reason`
/// (kept in English so moderation data stays consistent); the label is
/// what the reporter sees.
List<(String, String)> _reasons(AppStrings s) => [
      ('Spam or Scam', s.reportReasonSpam),
      ('Hate Speech or Harassment', s.reportReasonHate),
      ('Inappropriate Content', s.reportReasonInappropriate),
      ('Misinformation', s.reportReasonMisinfo),
      ('Other', s.reportReasonOther),
    ];

Future<void> showReportDialog(BuildContext context, String targetId, String type) async {
  final s = context.l10nRead;

  await showDialog(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: Text(s.reportTitle),
      children: _reasons(s).map((reason) => SimpleDialogOption(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        child: Text(reason.$2),
        onPressed: () async {
          Navigator.pop(ctx); // Close dialog first

          try {
            await Supabase.instance.client.from('reports').insert({
              'reporter_id': Supabase.instance.client.auth.currentUser!.id,
              'target_id': targetId,
              'target_type': type,
              'reason': reason.$1,
            });

            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.reportThanks))
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.reportFailed)));
            }
          }
        },
      )).toList(),
    ),
  );
}

/// The "⋮ → Report" menu used on posts, comments, events, listings and
/// profiles. [type] is the `reports.target_type` value.
class ReportMenuButton extends StatelessWidget {
  final String targetId;
  final String type;

  /// Custom trigger (e.g. a scrim circle over a hero image).
  final Widget? icon;
  final double? iconSize;

  /// Overrides the item label (profiles say "Report user").
  final String? label;

  const ReportMenuButton({
    super.key,
    required this.targetId,
    required this.type,
    this.icon,
    this.iconSize,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = context.l10n;
    return PopupMenuButton<String>(
      tooltip: s.more,
      icon: icon ??
          Icon(Icons.more_vert,
              size: iconSize, color: scheme.onSurfaceVariant),
      onSelected: (_) => showReportDialog(context, targetId, type),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'report',
          child: Row(
            children: [
              Icon(Icons.flag_outlined, color: scheme.error, size: 20),
              const SizedBox(width: 8),
              Text(label ?? s.report, style: TextStyle(color: scheme.error)),
            ],
          ),
        ),
      ],
    );
  }
}
