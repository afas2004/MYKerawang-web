import '../../l10n/app_strings.dart';

/// Copy for the Announcements hub, the shell's guest controls and the
/// profile avatar action. English and Malay; Japanese maps to English.
///
/// Usage: `context.l10n.hub.title`.
class HubStrings {
  /// Bottom-bar / rail label (short: five slots on a 375 px phone).
  final String navLabel;

  /// App bar / sidebar title.
  final String title;

  final String catAll;
  final String catKolej;
  final String catJpk;
  final String catClubs;
  final String catEvents;
  final String catGeneral;

  /// Per-category empty states (All uses emptyTitle / emptyBody).
  final String emptyKolej;
  final String emptyJpk;
  final String emptyClub;
  final String emptyEvent;
  final String emptyGeneral;
  final String emptyCategoryBody;

  final String newAnnouncement;
  final String earlierPosts;

  final String featured;
  final String pinned;
  final String official;
  final String channels;
  final String allChannels;
  final String upcomingOfficial;
  final String emptyTitle;
  final String emptyBody;
  final String emptyFilterTitle;
  final String emptyFilterBody;

  // Shell (guests)
  final String signIn;
  final String joinWithStudentEmail;
  final String guestTagline;
  final String yourProfile;

  const HubStrings({
    required this.navLabel,
    required this.title,
    required this.catAll,
    required this.catKolej,
    required this.catJpk,
    required this.catClubs,
    required this.catEvents,
    required this.catGeneral,
    required this.emptyKolej,
    required this.emptyJpk,
    required this.emptyClub,
    required this.emptyEvent,
    required this.emptyGeneral,
    required this.emptyCategoryBody,
    required this.newAnnouncement,
    required this.earlierPosts,
    required this.featured,
    required this.pinned,
    required this.official,
    required this.channels,
    required this.allChannels,
    required this.upcomingOfficial,
    required this.emptyTitle,
    required this.emptyBody,
    required this.emptyFilterTitle,
    required this.emptyFilterBody,
    required this.signIn,
    required this.joinWithStudentEmail,
    required this.guestTagline,
    required this.yourProfile,
  });

  static const en = HubStrings(
    navLabel: "News",
    title: "Announcements",
    catAll: "All",
    catKolej: "Kolej",
    catJpk: "JPK",
    catClubs: "Clubs",
    catEvents: "Events",
    catGeneral: "General",
    emptyKolej: "No Kolej announcements yet",
    emptyJpk: "No JPK announcements yet",
    emptyClub: "No club announcements yet",
    emptyEvent: "No event announcements yet",
    emptyGeneral: "No general notices yet",
    emptyCategoryBody: "New ones will show up here. Check All for everything else.",
    newAnnouncement: "New announcement",
    earlierPosts: "Recent posts from official accounts",
    featured: "Featured",
    pinned: "Pinned",
    official: "Official",
    channels: "Official channels",
    allChannels: "All channels",
    upcomingOfficial: "Upcoming official events",
    emptyTitle: "No announcements yet",
    emptyBody: "Official news from Kolej, JPK and clubs will show up here.",
    emptyFilterTitle: "Nothing here yet",
    emptyFilterBody: "No announcements in this category. Try All.",
    signIn: "Sign in",
    joinWithStudentEmail: "Join with student email",
    guestTagline: "Browse freely. Sign in to post, join and chat.",
    yourProfile: "Your profile",
  );

  static const ms = HubStrings(
    navLabel: "Berita",
    title: "Pengumuman",
    catAll: "Semua",
    catKolej: "Kolej",
    catJpk: "JPK",
    catClubs: "Kelab",
    catEvents: "Acara",
    catGeneral: "Umum",
    emptyKolej: "Belum ada pengumuman Kolej",
    emptyJpk: "Belum ada pengumuman JPK",
    emptyClub: "Belum ada pengumuman kelab",
    emptyEvent: "Belum ada pengumuman acara",
    emptyGeneral: "Belum ada notis umum",
    emptyCategoryBody: "Yang baru akan keluar di sini. Tengok Semua untuk yang lain.",
    newAnnouncement: "Pengumuman baru",
    earlierPosts: "Post terkini daripada akaun rasmi",
    featured: "Pilihan",
    pinned: "Dipin",
    official: "Rasmi",
    channels: "Saluran rasmi",
    allChannels: "Semua saluran",
    upcomingOfficial: "Acara rasmi akan datang",
    emptyTitle: "Belum ada pengumuman",
    emptyBody: "Berita rasmi daripada Kolej, JPK dan kelab akan keluar di sini.",
    emptyFilterTitle: "Belum ada apa-apa",
    emptyFilterBody: "Tiada pengumuman dalam kategori ini. Cuba Semua.",
    signIn: "Log masuk",
    joinWithStudentEmail: "Sertai dengan emel pelajar",
    guestTagline: "Tengok dulu. Log masuk untuk post, join dan berbual.",
    yourProfile: "Profil anda",
  );
}

extension HubStringsOf on AppStrings {
  HubStrings get hub =>
      identical(this, AppStrings.ms) ? HubStrings.ms : HubStrings.en;
}
