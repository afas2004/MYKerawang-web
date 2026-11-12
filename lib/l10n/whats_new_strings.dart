import 'app_strings.dart';

/// Copy around the release notes: the pop-up after an update, the
/// Settings page and the owner's Updates tab. The notes themselves live
/// in lib/services/whats_new_notes.dart.
extension WhatsNewStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  // Pop-up.
  String whatsNewIn(String version) =>
      _t("What's new in $version", 'Apa yang baharu dalam $version', '$version の新機能');
  String get whatsNewGotIt => _t('Got it', 'Baik', 'OK');
  String get whatsNewSeeAll => _t('See all updates', 'Lihat semua kemas kini', 'すべての更新を見る');

  // Settings tile and page.
  String get whatsNewTitle => _t("What's new", 'Apa yang baharu', '新機能');
  String get whatsNewSub => _t('Updates so far', 'Kemas kini setakat ini', 'これまでの更新');
  String get whatsNewCurrent => _t('You have this one', 'Versi awak sekarang', 'ご利用中のバージョン');

  // Owner tab.
  String get whatsNewAdminTab => _t('Updates', 'Kemas kini', '更新');
  String get whatsNewAdminHint => _t(
      'Share a release with everyone: open it as a new post, or post and pin it in one go. Posts are written in English and Malay.',
      'Kongsi kemas kini dengan semua: buka sebagai hantaran baharu, atau siar dan pin terus. Hantaran ditulis dalam Bahasa Inggeris dan Melayu.',
      'リリースをみんなに共有:新しい投稿として開くか、投稿してそのままピン留めします。投稿は英語とマレー語で書かれます。');
  String get whatsNewAdminPost => _t('New post', 'Hantaran baharu', '新規投稿');
  String get whatsNewAdminPin => _t('Post and pin', 'Siar dan pin', '投稿してピン留め');
  String whatsNewAdminConfirm(String version) => _t(
      'Post the $version notes as you and pin them to the top of Home?',
      'Siarkan nota $version atas nama awak dan pin di atas Laman Utama?',
      '$version のお知らせをあなたの名前で投稿し、ホームの上部にピン留めしますか?');
  String get whatsNewAdminPosted => _t('Posted', 'Sudah disiarkan', '投稿しました');
}
