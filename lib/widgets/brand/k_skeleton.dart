import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// Loading placeholder with a soft shimmer sweep (static under reduced
/// motion). Use instead of a spinner wherever the content's shape is known.
///
/// Skeletons are hidden from screen readers; announce loading once on the
/// container (e.g. `Semantics(label: s.loading, liveRegion: true, ...)`).
///
///   const KSkeleton(width: 120, height: 14)
///   const KSkeleton.circle(size: 40)
///   KSkeleton.lines(3)
class KSkeleton extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const KSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = KRadius.small,
  });

  /// Avatar placeholder.
  const KSkeleton.circle({super.key, double size = 40})
      : width = size,
        height = size,
        borderRadius = const BorderRadius.all(Radius.circular(999));

  /// A paragraph: [count] text lines, the last one shorter.
  static Widget lines(int count,
      {double lineHeight = 12, double lastLineFraction = 0.6}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(height: KSpace.s),
          FractionallySizedBox(
            widthFactor: i == count - 1 ? lastLineFraction : 1,
            child: KSkeleton(height: lineHeight),
          ),
        ],
      ],
    );
  }

  @override
  State<KSkeleton> createState() => _KSkeletonState();
}

class _KSkeletonState extends State<KSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (KMotion.reduced(context)) {
      _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = KTokens.of(context);
    final box = SizedBox(width: widget.width, height: widget.height);

    if (KMotion.reduced(context)) {
      return ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: k.skeletonBase,
            borderRadius: widget.borderRadius,
          ),
          child: box,
        ),
      );
    }

    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _sweep,
          builder: (context, child) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              gradient: LinearGradient(
                colors: [k.skeletonBase, k.skeletonHighlight, k.skeletonBase],
                stops: const [0.35, 0.5, 0.65],
                transform: _Slide(_sweep.value),
              ),
            ),
            child: child,
          ),
          child: box,
        ),
      ),
    );
  }
}

/// Moves the highlight band from off the left edge to off the right.
class _Slide extends GradientTransform {
  final double t;
  const _Slide(this.t);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * (t * 2 - 1), 0, 0);
}
