import 'app_strings.dart';

/// Copy for Settings → Open-source credits, in the same three languages as
/// [AppStrings].
///
/// Kept beside AppStrings in its own file, the way [AccessStrings] is, so it
/// can land without touching that file; fold it in whenever convenient —
/// call sites (`s.licTitle`) won't change.
extension LicensesStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  String get licTitle => _t(
      "Open-source credits", "Penghargaan sumber terbuka", "オープンソースのクレジット");

  /// Says what the page is for, since the licence texts themselves explain
  /// nothing to a reader who isn't a lawyer.
  String get licIntro => _t(
      "MYKerawang is built on work other people shared for free. The drawings, fonts and code below are theirs, used under the terms shown. Nothing here affects your data or your account.",
      "MYKerawang dibina atas hasil kerja yang dikongsi secara bebas oleh orang lain. Lukisan, fon dan kod di bawah adalah milik mereka, digunakan menurut terma yang dipaparkan. Tiada apa di sini memberi kesan kepada data atau akaun anda.",
      "MYKerawang は、他の人々が無償で公開した成果の上に成り立っています。以下のイラスト、フォント、コードはそれぞれの作者のもので、記載された条件に従って利用しています。あなたのデータやアカウントには影響しません。");

  String get licFilterHint =>
      _t("Search by name", "Cari nama", "名前で検索");

  String get licArt =>
      _t("Artwork and fonts", "Karya seni dan fon", "イラストとフォント");

  /// The CC BY 4.0 drawings must be credited, so they go first instead of
  /// being buried alphabetically among the packages.
  String get licArtNote => _t(
      "Credited by name because their licence asks for it.",
      "Dikreditkan dengan nama kerana lesennya menetapkan begitu.",
      "ライセンスの条件により、名前を明記しています。");

  String get licLibraries =>
      _t("Software libraries", "Pustaka perisian", "ソフトウェアライブラリ");

  String get licLibrariesNote => _t(
      "Grouped by licence. Open a group to see what is inside.",
      "Dikumpulkan mengikut lesen. Buka kumpulan untuk melihat isinya.",
      "ライセンスごとにまとめています。グループを開くと中身が見られます。");

  String get licFullText =>
      _t("Licence text", "Teks lesen", "ライセンス全文");

  String get licNoneTitle =>
      _t("Nothing matches", "Tiada yang sepadan", "一致するものがありません");

  String get licNoneBody => _t(
      "Try part of a name instead.",
      "Cuba sebahagian daripada nama.",
      "名前の一部で試してください。");

  String get licLoadFailed => _t(
      "The credits could not be read.",
      "Penghargaan tidak dapat dibaca.",
      "クレジットを読み込めませんでした。");

  /// Shown as "12 items" under a licence group.
  String licItems(int n) => _t("$n items", "$n item", "$n 件");
}
