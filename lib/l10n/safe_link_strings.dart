import 'app_strings.dart';

/// Copy for safe links (Admin → Allowed links), in the same three languages
/// as [AppStrings]. Kept beside it, like access_strings.dart.
extension SafeLinkStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  String get slTab => _t("Allowed links", "Pautan dibenarkan", "許可リンク");
  String get slIntro => _t(
      "Links in posts, comments and event descriptions can be tapped only when they go to one of these sites (or a subdomain, e.g. student.uitm.edu.my for uitm.edu.my). Every other link stays plain text, which protects students from scam and phishing links.",
      "Pautan dalam hantaran, komen dan penerangan acara boleh ditekan hanya jika ia ke salah satu laman ini (atau subdomainnya, cth. student.uitm.edu.my untuk uitm.edu.my). Pautan lain kekal sebagai teks biasa, untuk melindungi pelajar daripada pautan penipuan dan phishing.",
      "投稿・コメント・イベント説明のリンクは、ここにあるサイト（またはそのサブドメイン。例: uitm.edu.my なら student.uitm.edu.my）へのものだけタップできます。それ以外のリンクは普通の文字のままで、詐欺やフィッシングから学生を守ります。");
  String get slAdd => _t("Add site", "Tambah laman", "サイトを追加");
  String get slFieldLabel => _t("Domain or link", "Domain atau pautan", "ドメインまたはリンク");
  String get slFieldHint => _t("e.g. forms.gle or a pasted link",
      "cth. forms.gle atau tampal pautan", "例: forms.gle、またはリンクを貼り付け");
  String get slNoteLabel => _t("Note (optional)", "Nota (pilihan)", "メモ（任意）");
  String slWillAdd(String d) =>
      _t("Will add: $d", "Akan ditambah: $d", "追加されるもの: $d");
  String get slInvalid => _t("That isn't a valid domain, e.g. forms.gle",
      "Itu bukan domain yang sah, cth. forms.gle", "有効なドメインではありません（例: forms.gle）");
  String slDuplicate(String d) => _t("$d is already on the list",
      "$d sudah ada dalam senarai", "$d はすでにリストにあります");
  String slAdded(String d) => _t("$d added", "$d ditambah", "$d を追加しました");
  String slRemoveTitle(String d) =>
      _t("Remove $d?", "Buang $d?", "$d を削除しますか？");
  String get slRemoveBody => _t(
      "Its links (and its subdomains' links) stop being tappable everywhere. You can add it back any time.",
      "Pautannya (dan pautan subdomainnya) tidak lagi boleh ditekan di mana-mana. Anda boleh tambah semula bila-bila masa.",
      "このサイト（とサブドメイン）のリンクはどこでもタップできなくなります。いつでも追加し直せます。");
  String get slRemove => _t("Remove", "Buang", "削除");
  String slRemoved(String d) => _t("$d removed", "$d dibuang", "$d を削除しました");
  String get slEmpty => _t("No sites yet: no link can be tapped.",
      "Belum ada laman: tiada pautan boleh ditekan.", "サイトがありません。どのリンクもタップできません。");
}
