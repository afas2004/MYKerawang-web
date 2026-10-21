import 'package:flutter/material.dart';

import 'brand/brand.dart';

/// Layout for the create / edit forms (event, listing): titled sections,
/// a centred card on wide screens, and a publish bar that stays put.

/// Centres the form at a comfortable width. With room (>=900px available)
/// the form sits on a card; on phones it's edge to edge.
class FormPageBody extends StatelessWidget {
  final Widget child;
  const FormPageBody({super.key, required this.child});

  static const double cardFrom = Responsive.desktopBreakpoint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(builder: (context, constraints) {
      final card = constraints.maxWidth >= cardFrom;
      final content = Padding(
        padding: EdgeInsets.all(card ? KSpace.xl : KSpace.l),
        child: child,
      );
      return SingleChildScrollView(
        padding: EdgeInsets.symmetric(vertical: card ? KSpace.xl : 0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: card
                ? Container(
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: KRadius.card,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: content,
                  )
                : content,
          ),
        ),
      );
    });
  }
}

/// A titled group of fields ("Photos", "Details", "When & where").
class FormSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const FormSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Row(
              children: [
                Icon(icon, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(width: 12),
                Expanded(child: Divider(color: scheme.outlineVariant)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

/// Bottom bar with the submit button, kept above the keyboard and centred
/// to the form width.
class PublishBar extends StatelessWidget {
  final bool busy;
  final bool editing;
  final String label;
  final String busyLabel;
  final VoidCallback onPressed;

  const PublishBar({
    super.key,
    required this.busy,
    required this.editing,
    required this.label,
    required this.busyLabel,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.all(16),
      child: SafeArea(
        top: false,
        // heightFactor: 1 — a plain Center as Scaffold.bottomNavigationBar
        // grows to the whole screen and hides the form and the app bar.
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: FilledButton.icon(
              onPressed: busy ? null : onPressed,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary))
                  : Icon(editing ? AppIcons.check : AppIcons.send),
              label: Text(busy ? busyLabel : label),
            ),
          ),
        ),
      ),
    );
  }
}
