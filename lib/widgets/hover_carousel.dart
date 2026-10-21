import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme/app_icons.dart';

/// Horizontal carousel with desktop affordances: chevron buttons appear
/// on hover (web only) so mouse users can page through without
/// Shift+scroll or dragging. On touch it behaves like a plain ListView.
class HoverCarousel extends StatefulWidget {
  final double height;
  final int itemCount;
  final EdgeInsets padding;
  final Widget Function(BuildContext, int) itemBuilder;

  const HoverCarousel({
    super.key,
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  State<HoverCarousel> createState() => _HoverCarouselState();
}

class _HoverCarouselState extends State<HoverCarousel> {
  final _controller = ScrollController();
  bool _hovering = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _page(double direction) {
    final target = (_controller.offset + direction * 560)
        .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = ListView.builder(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      padding: widget.padding,
      itemCount: widget.itemCount,
      itemBuilder: widget.itemBuilder,
    );

    if (!kIsWeb) return SizedBox(height: widget.height, child: list);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: SizedBox(
        height: widget.height,
        child: Stack(
          children: [
            list,
            if (_hovering) ...[
              _chevron(context, alignLeft: true),
              _chevron(context, alignLeft: false),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chevron(BuildContext context, {required bool alignLeft}) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned(
      left: alignLeft ? 4 : null,
      right: alignLeft ? null : 4,
      top: 0,
      bottom: 0,
      child: Center(
        child: Material(
          color: scheme.surface,
          // Borders, not shadows (modern foundation).
          shape: CircleBorder(side: BorderSide(color: scheme.outlineVariant)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => _page(alignLeft ? -1 : 1),
            child: Padding(
              padding: const EdgeInsets.all(8),
              // AppIcons has one chevron; mirror it for "previous".
              child: RotatedBox(
                quarterTurns: alignLeft ? 2 : 0,
                child: Icon(AppIcons.chevronRight,
                    size: 24, color: scheme.onSurface),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
