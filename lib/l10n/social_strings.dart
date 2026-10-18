import 'app_strings.dart';

/// Copy for profile, notifications, search and onboarding added after the
/// main [AppStrings] table. Kept in its own file so parallel work on
/// app_strings.dart doesn't collide; fold it in when convenient.
///
/// Usage: `context.l10n.social.markAllRead`.
class SocialStrings {
  // Edit profile — username rename
  final String usernameSavedOnSave;
  final String usernameChangeTitle;
  final String usernameChangeBody;
  final String usernameChangeConfirm;

  // Notifications
  final String markAllRead;
  final String someone;

  // WhatsApp number (optional at onboarding, required to sell)
  final String whatsappOptionalHelper;
  final String whatsappNeededTitle;
  final String whatsappNeededBody;

  const SocialStrings({
    required this.usernameSavedOnSave,
    required this.usernameChangeTitle,
    required this.usernameChangeBody,
    required this.usernameChangeConfirm,
    required this.markAllRead,
    required this.someone,
    required this.whatsappOptionalHelper,
    required this.whatsappNeededTitle,
    required this.whatsappNeededBody,
  });

  static const en = SocialStrings(
    usernameSavedOnSave: "Letters, numbers and _ only. Saved when you tap Save changes.",
    usernameChangeTitle: "Change username?",
    usernameChangeBody:
        "You'll go from @{0} to @{1}. Existing @{0} mentions in posts and comments won't link to you any more, and someone else could take @{0}.",
    usernameChangeConfirm: "Change username",
    markAllRead: "Mark all as read",
    someone: "Someone",
    whatsappOptionalHelper: "Optional — you'll need it to sell in the Market",
    whatsappNeededTitle: "Add your WhatsApp number",
    whatsappNeededBody:
        "Buyers contact sellers on WhatsApp. Add your number in Edit profile before publishing a listing.",
  );

  static const ms = SocialStrings(
    usernameSavedOnSave: "Huruf, nombor dan _ sahaja. Disimpan bila anda tekan Simpan perubahan.",
    usernameChangeTitle: "Tukar nama pengguna?",
    usernameChangeBody:
        "Anda akan bertukar dari @{0} ke @{1}. Sebutan @{0} yang sedia ada dalam post dan komen tidak lagi dipautkan kepada anda, dan orang lain boleh mengambil @{0}.",
    usernameChangeConfirm: "Tukar nama pengguna",
    markAllRead: "Tanda semua sudah dibaca",
    someone: "Seseorang",
    whatsappOptionalHelper: "Pilihan — diperlukan untuk menjual di Pasar",
    whatsappNeededTitle: "Tambah nombor WhatsApp anda",
    whatsappNeededBody:
        "Pembeli menghubungi penjual melalui WhatsApp. Tambah nombor anda di Edit profil sebelum menerbitkan iklan.",
  );

  static const ja = SocialStrings(
    usernameSavedOnSave: "英数字と _ のみ。「変更を保存」を押すと保存されます。",
    usernameChangeTitle: "ユーザー名を変更しますか？",
    usernameChangeBody:
        "@{0} から @{1} に変わります。投稿やコメント内の既存の @{0} メンションはあなたにリンクされなくなり、他の人が @{0} を使えるようになります。",
    usernameChangeConfirm: "ユーザー名を変更",
    markAllRead: "すべて既読にする",
    someone: "誰か",
    whatsappOptionalHelper: "任意 — マーケットで出品するには必要です",
    whatsappNeededTitle: "WhatsApp番号を追加してください",
    whatsappNeededBody:
        "購入者はWhatsAppで出品者に連絡します。出品する前にプロフィール編集で番号を追加してください。",
  );
}

extension SocialStringsOf on AppStrings {
  /// The [SocialStrings] matching this language table.
  SocialStrings get social {
    if (identical(this, AppStrings.ms)) return SocialStrings.ms;
    if (identical(this, AppStrings.ja)) return SocialStrings.ja;
    return SocialStrings.en;
  }
}
