/// Lightweight app localization: English (default), Bahasa Melayu, Japanese.
///
/// Usage: `context.watch<LanguageCubit>().state.strings.navHome`
/// or the shorthand extension `context.l10n.navHome` (see language_cubit.dart).
enum AppLanguage { en, ms, ja }

class AppStrings {
  // Navigation
  final String navHome;
  final String navSearch;
  final String navMarket;
  final String navEvents;
  final String navProfile;
  final String createPost;

  // Home
  final String happeningSoon;
  final String freshFinds;
  final String refresh;
  final String notifications;
  final String settings;
  final String connectionError;
  final String tryAgain;

  // Right rail
  final String eventsThisWeek;
  final String newInMarket;

  // Login
  final String welcomeBack;
  final String loginToContinue;
  final String joinApp;
  final String registerToStart;
  final String email;
  final String password;
  final String showPassword;
  final String hidePassword;
  final String login;
  final String signUp;
  final String continueWithGoogle;
  final String newUserPrefix;
  final String createAccount;
  final String haveAccountPrefix;
  final String loginLink;

  // Marketplace
  final String marketplaceTitle;
  final String searchItems;
  final String noItemsFound;

  // Settings
  final String language;

  const AppStrings({
    required this.navHome,
    required this.navSearch,
    required this.navMarket,
    required this.navEvents,
    required this.navProfile,
    required this.createPost,
    required this.happeningSoon,
    required this.freshFinds,
    required this.refresh,
    required this.notifications,
    required this.settings,
    required this.connectionError,
    required this.tryAgain,
    required this.eventsThisWeek,
    required this.newInMarket,
    required this.welcomeBack,
    required this.loginToContinue,
    required this.joinApp,
    required this.registerToStart,
    required this.email,
    required this.password,
    required this.showPassword,
    required this.hidePassword,
    required this.login,
    required this.signUp,
    required this.continueWithGoogle,
    required this.newUserPrefix,
    required this.createAccount,
    required this.haveAccountPrefix,
    required this.loginLink,
    required this.marketplaceTitle,
    required this.searchItems,
    required this.noItemsFound,
    required this.language,
  });

  static const en = AppStrings(
    navHome: "Home",
    navSearch: "Search",
    navMarket: "Market",
    navEvents: "Events",
    navProfile: "Profile",
    createPost: "Create post",
    happeningSoon: "Happening Soon",
    freshFinds: "Fresh Finds",
    refresh: "Refresh",
    notifications: "Notifications",
    settings: "Settings",
    connectionError: "Couldn't connect. Try again?",
    tryAgain: "Try again",
    eventsThisWeek: "Events this week",
    newInMarket: "Fresh in the market",
    welcomeBack: "Welcome back",
    loginToContinue: "Login to continue",
    joinApp: "Join MYKerawang",
    registerToStart: "Create an account to get started",
    email: "Email",
    password: "Password",
    showPassword: "Show",
    hidePassword: "Hide",
    login: "Login",
    signUp: "Sign up",
    continueWithGoogle: "Continue with Google",
    newUserPrefix: "New user? ",
    createAccount: "Create account",
    haveAccountPrefix: "Have an account? ",
    loginLink: "Login",
    marketplaceTitle: "Marketplace",
    searchItems: "Search items...",
    noItemsFound: "No items found",
    language: "Language",
  );

  static const ms = AppStrings(
    navHome: "Utama",
    navSearch: "Cari",
    navMarket: "Pasar",
    navEvents: "Acara",
    navProfile: "Profil",
    createPost: "Jom post",
    happeningSoon: "Jangan Terlepas",
    freshFinds: "Baru Masuk",
    refresh: "Muat semula",
    notifications: "Notifikasi",
    settings: "Tetapan",
    connectionError: "Tak dapat sambung. Cuba lagi?",
    tryAgain: "Cuba semula",
    eventsThisWeek: "Acara minggu ini",
    newInMarket: "Baru masuk pasar",
    welcomeBack: "Selamat kembali",
    loginToContinue: "Log masuk untuk teruskan",
    joinApp: "Jom sertai MYKerawang",
    registerToStart: "Daftar akaun untuk mula",
    email: "Emel",
    password: "Kata laluan",
    showPassword: "Tunjuk",
    hidePassword: "Sembunyi",
    login: "Log masuk",
    signUp: "Daftar",
    continueWithGoogle: "Teruskan dengan Google",
    newUserPrefix: "Pengguna baru? ",
    createAccount: "Daftar sini",
    haveAccountPrefix: "Dah ada akaun? ",
    loginLink: "Log masuk",
    marketplaceTitle: "Pasar",
    searchItems: "Cari barang...",
    noItemsFound: "Tiada barang dijumpai",
    language: "Bahasa",
  );

  static const ja = AppStrings(
    navHome: "ホーム",
    navSearch: "検索",
    navMarket: "マーケット",
    navEvents: "イベント",
    navProfile: "プロフィール",
    createPost: "投稿する",
    happeningSoon: "近日開催",
    freshFinds: "新着アイテム",
    refresh: "更新",
    notifications: "通知",
    settings: "設定",
    connectionError: "接続できません。もう一度？",
    tryAgain: "再試行",
    eventsThisWeek: "今週のイベント",
    newInMarket: "マーケット新着",
    welcomeBack: "おかえりなさい",
    loginToContinue: "ログインして続ける",
    joinApp: "MYKerawangへようこそ",
    registerToStart: "アカウントを作成して始めよう",
    email: "メール",
    password: "パスワード",
    showPassword: "表示",
    hidePassword: "非表示",
    login: "ログイン",
    signUp: "登録",
    continueWithGoogle: "Googleで続行",
    newUserPrefix: "初めての方？ ",
    createAccount: "アカウント作成",
    haveAccountPrefix: "アカウントをお持ちの方？ ",
    loginLink: "ログイン",
    marketplaceTitle: "マーケット",
    searchItems: "商品を検索...",
    noItemsFound: "商品が見つかりません",
    language: "言語",
  );

  static AppStrings of(AppLanguage lang) => switch (lang) {
        AppLanguage.en => en,
        AppLanguage.ms => ms,
        AppLanguage.ja => ja,
      };
}
