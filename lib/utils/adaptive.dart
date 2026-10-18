import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../theme/app_themes.dart';
import 'responsive.dart';

/// Desktop breakpoint used for interaction patterns (not just layout).
bool isWide(BuildContext context) => Responsive.isDesktop(context);

/// Can this device realistically take a photo?
///
/// `kIsWeb` alone was too blunt: a PWA on a phone *does* have a camera
/// (image_picker uses an `accept`/`capture` file input), so hiding the
/// option there removed a real capability. Desktop browsers are the case
/// that genuinely can't.
bool canUseCamera(BuildContext context) {
  if (!kIsWeb) return true; // native Android/iOS
  final size = MediaQuery.sizeOf(context);
  // phone/tablet-sized viewport
  final touch = size.shortestSide < Responsive.desktopBreakpoint;
  return touch;
}

/// An AppBar whose *contents* line up with the centred content column
/// instead of hugging the far edges of a wide window (UI_UX_AUDIT G1).
PreferredSizeWidget appBarConstrained(
  BuildContext context, {
  Widget? title,
  List<Widget>? actions,
  Widget? leading,
  double maxWidth = Responsive.feedMaxWidth,
  bool centerTitle = false,
}) {
  final bar = AppBar(
    title: title,
    actions: actions,
    leading: leading,
    centerTitle: centerTitle,
  );

  if (!isWide(context)) return bar;

  return PreferredSize(
    preferredSize: bar.preferredSize,
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: bar,
      ),
    ),
  );
}

/// Keeps a persistent bottom action bar aligned with the content column
/// instead of stretching a stripe across the whole window (G3).
Widget bottomBarConstrained(BuildContext context, Widget child) {
  if (!isWide(context)) return child;
  // heightFactor: 1 is essential — without it Align expands to fill the
  // whole viewport and the bottom sheet covers the entire page.
  return Align(
    alignment: Alignment.bottomCenter,
    heightFactor: 1,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: Responsive.feedMaxWidth),
      child: child,
    ),
  );
}

/// Bottom sheet on touch, centred dialog on desktop (G2).
/// Desktop browsers have no "swipe up from the bottom" affordance, so a
/// sheet that slides across a 1400px window reads as a phone artefact.
Future<T?> showAdaptiveSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  double dialogMaxWidth = 460,
}) {
  if (isWide(context)) {
    return showDialog<T>(
      context: context,
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        shape: const RoundedRectangleBorder(borderRadius: kerawangCut),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: dialogMaxWidth),
          child: SingleChildScrollView(child: builder(ctx)),
        ),
      ),
    );
  }

  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    builder: builder,
  );
}
