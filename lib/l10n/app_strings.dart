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
  final String pastEvents;
  final String newInMarket;

  // Composer + embeds
  final String composerHint;
  final String viewItem;
  final String viewEvent;

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
  final String forgotPassword;
  final String enterEmailFirst;
  final String resetLinkSent;

  // Marketplace
  final String marketplaceTitle;
  final String searchItems;
  final String noItemsFound;

  // Create actions
  final String sellItem;
  final String newEvent;
  final String takePhoto;
  final String chooseFromGallery;
  final String viewFullscreen;
  final String setAsCover;
  final String removePhoto;
  final String createPostTitle;
  final String post;
  final String save;
  final String cancel;
  final String delete;
  final String edit;
  final String share;
  final String report;
  final String searchEvents;
  final String eventsTitle;
  final String profileTitle;
  final String threadTitle;
  final String notificationsTitle;
  final String settingsTitle;
  final String noNotifications;
  final String comments;
  final String whatsOnYourMind;
  final String postedAnonymously;
  final String addTags;
  final String tagsHint;
  final String saveChanges;
  final String saved;
  final String saving;
  final String changePhoto;
  final String cropHint;
  final String editProfile;
  final String followers;
  final String following;
  final String follow;
  final String unfollow;

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
    required this.pastEvents,
    required this.newInMarket,
    required this.composerHint,
    required this.viewItem,
    required this.viewEvent,
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
    required this.forgotPassword,
    required this.enterEmailFirst,
    required this.resetLinkSent,
    required this.marketplaceTitle,
    required this.searchItems,
    required this.noItemsFound,
    required this.sellItem,
    required this.newEvent,
    required this.takePhoto,
    required this.chooseFromGallery,
    required this.viewFullscreen,
    required this.setAsCover,
    required this.removePhoto,
    required this.createPostTitle,
    required this.post,
    required this.save,
    required this.cancel,
    required this.delete,
    required this.edit,
    required this.share,
    required this.report,
    required this.searchEvents,
    required this.eventsTitle,
    required this.profileTitle,
    required this.threadTitle,
    required this.notificationsTitle,
    required this.settingsTitle,
    required this.noNotifications,
    required this.comments,
    required this.whatsOnYourMind,
    required this.postedAnonymously,
    required this.addTags,
    required this.tagsHint,
    required this.saveChanges,
    required this.saved,
    required this.saving,
    required this.changePhoto,
    required this.cropHint,
    required this.editProfile,
    required this.followers,
    required this.following,
    required this.follow,
    required this.unfollow,
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
    pastEvents: "Past events",
    newInMarket: "Fresh in the market",
    composerHint: "What's happening at kolej?",
    viewItem: "View item",
    viewEvent: "View event",
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
    forgotPassword: "Forgot password?",
    enterEmailFirst: "Enter your email first",
    resetLinkSent: "Password reset link sent — check your email",
    marketplaceTitle: "Marketplace",
    searchItems: "Search items...",
    noItemsFound: "No items found",
    sellItem: "Sell item",
    newEvent: "New event",
    takePhoto: "Take photo",
    chooseFromGallery: "Choose from gallery",
    viewFullscreen: "View fullscreen",
    setAsCover: "Set as cover photo",
    removePhoto: "Remove photo",
    createPostTitle: "Create post",
    post: "POST",
    save: "SAVE",
    cancel: "Cancel",
    delete: "Delete",
    edit: "Edit",
    share: "Share",
    report: "Report",
    searchEvents: "Search events...",
    eventsTitle: "Events",
    profileTitle: "Profile",
    threadTitle: "Thread",
    notificationsTitle: "Notifications",
    settingsTitle: "Settings",
    noNotifications: "No new notifications",
    comments: "Comments",
    whatsOnYourMind: "What's on your mind?",
    postedAnonymously: "Posted anonymously",
    addTags: "Tags",
    tagsHint: "#studygroup #kolej ...",
    saveChanges: "Save changes",
    saved: "Saved",
    saving: "Saving...",
    changePhoto: "Change photo",
    cropHint: "Drag and pinch to position",
    editProfile: "Edit profile",
    followers: "Followers",
    following: "Following",
    follow: "Follow",
    unfollow: "Unfollow",
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
    pastEvents: "Acara lepas",
    newInMarket: "Baru masuk pasar",
    composerHint: "Apa cerita kat kolej?",
    viewItem: "Lihat barang",
    viewEvent: "Jom join",
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
    forgotPassword: "Lupa kata laluan?",
    enterEmailFirst: "Masukkan emel dulu",
    resetLinkSent: "Pautan set semula dihantar — semak emel anda",
    marketplaceTitle: "Pasar",
    searchItems: "Cari barang...",
    noItemsFound: "Tiada barang dijumpai",
    sellItem: "Jual barang",
    newEvent: "Acara baru",
    takePhoto: "Ambil gambar",
    chooseFromGallery: "Pilih dari galeri",
    viewFullscreen: "Lihat skrin penuh",
    setAsCover: "Jadikan gambar utama",
    removePhoto: "Buang gambar",
    createPostTitle: "Buat post",
    post: "HANTAR",
    save: "SIMPAN",
    cancel: "Batal",
    delete: "Padam",
    edit: "Edit",
    share: "Kongsi",
    report: "Lapor",
    searchEvents: "Cari acara...",
    eventsTitle: "Acara",
    profileTitle: "Profil",
    threadTitle: "Bicara",
    notificationsTitle: "Notifikasi",
    settingsTitle: "Tetapan",
    noNotifications: "Tiada notifikasi baru",
    comments: "Komen",
    whatsOnYourMind: "Apa dalam fikiran anda?",
    postedAnonymously: "Dihantar tanpa nama",
    addTags: "Tag",
    tagsHint: "#studygroup #kolej ...",
    saveChanges: "Simpan perubahan",
    saved: "Disimpan",
    saving: "Menyimpan...",
    changePhoto: "Tukar gambar",
    cropHint: "Seret dan cubit untuk laraskan",
    editProfile: "Edit profil",
    followers: "Pengikut",
    following: "Mengikuti",
    follow: "Ikut",
    unfollow: "Berhenti ikut",
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
    pastEvents: "過去のイベント",
    newInMarket: "マーケット新着",
    composerHint: "キャンパスで何かあった？",
    viewItem: "商品を見る",
    viewEvent: "参加する",
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
    forgotPassword: "パスワードをお忘れですか？",
    enterEmailFirst: "先にメールを入力してください",
    resetLinkSent: "再設定リンクを送信しました",
    marketplaceTitle: "マーケット",
    searchItems: "商品を検索...",
    noItemsFound: "商品が見つかりません",
    sellItem: "出品する",
    newEvent: "イベント作成",
    takePhoto: "写真を撮る",
    chooseFromGallery: "ギャラリーから選択",
    viewFullscreen: "全画面表示",
    setAsCover: "カバーに設定",
    removePhoto: "写真を削除",
    createPostTitle: "投稿を作成",
    post: "投稿",
    save: "保存",
    cancel: "キャンセル",
    delete: "削除",
    edit: "編集",
    share: "共有",
    report: "報告",
    searchEvents: "イベントを検索...",
    eventsTitle: "イベント",
    profileTitle: "プロフィール",
    threadTitle: "スレッド",
    notificationsTitle: "通知",
    settingsTitle: "設定",
    noNotifications: "新しい通知はありません",
    comments: "コメント",
    whatsOnYourMind: "いま何してる？",
    postedAnonymously: "匿名で投稿",
    addTags: "タグ",
    tagsHint: "#studygroup #kolej ...",
    saveChanges: "変更を保存",
    saved: "保存しました",
    saving: "保存中...",
    changePhoto: "写真を変更",
    cropHint: "ドラッグ・ピンチで調整",
    editProfile: "プロフィール編集",
    followers: "フォロワー",
    following: "フォロー中",
    follow: "フォロー",
    unfollow: "フォロー解除",
    language: "言語",
  );

  static AppStrings of(AppLanguage lang) => switch (lang) {
        AppLanguage.en => en,
        AppLanguage.ms => ms,
        AppLanguage.ja => ja,
      };
}
