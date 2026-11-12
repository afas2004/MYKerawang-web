import 'package:flutter/material.dart';

import 'brand/brand.dart';

/// An optional part of a long form, folded to one line until tapped. The
/// line says what is set ("Closes when it starts · No limit · Free"), so
/// most people never need to open it.
///
/// The fields stay mounted while folded, so typing, validation and the
/// unsaved-changes guard keep working. [openSignal] opens it from outside
/// (the form does that when publishing finds a problem inside).
class FoldSection extends StatefulWidget {
  final String title;
  final IconData icon;

  /// The one-line summary, rebuilt whenever [listenTo] changes.
  final String Function() summary;
  final Listenable? listenTo;
  final List<Widget> children;
  final Listenable? openSignal;
  final bool initiallyOpen;

  const FoldSection({
    super.key,
    required this.title,
    required this.icon,
    required this.summary,
    required this.children,
    this.listenTo,
    this.openSignal,
    this.initiallyOpen = false,
  });

  @override
  State<FoldSection> createState() => _FoldSectionState();
}

class _FoldSectionState extends State<FoldSection> {
  late bool _open = widget.initiallyOpen;

  @override
  void initState() {
    super.initState();
    widget.openSignal?.addListener(_openUp);
  }

  @override
  void didUpdateWidget(FoldSection old) {
    super.didUpdateWidget(old);
    if (old.openSignal != widget.openSignal) {
      old.openSignal?.removeListener(_openUp);
      widget.openSignal?.addListener(_openUp);
    }
  }

  @override
  void dispose() {
    widget.openSignal?.removeListener(_openUp);
    super.dispose();
  }

  void _openUp() {
    if (mounted && !_open) setState(() => _open = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final header = Semantics(
      button: true,
      expanded: _open,
      child: InkWell(
        borderRadius: KRadius.input,
        onTap: () => setState(() => _open = !_open),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(widget.icon, size: 20, color: scheme.primary),
              const SizedBox(width: KSpace.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.title,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    if (!_open)
                      ListenableBuilder(
                        listenable: widget.listenTo ?? _noChanges,
                        builder: (context, _) => Text(
                          widget.summary(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                  ],
                ),
              ),
              AnimatedRotation(
                turns: _open ? 0.25 : 0,
                duration: const Duration(milliseconds: 150),
                child: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: KSpace.s),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: KRadius.input,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            // Kept mounted while folded: no lost input, validation still runs.
            Visibility(
              visible: _open,
              maintainState: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.children,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Stands in when a summary has nothing to listen to.
final Listenable _noChanges = ValueNotifier<int>(0);

/// "1. Basics  2. When & where  3. …" as a bar; tap a step to jump to it.
class StepProgress extends StatelessWidget {
  final List<String> steps;
  final int current;
  final ValueChanged<int> onTap;

  const StepProgress({super.key, required this.steps, required this.current, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Semantics(
              button: true,
              selected: i == current,
              child: InkWell(
                key: ValueKey('step-tab-$i'),
                borderRadius: KRadius.small,
                onTap: () => onTap(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: i <= current ? scheme.primary : scheme.outlineVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${i + 1}. ${steps[i]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: i == current ? scheme.primary : scheme.onSurfaceVariant,
                          fontWeight: i == current ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
