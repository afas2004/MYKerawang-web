import 'app_strings.dart';

/// Copy for the v1.4 create flows (post-as, listing extras, the create
/// sheet's Announcement entry). English and Malay; Japanese → English.
///
/// Usage: `context.l10n.create.condition`.
class CreateStrings {
  final String postAs;
  final String yourself;
  final String sellingAs;
  final String hostedBy;
  final String clubContactNote;
  final String clubEventNote;
  final String condition;
  final String conditionNew;
  final String conditionLikeNew;
  final String conditionUsed;
  final String meetup;
  final String meetupHint;
  final String quantity;
  final String quantityHelp;
  final String quantityInvalid;
  final String announcement;
  final String announcementSub;

  const CreateStrings({
    required this.postAs,
    required this.yourself,
    required this.sellingAs,
    required this.hostedBy,
    required this.clubContactNote,
    required this.clubEventNote,
    required this.condition,
    required this.conditionNew,
    required this.conditionLikeNew,
    required this.conditionUsed,
    required this.meetup,
    required this.meetupHint,
    required this.quantity,
    required this.quantityHelp,
    required this.quantityInvalid,
    required this.announcement,
    required this.announcementSub,
  });

  static const en = CreateStrings(
    postAs: "Post as",
    yourself: "Yourself",
    sellingAs: "Selling as",
    hostedBy: "Hosted by",
    clubContactNote: "Buyers get the club's contact details, not yours.",
    clubEventNote: "Shown as an official club event.",
    condition: "Condition",
    conditionNew: "New",
    conditionLikeNew: "Like new",
    conditionUsed: "Used",
    meetup: "Meet-up point",
    meetupHint: "e.g. Kolej lobby, weekdays after 6pm",
    quantity: "Quantity available",
    quantityHelp: "For club merch or tickets with several units.",
    quantityInvalid: "Enter a whole number of at least 1",
    announcement: "Announcement",
    announcementSub: "Official notice from your club or the kolej",
  );

  static const ms = CreateStrings(
    postAs: "Siar sebagai",
    yourself: "Diri sendiri",
    sellingAs: "Jual sebagai",
    hostedBy: "Dianjurkan oleh",
    clubContactNote: "Pembeli mendapat butiran hubungan kelab, bukan anda.",
    clubEventNote: "Dipaparkan sebagai acara rasmi kelab.",
    condition: "Keadaan",
    conditionNew: "Baharu",
    conditionLikeNew: "Seperti baharu",
    conditionUsed: "Terpakai",
    meetup: "Tempat berjumpa",
    meetupHint: "cth. Lobi kolej, hari bekerja selepas 6 petang",
    quantity: "Kuantiti tersedia",
    quantityHelp: "Untuk barangan kelab atau tiket dengan beberapa unit.",
    quantityInvalid: "Masukkan nombor bulat sekurang-kurangnya 1",
    announcement: "Pengumuman",
    announcementSub: "Notis rasmi daripada kelab anda atau kolej",
  );

  /// Stored values of listings.condition, in display order.
  static const conditions = ['new', 'like_new', 'used'];

  String conditionLabel(String? c) => switch (c) {
        'new' => conditionNew,
        'like_new' => conditionLikeNew,
        'used' => conditionUsed,
        _ => '',
      };
}

extension CreateStringsOf on AppStrings {
  CreateStrings get create => identical(this, AppStrings.ms) ? CreateStrings.ms : CreateStrings.en;
}
