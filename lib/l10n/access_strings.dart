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
  String get fieldRequired => _t("Required", "Wajib diisi", "必須");
  String get priceInvalid => _t("Enter a price, e.g. 12.50",
      "Masukkan harga, cth. 12.50", "価格を入力してください（例：12.50）");
}
