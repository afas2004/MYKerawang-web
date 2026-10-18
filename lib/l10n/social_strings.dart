import 'app_strings.dart';

/// Copy for profile, notifications, search, onboarding, privacy and saved
/// items added after the main [AppStrings] table. Kept in its own file so
/// parallel work on app_strings.dart doesn't collide; fold it in when
/// convenient. English and Malay only — Japanese was dropped and maps to
/// English.
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

  // Settings — privacy & data
  final String privacyData;
  final String privacyPolicy;
  final String privacyPolicySub;
  final String downloadMyData;
  final String downloadMyDataSub;
  final String preparingExport;
  final String exportReady;
  final String exportFailed;
  final String deleteAccount;
  final String deleteAccountSub;
  final String deleteAccountTitle;
  final String deleteAccountBody;
  final String typeUsernameToConfirm;
  final String deleteForever;
  final String deletingAccount;
  final String accountDeleted;
  final String deleteAccountFailed;
  final String ownerCannotDelete;
  final String retry;

  // Saved items
  final String saved;
  final String save;
  final String unsave;
  final String savedToast;
  final String unsavedToast;
  final String saveFailed;
  final String nothingSaved;
  final String nothingSavedSub;
  final String savedNoLongerAvailable;

  // Home feed
  final String feedEmptyTitle;
  final String feedEmptyBody;
  final String createFirstPost;
  final String loadMoreFailed;

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
    required this.privacyData,
    required this.privacyPolicy,
    required this.privacyPolicySub,
    required this.downloadMyData,
    required this.downloadMyDataSub,
    required this.preparingExport,
    required this.exportReady,
    required this.exportFailed,
    required this.deleteAccount,
    required this.deleteAccountSub,
    required this.deleteAccountTitle,
    required this.deleteAccountBody,
    required this.typeUsernameToConfirm,
    required this.deleteForever,
    required this.deletingAccount,
    required this.accountDeleted,
    required this.deleteAccountFailed,
    required this.ownerCannotDelete,
    required this.retry,
    required this.saved,
    required this.save,
    required this.unsave,
    required this.savedToast,
    required this.unsavedToast,
    required this.saveFailed,
    required this.nothingSaved,
    required this.nothingSavedSub,
    required this.savedNoLongerAvailable,
    required this.feedEmptyTitle,
    required this.feedEmptyBody,
    required this.createFirstPost,
    required this.loadMoreFailed,
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
    privacyData: "Privacy & data",
    privacyPolicy: "Privacy policy",
    privacyPolicySub: "What we store and who can see it",
    downloadMyData: "Download my data",
    downloadMyDataSub: "A JSON file with your profile, posts, comments, listings, events and follows",
    preparingExport: "Preparing your data…",
    exportReady: "Your data has been downloaded",
    exportFailed: "Couldn't export your data: {0}",
    deleteAccount: "Delete my account",
    deleteAccountSub: "Permanently remove your account and everything you posted",
    deleteAccountTitle: "Delete your account?",
    deleteAccountBody:
        "This permanently deletes your profile, posts, comments, listings, events, follows, saved items and contact details. It can't be undone. You may want to download your data first.",
    typeUsernameToConfirm: "Type your username ({0}) to confirm",
    deleteForever: "Delete forever",
    deletingAccount: "Deleting your account…",
    accountDeleted: "Your account has been deleted",
    deleteAccountFailed: "Couldn't delete your account: {0}",
    ownerCannotDelete: "The owner account can't delete itself. Transfer ownership first.",
    retry: "Retry",
    saved: "Saved",
    save: "Save",
    unsave: "Remove from saved",
    savedToast: "Saved",
    unsavedToast: "Removed from saved",
    saveFailed: "Couldn't update saved items",
    nothingSaved: "Nothing saved yet",
    nothingSavedSub: "Tap the bookmark on a post, item or event to keep it here.",
    savedNoLongerAvailable: "No longer available",
    feedEmptyTitle: "No posts yet",
    feedEmptyBody: "Be the first to say something to the college.",
    createFirstPost: "Create the first post",
    loadMoreFailed: "Couldn't load more posts",
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
    privacyData: "Privasi & data",
    privacyPolicy: "Dasar privasi",
    privacyPolicySub: "Apa yang kami simpan dan siapa boleh lihat",
    downloadMyData: "Muat turun data saya",
    downloadMyDataSub: "Fail JSON berisi profil, post, komen, iklan, acara dan ikutan anda",
    preparingExport: "Menyediakan data anda…",
    exportReady: "Data anda telah dimuat turun",
    exportFailed: "Tidak dapat mengeksport data: {0}",
    deleteAccount: "Padam akaun saya",
    deleteAccountSub: "Buang akaun anda dan semua yang anda siarkan secara kekal",
    deleteAccountTitle: "Padam akaun anda?",
    deleteAccountBody:
        "Ini akan memadam profil, post, komen, iklan, acara, ikutan, item disimpan dan maklumat hubungan anda secara kekal. Tidak boleh dibatalkan. Anda mungkin mahu memuat turun data anda dahulu.",
    typeUsernameToConfirm: "Taip nama pengguna anda ({0}) untuk mengesahkan",
    deleteForever: "Padam selama-lamanya",
    deletingAccount: "Memadam akaun anda…",
    accountDeleted: "Akaun anda telah dipadam",
    deleteAccountFailed: "Tidak dapat memadam akaun: {0}",
    ownerCannotDelete: "Akaun pemilik tidak boleh dipadam sendiri. Pindahkan pemilikan dahulu.",
    retry: "Cuba lagi",
    saved: "Disimpan",
    save: "Simpan",
    unsave: "Buang dari simpanan",
    savedToast: "Disimpan",
    unsavedToast: "Dibuang dari simpanan",
    saveFailed: "Tidak dapat mengemas kini item disimpan",
    nothingSaved: "Belum ada yang disimpan",
    nothingSavedSub: "Tekan penanda pada post, barang atau acara untuk menyimpannya di sini.",
    savedNoLongerAvailable: "Tidak lagi tersedia",
    feedEmptyTitle: "Belum ada post",
    feedEmptyBody: "Jadilah yang pertama bersuara kepada kolej.",
    createFirstPost: "Cipta post pertama",
    loadMoreFailed: "Tidak dapat memuatkan lebih banyak post",
  );
}

extension SocialStringsOf on AppStrings {
  /// The [SocialStrings] matching this language table (Japanese → English).
  SocialStrings get social =>
      identical(this, AppStrings.ms) ? SocialStrings.ms : SocialStrings.en;
}
