import 'app_strings.dart';

/// Copy for account recovery and duplicate-account notices.
///
/// Kept apart from [AppStrings] so the (very long) main constructor stays
/// untouched, and apart from [ModerationStrings] because none of this is
/// moderation. Access with `context.l10n.account.backupEmailTitle`.
class AccountStrings {
  // ---- backup email
  final String backupEmail;
  final String backupEmailHelp;
  final String backupEmailHint;
  final String backupEmailInvalid;
  final String backupEmailSaved;
  final String backupEmailNone;
  final String backupEmailRemove;
  final String backupEmailSection;

  // ---- graduation reminder
  final String backupNudgeTitle;
  final String backupNudgeBody;
  final String backupNudgeAdd;
  final String backupNudgeLater;

  // ---- second account on this device
  final String otherAccountTitle;
  final String otherAccountBody;
  final String otherAccountStay;
  final String otherAccountSwitch;
  final String otherAccountSwitching;

  const AccountStrings({
    required this.backupEmail,
    required this.backupEmailHelp,
    required this.backupEmailHint,
    required this.backupEmailInvalid,
    required this.backupEmailSaved,
    required this.backupEmailNone,
    required this.backupEmailRemove,
    required this.backupEmailSection,
    required this.backupNudgeTitle,
    required this.backupNudgeBody,
    required this.backupNudgeAdd,
    required this.backupNudgeLater,
    required this.otherAccountTitle,
    required this.otherAccountBody,
    required this.otherAccountStay,
    required this.otherAccountSwitch,
    required this.otherAccountSwitching,
  });

  static const en = AccountStrings(
    backupEmail: "Backup email",
    backupEmailHelp:
        "Where we can reach you if you lose access to your login email. "
        "Nobody else can see it.",
    backupEmailHint: "you@gmail.com",
    backupEmailInvalid: "Enter a valid email address",
    backupEmailSaved: "Backup email saved",
    backupEmailNone: "Not set",
    backupEmailRemove: "Remove",
    backupEmailSection: "Account recovery",
    backupNudgeTitle: "Keep this account after graduation",
    backupNudgeBody:
        "You sign in with {0}. UiTM closes that address about a year after "
        "you graduate, and you would lose this account. Add a backup email "
        "so you can still get back in.",
    backupNudgeAdd: "Add backup email",
    backupNudgeLater: "Not now",
    otherAccountTitle: "Another account on this device",
    otherAccountBody:
        "This device has signed in as {0} before. If that is you, continue "
        "there instead of using two accounts.",
    otherAccountStay: "Stay on this account",
    otherAccountSwitch: "Use {0}",
    otherAccountSwitching: "Signing out so you can switch",
  );

  static const ms = AccountStrings(
    backupEmail: "E-mel sandaran",
    backupEmailHelp:
        "Di mana kami boleh hubungi anda jika anda hilang akses kepada "
        "e-mel log masuk. Tiada orang lain boleh melihatnya.",
    backupEmailHint: "anda@gmail.com",
    backupEmailInvalid: "Masukkan alamat e-mel yang sah",
    backupEmailSaved: "E-mel sandaran disimpan",
    backupEmailNone: "Belum ditetapkan",
    backupEmailRemove: "Buang",
    backupEmailSection: "Pemulihan akaun",
    backupNudgeTitle: "Kekalkan akaun ini selepas graduasi",
    backupNudgeBody:
        "Anda log masuk dengan {0}. UiTM menutup alamat itu kira-kira "
        "setahun selepas anda bergraduasi, dan anda akan kehilangan akaun "
        "ini. Tambah e-mel sandaran supaya anda masih boleh masuk semula.",
    backupNudgeAdd: "Tambah e-mel sandaran",
    backupNudgeLater: "Bukan sekarang",
    otherAccountTitle: "Akaun lain pada peranti ini",
    otherAccountBody:
        "Peranti ini pernah log masuk sebagai {0}. Jika itu anda, teruskan "
        "di akaun itu daripada menggunakan dua akaun.",
    otherAccountStay: "Kekal pada akaun ini",
    otherAccountSwitch: "Guna {0}",
    otherAccountSwitching: "Log keluar untuk bertukar akaun",
  );

  /// Japanese is being dropped from the app; English stands in.
  static const ja = en;
}

extension AccountStringsOf on AppStrings {
  AccountStrings get account =>
      identical(this, AppStrings.ms) ? AccountStrings.ms : AccountStrings.en;
}
