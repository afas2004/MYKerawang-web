import 'app_strings.dart';

/// Copy for the redesigned app shell and the profile / settings /
/// notifications / search / onboarding screens. Separate file so parallel
/// UI branches don't collide in app_strings.dart. English and Malay;
/// Japanese maps to English.
///
/// Usage: `context.l10n.shell.create`.
class ShellStrings {
  // Shell
  final String create;
  final String createWhat;
  final String createPostSub;
  final String createEventSub;
  final String sellItemSub;
  final String mainNavigation;

  // Right rail
  final String railNothing;

  // Profile / edit profile
  final String profilePhoto;
  final String aboutYou;
  final String contactPayments;
  final String publicProfile;
  final String contactPrivate;

  // Settings
  final String appearance;
  final String account;

  // Notifications
  final String today;
  final String thisWeek;
  final String earlier;
  final String markRead;
  final String unread;
  final String allCaughtUp;
  final String notificationsEmptyBody;

  // Search
  final String recentSearches;
  final String clearRecent;
  final String removeRecent;
  final String searchPromptTitle;
  final String searchPromptBody;
  final String noResultsFor;
  final String tryDifferent;

  // Onboarding
  final String stepOf;

  const ShellStrings({
    required this.create,
    required this.createWhat,
    required this.createPostSub,
    required this.createEventSub,
    required this.sellItemSub,
    required this.mainNavigation,
    required this.railNothing,
    required this.profilePhoto,
    required this.aboutYou,
    required this.contactPayments,
    required this.publicProfile,
    required this.contactPrivate,
    required this.appearance,
    required this.account,
    required this.today,
    required this.thisWeek,
    required this.earlier,
    required this.markRead,
    required this.unread,
    required this.allCaughtUp,
    required this.notificationsEmptyBody,
    required this.recentSearches,
    required this.clearRecent,
    required this.removeRecent,
    required this.searchPromptTitle,
    required this.searchPromptBody,
    required this.noResultsFor,
    required this.tryDifferent,
    required this.stepOf,
  });

  static const en = ShellStrings(
    create: "Create",
    createWhat: "What do you want to create?",
    createPostSub: "Share news, ask or reply to the college",
    createEventSub: "Talks, sports, club meetups",
    sellItemSub: "List something in the Market",
    mainNavigation: "Main navigation",
    railNothing: "Nothing here yet",
    profilePhoto: "Profile photo",
    aboutYou: "About you",
    contactPayments: "Contact & payments",
    publicProfile: "Everyone can see this",
    contactPrivate: "Private. Only a buyer who taps Contact on your listing gets these.",
    appearance: "Appearance",
    account: "Account",
    today: "Today",
    thisWeek: "This week",
    earlier: "Earlier",
    markRead: "Mark as read",
    unread: "Unread",
    allCaughtUp: "You're all caught up",
    notificationsEmptyBody: "Follows, mentions and replies will show up here.",
    recentSearches: "Recent searches",
    clearRecent: "Clear",
    removeRecent: "Remove",
    searchPromptTitle: "Search MYKerawang",
    searchPromptBody: "People, posts, events and Market items.",
    noResultsFor: "Nothing found for “{0}”",
    tryDifferent: "Try another word or a different filter.",
    stepOf: "Step {0} of {1}",
  );

  static const ms = ShellStrings(
    create: "Cipta",
    createWhat: "Nak cipta apa?",
    createPostSub: "Kongsi berita, tanya atau balas warga kolej",
    createEventSub: "Ceramah, sukan, perjumpaan kelab",
    sellItemSub: "Jual sesuatu di Pasar",
    mainNavigation: "Navigasi utama",
    railNothing: "Belum ada apa-apa",
    profilePhoto: "Gambar profil",
    aboutYou: "Tentang anda",
    contactPayments: "Hubungan & bayaran",
    publicProfile: "Semua orang boleh lihat",
    contactPrivate: "Peribadi. Hanya pembeli yang tekan Hubungi pada iklan anda akan dapat.",
    appearance: "Paparan",
    account: "Akaun",
    today: "Hari ini",
    thisWeek: "Minggu ini",
    earlier: "Sebelum ini",
    markRead: "Tanda dibaca",
    unread: "Belum dibaca",
    allCaughtUp: "Semua dah dibaca",
    notificationsEmptyBody: "Ikutan, sebutan dan balasan akan muncul di sini.",
    recentSearches: "Carian terkini",
    clearRecent: "Padam",
    removeRecent: "Buang",
    searchPromptTitle: "Cari di MYKerawang",
    searchPromptBody: "Orang, post, acara dan barang Pasar.",
    noResultsFor: "Tiada hasil untuk “{0}”",
    tryDifferent: "Cuba perkataan lain atau tapis yang berbeza.",
    stepOf: "Langkah {0} daripada {1}",
  );
}

extension ShellStringsOf on AppStrings {
  ShellStrings get shell =>
      identical(this, AppStrings.ms) ? ShellStrings.ms : ShellStrings.en;
}
