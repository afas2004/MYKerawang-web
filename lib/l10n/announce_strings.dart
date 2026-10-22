import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../language_cubit.dart';
import 'app_strings.dart';

/// Copy for the announcement composer, detail template and feed card
/// (v1.4). English and Malay; Japanese maps to English. Fold into
/// AppStrings when convenient.
///
/// `context.announceL10n.x` in build, `context.announceL10nRead.x` in callbacks.
class AnnounceStrings {
  final String newAnnouncement;
  final String editAnnouncement;
  final String publish;
  final String schedule;
  final String saveChanges;
  final String preview;
  final String backToEdit;
  final String postAs;
  final String category;
  final String catKolej;
  final String catJpk;
  final String catClub;
  final String catEvent;
  final String catGeneral;
  final String title;
  final String titleHint;
  final String body;
  final String bodyHint;
  final String formattingHelp;
  final String cover;
  final String coverHint;
  final String coverGuide;
  final String extraImages;
  final String actions;
  final String actionLabel;
  final String actionUrl;
  final String actionUrlHint;
  final String addAction;
  final String removeAction;
  final String linkEvent;
  final String linkEventNone;
  final String chooseEvent;
  final String publishWhen;
  final String publishNow;
  final String featureUntil;
  final String featureUntilNone;
  final String commentsOn;
  final String commentsOnSub;
  final String showInFeed;
  final String showInFeedSub;
  final String official;
  final String commentsOff;
  final String scheduledFor; // {0}
  final String published;
  final String scheduled; // {0}
  final String updated;
  final String notAllowed;
  final String loadFailed;
  // validation
  final String errTitleRequired;
  final String errTitleTooLong; // {0}
  final String errBodyTooLong; // {0}
  final String errCategory;
  final String errImages; // {0}
  final String errActions; // {0}
  final String errFeatureBeforePublish;
  final String errActionEmptyLabel;
  final String errActionLabelTooLong; // {0}
  final String errActionEmptyUrl;
  final String errActionNotHttps;
  final String errActionUnknownRoute;
  final String errActionBadUrl;

  const AnnounceStrings({
    required this.newAnnouncement,
    required this.editAnnouncement,
    required this.publish,
    required this.schedule,
    required this.saveChanges,
    required this.preview,
    required this.backToEdit,
    required this.postAs,
    required this.category,
    required this.catKolej,
    required this.catJpk,
    required this.catClub,
    required this.catEvent,
    required this.catGeneral,
    required this.title,
    required this.titleHint,
    required this.body,
    required this.bodyHint,
    required this.formattingHelp,
    required this.cover,
    required this.coverHint,
    required this.coverGuide,
    required this.extraImages,
    required this.actions,
    required this.actionLabel,
    required this.actionUrl,
    required this.actionUrlHint,
    required this.addAction,
    required this.removeAction,
    required this.linkEvent,
    required this.linkEventNone,
    required this.chooseEvent,
    required this.publishWhen,
    required this.publishNow,
    required this.featureUntil,
    required this.featureUntilNone,
    required this.commentsOn,
    required this.commentsOnSub,
    required this.showInFeed,
    required this.showInFeedSub,
    required this.official,
    required this.commentsOff,
    required this.scheduledFor,
    required this.published,
    required this.scheduled,
    required this.updated,
    required this.notAllowed,
    required this.loadFailed,
    required this.errTitleRequired,
    required this.errTitleTooLong,
    required this.errBodyTooLong,
    required this.errCategory,
    required this.errImages,
    required this.errActions,
    required this.errFeatureBeforePublish,
    required this.errActionEmptyLabel,
    required this.errActionLabelTooLong,
    required this.errActionEmptyUrl,
    required this.errActionNotHttps,
    required this.errActionUnknownRoute,
    required this.errActionBadUrl,
  });

  String categoryLabel(String? c) => switch (c) {
        'kolej' => catKolej,
        'jpk' => catJpk,
        'club' => catClub,
        'event' => catEvent,
        _ => catGeneral,
      };

