import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// True once the theme's web fonts (Plus Jakarta Sans, Fraunces) have loaded.
final fontsLoaded = ValueNotifier<bool>(false);
bool _watching = false;

/// Builds [child] again from new render objects once the web fonts arrive.
///
/// main() waits for the fonts before the first frame (preloadThemeFonts),
/// but gives up after a moment on a slow connection; then they load after
/// the first frame. A chip measures its label once and
/// keeps that size, so a chip row on screen from the start (the Market and
/// Events filters) kept the narrower fallback-font width and the real font
/// spilled past it: the last letter faded out. Rebuilding with a new key
/// measures again with the real font.
class AfterFontsLoad extends StatelessWidget {
  final Widget child;
  const AfterFontsLoad({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!_watching) {
      _watching = true;
      GoogleFonts.pendingFonts().then(
        (_) => fontsLoaded.value = true,
        onError: (_) => fontsLoaded.value = true,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: fontsLoaded,
      builder: (context, loaded, child) =>
          KeyedSubtree(key: ValueKey(loaded), child: child!),
      child: child,
    );
  }
}
