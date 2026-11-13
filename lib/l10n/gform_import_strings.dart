import 'app_strings.dart';

/// Copy for "Import from Google Form" (lib/widgets/google_form_import.dart).
extension GoogleFormImportStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  String get gfImport => _t("Import from Google Form", "Import dari Google Form",
      "Googleフォームから取り込む");
  String get gfImportSub => _t(
      "Paste a Google Form link to copy its questions.",
      "Tampal pautan Google Form untuk menyalin soalannya.",
      "Googleフォームのリンクを貼り付けて質問をコピーします。");
  String get gfLinkLabel => _t("Google Form link", "Pautan Google Form", "Googleフォームのリンク");
  String get gfLinkHint => "https://forms.gle/…";
  String get gfFetch => _t("Get questions", "Dapatkan soalan", "質問を取得");
  String get gfFetching => _t("Reading the form…", "Membaca borang…", "フォームを読み込み中…");
  String get gfBadLink => _t(
      "That isn't a Google Form link. It should start with forms.gle/ or docs.google.com/forms/.",
      "Itu bukan pautan Google Form. Ia sepatutnya bermula dengan forms.gle/ atau docs.google.com/forms/.",
      "Googleフォームのリンクではありません。forms.gle/ または docs.google.com/forms/ で始まるリンクを使ってください。");
  String get gfTitleHint => _t(
      "This form had no title. Give it one.",
      "Borang ini tiada tajuk. Berikan satu.",
      "このフォームには題名がありません。付けてください。");
  String gfQuestions(int n) => _t(
      n == 1 ? "1 question" : "$n questions",
      "$n soalan",
      "$n 問");
  String get gfCreate => _t("Create form", "Cipta borang", "フォームを作成");
  String get gfTryAnother => _t("Try another link", "Cuba pautan lain", "別のリンクを試す");
  String get gfEmpty => _t(
      "No questions could be copied from this form.",
      "Tiada soalan yang dapat disalin daripada borang ini.",
      "このフォームからコピーできる質問がありません。");
  String get gfDraftNote => _t(
      "It's saved as a draft. Check it in the editor, then publish.",
      "Ia disimpan sebagai draf. Semak dalam editor, kemudian terbitkan.",
      "下書きとして保存されます。エディターで確認してから公開してください。");
  String get gfCreatedDraft => _t(
      "Form created as a draft. Publish it before people can answer.",
      "Borang dicipta sebagai draf. Terbitkan sebelum orang boleh menjawab.",
      "下書きとして作成しました。回答を受け付けるには公開してください。");
  String get gfEdit => _t("Edit", "Sunting", "編集");
  String get gfIntro => _t("Description", "Penerangan", "説明");

  // ---- notes ----
  String get gfSkippedTitle => _t("Not imported", "Tidak diimport", "取り込まれなかった項目");
  String get gfChangedTitle => _t("Changed a little", "Sedikit berubah", "少し変更された項目");
  String gfNote(String code) => switch (code) {
        'grid' => _t("Grid questions aren't supported.", "Soalan grid tidak disokong.",
            "グリッド形式の質問は使えません。"),
        'file' => _t("File uploads aren't supported.", "Muat naik fail tidak disokong.",
            "ファイルのアップロードは使えません。"),
        'image' => _t("Images aren't copied.", "Gambar tidak disalin.", "画像はコピーされません。"),
        'video' => _t("Videos aren't copied.", "Video tidak disalin.", "動画はコピーされません。"),
        'blocked' => _t(
            "Asks for a password, PIN or card number — not allowed on MYKerawang forms.",
            "Meminta kata laluan, PIN atau nombor kad — tidak dibenarkan dalam borang MYKerawang.",
            "パスワード・PIN・カード番号を尋ねる質問は使えません。"),
        'too_many' => _t("Over the 40-question limit.", "Melebihi had 40 soalan.",
            "40問の上限を超えています。"),
        'time' => _t("Time question: becomes short text (e.g. 14:30).",
            "Soalan masa: menjadi teks pendek (cth. 14:30).", "時刻の質問：短い文章になります（例 14:30）。"),
        'other' => _t("\"Other\" becomes a plain choice, without a text box.",
            "\"Lain-lain\" menjadi pilihan biasa, tanpa kotak teks.",
            "「その他」は記入欄のない普通の選択肢になります。"),
        'scale_as_choice' => _t("Scale outside 1–10: becomes numbered choices.",
            "Skala di luar 1–10: menjadi pilihan bernombor.", "1〜10以外の目盛り：番号の選択肢になります。"),
        'trimmed' => _t("Shortened to fit.", "Dipendekkan supaya muat.", "長すぎるため短くしました。"),
        'one_choice' => _t("Only one option: becomes a tick-to-agree box.",
            "Hanya satu pilihan: menjadi kotak tanda setuju.", "選択肢が1つ：同意のチェックになります。"),
        'picture_choices' => _t("Picture-only options aren't copied.",
            "Pilihan bergambar sahaja tidak disalin.", "画像だけの選択肢はコピーされません。"),
        'branching' => _t(
            "\"Go to section based on answer\" isn't supported: everyone sees every question.",
            "\"Pergi ke bahagian berdasarkan jawapan\" tidak disokong: semua orang melihat semua soalan.",
            "回答による「セクションへ移動」は使えません。全員がすべての質問を見ます。"),
        'no_choices' => _t("No usable options: becomes short text.",
            "Tiada pilihan yang boleh digunakan: menjadi teks pendek.", "選択肢がないため短い文章になります。"),
        _ => _t("This item type isn't supported.", "Jenis item ini tidak disokong.",
            "この種類の項目は使えません。"),
      };

  /// Why the server could not read the form.
  String gfFailed(String? reason) => switch (reason) {
        'sign_in' => _t(
            "This form needs a Google sign-in (for example, only UiTM accounts), so it can't be read. "
                "Ask the owner to turn off \"Restrict to users\" in the form's settings, or copy the questions by hand.",
            "Borang ini memerlukan log masuk Google (contohnya hanya akaun UiTM), jadi ia tidak dapat dibaca. "
                "Minta pemilik matikan \"Hadkan kepada pengguna\" dalam tetapan borang, atau salin soalan secara manual.",
            "このフォームはGoogleへのログインが必要なため読み込めません（例：UiTMアカウント限定）。"
                "所有者に「ユーザーを制限」をオフにしてもらうか、質問を手で写してください。"),
        'closed' => _t(
            "This form is closed and no longer shows its questions.",
            "Borang ini telah ditutup dan tidak lagi menunjukkan soalannya.",
            "このフォームは締め切られていて、質問が表示されません。"),
        'not_found' => _t(
            "No form at that link. Check it's copied in full.",
            "Tiada borang pada pautan itu. Pastikan ia disalin sepenuhnya.",
            "そのリンクにフォームがありません。リンク全体をコピーしたか確認してください。"),
        'rate_limited' => _t(
            "Too many imports for now. Try again in a few minutes.",
            "Terlalu banyak import buat masa ini. Cuba lagi dalam beberapa minit.",
            "取り込みが多すぎます。数分後にもう一度お試しください。"),
        'bad_url' => gfBadLink,
        'unavailable' => _t(
            "Importing isn't switched on yet. Please try again later.",
            "Import belum diaktifkan. Sila cuba lagi kemudian.",
            "取り込み機能はまだ有効ではありません。後でもう一度お試しください。"),
        'too_big' => _t(
            "This form is too large to import.",
            "Borang ini terlalu besar untuk diimport.",
            "このフォームは大きすぎて取り込めません。"),
        _ => _t(
            "Couldn't read that form. Check the link opens without signing in, then try again.",
            "Tidak dapat membaca borang itu. Pastikan pautan dibuka tanpa log masuk, kemudian cuba lagi.",
            "フォームを読み込めませんでした。ログインなしで開けるか確認して、もう一度お試しください。"),
      };

  // ---- composer hint ----
  String get gfSuggest => _t(
      "Turn this Google Form into a MYKerawang form?",
      "Tukar Google Form ini kepada borang MYKerawang?",
      "このGoogleフォームをMYKerawangのフォームにしますか？");
  String get gfSuggestSub => _t(
      "Answers then stay in the app, and people answer without leaving it.",
      "Jawapan kekal dalam aplikasi, dan orang menjawab tanpa keluar.",
      "回答がアプリ内に残り、アプリから離れずに答えられます。");
  String get gfSuggestAction => _t("Import", "Import", "取り込む");
  String get gfSuggestDismiss => _t("Not now", "Bukan sekarang", "今はしない");
}
