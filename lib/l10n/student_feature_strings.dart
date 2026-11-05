import 'app_strings.dart';

/// Copy for the "student features" owner switch. Its own file so it can
/// land beside the announcements and clubs switch work without touching
/// the same lines of access_strings.dart.
extension StudentFeatureStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  /// Shown under the switch while student features are off but the
  /// database still asks for student emails or verified students.
  String get featureStudentOffHint => _t(
      "Student features are off, so the app no longer mentions student emails or verification. The database still enforces both: also turn on \"Allow any email to sign up\" and turn off \"Require verified students\" below, or new members will be refused and unverified ones blocked.",
      "Ciri pelajar dimatikan, jadi aplikasi tidak lagi menyebut e-mel pelajar atau pengesahan. Pangkalan data masih menguatkuasakan kedua-duanya: hidupkan juga \"Benarkan daftar dengan mana-mana e-mel\" dan matikan \"Wajibkan pelajar disahkan\" di bawah, atau ahli baharu akan ditolak dan yang belum disahkan akan disekat.",
      "学生向け機能はオフのため、アプリは学生メールや学生確認に触れません。ただしデータベースは引き続き両方を適用します。下で登録を開放し、「学生確認を必須にする」をオフにしてください。");
}
