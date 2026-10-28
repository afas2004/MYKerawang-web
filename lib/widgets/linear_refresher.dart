import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';

import 'brand/app_motif.dart';
import '../theme/tokens.dart';

/// The app's one pull-to-refresh: a wau (kite) comes down on its string as
/// you pull, and flies — a gentle bob over a thin bar — while the list
/// reloads. Use this everywhere a list can be refreshed.
class LinearRefresher extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget child;
  final double offset;

  /// Pull distance (px) before a release triggers a refresh.
  final double triggerDistance;

  const LinearRefresher({
    super.key,
    required this.onRefresh,
    required this.child,
    this.offset = 0.0,
    this.triggerDistance = 120.0,
  });

  @override
  Widget build(BuildContext context) {
    return CustomRefreshIndicator(
      onRefresh: onRefresh,
      offsetToArmed: triggerDistance,
      builder: (context, child, controller) {
        return Stack(
          children: [
            child,
            AnimatedBuilder(
              animation: controller,
              builder: (context, _) {
                if (controller.isIdle) return const SizedBox.shrink();
                final loading = controller.isLoading || controller.isSettling;
                final pull = controller.value.clamp(0.0, 1.5);
                return Positioned(
                  top: offset,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Column(
                      children: [
                        LinearProgressIndicator(
                          // Fills while dragging, then indeterminate when loading.
                          value: loading ? null : pull.clamp(0.0, 1.0),
                          backgroundColor: Colors.transparent,
                          color: Theme.of(context).colorScheme.primary,
                          minHeight: 3,
                        ),
                        _Wau(pull: pull, flying: loading),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
      child: child,
    );
  }
}

class _Wau extends StatefulWidget {
  final double pull;
  final bool flying;
  const _Wau({required this.pull, required this.flying});

  @override
  State<_Wau> createState() => _WauState();
}

class _WauState extends State<_Wau> with SingleTickerProviderStateMixin {
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didUpdateWidget(_Wau old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    final fly = widget.flying && !KMotion.reduced(context);
    if (fly && !_bob.isAnimating) _bob.repeat();
    if (!fly && _bob.isAnimating) _bob.stop();
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 34.0;
    final color = Theme.of(context).colorScheme.primary;
    final drop = (widget.flying ? 1.0 : widget.pull.clamp(0.0, 1.0)) * 28;
    return SizedBox(
      height: 70,
      child: AnimatedBuilder(
        animation: _bob,
        builder: (context, _) {
          final phase = _bob.value * 2 * math.pi;
          final bob = widget.flying ? math.sin(phase) * 4 : 0.0;
          final tilt = widget.flying ? math.sin(phase + 1) * 0.12 : (widget.pull - 0.5) * 0.2;
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              // The string, from the bar down to the kite.
              Container(width: 1, height: drop + 4, color: color.withValues(alpha: 0.5)),
              Positioned(
                top: drop + bob,
                child: Opacity(
                  opacity: widget.pull.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: tilt,
                    child: MotifArt(AppMotif.wauBulan, size: size, color: color),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
