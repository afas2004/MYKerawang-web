import 'app_strings.dart';

/// Copy for event timing (once / repeats / pick dates), series, registration
/// close time and online / hybrid events, in the same three languages as
/// [AppStrings]. Kept beside it, like access_strings.dart.
extension EventTimingStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  // ---- timing modes
  String get tmOnce => _t("Once", "Sekali", "1回");
  String get tmRepeats => _t("Repeats", "Berulang", "繰り返し");
  String get tmDates => _t("Pick dates", "Pilih tarikh", "日付を選ぶ");
  String get tmOnceHint => _t(
      "Ends on a later day? That's a multi-day event with one check-in.",
      "Tamat pada hari lain? Itu acara beberapa hari dengan satu daftar masuk.",
      "別の日に終わる場合は、チェックイン1回の複数日イベントになります。");
  String get tmSeriesNote => _t(
      "Each date is published as its own event. People join each date separately.",
      "Setiap tarikh diterbitkan sebagai acara sendiri. Peserta join setiap tarikh secara berasingan.",
      "各日付は個別のイベントとして公開され、参加も日付ごとです。");

  // ---- repeats
  String get tmOn => _t("On", "Pada", "曜日");
  String get tmFrom => _t("From", "Dari", "開始");
  String get tmTo => _t("To", "Hingga", "終了");
  String get tmEvery => _t("Every", "Setiap", "間隔");
  String tmWeeks(int n) => n == 1
      ? _t("1 week", "1 minggu", "毎週")
      : _t("$n weeks", "$n minggu", "$n週ごと");
  String get tmFewerWeeks => _t("Fewer weeks", "Kurang minggu", "間隔を短く");
  String get tmMoreWeeks => _t("More weeks", "Lebih minggu", "間隔を長く");
  String get tmFirstDate => _t("First date", "Tarikh pertama", "初回");
  String get tmUntil => _t("Until", "Sehingga", "最終日");
  String get tmDatesLabel => _t("Dates", "Tarikh", "日程");
  String tmSessions(int n) => _t(n == 1 ? "1 date" : "$n dates", "$n tarikh", "$n回");
  String get tmAddExtra => _t("Add extra date", "Tambah tarikh lain", "日付を追加");
  String get tmSkip => _t("Skip this date", "Langkau tarikh ini", "この日を除く");
  String get tmUndoSkip => _t("Undo", "Batal", "元に戻す");
  String get tmExtra => _t("extra", "tambahan", "追加");

  /// Short weekday names, Monday first (DateTime.monday == 1).
  List<String> get weekdaysShort => identical(this, AppStrings.ms)
      ? const ['Isn', 'Sel', 'Rab', 'Kha', 'Jum', 'Sab', 'Ahd']
      : identical(this, AppStrings.ja)
          ? const ['月', '火', '水', '木', '金', '土', '日']
          : const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  // ---- pick dates
  String get tmAddDate => _t("Add date", "Tambah tarikh", "日付を追加");
  String get tmRemoveDate => _t("Remove this date", "Buang tarikh ini", "この日を削除");
  String get tmDatesHint => _t("Each date can have its own time.",
      "Setiap tarikh boleh ada masa sendiri.", "日付ごとに時間を設定できます。");
  String tmDatesOf(int n, int max) => _t("$n of $max dates", "$n daripada $max tarikh", "$n / $max日");

  // ---- problems
  String get tmNeedWeekday => _t("Pick at least one day.", "Pilih sekurang-kurangnya satu hari.",
      "曜日を1つ以上選んでください。");
  String get tmNeedDate => _t("Add at least one date.", "Tambah sekurang-kurangnya satu tarikh.",
      "日付を1つ以上追加してください。");
  String tmTooMany(int max) => _t("A series can have up to $max dates.",
      "Satu siri boleh ada sehingga $max tarikh.", "シリーズは最大$max日までです。");
  String get tmEndBeforeStart => _t("Each date must end after it starts.",
      "Setiap tarikh mesti tamat selepas ia bermula.", "各日程は開始より後に終わる必要があります。");
  String get tmDuplicate => _t("Two dates start at the same time.",
      "Dua tarikh bermula pada masa yang sama.", "同じ開始時刻の日程が2つあります。");

  // ---- registration closes
  String get rcLabel => _t("Registration closes", "Pendaftaran ditutup", "受付締切");
  String get rcAtStart => _t("When it starts", "Bila bermula", "開始時");
  String get rcSetTime => _t("At a set time", "Pada masa ditetapkan", "指定日時");
  String get rcNever => _t("Never", "Tidak ditutup", "締切なし");
  String get rcHintStart => _t("Closes when the event starts.",
      "Ditutup apabila acara bermula.", "イベント開始時に締め切ります。");
  String get rcHintSeriesStart => _t("Each date closes when it starts.",
      "Setiap tarikh ditutup apabila ia bermula.", "各日程は開始時に締め切ります。");
  String get rcHintSet => _t("Pick any time before the start.",
      "Pilih mana-mana masa sebelum acara bermula.", "開始前の日時を選んでください。");
  String get rcHintSeriesSet => _t("Counted back from each date's start.",
      "Dikira dari masa mula setiap tarikh.", "各日程の開始時刻から逆算します。");
  String get rcHintNever => _t("People can join until it ends.",
      "Peserta boleh join sehingga acara tamat.", "終了まで参加できます。");
  String get rcAfterStart => _t("Registration must close by the start.",
      "Pendaftaran mesti ditutup sebelum acara bermula.", "締切は開始時刻までに設定してください。");
  String rcBefore(Duration d) {
    if (d.inDays >= 7 && d.inDays % 7 == 0) {
      final w = d.inDays ~/ 7;
      return _t(w == 1 ? "1 week before each date" : "$w weeks before each date",
          "$w minggu sebelum setiap tarikh", "各日程の$w週間前");
    }
    if (d.inDays >= 1) {
      final n = d.inDays;
      return _t(n == 1 ? "1 day before each date" : "$n days before each date",
          "$n hari sebelum setiap tarikh", "各日程の$n日前");
    }
    final h = d.inHours;
    return _t(h == 1 ? "1 hour before each date" : "$h hours before each date",
        "$h jam sebelum setiap tarikh", "各日程の$h時間前");
  }

  // ---- where
  String get lmWhere => _t("Where", "Di mana", "場所");
  String get lmInPerson => _t("In person", "Bersemuka", "対面");
  String get lmOnline => _t("Online", "Dalam talian", "オンライン");
  String get lmHybrid => _t("Hybrid", "Hibrid", "ハイブリッド");
  String get meetingLink => _t("Meeting link", "Pautan sesi dalam talian", "ミーティングリンク");
  String get meetingLinkRequired => _t("Add the meeting link.", "Masukkan pautan sesi dalam talian.",
      "ミーティングリンクを入力してください。");
  String get joinOnline => _t("Join online", "Sertai dalam talian", "オンラインで参加");
  String get onlineEvent => _t("Online event", "Acara dalam talian", "オンラインイベント");
  String get alsoOnline => _t("Also online", "Juga dalam talian", "オンライン参加も可");

  /// The place line for cards and the event page: the venue, "Online
  /// event", or "venue · Online" for hybrid.
  String placeOf(Map<String, dynamic> event) {
    final loc = '${event['location'] ?? ''}'.trim();
    switch ('${event['location_mode'] ?? 'in_person'}') {
      case 'online':
        return onlineEvent;
      case 'hybrid':
        return loc.isEmpty ? onlineEvent : '$loc · $lmOnline';
      default:
        return loc.isEmpty ? locationTba : loc;
    }
  }

  /// "Every Thu", "Every 2 weeks on Mon, Thu", "On selected dates".
  String seriesSummary(Object? rule) {
    if (rule is Map && rule['kind'] == 'weekly') {
      final days = (rule['weekdays'] as List? ?? const [])
          .whereType<num>()
          .map((d) => d.toInt())
          .where((d) => d >= 1 && d <= 7)
          .map((d) => weekdaysShort[d - 1])
          .join(', ');
      final every = (rule['every'] as num?)?.toInt() ?? 1;
      if (days.isEmpty) return seriesSelected;
      return every <= 1 ? seriesWeekly(days) : seriesEveryN(every, days);
    }
    return seriesSelected;
  }

  // ---- series on the event page and in lists
  String get seriesDates => _t("Dates in this series", "Tarikh dalam siri ini", "このシリーズの日程");
  String seriesWeekly(String days) => _t("Every $days", "Setiap $days", "毎週$days");
  String seriesEveryN(int n, String days) =>
      _t("Every $n weeks on $days", "Setiap $n minggu, $days", "$n週ごと（$days）");
  String get seriesSelected => _t("On selected dates", "Pada tarikh terpilih", "指定日に開催");
  String seriesMore(int n) => _t(n == 1 ? "+1 more date" : "+$n more dates", "+$n tarikh lagi", "他$n日程");
  String get thisDate => _t("This date", "Tarikh ini", "この日");
  String get seriesShowAll => _t("Show all dates", "Tunjuk semua tarikh", "すべての日程を表示");
  String get seriesShowFewer => _t("Show fewer", "Tunjuk kurang", "表示を減らす");

  // ---- editing / cancelling one date of a series
  String seriesEditBanner(int n) => _t(
      "This is one of $n dates in a series. Changes to the date and time apply to this date only.",
      "Ini salah satu daripada $n tarikh dalam satu siri. Perubahan tarikh dan masa hanya untuk tarikh ini.",
      "これは$n日あるシリーズの1日です。日時の変更はこの日にのみ適用されます。");
  String get applyTo => _t("Apply changes to", "Guna perubahan pada", "変更の適用先");
  String get cancelWhich => _t("Cancel which dates?", "Batalkan tarikh mana?", "どの日程を中止しますか？");
  String get onlyThisDate => _t("Only this date", "Tarikh ini sahaja", "この日のみ");
  String get thisAndLater => _t("This and later dates", "Tarikh ini dan seterusnya", "この日以降すべて");
  String get applyLaterNote => _t(
      "Later dates keep their own date and time.",
      "Tarikh seterusnya kekal dengan tarikh dan masa sendiri.",
      "以降の日程の日時は変わりません。");
  // ---- form layout (one page / steps)
  String get stepBasics => _t("Basics", "Asas", "基本");
  String get stepExtras => _t("Extras", "Tambahan", "その他");
  String get stepNext => _t("Next", "Seterusnya", "次へ");
  String get stepBack => _t("Back", "Kembali", "戻る");
  String get foldEmpty => _t("Empty", "Kosong", "未入力");
  String get foldNone => _t("None", "Tiada", "なし");
  String get foldOn => _t("On", "Ya", "あり");
  String get foldOff => _t("Off", "Tidak", "なし");
  String get foldNoLimit => _t("No limit", "Tiada had", "定員なし");
  String foldPlaces(int n) => _t("$n places", "$n tempat", "定員$n人");
  String foldButtons(int n) => _t(n == 1 ? "1 button" : "$n buttons", "$n butang", "ボタン$n個");
  String get foldButtonsTitle => _t("Buttons & form", "Butang & borang", "ボタン・フォーム");
  String get foldPeopleTitle => _t("Contacts & people", "Hubungan & orang", "連絡先・担当者");
  String get previewTitle => _t("Preview", "Pratonton", "プレビュー");
  String get previewNote => _t("Preview only: nothing is published.",
      "Pratonton sahaja: tiada apa diterbitkan.", "プレビューのため公開されません。");

  // ---- admin: choosing the layout
  String get layoutTitle => _t("Create event layout", "Susun atur Cipta acara", "イベント作成のレイアウト");
  String get layoutBody => _t(
      "How organisers see the Create event page. Both save exactly the same details.",
      "Cara penganjur melihat halaman Cipta acara. Kedua-duanya menyimpan butiran yang sama.",
      "主催者に表示されるイベント作成ページの形式です。どちらも保存される内容は同じです。");
  String get layoutFolded => _t("One page", "Satu halaman", "1ページ");
  String get layoutFoldedBody => _t("Essentials open, extras folded with a summary.",
      "Perkara utama dibuka, tambahan dilipat dengan ringkasan.", "必須項目を表示し、その他は要約付きで折りたたみます。");
  String get layoutSteps => _t("Steps", "Langkah", "ステップ");
  String get layoutStepsBody => _t("Four short screens with a progress bar.",
      "Empat skrin pendek dengan bar kemajuan.", "進行バー付きの4つの短い画面。");
  String get layoutInUse => _t("In use", "Sedang digunakan", "使用中");
  String get layoutUse => _t("Use this", "Guna ini", "これを使う");
  String layoutConfirmTitle(String name) =>
      _t("Switch to “$name”?", "Tukar kepada “$name”?", "「$name」に切り替えますか？");
  String get layoutConfirmBody => _t(
      "Organisers will see this layout the next time they open Create event. Anything they're filling in right now isn't affected.",
      "Penganjur akan melihat susun atur ini apabila membuka Cipta acara seterusnya. Apa yang sedang diisi sekarang tidak terjejas.",
      "主催者が次にイベント作成を開いたときからこの形式になります。入力中の内容には影響しません。");
  String get layoutSwitch => _t("Switch", "Tukar", "切り替える");
  String layoutNow(String name) => _t("Create event now uses “$name”.",
      "Cipta acara kini menggunakan “$name”.", "イベント作成は「$name」になりました。");

  String get errSeriesFull => _t("This series already has the most dates allowed.",
      "Siri ini sudah mencapai had tarikh.", "このシリーズは日程の上限に達しています。");
}
