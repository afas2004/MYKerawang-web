import 'package:flutter/material.dart';

import '../utils/responsive.dart';
import '../widgets/brand/k_ground.dart';
import 'tokens.dart';

/// Page transitions for every route, via `pageTransitionsTheme`. With
/// reduced motion every change is an instant cut.
///
/// - **Desktop (≥ 900)**: the route itself doesn't move. Pages keep the
///   sidebar still and fade only their content ([RouteContentFade], used
///   by DesktopChrome and the tab shell), so a push no longer flashes and
///   regrows the whole window.
/// - **Phone / tablet**: a pushed page slides in from the right over the
///   one below, which drifts left; a full-screen dialog (create / edit
///   forms) rises from the bottom. iOS gets the native Cupertino slide,
///   with its swipe-back.
///
/// Pages are transparent (one ground behind the router), so a page that
/// moves over another carries its own [KGround]; otherwise both would show.
class AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const AppPageTransitionsBuilder();

  static const _cupertino = CupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (KMotion.reduced(context)) return child;
    if (Responsive.isDesktop(context)) {
      return _RouteMotion(
        animation: animation,
        secondaryAnimation: secondaryAnimation,
        child: child,
      );
    }
    final page = KGround(child: child);
    if (Theme.of(context).platform == TargetPlatform.iOS) {
      return _cupertino.buildTransitions(
          route, context, animation, secondaryAnimation, page);
    }
    if (route.fullscreenDialog) {
      return SlideTransition(position: animation.drive(_rise), child: page);
    }
    return SlideTransition(
      position: secondaryAnimation.drive(_drift),
      child: SlideTransition(position: animation.drive(_slideIn), child: page),
    );
  }

  static final _slideIn = Tween(begin: const Offset(1, 0), end: Offset.zero)
      .chain(CurveTween(curve: KMotion.enter));
  static final _drift = Tween(begin: Offset.zero, end: const Offset(-0.25, 0))
      .chain(CurveTween(curve: KMotion.enter));
  static final _rise = Tween(begin: const Offset(0, 1), end: Offset.zero)
      .chain(CurveTween(curve: KMotion.enter));
}

/// The route's animations, handed down to [RouteContentFade] on desktop.
class _RouteMotion extends InheritedWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;

  const _RouteMotion({
    required this.animation,
    required this.secondaryAnimation,
    required super.child,
  });

  @override
  bool updateShouldNotify(_RouteMotion old) =>
      animation != old.animation || secondaryAnimation != old.secondaryAnimation;
}

/// Fade-through for the part of a page that changes: the page being left
/// fades out in the first 30% of the route, then the new one fades in.
/// On desktop this wraps the content beside the sidebar; a page with no
/// sidebar wraps itself. Does nothing on phones (the route slides).
class RouteContentFade extends StatelessWidget {
  final Widget child;
  const RouteContentFade({super.key, required this.child});

  static final _in =
      CurveTween(curve: const Interval(0.3, 0.85, curve: KMotion.enter));
  static final _out = Tween<double>(begin: 1, end: 0)
      .chain(CurveTween(curve: const Interval(0, 0.3, curve: KMotion.exit)));

  @override
  Widget build(BuildContext context) {
    final motion = context.dependOnInheritedWidgetOfExactType<_RouteMotion>();
    if (motion == null) return child;
    return FadeTransition(
      opacity: motion.secondaryAnimation.drive(_out),
      child: FadeTransition(opacity: motion.animation.drive(_in), child: child),
    );
  }
}
