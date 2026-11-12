import 'package:flutter/material.dart';

import '../l10n/page_tips_strings.dart';
import '../language_cubit.dart';

/// A small (i) next to a field label. Tapping it shows a dark bubble with
/// the field's limits or how to use it; tapping anywhere closes it.
class InfoTip extends StatelessWidget {
  final String message;
  const InfoTip(this.message, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: message,
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 12),
      enableTapToDismiss: true,
      preferBelow: true,
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      textStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 13,
        height: 1.45,
      ),
      child: Semantics(
        button: true,
        label: '${context.l10n.infoMore}: $message',
        excludeSemantics: true,
        // 32px hit area around a 16px icon.
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            Icons.info_outline,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// A field label with an (i) after it.
class LabelWithInfo extends StatelessWidget {
  final String text;
  final String? info;
  final TextStyle? style;
  const LabelWithInfo(this.text, {super.key, this.info, this.style});

  @override
  Widget build(BuildContext context) {
    final label = Text(text, style: style);
    if (info == null) return label;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: label),
        Transform.translate(offset: const Offset(-2, 0), child: InfoTip(info!)),
      ],
    );
  }
}
