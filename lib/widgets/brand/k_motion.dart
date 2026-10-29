import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// The marigold accent button: one per screen at most, for the action the
/// screen exists for (join an event, contact a seller, sell something).
///
///   FilledButton.icon(style: accentButtonStyle(context), ...)
ButtonStyle accentButtonStyle(BuildContext context, {Size? minimumSize}) {
  final k = KTokens.of(context);
  return FilledButton.styleFrom(
    backgroundColor: k.accent,
    foregroundColor: k.onAccent,
    minimumSize: minimumSize,
  );
}

/// Fades and lifts its child into place once, after [delay] — for the
/// first cards of a list. One controller, no timers, and nothing at all
/// under reduced motion.
///
///   KEntrance(index: i, child: PostCard(...))
class KEntrance extends StatefulWidget {
  final Widget child;

  /// Position in the list; each step adds 60 ms. Items past [maxStaggered]
  /// appear without a delay.
  final int index;
  final int maxStaggered;

  const KEntrance({super.key, required this.child, this.index = 0, this.maxStaggered = 3});

  @override
  State<KEntrance> createState() => _KEntranceState();
}

class _KEntranceState extends State<KEntrance> with SingleTickerProviderStateMixin {
  static const _step = 60;
  static const _run = 380;

  late final int _delay = math.min(widget.index, widget.maxStaggered) * _step;
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _delay + _run),
  );
  late final Animation<double> _t = CurvedAnimation(
    parent: _c,
    curve: Interval(_delay / (_delay + _run), 1, curve: KMotion.enter),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (KMotion.reduced(context)) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _t,
        child: widget.child,
        builder: (context, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, (1 - _t.value) * 10), child: child),
        ),
      );
}

/// A like control's celebration: the icon pops, and six small marigold
/// diamonds — the songket diamond — burst outward when [active] turns on.
/// Static under reduced motion. Paints outside its box without taking
/// layout space, so it never shifts the row it sits in.
class KLikeBurst extends StatefulWidget {
  final bool active;
  final Widget child;
  const KLikeBurst({super.key, required this.active, required this.child});

  @override
  State<KLikeBurst> createState() => _KLikeBurstState();
}

class _KLikeBurstState extends State<KLikeBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 450));

  @override
  void didUpdateWidget(KLikeBurst old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active && !KMotion.reduced(context)) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = KTokens.of(context).accent;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = _c.value;
        // 0.7 → 1.2 → 1.0 over the first 60 %.
        final pop = !_c.isAnimating
            ? 1.0
            : t < 0.3
                ? 0.7 + t / 0.3 * 0.5
                : t < 0.6
                    ? 1.2 - (t - 0.3) / 0.3 * 0.2
                    : 1.0;
        return CustomPaint(
          foregroundPainter: _c.isAnimating ? _BurstPainter(t, color) : null,
          child: Transform.scale(scale: pop, child: child),
        );
      },
    );
  }
}

class _BurstPainter extends CustomPainter {
  final double t;
  final Color color;
  const _BurstPainter(this.t, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final dist = 6 + Curves.easeOut.transform(t) * 16;
    final r = 2.6 * (1 - t * 0.4);
    final paint = Paint()..color = color.withValues(alpha: (1 - t).clamp(0.0, 1.0));
    for (var i = 0; i < 6; i++) {
      final a = -math.pi / 2 + i * math.pi / 3;
      final p = c + Offset(math.cos(a), math.sin(a)) * dist;
      canvas.drawPath(
        Path()
          ..moveTo(p.dx, p.dy - r)
          ..lineTo(p.dx + r, p.dy)
          ..lineTo(p.dx, p.dy + r)
          ..lineTo(p.dx - r, p.dy)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.t != t || old.color != color;
}

/// Switches between two states of an action (Join → Joined, Follow →
/// Following) with a short "stamp": the new state lands from slightly
/// larger, like a stamp on a ticket. Plain swap under reduced motion.
class KStampSwitcher extends StatelessWidget {
  final Widget child;
  const KStampSwitcher({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final motion = KMotion.of(context);
    return AnimatedSwitcher(
      duration: motion.slow,
      switchInCurve: Curves.easeOutBack,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(
          scale: Tween<double>(begin: 1.12, end: 1).animate(anim),
          child: child,
        ),
      ),
      child: child,
    );
  }
}
