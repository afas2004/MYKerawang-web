import 'package:flutter/material.dart';

import 'tokens.dart';

/// Fade-through page transition: the old page fades out, then the new one
/// fades in while settling from 96% scale. Used for every route via
/// `pageTransitionsTheme`. With reduced motion it's an instant cut.
///
/// Routes run for ~300 ms; the visible motion is squeezed into the first
/// ~250 ms (see the shared motion rule, 150–250 ms).
class FadeThroughPageTransitionsBuilder extends PageTransitionsBuilder {
  const FadeThroughPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (KMotion.reduced(context)) return child;
    return _FadeThrough(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _FadeThrough extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const _FadeThrough({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  // Incoming: fade in over 30%→85% of the route, scale 0.96→1.
  static final _inFade =
      CurveTween(curve: const Interval(0.3, 0.85, curve: KMotion.enter));
  static final _inScale = Tween<double>(begin: 0.96, end: 1)
      .chain(CurveTween(curve: const Interval(0.3, 0.85, curve: KMotion.enter)));
  // Outgoing (this page covered by the next one): fade out in the first 30%.
  static final _outFade = Tween<double>(begin: 1, end: 0)
      .chain(CurveTween(curve: const Interval(0, 0.3, curve: KMotion.exit)));

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _outFade.animate(secondaryAnimation),
      child: FadeTransition(
        opacity: _inFade.animate(animation),
        child: ScaleTransition(
          scale: _inScale.animate(animation),
          child: child,
        ),
      ),
    );
  }
}
