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
