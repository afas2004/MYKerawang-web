import 'app_strings.dart';

/// Copy for the welcome tour: the popup a brand-new account sees once,
/// right after account setup (lib/widgets/welcome_tour.dart).
extension WelcomeTourStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  // Buttons.
  String get tourSkip => _t('Skip', 'Langkau', 'スキップ');
  String get tourBack => _t('Back', 'Kembali', '戻る');
  String get tourNext => _t('Next', 'Seterusnya', '次へ');
  String get tourShowMe => _t('Show me', 'Tunjuk', '見てみる');
  String get tourStartExploring => _t('Start exploring', 'Mula meneroka', 'はじめる');
  String get tourSellFirst => _t('Sell something first', 'Jual sesuatu dulu', 'まず出品する');

  /// Screen readers: "Step 2 of 4".
  String tourStep(int n, int of) => _t('Step $n of $of', 'Langkah $n daripada $of', 'ステップ $n / $of');

  // 1 · Welcome.
  String tourWelcomeTitle(String? name) => name == null || name.isEmpty
      ? _t('Welcome to MYKerawang', 'Selamat datang ke MYKerawang', 'MYKerawangへようこそ')
      : _t('Welcome to MYKerawang, $name', 'Selamat datang ke MYKerawang, $name',
          'MYKerawangへようこそ、$nameさん');
  String get tourWelcomeBody => _t(
      'The student app for Kerawang. Buy and sell, find what\'s on, and keep up with what people around college are talking about.',
      'Aplikasi pelajar untuk Kerawang. Jual beli, cari aktiviti, dan ikuti apa yang orang sekitar kolej sedang bualkan.',
      'ケラワンの学生のためのアプリ。売り買いしたり、イベントを探したり、カレッジのみんなの話題をチェックしたりできます。');
  String get tourWelcomeHint => _t('Here\'s a quick look. It takes 20 seconds.',
      'Jom tengok sekejap. 20 saat je.', 'さっと紹介します。20秒で終わります。');

  // 2 · Market.
  String get tourMarketTitle => _t('Buy and sell in Kerawang', 'Jual beli di Kerawang', 'ケラワンで売り買い');
  String get tourMarketBody => _t(
      'Post an item in a minute and share one link that stays up. Buyers message you straight on WhatsApp.',
      'Siarkan barang dalam seminit dan kongsi satu link yang kekal. Pembeli terus WhatsApp awak.',
      '1分で出品して、ずっと使えるリンクをシェア。買い手はWhatsAppで直接連絡してきます。');
  String get tourSampleRamen => _t('Ramen cup', 'Ramen cawan', 'カップ麺');
  String get tourSampleLamp => _t('Desk lamp', 'Lampu meja', 'デスクライト');

  // 3 · Events.
  String get tourEventsTitle => _t('See what\'s on this week', 'Tengok apa ada minggu ni', '今週のイベントをチェック');
  String get tourEventsBody => _t(
      'Find events around college and save the ones you like, so you don\'t miss them.',
      'Cari aktiviti sekitar kolej dan simpan yang awak suka, supaya tak terlepas.',
      'カレッジ周辺のイベントを探して、気になるものを保存すれば見逃しません。');
  String get tourSampleEvent => _t('Futsal night', 'Malam futsal', 'フットサルナイト');
  String get tourSampleEventWhen =>
      _t('9:00 pm · Futsal court', '9:00 mlm · Gelanggang futsal', '21:00 · フットサルコート');

  // 4 · You're all set.
  String tourDoneTitle(String? name) => name == null || name.isEmpty
      ? _t('You\'re all set', 'Semua dah siap', '準備完了です')
      : _t('You\'re all set, $name', 'Semua dah siap, $name', '準備完了です、$nameさん');
  String get tourDoneBody => _t('Made by students, for Kerawang. Help keep it a good place.',
      'Dibuat oleh pelajar, untuk Kerawang. Sama-sama jaga tempat ni.',
      '学生がケラワンのために作りました。みんなで良い場所にしましょう。');
  String get tourDisclaimer => _t('A community app, not an official UiTM or college service.',
      'Aplikasi komuniti, bukan perkhidmatan rasmi UiTM atau kolej.',
      'コミュニティアプリであり、UiTMやカレッジの公式サービスではありません。');
  String get tourRuleKind =>
      _t('Be kind. No naming or shaming.', 'Berbudi bahasa. Jangan aibkan sesiapa.', '思いやりを。名指しの批判や晒しは禁止。');
  String get tourRulePrivate => _t('Keep phone and matric numbers private',
      'Jangan dedahkan nombor telefon dan matrik', '電話番号や学籍番号は公開しない');
  String get tourRuleReport => _t("Something wrong? Report it from the post's menu",
      'Ada yang tak kena? Laporkan dari menu siaran', '問題があれば投稿のメニューから報告');

  // Settings › replay.
  String get tourSettingTitle => _t('Welcome tour', 'Lawatan pengenalan', 'ようこそツアー');
  String get tourSettingSub => _t('See the intro again', 'Tengok pengenalan semula', '紹介をもう一度見る');
}
