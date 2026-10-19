import 'package:flutter/material.dart';
import '../widgets/report_sheet.dart';
import '../language_cubit.dart';

/// Opens the report sheet (categories, duplicate / own-content
/// feedback): see widgets/report_sheet.dart.
Future<void> showReportDialog(BuildContext context, String targetId, String type) =>
    showReportSheet(context, targetId, type);

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
