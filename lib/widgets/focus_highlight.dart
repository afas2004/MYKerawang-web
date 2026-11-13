import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Wraps the item a notification pointed at (a comment): scrolls it into
/// view once and tints it briefly, so the reader sees exactly what the
/// notification was about. With [focused] false it is just [child].
class FocusHighlight extends StatefulWidget {
  final bool focused;
  final Widget child;
  const FocusHighlight({super.key, required this.focused, required this.child});

  @override
  State<FocusHighlight> createState() => _FocusHighlightState();
}

class _FocusHighlightState extends State<FocusHighlight> {
  bool _tint = false;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _maybeScroll();
  }

  @override
  void didUpdateWidget(FocusHighlight old) {
    super.didUpdateWidget(old);
    _maybeScroll();
  }

  void _maybeScroll() {
    if (!widget.focused || _done) return;
    _done = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      setState(() => _tint = true);
      await Scrollable.ensureVisible(context,
          alignment: 0.3, duration: const Duration(milliseconds: 400), curve: Curves.easeOut);
      await Future.delayed(const Duration(milliseconds: 1800));
      if (mounted) setState(() => _tint = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.focused) return widget.child;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 600),
      decoration: BoxDecoration(
        color: _tint
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .55)
            : Colors.transparent,
        borderRadius: KRadius.input,
      ),
      child: widget.child,
    );
  }
}
