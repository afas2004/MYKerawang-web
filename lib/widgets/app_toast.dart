import 'dart:async';

import 'package:flutter/material.dart';

import 'brand/brand.dart';

/// One message on screen.
class _Toast {
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool error;
  const _Toast(this.message, this.actionLabel, this.onAction, this.error);
}

final ValueNotifier<_Toast?> _current = ValueNotifier(null);
Timer? _timer;

/// True while an [AppToastHost] is on screen. Without one (most widget
/// tests) nothing is shown and no timer is left running.
bool _hosted = false;

void _clear() {
  _timer?.cancel();
  _timer = null;
  _current.value = null;
}

/// Shows a short pop-up above the bottom navigation. It always goes away by
/// itself, a new one replaces the old one, and it needs no context, so it is
/// safe after an await. Replaces every SnackBar in the app.
void showToast(
  String message, {
  String? actionLabel,
  VoidCallback? onAction,
  bool error = false,
  Duration? duration,
}) {
  _timer?.cancel();
  _current.value = _Toast(message, actionLabel, onAction, error);
  if (!_hosted) return;
  final ms = duration ?? Duration(seconds: onAction != null ? 6 : 4);
  _timer = Timer(ms, _clear);
}

/// Sits above every route (see `MaterialApp.builder`) and draws the toast.
class AppToastHost extends StatefulWidget {
  final Widget child;
  const AppToastHost({super.key, required this.child});

  @override
  State<AppToastHost> createState() => _AppToastHostState();
}

class _AppToastHostState extends State<AppToastHost> {
  @override
  void initState() {
    super.initState();
    _hosted = true;
  }

  @override
  void dispose() {
    _hosted = false;
    _clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        Positioned(
          left: KSpace.l,
          right: KSpace.l,
          // Clears the phone's bottom navigation.
          bottom: MediaQuery.paddingOf(context).bottom + (desktop ? KSpace.xl : 88),
          child: ValueListenableBuilder<_Toast?>(
            valueListenable: _current,
            builder: (context, toast, _) => AnimatedSwitcher(
              duration: KMotion.of(context).fast,
              child: toast == null
                  ? const SizedBox.shrink()
                  : _ToastCard(key: ObjectKey(toast), toast: toast),
            ),
          ),
        ),
      ],
    );
  }
}

class _ToastCard extends StatelessWidget {
  final _Toast toast;
  const _ToastCard({super.key, required this.toast});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final bg = toast.error ? scheme.errorContainer : scheme.inverseSurface;
    final fg = toast.error ? scheme.onErrorContainer : scheme.onInverseSurface;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Semantics(
          liveRegion: true,
          child: Material(
            color: bg,
            elevation: 4,
            borderRadius: KRadius.card,
            child: Padding(
              padding: const EdgeInsets.only(left: KSpace.l, right: KSpace.xs),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: KSpace.s),
                        child: Text(toast.message,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(color: fg)),
                      ),
                    ),
                    if (toast.actionLabel != null)
                      TextButton(
                        style: TextButton.styleFrom(foregroundColor: fg),
                        onPressed: () {
                          _clear();
                          toast.onAction?.call();
                        },
                        child: Text(toast.actionLabel!,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    // No tooltip: the host sits above the Navigator, so
                    // there is no Overlay for one to attach to.
                    Semantics(
                      label: MaterialLocalizations.of(context).closeButtonLabel,
                      child: IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: Icon(AppIcons.close, size: 16, color: fg),
                        onPressed: _clear,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
