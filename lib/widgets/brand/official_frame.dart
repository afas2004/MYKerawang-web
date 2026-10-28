import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/app_icons.dart';
import '../../theme/tokens.dart';
import 'songket_hem.dart';

/// Marks official / pinned / verified content — the one place the kerawang
/// shape lives in the UI: a songket hem along the top edge, an accent
/// hairline, and the top-right corner cut off (the "kerawang cut"). With a
/// [label] (or [semanticLabel]) an accent label row sits under the hem —
/// e.g. "📌 Pinned", "✓ Official club".
///
/// The accent is the app's one special colour; use this only for content
/// that is genuinely official or pinned.
///
///   OfficialFrame(label: s.pinned, child: PostCard(...))
///   OfficialFrame(enabled: isClub, semanticLabel: roleLabel(...), child: ...)
class OfficialFrame extends StatelessWidget {
  final Widget child;

  /// When false the child is returned untouched (saves call-site ternaries).
  final bool enabled;

  final BorderRadius borderRadius;

  /// Text for the label row. Defaults to [semanticLabel]; no row when both
  /// are null.
  final String? label;

  /// Icon before the label (pin for pinned, [AppIcons.verified] for official).
  final IconData icon;

  /// Read by screen readers; also the default [label].
  final String? semanticLabel;

  /// Unused since the corner ornament was retired; kept for compatibility.
  final Alignment corner;

  /// Size of the cut-off top-right corner.
  final double cornerExtent;

  const OfficialFrame({
    super.key,
    required this.child,
    this.enabled = true,
    this.borderRadius = KRadius.card,
    this.label,
    this.icon = AppIcons.verified,
    this.semanticLabel,
    this.corner = Alignment.topRight,
    this.cornerExtent = 14,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final theme = Theme.of(context);
    final k = KTokens.of(context);
    final text = label ?? semanticLabel;
    final shape = KerawangCutBorder(
      radius: borderRadius.topLeft.x,
      cut: cornerExtent,
      side: BorderSide(color: k.accent.withValues(alpha: 0.75)),
    );

    final framed = DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(shape: shape),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SongketHem(height: 7, color: k.accent),
            if (text != null)
              Container(
                color: k.accent.withValues(alpha: 0.10),
                padding: const EdgeInsets.fromLTRB(
                    KSpace.m, KSpace.xs + 2, KSpace.xl, KSpace.xs + 2),
                child: Row(
                  children: [
                    Icon(icon, size: 14, color: theme.colorScheme.tertiary),
                    const SizedBox(width: KSpace.xs + 2),
                    Flexible(
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: theme.colorScheme.tertiary),
                      ),
                    ),
                  ],
                ),
              ),
            child,
          ],
        ),
      ),
    );

    if (semanticLabel == null) return framed;
    return Semantics(label: semanticLabel, container: true, child: framed);
  }
}

/// A rounded rectangle whose top-right corner is cut off at 45°.
class KerawangCutBorder extends ShapeBorder {
  final double radius;
  final double cut;
  final BorderSide side;

  const KerawangCutBorder({this.radius = 16, this.cut = 14, this.side = BorderSide.none});

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _path(Rect rect) {
    final r = math.min(radius, rect.shortestSide / 2);
    final c = math.min(cut, rect.shortestSide / 2);
    return Path()
      ..moveTo(rect.left + r, rect.top)
      ..lineTo(rect.right - c, rect.top)
      ..lineTo(rect.right, rect.top + c)
      ..lineTo(rect.right, rect.bottom - r)
      ..arcToPoint(Offset(rect.right - r, rect.bottom), radius: Radius.circular(r))
      ..lineTo(rect.left + r, rect.bottom)
      ..arcToPoint(Offset(rect.left, rect.bottom - r), radius: Radius.circular(r))
      ..lineTo(rect.left, rect.top + r)
      ..arcToPoint(Offset(rect.left + r, rect.top), radius: Radius.circular(r))
      ..close();
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _path(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      KerawangCutBorder(radius: radius * t, cut: cut * t, side: side.scale(t));
}
