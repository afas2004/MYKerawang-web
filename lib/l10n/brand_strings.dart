import 'app_strings.dart';

/// Copy that comes with the visual identity: the lost page, the error
/// state and the open-source credits. English and Malay; Japanese maps to
/// English.
///
/// Usage: `context.l10n.brand.lostTitle`.
class BrandStrings {
  /// 404 title: the kite's string snapped.
  final String lostTitle;
  final String lostBody;

  /// Load-failure title: a thread came loose.
  final String errorTitle;

  /// Settings entry for the licences page.
  final String openSourceCredits;
  final String openSourceCreditsSub;

  const BrandStrings({
    required this.lostTitle,
    required this.lostBody,
    required this.errorTitle,
    required this.openSourceCredits,
    required this.openSourceCreditsSub,
  });

  static const en = BrandStrings(
    lostTitle: "The kite string snapped",
    lostBody: "This page doesn't exist or has moved.",
    errorTitle: "A thread came loose",
    openSourceCredits: "Open-source credits",
    openSourceCreditsSub: "Illustrations, fonts and libraries we use",
  );

  static const ms = BrandStrings(
    lostTitle: "Wau terputus tali",
    lostBody: "Halaman ini tiada atau sudah dipindahkan.",
    errorTitle: "Ada benang terputus",
    openSourceCredits: "Penghargaan sumber terbuka",
    openSourceCreditsSub: "Ilustrasi, fon dan pustaka yang kami guna",
  );
}

extension BrandStringsOf on AppStrings {
  BrandStrings get brand =>
      identical(this, AppStrings.ms) ? BrandStrings.ms : BrandStrings.en;
}
