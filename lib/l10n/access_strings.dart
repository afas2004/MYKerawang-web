import 'app_strings.dart';

/// Copy for guest access, sharing, event cancellation and the contact
/// sheet, in the same three languages as [AppStrings].
///
/// Kept beside AppStrings rather than inside it so this work could land
/// in parallel with other edits to that file; fold these into AppStrings
/// whenever convenient — call sites (`s.guestPromptTitle`) won't change.
extension AccessStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  // ---- guest access ----
  String get guestPromptTitle =>
      _t("Log in to continue", "Log masuk untuk teruskan", "続けるにはログイン");
  String get guestPromptBody => _t(
      "Log in or sign up to comment, join events, contact sellers and follow people.",
      "Log masuk atau daftar untuk komen, join acara, hubungi penjual dan follow orang.",
      "コメント、イベント参加、出品者への連絡、フォローにはログインまたは登録が必要です。");
  String get loginOrSignUp =>
      _t("Log in / Sign up", "Log masuk / Daftar", "ログイン / 登録");
  String get notNow => _t("Not now", "Nanti dulu", "あとで");
  String get guestBanner => _t(
      "You're viewing as a guest", "Anda melihat sebagai tetamu", "ゲストとして閲覧中");
  String get loginToComment =>
      _t("Log in to comment", "Log masuk untuk komen", "コメントするにはログイン");
  String get loginToFollow =>
      _t("Log in to follow", "Log masuk untuk follow", "フォローするにはログイン");
  String get loginToContact => _t("Log in to contact the seller",
      "Log masuk untuk hubungi penjual", "出品者に連絡するにはログイン");

  // ---- sign-up ----
  String get studentEmailOnly => _t(
      "New accounts need a UiTM student email (@student.uitm.edu.my).",
      "Akaun baharu perlu guna emel pelajar UiTM (@student.uitm.edu.my).",
      "新規登録にはUiTMの学生用メール（@student.uitm.edu.my）が必要です。");
  String get anyEmailHint => _t(
      "New here? Sign up with any email address.",
      "Baru di sini? Daftar dengan mana-mana alamat e-mel.",
      "新規登録はどのメールアドレスでもできます。");

  // ---- registration switch (owner) ----
  String get regTitle => _t("Registration", "Pendaftaran", "登録");
  String get regOpenTitle =>
      _t("Allow any email to sign up", "Benarkan daftar dengan mana-mana e-mel", "Allow any email to sign up");
  String get regOpenBody => _t(
      "Off: only @student.uitm.edu.my addresses can create an account. On: anyone can, and student status is proven separately.",
      "Tutup: hanya alamat @student.uitm.edu.my boleh cipta akaun. Buka: sesiapa boleh, dan status pelajar dibuktikan secara berasingan.",
      "Off: student addresses only. On: anyone can sign up.");
  String get regConfirmTitle => _t("Open signup to any email?",
      "Buka pendaftaran untuk semua e-mel?", "Open signup to any email?");
  String get regConfirmBody => _t(
      "Anyone with an email address will be able to create an account, and the public signup page becomes reachable by link. Existing accounts are not affected.",
      "Sesiapa yang ada alamat e-mel boleh mencipta akaun, dan halaman pendaftaran awam boleh dicapai melalui pautan. Akaun sedia ada tidak terjejas.",
      "Anyone with an email can create an account.");
  String get regConfirmAction => _t("Open signup", "Buka pendaftaran", "Open signup");
  String get regNowOpen => _t("Signup is open to any email",
      "Pendaftaran dibuka untuk semua e-mel", "Signup is open to any email");
  String get regNowStudentOnly => _t("Signup is limited to student emails",
      "Pendaftaran terhad kepada e-mel pelajar", "Signup is limited to student emails");

  // ---- student verification ----
  String get verifySectionTitle =>
      _t("Student verification", "Pengesahan pelajar", "学生確認");
  String get verifySwitchTitle =>
      _t("Require verified students", "Wajibkan pelajar disahkan", "学生確認を必須にする");
  String get verifySwitchBody => _t(
      "Joining an event, creating an event and selling then need a verified student account. Posting and commenting stay open. Admins and owners are exempt.",
      "Menyertai acara, mencipta acara dan menjual kemudiannya memerlukan akaun pelajar yang disahkan. Menyiar dan mengomen kekal terbuka. Admin dan pemilik dikecualikan.",
      "イベント参加・作成・出品には学生確認済みのアカウントが必要になります。投稿とコメントは自由です。管理者は対象外です。");
  String get verifyConfirmTitle =>
      _t("Turn on student verification?", "Hidupkan pengesahan pelajar?", "学生確認を有効にしますか？");
  String get verifyConfirmBody => _t(
      "Accounts that are not verified yet will not be able to join events, create events or sell until an admin verifies them. Nobody can verify themselves yet — the email code flow is not built.",
      "Akaun yang belum disahkan tidak boleh menyertai acara, mencipta acara atau menjual sehingga admin mengesahkannya. Buat masa ini tiada siapa boleh mengesahkan diri sendiri — aliran kod e-mel belum dibina.",
      "未確認のアカウントは、管理者が確認するまでイベント参加・作成・出品ができなくなります。現在、自己確認の仕組みはまだありません。");
  String get verifyConfirmAction =>
      _t("Turn on", "Hidupkan", "有効にする");
  String get verifyOn =>
      _t("Student verification is on", "Pengesahan pelajar dihidupkan", "学生確認を有効にしました");
  String get verifyOff =>
      _t("Student verification is off", "Pengesahan pelajar dimatikan", "学生確認を無効にしました");
  String get verifyRequired =>
      _t("Verify your student status to do this.", "Sahkan status pelajar anda untuk melakukan ini.", "これを行うには学生確認が必要です。");

  // ---- verification: the student's side ----
  String get verifyTitle => _t("Student verification", "Pengesahan pelajar", "学生確認");
  String get verifyStatusNone => _t("Not verified", "Belum disahkan", "未確認");
  String get verifyStatusPending =>
      _t("Waiting for review", "Menunggu semakan", "審査待ち");
  String get verifyStatusVerified =>
      _t("Verified student", "Pelajar disahkan", "確認済み");
  String get verifyStatusRejected => _t("Not approved", "Tidak diluluskan", "承認されませんでした");
  String get verifyStatusRevoked => _t("Revoked", "Ditarik balik", "取り消し済み");
  String get verifySheetTitle =>
      _t("Verify your student status", "Sahkan status pelajar anda", "学生確認");
  String get verifySheetIntro => _t(
      "Enter the UiTM student email you can still open. An admin checks it by hand — there is no code by email yet.",
      "Masukkan e-mel pelajar UiTM yang masih boleh anda buka. Admin menyemaknya secara manual — belum ada kod melalui e-mel.",
      "まだ開けるUiTMの学生メールを入力してください。管理者が手作業で確認します（メールコードはまだありません）。");
  String get verifyEmailLabel => _t("Student email", "E-mel pelajar", "学生メール");
  String get verifyEmailHint =>
      _t("you@student.uitm.edu.my", "anda@student.uitm.edu.my", "you@student.uitm.edu.my");
  String get verifySubmit => _t("Submit for review", "Hantar untuk semakan", "審査に提出");
  String get verifySubmitted =>
      _t("Submitted for review", "Dihantar untuk semakan", "審査に提出しました");
  String get verifyPendingBody => _t(
      "An admin will check your request. You can keep using the app in the meantime.",
      "Admin akan menyemak permintaan anda. Anda boleh terus menggunakan aplikasi sementara itu.",
      "管理者が確認します。それまでアプリはそのまま使えます。");
  String get verifyVerifiedBody => _t(
      "Verified on {0}. You can join and create events and sell in the Market.",
      "Disahkan pada {0}. Anda boleh menyertai dan mencipta acara serta menjual di Pasar.",
      "{0}に確認されました。イベントの参加・作成、出品ができます。");
  String get verifyRejectedBody => _t(
      "Your last request was not approved. Check the address and send it again.",
      "Permintaan terakhir anda tidak diluluskan. Semak alamat dan hantar semula.",
      "前回の申請は承認されませんでした。アドレスを確認して再提出してください。");
  String get verifyRevokedBody => _t(
      "Your verification was revoked. Send a request again if this is a mistake.",
      "Pengesahan anda ditarik balik. Hantar permintaan semula jika ini satu kesilapan.",
      "確認は取り消されました。誤りであれば再申請してください。");

  // ---- verification: refusals ----
  String get verifyClosed => _t("Student verification is not open yet.",
      "Pengesahan pelajar belum dibuka.", "学生確認はまだ開始されていません。");
  String get verifyDomainError => _t("Use your @student.uitm.edu.my address.",
      "Gunakan alamat @student.uitm.edu.my anda.", "@student.uitm.edu.my のアドレスを使ってください。");
  String get verifyTakenError => _t("That address is already used by another account.",
      "Alamat itu sudah digunakan oleh akaun lain.", "そのアドレスは別のアカウントで使われています。");
  String get verifyWaitError => _t("Try again in a few minutes.",
      "Cuba lagi dalam beberapa minit.", "数分後にもう一度お試しください。");
  String get verifyAlreadyError => _t("You are already verified.",
      "Anda sudah disahkan.", "すでに確認済みです。");

  // ---- verification: admin queue ----
  String get verifyQueueTitle => _t("Verifications", "Pengesahan", "学生確認");
  String get verifyQueueEmpty => _t("No pending requests.", "Tiada permintaan menunggu.", "保留中の申請はありません。");
  String get verifyApprove => _t("Approve", "Luluskan", "承認");
  String get verifyReject => _t("Reject", "Tolak", "却下");
  String get verifyApproved => _t("Approved", "Diluluskan", "承認しました");
  String get verifyRejectedDone => _t("Rejected", "Ditolak", "却下しました");
  String get verifySubmittedAt => _t("Submitted {0}", "Dihantar {0}", "提出 {0}");

  // ---- event details: registration, merit, contacts, attendance ----
  String get eventSearchHint => _t("Search events", "Cari acara", "Search events");
  String get eventPickerEmpty =>
      _t("No events match that search.", "Tiada acara sepadan dengan carian itu.", "No events match.");
  String get evRegistration => _t("Registration", "Pendaftaran", "Registration");
  String get evCloseAtStart => _t("Close registration when the event starts",
      "Tutup pendaftaran apabila acara bermula", "Close registration when the event starts");
  String get evCloseAtStartHint => _t(
      "Nobody can join once it begins. You can also close it early from the event page.",
      "Tiada siapa boleh menyertai selepas ia bermula. Anda juga boleh menutupnya lebih awal dari halaman acara.",
      "Nobody can join once it begins.");
  String get evClosed => _t("Registration closed", "Pendaftaran ditutup", "Registration closed");
  String get evFull => _t("This event is full", "Acara ini sudah penuh", "This event is full");
  String get evCloseNow => _t("Close registration now", "Tutup pendaftaran sekarang", "Close registration now");
  String get evCapacity => _t("Places (optional)", "Tempat (pilihan)", "Places (optional)");
  String get evCapacityHint =>
      _t("Leave empty for unlimited", "Biarkan kosong untuk tanpa had", "Leave empty for unlimited");
  String get evFee => _t("Fee (RM)", "Yuran (RM)", "Fee (RM)");
  String get evFeeHint => _t("Empty or 0 means free", "Kosong atau 0 bermaksud percuma", "Empty or 0 means free");
  String get evFeeFree => _t("Free", "Percuma", "Free");
  // ---- composer: the two fields events were missing ----
  String get eventPic => _t("Person in charge (optional)", "Pegawai bertanggungjawab (pilihan)", "Person in charge (optional)");
  String get eventPicHint => _t("Name and phone", "Nama dan telefon", "Name and phone");
  String get eventCategoryHint =>
      _t("Type to search a category", "Taip untuk cari kategori", "Type to search a category");
  String get eventButtons => _t("Buttons", "Butang", "Buttons");
  String get eventButtonsHint => _t(
      "Up to two: a form, a map, a registration page. https:// or an app route like /event/…",
      "Maksimum dua: borang, peta, halaman pendaftaran. https:// atau laluan aplikasi seperti /event/…",
      "Up to two: https:// or an app route.");
  String get eventAddButton => _t("Add button", "Tambah butang", "Add button");
  String get evPic =>
      _t("Person in charge", "Pegawai bertanggungjawab", "Person in charge");
  String get evManage => _t("Manage event", "Urus acara", "Manage event");
  String get evManageSubtitle => _t(
      "Attendance, reports and the door code",
      "Kehadiran, laporan dan kod pintu",
      "Attendance, reports and the door code");
  String get evCheckinOpen =>
      _t("Check-in is open", "Daftar masuk dibuka", "Check-in is open");
  String get evCheckinOpenHint => _t(
      "Scan the code at the door, or open the event on your phone.",
      "Imbas kod di pintu, atau buka acara ini di telefon.",
      "Scan the code at the door, or open the event on your phone.");
  String get evLive => _t("Live now", "Sedang berlangsung", "Live now");

  // ---- the take-attendance flow ----
  String get evTakeAttendance =>
      _t("Take attendance", "Ambil kehadiran", "Take attendance");
  String get evStartTitle => _t("Take attendance", "Ambil kehadiran", "Take attendance");
  String get evStartBody => _t(
      "Students scan the code at the door. You can end it whenever you like.",
      "Pelajar imbas kod di pintu. Anda boleh tamatkan bila-bila masa.",
      "Students scan the code at the door.");
  String get evAddKiQuestion => _t(
      "Add the KI report to this check-in?",
      "Tambah laporan KI pada daftar masuk ini?",
      "Add the KI report to this check-in?");
  String get evAddKiHint => _t(
      "Students who check in are asked to answer the form straight afterwards.",
      "Pelajar yang mendaftar masuk akan diminta menjawab borang selepas itu.",
      "Students answer the form straight after checking in.");
  String get evStart => _t("Start", "Mula", "Start");
  String get evEndAttendance =>
      _t("End attendance", "Tamatkan kehadiran", "End attendance");
  String get evEndConfirmTitle =>
      _t("End attendance?", "Tamatkan kehadiran?", "End attendance?");
  String get evEndConfirmBody => _t(
      "The code stops working and you'll see the totals. You can start again later.",
      "Kod tidak lagi berfungsi dan anda akan nampak jumlah. Boleh mula semula nanti.",
      "The code stops working. You can start again later.");
  String get evAttendanceClosed =>
      _t("Attendance closed", "Kehadiran ditutup", "Attendance closed");
  String get evTotalAttendance =>
      _t("Checked in", "Jumlah hadir", "Checked in");
  String get evKiReports => _t("KI reports", "Laporan KI", "KI reports");
  String get evWaitingFirstScan => _t(
      "Waiting for the first scan", "Menunggu imbasan pertama", "Waiting for the first scan");
  String evJustCheckedIn(String name) =>
      _t("$name just checked in", "$name baru mendaftar masuk", "$name just checked in");
  String get evExportAttendance =>
      _t("Attendance CSV", "CSV kehadiran", "Attendance CSV");
  String get evExportKi => _t("KI report CSV", "CSV laporan KI", "KI report CSV");
  String get evExportBoth => _t("Both (2 files)", "Kedua-dua (2 fail)", "Both (2 files)");
  String get evDone => _t("Done", "Selesai", "Done");
  String get evExportFailed => _t(
      "Could not export. Try again.", "Tidak dapat eksport. Cuba lagi.", "Could not export.");
  String get evNoOpenFormYet => _t(
      "Publish a KI form first, then take attendance with it.",
      "Terbitkan borang KI dahulu, kemudian ambil kehadiran dengannya.",
      "Publish a KI form first.");
  String get evAudience => _t("Open to", "Terbuka kepada", "Open to");
  String evAudienceLabel(String? v) => switch (v) {
        'kolej' => _t("This college", "Kolej ini", "This college"),
        'klab' => _t("Club members", "Ahli kelab", "Club members"),
        'awam' => _t("Public", "Awam", "Public"),
        _ => _t("UiTM students", "Pelajar UiTM", "UiTM students"),
      };
  String get evMerit => _t("Merit offered", "Merit disediakan", "Merit offered");
  String get evMeritHint => _t("Only a club (as the host) or an admin can offer merit.",
      "Hanya kelab (sebagai penganjur) atau admin boleh menawarkan merit.",
      "Only a club or an admin can offer merit.");
  String get evMeritNote => _t("Merit note", "Nota merit", "Merit note");
  String get evMeritNoteHint => _t("e.g. 2 merit, kokurikulum", "cth. 2 merit, kokurikulum", "e.g. 2 merit");
  String get evActivityRef => _t("Activity reference", "Rujukan aktiviti", "Activity reference");
  String get evCoOrganiser =>
      _t("With cooperation from", "Dengan kerjasama", "With cooperation from");
  String get evContacts => _t("Contact the organiser", "Hubungi penganjur", "Contact the organiser");
  String get evContactHint =>
      _t("Leave blank to hide a channel.", "Biarkan kosong untuk sembunyikan saluran.", "Leave blank to hide a channel.");
  String get evContactNone => _t("The organiser has not shared a contact.",
      "Penganjur belum berkongsi hubungan.", "The organiser has not shared a contact.");

  // ---- attendance ----
  String get evAttendance => _t("Attendance", "Kehadiran", "Attendance");
  String get evAttendanceHint => _t(
      "Show this code at the door. It refreshes every 10 seconds; students scan it in the app or with their phone camera.",
      "Tunjukkan kod ini di pintu. Ia diperbaharui setiap 10 saat; pelajar mengimbasnya dalam aplikasi atau dengan kamera telefon.",
      "Show this code at the door.");
  String get evAttendanceOff => _t("Turn on attendance", "Hidupkan kehadiran", "Turn on attendance");
  String get evCheckIn => _t("Check in", "Daftar masuk", "Check in");
  String get evScanHint =>
      _t("Point the camera at the organiser's QR code.", "Halakan kamera ke kod QR penganjur.", "Point at the QR code.");
  String get evCheckedIn => _t("You're checked in", "Anda telah didaftarkan", "You're checked in");
  String get evAlreadyIn =>
      _t("You were already checked in", "Anda sudah pun didaftarkan", "You were already checked in");
  String get evCheckinExpired => _t("That code just expired — ask the organiser to show it again.",
      "Kod itu baru tamat — minta penganjur menunjukkannya semula.", "That code expired.");
  String get evCheckinInvalid =>
      _t("That is not a check-in code.", "Itu bukan kod daftar masuk.", "That is not a check-in code.");
  String get evCheckinVerify => _t("Verify your student status before checking in for merit.",
      "Sahkan status pelajar anda sebelum mendaftar masuk untuk merit.", "Verify your student status first.");
  String get evAttendanceEmpty =>
      _t("Nobody has checked in yet.", "Belum ada yang mendaftar masuk.", "Nobody has checked in yet.");
  String get evAttendanceCount =>
      _t("{0} checked in", "{0} telah mendaftar masuk", "{0} checked in");
  String get evExportCsv =>
      _t("Export attendance (CSV)", "Eksport kehadiran (CSV)", "Export attendance (CSV)");
  String get evStudentId => _t("Student ID", "No. pelajar", "Student ID");
  String get evCheckedAt => _t("Checked in", "Daftar masuk", "Checked in");
  String get evName => _t("Name", "Nama", "Name");

  // ---- club recruitment ----
  String get signOutConfirmTitle => _t("Sign out?", "Log keluar?", "Sign out?");
  String get signOutConfirmBody => _t(
      "You can keep reading as a guest, or sign back in any time.",
      "Anda boleh terus membaca sebagai tetamu, atau log masuk semula bila-bila masa.",
      "You can keep reading as a guest.");
  String get ownerDeleteBlocked => _t(
      "The owner account can't delete itself — the app would be left without an owner. Hand the owner role to another account first.",
      "Akaun pemilik tidak boleh memadam dirinya — aplikasi akan hilang pemilik. Pindahkan peranan pemilik kepada akaun lain dahulu.",
      "The owner account can't delete itself.");
  String get deleteNeedsUsername => _t(
      "Finish setting up your profile (choose a username) before deleting the account.",
      "Selesaikan profil anda (pilih nama pengguna) sebelum memadam akaun.",
      "Finish your profile before deleting the account.");
  String get clubRecruitment =>
      _t("Membership", "Keahlian", "Membership");
  String get clubRecruitmentOpen =>
      _t("Accept join requests", "Terima permintaan menyertai", "Accept join requests");
  String get clubRecruitmentHelp => _t(
      "When off, the club page shows no way to request membership, and nobody can apply. You can still add members by username.",
      "Apabila dimatikan, halaman kelab tidak menunjukkan cara untuk memohon, dan tiada siapa boleh memohon. Anda masih boleh menambah ahli melalui nama pengguna.",
      "When off, nobody can request to join.");
  String get clubRecruitmentClosed => _t(
      "This club isn't taking requests right now.",
      "Kelab ini tidak menerima permohonan buat masa ini.",
      "This club isn't taking requests right now.");
  String get clubRequestJoin =>
      _t("Request to join", "Mohon menyertai", "Request to join");

  // ---- categories ----
  String get catTitle => _t("Categories", "Kategori", "カテゴリー");
  String get catEvents => _t("Event topics", "Topik acara", "イベント");
  String get catListings => _t("Market categories", "Kategori Pasar", "マーケット");
  String get catAdd => _t("Add category", "Tambah kategori", "カテゴリーを追加");
  String get catEdit => _t("Edit category", "Edit kategori", "カテゴリーを編集");
  String get catNameEn => _t("Name (English)", "Nama (Inggeris)", "名前（英語）");
  String get catNameMs => _t("Name (Malay)", "Nama (Melayu)", "名前（マレー語）");
  String get catSlug => _t("Slug", "Slug", "スラッグ");
  String get catSlugHint => _t("lowercase-with-dashes", "huruf-kecil-dengan-sempang", "lowercase-with-dashes");
  String get catActive => _t("Active", "Aktif", "有効");
  String get catInactive => _t("Hidden", "Disembunyikan", "非表示");
  String get catSaved => _t("Category saved", "Kategori disimpan", "カテゴリーを保存しました");
  String get catDeleted => _t("Category deleted", "Kategori dipadam", "カテゴリーを削除しました");
  String get catInUse => _t(
      "Posts still use this category, so it can't be deleted. Switch it off instead.",
      "Masih ada post menggunakan kategori ini, jadi ia tidak boleh dipadam. Matikannya sahaja.",
      "このカテゴリーはまだ使われているため削除できません。無効にしてください。");
  String get catLastOne => _t("A category needs a name and a slug.",
      "Kategori perlu nama dan slug.", "名前とスラッグが必要です。");

  String get categoryPickHint => _t(
      "Pick up to {0}. The first one is the main category.",
      "Pilih sehingga {0}. Yang pertama ialah kategori utama.",
      "最大{0}件まで。最初のものがメインカテゴリーです。");
  String get categoryRequired => _t("Pick at least one category.",
      "Pilih sekurang-kurangnya satu kategori.", "カテゴリーを1つ以上選んでください。");

  // ---- sharing ----
  String get copyLink => _t("Copy link", "Salin pautan", "リンクをコピー");
  String get linkCopied =>
      _t("Link copied", "Pautan disalin", "リンクをコピーしました");
  String get attachPhotosInstead => _t("Attach the photos instead",
      "Lampirkan gambar sebagai ganti", "代わりに写真を添付");
  String get attachPhotosWebWarning => _t(
      "Most apps drop your message when photos are attached. The link keeps it, and still shows every photo.",
      "Kebanyakan app buang mesej bila gambar dilampirkan. Pautan kekalkan mesej, dan masih tunjuk semua gambar.",
      "写真を添付するとメッセージが消えるアプリがほとんどです。リンクならメッセージが残り、写真もすべて見られます。");
  String get attachPhotosNativeWarning => _t(
      "Some apps drop the message when several photos are attached.",
      "Sesetengah app buang mesej bila banyak gambar dilampirkan.",
      "複数の写真を添付するとメッセージが消えるアプリがあります。");

  // ---- event cancellation ----
  String get cancelled => _t("Cancelled", "Dibatalkan", "中止");
  String get eventCancelledBanner => _t(
      "This event has been cancelled.",
      "Acara ini telah dibatalkan.",
      "このイベントは中止されました。");
  String get cancelEventSoftConfirm => _t(
      "Everyone who joined will be notified. The event stays visible, marked as cancelled, and you can restore it later.",
      "Semua yang join akan dimaklumkan. Acara kekal kelihatan dengan tanda dibatalkan, dan boleh dipulihkan nanti.",
      "参加者全員に通知されます。イベントは「中止」として表示されたまま残り、後で再開できます。");
  String get restoreEvent => _t("Restore event", "Pulihkan acara", "イベントを再開");
  String get eventRestored =>
      _t("Event restored", "Acara dipulihkan", "イベントを再開しました");
  String get deleteEvent => _t("Delete event", "Padam acara", "イベントを削除");
  String get deleteEventConfirm => _t(
      "This permanently removes the event, its comments and who joined. It can't be undone.\n\nType the event title to confirm:",
      "Ini akan padam acara, komen dan senarai peserta selama-lamanya. Tak boleh diundur.\n\nTaip tajuk acara untuk sahkan:",
      "イベント、コメント、参加者リストが完全に削除されます。元に戻せません。\n\n確認のためイベント名を入力してください：");
  String get eventDeleted =>
      _t("Event deleted", "Acara dipadam", "イベントを削除しました");
  String get manageEvent => _t("Manage event", "Urus acara", "イベントを管理");

  // ---- contact sheet ----
  String get chatFirstHint => _t(
      "Chat with the seller first to agree on the price and where to meet.",
      "Chat dengan penjual dulu untuk setuju harga dan tempat jumpa.",
      "まず出品者とチャットして、価格と待ち合わせ場所を決めましょう。");
  String get showPaymentQr =>
      _t("Show payment QR", "Tunjuk QR bayaran", "支払い用QRを表示");
  String get paymentCaution => _t(
      "Only pay once you've met the seller or agreed on the deal.",
      "Bayar hanya selepas jumpa penjual atau dah setuju urusan.",
      "支払いは出品者と会うか、取引に合意してからにしましょう。");

  String get tooManyContactRequests => _t(
      "Too many contact requests, try again later.",
      "Terlalu banyak permintaan hubungan, cuba lagi nanti.",
      "連絡先のリクエストが多すぎます。しばらくしてからお試しください。");
  String get listingNowSold => _t("This item has just been sold.",
      "Barang ini baru sahaja terjual.", "この商品は売り切れになりました。");

  // ---- listing status ----
  String get statusAvailable => _t("Available", "Ada", "販売中");
  String get statusReserved => _t("Reserved", "Ditempah", "取引中");
  String get listingStatus => _t("Status", "Status", "ステータス");
  String get reservedHint => _t(
      "Someone is arranging this with the seller. You can still message them in case it falls through.",
      "Ada orang sedang berurusan dengan penjual. Anda masih boleh mesej kalau tak jadi.",
      "他の人が出品者と取引中です。不成立の場合に備えて連絡することはできます。");
  String get statusUpdated =>
      _t("Status updated", "Status dikemas kini", "ステータスを更新しました");

  // ---- feedback ----
  String get retry => _t("Retry", "Cuba lagi", "再試行");
  String get somethingWentWrong => _t("Something went wrong. Check your connection and try again.",
      "Ada masalah. Semak sambungan dan cuba lagi.", "問題が発生しました。接続を確認してもう一度お試しください。");
  String get commentPosted => _t("Comment posted", "Komen dihantar", "コメントを投稿しました");

  // ---- market filters ----
  String get filters => _t("Filters", "Penapis", "絞り込み");
  String get priceRange => _t("Price (RM)", "Harga (RM)", "価格（RM）");
  String get minPrice => _t("Min", "Min", "最低");
  String get maxPrice => _t("Max", "Maks", "最高");
  String get sortBy => _t("Sort by", "Susun ikut", "並び替え");
  String get sortNewest => _t("Newest", "Terbaru", "新着順");
  String get sortCheapest => _t("Cheapest", "Termurah", "安い順");
  String get sortPriciest => _t("Most expensive", "Termahal", "高い順");
  String get resetFilters => _t("Reset", "Set semula", "リセット");
  String get showResults => _t("Show results", "Tunjuk hasil", "結果を表示");
  String get loadMore => _t("Load more", "Muat lagi", "さらに読み込む");
  String get noMatchingItems => _t("No items match these filters.",
      "Tiada barang sepadan dengan penapis ini.", "条件に合う商品はありません。");

  // ---- events list ----
  String get eventToday => _t("Today", "Hari ini", "今日");
  String get eventTomorrow => _t("Tomorrow", "Esok", "明日");
  String get eventInDays => _t("In {0} days", "Lagi {0} hari", "{0}日後");
  String get eventHappeningNow => _t("Happening now", "Sedang berlangsung", "開催中");

  // ---- event detail extras ----
  String get addToCalendar =>
      _t("Add to calendar", "Tambah ke kalendar", "カレンダーに追加");
  String get calendarFileSaved => _t("Calendar file downloaded — open it to add the event.",
      "Fail kalendar dimuat turun — buka untuk tambah acara.", "カレンダーファイルをダウンロードしました。開いて追加してください。");
  String get followingGoingOne => _t("1 person you follow is going",
      "1 orang yang anda follow akan pergi", "フォロー中の1人が参加予定");
  String get followingGoingMany => _t("{0} people you follow are going",
      "{0} orang yang anda follow akan pergi", "フォロー中の{0}人が参加予定");

  // ---- UI redesign: events / market / login ----
  String get sectionThisWeek => _t("This week", "Minggu ni", "今週");
  String get sectionLater => _t("Later", "Akan datang", "今後");
  String get sectionEnded =>
      _t("Ended & cancelled", "Dah tamat & dibatalkan", "終了・中止");
  String get goingCount => _t("{0} going", "{0} pergi", "{0}人参加");
  String get byOrganiser => _t("by {0}", "oleh {0}", "主催：{0}");
  String get officialAccount => _t("Official", "Rasmi", "公式");
  String get noEventsYetHint => _t(
      "Nothing on yet. Clubs and friends post events here — check back soon, or create one.",
      "Belum ada apa-apa lagi. Kelab dan kawan-kawan akan post acara di sini — jenguk lagi nanti, atau buat sendiri.",
      "まだイベントはありません。");
  String get noItemsYetHint => _t(
      "No listings here yet. Got something to let go? Sell it to your college mates.",
      "Belum ada barang lagi. Ada barang nak lepas? Jual kat member kolej.",
      "まだ出品はありません。");
  String get clearSearch => _t("Clear search", "Kosongkan carian", "検索をクリア");
  String get openInMaps => _t("Open in Maps", "Buka dalam Maps", "地図で開く");
  String get organiserBadge => _t("Organiser", "Penganjur", "主催者");
  String get photoCount => _t("Photo {0} of {1}", "Gambar {0} daripada {1}", "{1}枚中{0}枚目");
  String get closeGallery => _t("Close", "Tutup", "閉じる");
  String get previousPhoto => _t("Previous photo", "Gambar sebelum", "前の写真");
  String get nextPhoto => _t("Next photo", "Gambar seterusnya", "次の写真");
  String get zoomIn => _t("Zoom in", "Zum masuk", "拡大");
  String get zoomOut => _t("Zoom out", "Zum keluar", "縮小");
  String get sectionDetails => _t("Details", "Butiran", "詳細");
  String get sectionPhotos => _t("Photos", "Gambar", "写真");
  String get sectionWhenWhere => _t("When & where", "Bila & di mana", "日時と場所");
  String get sectionPricing => _t("Price & category", "Harga & kategori", "価格とカテゴリー");
  String get loginValueTitle => _t("Your college, in one place",
      "Kolej anda, semua dalam satu tempat", "あなたのカレッジをひとつに");
  String get loginValueEvents => _t("See what's on — club events, talks and makan-makan.",
      "Tengok apa yang berlangsung — acara kelab, ceramah dan makan-makan.", "クラブのイベントや講演をチェック");
  String get loginValueMarket => _t("Buy and sell with people from your own college.",
      "Jual beli dengan orang kolej sendiri.", "同じカレッジの仲間と売り買い");
  String get loginValueCommunity => _t("Ask, share and stay in the loop with posts and comments.",
      "Tanya, kongsi dan ikuti perkembangan melalui post dan komen.", "投稿とコメントで情報共有");
  String get studentEmailHint => _t("New here? Sign up with your @student.uitm.edu.my email.",
      "Baru di sini? Daftar dengan emel @student.uitm.edu.my anda.", "新規登録は@student.uitm.edu.myのメールで");
  String get emailInvalid => _t("Enter a valid email address.",
      "Masukkan alamat emel yang sah.", "有効なメールアドレスを入力してください。");
  String get passwordTooShort => _t("At least 6 characters.",
      "Sekurang-kurangnya 6 aksara.", "6文字以上");
  String get priceInvalid => _t("Enter a price, e.g. 12.50",
      "Masukkan harga, cth. 12.50", "価格を入力してください（例：12.50）");

  // ---- navigation ----
  String get eventPublished => _t("Event published", "Acara diterbitkan", "イベントを公開しました");
  String get eventUpdated => _t("Event updated", "Acara dikemas kini", "イベントを更新しました");

  // ---- events list ----
  String get pastEvents => _t("Past events", "Acara lepas", "過去のイベント");
  String get pastEventsCount =>
      _t("{0} ended or cancelled", "{0} dah tamat atau dibatalkan", "{0}件 終了・中止");
  String get postedOn => _t("Posted", "Dipos", "投稿日");
  String get draftRestored => _t("Restored what you were writing.",
      "Draf yang belum siap dipulihkan.", "書きかけの内容を復元しました。");
}
