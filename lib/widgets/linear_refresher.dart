import 'package:flutter/material.dart';
import 'package:custom_refresh_indicator/custom_refresh_indicator.dart';

/// The app's one pull-to-refresh: a thin primary-coloured bar instead of
/// the Material spinner. Use this everywhere a list can be refreshed.
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

                final bool isLoading = controller.isLoading || controller.isSettling;
                
                return Positioned(
                  top: offset, 
                  left: 0, 
                  right: 0,
                  child: LinearProgressIndicator(
                    // Show progress while dragging (0% to 100%), then indeterminate when loading
                    value: isLoading ? null : controller.value.clamp(0.0, 1.0),
                    backgroundColor: Colors.transparent,
                    color: Theme.of(context).colorScheme.primary,
                    minHeight: 6, 
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