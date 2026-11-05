import 'app_strings.dart';

/// Copy for a nav destination whose feature the owner has switched off
/// (admin Settings → App features). The tab stays so the bar keeps its
/// shape; tapping it explains instead of opening the feature.
extension FeatureOffStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  String get comingSoonTitle => _t('Coming soon', 'Akan datang', '近日公開');

  String get comingSoonNewsBody => _t(
      'Official news isn\'t available yet. Check back later.',
      'Berita rasmi belum tersedia lagi. Sila semak semula nanti.',
      '公式ニュースはまだご利用いただけません。後でもう一度ご確認ください。');
}
