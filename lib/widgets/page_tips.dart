import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../l10n/page_tips_strings.dart';
import '../language_cubit.dart';
import 'welcome_tour.dart';

/// Page tips: the first time a signed-in person opens a main page, the page
/// dims and one control stays lit, with a short card beside it ("1 of 3").
/// Next moves on, Got it ends, and Skip, Esc or a tap outside the card ends
/// early. A page never shows its tips again for that account (Settings has
/// "Show page tips again").
///
/// Controls are marked with [TipAnchor] and found by id, so a page can point
/// at something another widget builds (the shell's Create button) and a
/// layout that hides a control simply skips that tip.
abstract final class PageTips {
  static const _prefix = 'page_tips_seen:';
  static String _key(String userId, String page) => '$_prefix$userId:$page';

  static bool _open = false;

  /// Whether tips are on screen now (tests).
  static bool get isOpen => _open;

  /// Shows [page]'s tips once per account. [steps] is called when the tips
  /// open, so it can read the page's current state. Returns whether they
  /// opened.
  static Future<bool> maybeShow(
    BuildContext context,
    String page,
    List<TipStep> Function() steps, {
    String? userId,
  }) async {
    final uid = userId ?? _signedInUser();
    if (uid == null ||
        _open ||
        WelcomeTour.isOpen ||
        WelcomeTour.shownThisSession) {
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key(uid, page)) == true) return false;
    if (await WelcomeTour.isPending(uid)) return false;
    // Let the page finish its first layout (and its entrance animation).
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!context.mounted || _open || WelcomeTour.isOpen) return false;
    final list = steps()
        .where((s) => s.before != null || TipAnchor.find(s.anchor) != null)
        .toList();
    if (list.isEmpty) return false;
    // Seen as soon as it opens: closing the app halfway still counts.
    await prefs.setBool(_key(uid, page), true);
    if (!context.mounted) return false;
    await show(context, list);
    return true;
  }

  /// The signed-in user, or null for guests (and before Supabase is set up,
  /// as in widget tests of a single screen).
  static String? _signedInUser() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Opens [steps] now, whatever was seen before.
  static Future<void> show(BuildContext context, List<TipStep> steps) async {
    if (_open || steps.isEmpty) return;
    _open = true;
    try {
      await Navigator.of(context, rootNavigator: true).push(_TipsRoute(steps));
    } finally {
      _open = false;
    }
  }

  /// Settings › Show page tips again: forgets which pages were seen.
  static Future<void> resetAll({String? userId}) async {
    final uid = userId ?? _signedInUser();
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    for (final k
        in prefs
            .getKeys()
            .where((k) => k.startsWith('$_prefix$uid:'))
            .toList()) {
      await prefs.remove(k);
    }
  }

  @visibleForTesting
  static void debugReset() => _open = false;
}

/// One tip: the control to light up ([anchor], a [TipAnchor] id) and the
/// line beside it. [before] runs first (scroll a part into view, move a
/// stepped form to the right step); a tip whose control isn't on screen
/// afterwards is skipped.
class TipStep {
  final String anchor;
  final String text;
  final Future<void> Function()? before;
  const TipStep(this.anchor, this.text, {this.before});
}

/// Marks a control a tip can point at. The last one mounted with an id wins,
/// so the same id can sit on the compact bar and the rail.
class TipAnchor extends StatefulWidget {
  final String id;
  final Widget child;
  const TipAnchor({super.key, required this.id, required this.child});

  static final Map<String, BuildContext> _live = {};

  /// The mounted control for [id], if any.
  static BuildContext? find(String id) {
    final c = _live[id];
    return (c != null && c.mounted) ? c : null;
  }

  /// Scrolls the control for [id] into view (a little below the top).
  static Future<void> reveal(String id) async {
    final c = find(id);
    if (c == null) return;
    await Scrollable.ensureVisible(
      c,
      alignment: 0.12,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  State<TipAnchor> createState() => _TipAnchorState();
}

class _TipAnchorState extends State<TipAnchor> {
  @override
  Widget build(BuildContext context) {
    TipAnchor._live[widget.id] = context;
    return widget.child;
  }

  @override
  void dispose() {
    if (identical(TipAnchor._live[widget.id], context)) {
      TipAnchor._live.remove(widget.id);
    }
    super.dispose();
  }
}

class _TipsRoute extends PopupRoute<void> {
  final List<TipStep> steps;
  _TipsRoute(this.steps);

  @override
  Color? get barrierColor => null;
  @override
  bool get barrierDismissible => false;
  @override
  String? get barrierLabel => null;
  @override
  Duration get transitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> a,
    Animation<double> b,
  ) => _TipsOverlay(steps: steps);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> _,
    Widget child,
  ) => FadeTransition(opacity: animation, child: child);
}

class _TipsOverlay extends StatefulWidget {
  final List<TipStep> steps;
  const _TipsOverlay({required this.steps});

  @override
  State<_TipsOverlay> createState() => _TipsOverlayState();
}

class _TipsOverlayState extends State<_TipsOverlay> {
  int _i = -1;
  bool _moving = true;
  final _next = FocusNode();

  @override
  void initState() {
    super.initState();
    _go(0);
  }