  static const en = AnnounceStrings(
    newAnnouncement: "New announcement",
    editAnnouncement: "Edit announcement",
    publish: "Publish",
    schedule: "Schedule",
    saveChanges: "Save changes",
    preview: "Preview",
    backToEdit: "Edit",
    postAs: "Announce as",
    category: "Category",
    catKolej: "Kolej",
    catJpk: "JPK",
    catClub: "Club",
    catEvent: "Event",
    catGeneral: "General",
    title: "Title",
    titleHint: "What's the announcement?",
    body: "Details",
    bodyHint: "Write the details. Blank line = new paragraph, start a line with - for a bullet, **bold**.",
    formattingHelp: "Paragraphs, - bullets, **bold**; https links become tappable",
    cover: "Cover banner",
    coverHint: "Add a 16:9 cover",
    coverGuide: "Keep text and faces inside the frame — it's cropped to 16:9",
    extraImages: "More photos ({0}/{1})",
    actions: "Buttons",
    actionLabel: "Button label",
    actionUrl: "Link",
    actionUrlHint: "https://… or an app page like /event/…",
    addAction: "Add a button",
    removeAction: "Remove button",
    linkEvent: "Linked event",
    linkEventNone: "No event linked",
    chooseEvent: "Choose an event",
    publishWhen: "When to publish",
    publishNow: "Now",
    featureUntil: "Show in the banner until",
    featureUntilNone: "Not featured",
    commentsOn: "Allow comments",
    commentsOnSub: "Turn off for notices that don't need replies",
    showInFeed: "Also show in the Home feed",
    showInFeedSub: "Otherwise it's only in Announcements",
    official: "Official",
    commentsOff: "Comments are off for this announcement",
    scheduledFor: "Scheduled for {0}",
    published: "Announcement published",
    scheduled: "Announcement scheduled for {0}",
    updated: "Announcement updated",
    notAllowed: "Only club officers and admins can post announcements.",
    loadFailed: "Couldn't check your announcement access",
    errTitleRequired: "Add a title",
    errTitleTooLong: "Keep the title under {0} characters",
    errBodyTooLong: "Keep the details under {0} characters",
    errCategory: "Choose a category you can post in",
    errImages: "Up to {0} more photos",
    errActions: "Up to {0} buttons",
    errFeatureBeforePublish: "The banner end must be after publishing",
    errActionEmptyLabel: "Add a button label",
    errActionLabelTooLong: "Labels can be up to {0} characters",
    errActionEmptyUrl: "Add a link",
    errActionNotHttps: "Use a secure https:// link",
    errActionUnknownRoute: "That isn't a page in the app",
    errActionBadUrl: "That doesn't look like a link",
  );

  static const ms = AnnounceStrings(
    newAnnouncement: "Pengumuman baru",
    editAnnouncement: "Edit pengumuman",
    publish: "Terbitkan",
    schedule: "Jadualkan",
    saveChanges: "Simpan perubahan",
    preview: "Pratonton",
    backToEdit: "Edit",
    postAs: "Umum sebagai",
    category: "Kategori",
    catKolej: "Kolej",
    catJpk: "JPK",
    catClub: "Kelab",
    catEvent: "Acara",
    catGeneral: "Umum",
    title: "Tajuk",
    titleHint: "Apa pengumumannya?",
    body: "Butiran",
    bodyHint: "Tulis butiran. Baris kosong = perenggan baru, mula baris dengan - untuk senarai, **tebal**.",
    formattingHelp: "Perenggan, - senarai, **tebal**; pautan https boleh ditekan",
    cover: "Banner muka depan",
    coverHint: "Tambah muka depan 16:9",
    coverGuide: "Pastikan teks dan muka dalam bingkai — ia dipotong ke 16:9",
    extraImages: "Gambar lain ({0}/{1})",
    actions: "Butang",
    actionLabel: "Label butang",
    actionUrl: "Pautan",
    actionUrlHint: "https://… atau halaman app seperti /event/…",
    addAction: "Tambah butang",
    removeAction: "Buang butang",
    linkEvent: "Acara berkaitan",
    linkEventNone: "Tiada acara",
    chooseEvent: "Pilih acara",
    publishWhen: "Bila terbit",
    publishNow: "Sekarang",
    featureUntil: "Papar di banner sehingga",
    featureUntilNone: "Tidak dipaparkan",
    commentsOn: "Benarkan komen",
    commentsOnSub: "Tutup untuk notis yang tak perlukan balasan",
    showInFeed: "Papar juga di suapan Home",
    showInFeedSub: "Kalau tak, hanya di Pengumuman",
    official: "Rasmi",
    commentsOff: "Komen ditutup untuk pengumuman ini",
    scheduledFor: "Dijadualkan pada {0}",
    published: "Pengumuman diterbitkan",
    scheduled: "Pengumuman dijadualkan pada {0}",
    updated: "Pengumuman dikemas kini",
    notAllowed: "Hanya AJK kelab dan admin boleh buat pengumuman.",
    loadFailed: "Tak dapat semak akses pengumuman kau",
    errTitleRequired: "Tambah tajuk",
    errTitleTooLong: "Tajuk maksimum {0} aksara",
    errBodyTooLong: "Butiran maksimum {0} aksara",
    errCategory: "Pilih kategori yang kau dibenarkan",
    errImages: "Maksimum {0} gambar lain",
    errActions: "Maksimum {0} butang",
    errFeatureBeforePublish: "Tarikh tamat banner mesti selepas terbit",
    errActionEmptyLabel: "Tambah label butang",
    errActionLabelTooLong: "Label maksimum {0} aksara",
    errActionEmptyUrl: "Tambah pautan",
    errActionNotHttps: "Guna pautan selamat https://",
    errActionUnknownRoute: "Itu bukan halaman dalam app",
    errActionBadUrl: "Itu tak nampak macam pautan",
  );

  static AnnounceStrings of(AppLanguage lang) => lang == AppLanguage.ms ? ms : en;
}

extension AnnounceL10nContext on BuildContext {
  AnnounceStrings get announceL10n =>
      AnnounceStrings.of(watch<LanguageCubit>().state.language);
  AnnounceStrings get announceL10nRead =>
      AnnounceStrings.of(read<LanguageCubit>().state.language);
}
