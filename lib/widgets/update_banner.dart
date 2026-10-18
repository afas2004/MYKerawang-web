import 'package:flutter/material.dart';

import '../language_cubit.dart';
import '../services/update_service.dart';

/// Floats a "new version" pill over every route once [UpdateService] sees a
/// newer deploy. Tapping Update drops stale caches and reloads.
class UpdateBanner extends StatefulWidget {
  final Widget child;
  const UpdateBanner({super.key, required this.child});

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> {
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Stack(
      children: [
        widget.child,
        ValueListenableBuilder<bool>(
          valueListenable: UpdateService.instance.updateAvailable,
          builder: (context, available, _) {
            if (!available || _dismissed) return const SizedBox.shrink();
            return Positioned(
              left: 12,
              right: 12,
              top: MediaQuery.paddingOf(context).top + 8,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Material(
                    elevation: 6,
                    color: cs.inverseSurface,
                    borderRadius: BorderRadius.circular(14),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                      child: Row(
                        children: [
                          Icon(Icons.system_update, color: cs.onInverseSurface, size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(context.l10n.updateAvailable,
                                style: TextStyle(color: cs.onInverseSurface)),
                          ),
                          TextButton(
                            onPressed: UpdateService.instance.applyUpdate,
                            style: TextButton.styleFrom(foregroundColor: cs.inversePrimary),
                            child: Text(context.l10n.updateNow,
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, size: 18, color: cs.onInverseSurface),
                            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                            onPressed: () => setState(() => _dismissed = true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