  @override
  void dispose() {
    _next.dispose();
    super.dispose();
  }

  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  /// Moves to the first tip from [from] whose control can be shown.
  Future<void> _go(int from) async {
    setState(() => _moving = true);
    for (var i = from; i < widget.steps.length; i++) {
      final step = widget.steps[i];
      if (step.before != null) await step.before!();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (TipAnchor.find(step.anchor) != null) {
        await TipAnchor.reveal(step.anchor);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        setState(() {
          _i = i;
          _moving = false;
        });
        _next.requestFocus();
        return;
      }
    }
    _close();
  }

  /// The lit control's rectangle, in this overlay's coordinates.
  Rect? _target(BuildContext overlay) {
    if (_i < 0) return null;
    final c = TipAnchor.find(widget.steps[_i].anchor);
    final box = c?.findRenderObject();
    final me = overlay.findRenderObject();
    if (box is! RenderBox || !box.hasSize || me is! RenderBox) return null;
    final topLeft =
        box.localToGlobal(Offset.zero, ancestor: null) -
        me.localToGlobal(Offset.zero);
    return (topLeft & box.size).inflate(6);
  }

  int get _shownCount => widget.steps.length;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final last = _i == widget.steps.length - 1;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) => _close(),
          ),
        },
        child: Material(
          type: MaterialType.transparency,
          child: LayoutBuilder(
            builder: (context, size) {
              final rect = _moving ? null : _target(context);
              return Stack(
                children: [
                  // A tap outside the card ends the tips.
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      child: Semantics(
                        label: s.tipsClose,
                        button: true,
                        child: CustomPaint(painter: _SpotlightPainter(rect)),
                      ),
                    ),
                  ),
                  if (rect != null)
                    _TipCard(
                      area: size.biggest,
                      target: rect,
                      step: _i + 1,
                      total: _shownCount,
                      text: widget.steps[_i].text,
                      last: last,
                      nextFocus: _next,
                      onSkip: _close,
                      onNext: last ? _close : () => _go(_i + 1),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? hole;
  _SpotlightPainter(this.hole);

  @override
  void paint(Canvas canvas, Size size) {
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.62);
    final all = Path()..addRect(Offset.zero & size);
    if (hole == null) {
      canvas.drawPath(all, dim);
      return;
    }
    final r = RRect.fromRectAndRadius(
      hole!,
      Radius.circular(hole!.shortestSide < 64 ? hole!.shortestSide / 2 : 16),
    );
    canvas.drawPath(
      Path.combine(PathOperation.difference, all, Path()..addRRect(r)),
      dim,
    );
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = Colors.white.withValues(alpha: 0.95),
    );
  }

  @override
  bool shouldRepaint(_SpotlightPainter old) => old.hole != hole;
}

class _TipCard extends StatelessWidget {
  final Size area;
  final Rect target;
  final int step;
  final int total;
  final String text;
  final bool last;
  final FocusNode nextFocus;
  final VoidCallback onSkip;
  final VoidCallback onNext;

  const _TipCard({
    required this.area,
    required this.target,
    required this.step,
    required this.total,
    required this.text,
    required this.last,
    required this.nextFocus,
    required this.onSkip,
    required this.onNext,
  });

  static const double _gap = 14;
  static const double _guessHeight = 150;

  @override
  Widget build(BuildContext context) {
    final s = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final width = (area.width - 32).clamp(200.0, 320.0);
    final left = (target.center.dx - width / 2).clamp(
      16.0,
      area.width - width - 16,
    );
    final below =
        area.height - target.bottom >= _guessHeight + _gap + 16 ||
        target.top < _guessHeight + _gap + 16;
    final arrowX = (target.center.dx - left).clamp(20.0, width - 20);

    final card = Container(
      width: width,
      padding: const EdgeInsets.fromLTRB(16, 14, 14, 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var i = 1; i <= total; i++)
                Container(
                  width: i == step ? 16 : 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: BoxDecoration(
                    color: i == step ? scheme.primary : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              const SizedBox(width: 4),
              Text(
                s.tipsStep(step, total),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Semantics(
            liveRegion: true,
            child: Text(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (!last)
                TextButton(
                  key: const ValueKey('tips-skip'),
                  onPressed: onSkip,
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.onSurfaceVariant,
                  ),
                  child: Text(s.tipsSkip),
                ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('tips-next'),
                focusNode: nextFocus,
                onPressed: onNext,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  minimumSize: const Size(64, 44),
                ),
                child: Text(last ? s.tipsGotIt : s.tipsNext),
              ),
            ],
          ),
        ],
      ),
    );

    final arrow = Transform.rotate(
      angle: 0.785398,
      child: Container(
        width: 14,
        height: 14,
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );

    return Positioned(
      left: left,
      top: below ? target.bottom + _gap : null,
      bottom: below ? null : area.height - target.top + _gap,
      // Taps on the card stay on the card.
      child: GestureDetector(
        onTap: () {},
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            card,
            Positioned(
              left: arrowX - 7,
              top: below ? -7 : null,
              bottom: below ? null : -7,
              child: arrow,
            ),
          ],
        ),
      ),
    );
  }
}
