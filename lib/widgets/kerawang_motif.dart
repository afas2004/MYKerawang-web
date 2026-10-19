import 'package:flutter/material.dart';

/// **Deprecated — renders nothing.** The diamond ornament was part of the
/// retired kerawang motif. Kept so existing call sites compile; remove
/// usages when you next touch a screen.
class KerawangDivider extends StatelessWidget {
  final double size;
  final Color? color;

  const KerawangDivider({super.key, this.size = 8, this.color});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
