import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_svg/flutter_svg.dart';

/// The app's spot illustrations (unDraw, see assets/illustrations/LICENSE.md).
enum AppIllo {
  emptyFeed('empty_feed'),
  emptyMarket('empty_market'),
  noEvents('no_events'),
  noNotifications('no_notifications'),
  noResults('no_results'),
  welcome('welcome'),
  login('login'),
  offline('offline');

  final String file;
  const AppIllo(this.file);

  String get asset => 'assets/illustrations/$file.svg';
}

/// A theme-tinted illustration: unDraw's purple accent becomes the theme
/// primary, and on dark themes the ink/grey tones are remapped so the art
/// stays readable on near-black.
///
///   AppIllustration(AppIllo.emptyFeed, size: 180)
///
/// Decorative by default (hidden from screen readers); pass
/// [semanticLabel] when the picture itself carries meaning.
class AppIllustration extends StatelessWidget {
  final AppIllo illo;

  /// Width; height follows the art's aspect ratio (max [size] too).
  final double size;
  final String? semanticLabel;

  const AppIllustration(this.illo, {super.key, this.size = 180, this.semanticLabel});

  static final Map<AppIllo, Future<String>> _cache = {};

  static Future<String> _load(AppIllo illo) =>
      _cache.putIfAbsent(illo, () => rootBundle.loadString(illo.asset));

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  /// Rewrites unDraw's palette for the current theme.
  static String recolor(String svg, ColorScheme scheme) {
    final map = <String, String>{
      '#6c63ff': _hex(scheme.primary),
    };
    if (scheme.brightness == Brightness.dark) {
      final ink = _hex(Color.alphaBlend(
          scheme.onSurface.withValues(alpha: 0.82), scheme.surface));
      final grey = _hex(scheme.surfaceContainerHighest);
      final greyStrong = _hex(scheme.outlineVariant);
      for (final c in ['#090814', '#2f2e41', '#2f2e43', '#3f3d56', '#707070']) {
        map[c] = ink;
      }
      for (final c in ['#f2f2f2', '#f0f0f0', '#e6e6e6', '#ffffff', '#fff']) {
        map[c] = grey;
      }
      map['#d6d6e3'] = greyStrong;
      map['#ccc'] = greyStrong;
    }
    return svg.replaceAllMapped(
      RegExp(r'#[0-9a-fA-F]{6}\b|#fff\b|#ccc\b', caseSensitive: false),
      (m) => map[m.group(0)!.toLowerCase()] ?? m.group(0)!,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: FutureBuilder<String>(
        future: _load(illo),
        builder: (context, snap) {
          if (!snap.hasData) return const SizedBox.shrink();
          return SvgPicture.string(
            recolor(snap.data!, scheme),
            width: size,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: semanticLabel == null,
            semanticsLabel: semanticLabel,
          );
        },
      ),
    );
  }
}
