import 'app_strings.dart';

/// Copy for page tips (lib/widgets/page_tips.dart) and the (i) info tips on
/// Create event (lib/widgets/info_tip.dart).
extension PageTipsStrings on AppStrings {
  String _t(String en, String ms, String ja) => identical(this, AppStrings.ms)
      ? ms
      : identical(this, AppStrings.ja)
      ? ja
      : en;

  // ---- the tip card
  String tipsStep(int n, int of) =>
      _t('$n of $of', '$n daripada $of', '$n / $of');
  String get tipsNext => _t('Next', 'Seterusnya', '次へ');
  String get tipsGotIt => _t('Got it', 'Faham', 'OK');
  String get tipsSkip => _t('Skip', 'Langkau', 'スキップ');
  String get tipsClose => _t('Close tips', 'Tutup petua', 'ヒントを閉じる');
  String get tipsSetting => _t('Page tips', 'Petua halaman', 'ページのヒント');
  String get tipsSettingOn => _t(
    'On. A short tip shows the first time you open Market, an event or a Create page.',
    'Hidup. Petua ringkas muncul kali pertama anda membuka Pasar, acara atau halaman Cipta.',
    'オン。マーケット、イベント、作成ページを初めて開いたときに短いヒントが出ます。',
  );
  String get tipsSettingOff => _t(
    'Off. No tips show on any page.',
    'Mati. Tiada petua di mana-mana halaman.',
    'オフ。どのページにもヒントは出ません。',
  );
  String get tipsReset => _t('See them again', 'Lihat semula', 'もう一度見る');
  String get tipsResetSub => _t(
    'Pages you already opened show their tips once more.',
    'Halaman yang sudah dibuka akan tunjuk petuanya sekali lagi.',
    '開いたことのあるページでも、もう一度ヒントが出ます。',
  );
  String get tipsResetDone => _t(
    'Tips will show the next time you open each page.',
    'Petua akan muncul apabila anda membuka setiap halaman nanti.',
    '次に各ページを開いたときにヒントが出ます。',
  );
  String get infoMore => _t('More info', 'Maklumat lanjut', '詳細');

  // ---- Market
  String get tipMarketSearch => _t(
    'Search, or filter by category and price.',
    'Cari, atau tapis ikut kategori dan harga.',
    '検索するか、カテゴリや価格で絞り込めます。',
  );
  String get tipMarketItem => _t(
    'Tap an item to see more and WhatsApp the seller.',
    'Tekan barang untuk lihat lagi dan WhatsApp penjual.',
    '商品をタップすると詳細が見られ、出品者にWhatsAppできます。',
  );
  String get tipMarketSell => _t(
    'Selling something? Post it from Create.',
    'Nak jual sesuatu? Siarkan dari Cipta.',
    '売りたいものがあれば、作成から出品できます。',
  );

  // ---- Event page
  String get tipEventJoin => _t(
    'Tap Join to sign up for this event.',
    'Tekan Sertai untuk mendaftar acara ini.',
    '参加をタップすると、このイベントに申し込めます。',
  );
  String get tipEventSave => _t(
    'Save it so you can find it again later.',
    'Simpan supaya mudah dicari semula nanti.',
    '保存しておくと、あとで見つけやすくなります。',
  );
  String get tipEventShare => _t(
    'Share the link. WhatsApp shows a preview of the event.',
    'Kongsi pautan. WhatsApp tunjuk pratonton acara.',
    'リンクを共有すると、WhatsAppにイベントのプレビューが表示されます。',
  );

  // ---- Create post
  String get tipPostTags => _t(
    'Add tags like #lostfound so the right people see it.',
    'Tambah tag seperti #lostfound supaya orang yang betul nampak.',
    '#lostfound のようなタグを付けると、必要な人に届きます。',
  );
  String get tipPostAnon => _t(
    'Turn this on to post without your name and photo.',
    'Hidupkan ini untuk siar tanpa nama dan gambar anda.',
    'オンにすると、名前と写真を出さずに投稿できます。',
  );
  String get tipPostRules => _t(
    'Be polite and respect others. Moderators can ban accounts for rude or harmful posts.',
    'Bersopan dan hormati orang lain. Moderator boleh menyekat akaun kerana hantaran kasar atau berbahaya.',
    '礼儀正しく、他の人を尊重しましょう。失礼な投稿や有害な投稿をしたアカウントは、モデレーターが利用停止にすることがあります。',
  );

  // ---- Create event: one page
  String get tipCeBasics => _t(
    'Start here: photos, who hosts it, a title, and up to 5 categories. Tap (i) for limits.',
    'Mula di sini: gambar, penganjur, tajuk, dan sehingga 5 kategori. Tekan (i) untuk had.',
    'まずはここから：写真、主催者、タイトル、カテゴリ（最大5つ）。制限は (i) をタップ。',
  );
  String get tipCeWhen => _t(
    'Once, every week, or on dates you pick. Each date is its own event, joined separately.',
    'Sekali, setiap minggu, atau tarikh pilihan. Setiap tarikh ialah acara sendiri dan disertai berasingan.',
    '1回、毎週、または選んだ日付。各日付は別々のイベントで、参加も日付ごとです。',
  );
  String get tipCeRepeats => _t(
    'Repeats: pick the days and time, then skip or add dates. Up to 26 dates.',
    'Berulang: pilih hari dan masa, kemudian langkau atau tambah tarikh. Sehingga 26 tarikh.',
    '繰り返し：曜日と時間を選び、日付を除いたり追加したりできます。最大26日。',
  );
  String get tipCeWhere => _t(
    'In person, online, or both. Online needs a meeting link.',
    'Bersemuka, dalam talian, atau kedua-dua. Dalam talian perlukan pautan sesi.',
    '対面、オンライン、または両方。オンラインにはミーティングリンクが必要です。',
  );
  String get tipCeFolds => _t(
    "The rest is folded. Each line shows what's set. Tap one to open it.",
    'Selebihnya dilipat. Setiap baris tunjuk apa yang ditetapkan. Tekan untuk buka.',
    '残りは折りたたまれています。各行に設定内容が表示され、タップすると開きます。',
  );
  String get tipCeDesc => _t(
    'Tell people what to expect. Lists, bold and links all work.',
    'Beritahu apa yang akan berlaku. Senarai, tebal dan pautan boleh digunakan.',
    '内容を伝えましょう。リスト、太字、リンクが使えます。',
  );
  String get tipCeReg => _t(
    'Already set: closes when it starts, no limit, free. Tap to change who can join.',
    'Sudah ditetapkan: tutup bila bermula, tiada had, percuma. Tekan untuk ubah siapa boleh sertai.',
    '初期設定：開始時に締切、定員なし、無料。参加できる人を変えるにはタップ。',
  );
  String get tipCeButtons => _t(
    'Add up to 2 buttons, like a sign-up form or a map.',
    'Tambah sehingga 2 butang, seperti borang daftar atau peta.',
    '申込フォームや地図など、ボタンを2つまで追加できます。',
  );
  String get tipCePeople => _t(
    'Person in charge, partners, and ways to reach you. Empty ones stay hidden.',
    'Orang bertanggungjawab, rakan kerjasama, dan cara hubungi anda. Yang kosong disembunyikan.',
    '担当者、協力団体、連絡方法。空欄のものは表示されません。',
  );
  String get tipCePublish => _t(
    'All set? Publish it. You can edit it later.',
    'Dah siap? Terbitkan. Anda boleh sunting kemudian.',
    '準備ができたら公開しましょう。あとで編集できます。',
  );

  // ---- Create event: steps
  String get tipCeStepsBar => _t(
    '4 short steps. Tap a step to go back. What you typed stays.',
    '4 langkah ringkas. Tekan langkah untuk kembali. Apa yang ditaip kekal.',
    '4つの短いステップです。ステップをタップすると戻れます。入力した内容は残ります。',
  );
  String get tipCeStepsNext => _t(
    'Fill in this step, then tap Next. It checks this step before moving on.',
    'Isi langkah ini, kemudian tekan Seterusnya. Ia menyemak langkah ini dahulu.',
    'このステップを入力して「次へ」をタップ。先に進む前にこのステップを確認します。',
  );
  String get tipCeStepsWhen => _t(
    'When: once, every week, or dates you pick. Where is further down: in person, online, or both.',
    'Bila: sekali, setiap minggu, atau tarikh pilihan. Di mana ada di bawah: bersemuka, dalam talian, atau kedua-dua.',
    'いつ：1回、毎週、または選んだ日付。場所はその下：対面、オンライン、または両方。',
  );
  String get tipCeStepsReg => _t(
    "Who can join: when sign-up closes, a limit, a fee, and who it's for.",
    'Siapa boleh sertai: bila pendaftaran tutup, had, yuran, dan untuk siapa.',
    '参加できる人：締切、定員、参加費、対象。',
  );

  // ---- (i) info tips on Create event
  String get infoPhotos => _t(
    'Optional. People see these at the top of the event page.',
    'Pilihan. Dipaparkan di bahagian atas halaman acara.',
    '任意。イベントページの上部に表示されます。',
  );
  String get infoTitle => _t(
    'Required. Keep it short so it fits on the event card.',
    'Wajib. Pendekkan supaya muat pada kad acara.',
    '必須。イベントカードに収まるよう短めに。',
  );
  String get infoCategory => _t(
    'Pick up to 5. The first one is the main category.',
    'Pilih sehingga 5. Yang pertama ialah kategori utama.',
    '最大5つ。最初のものがメインのカテゴリです。',
  );
  String get infoDescription => _t(
    'Blank line for a new paragraph, - for bullets, **bold**. https links can be tapped. Type @ to tag a club or person.',
    'Baris kosong untuk perenggan baru, - untuk senarai, **tebal**. Pautan https boleh ditekan. Taip @ untuk tag kelab atau orang.',
    '空行で段落、- で箇条書き、**太字**。https のリンクはタップできます。@ でクラブや人をタグ付け。',
  );
  String get infoWhen => _t(
    "Once: one start and end, up to a year ahead. Ends on a later day? It's one event over several days. Repeats or Pick dates: each date is its own event, joined separately. Up to 26 dates.",
    'Sekali: satu masa mula dan tamat, sehingga setahun ke depan. Tamat hari lain? Itu satu acara beberapa hari. Berulang atau Pilih tarikh: setiap tarikh acara sendiri, disertai berasingan. Sehingga 26 tarikh.',
    '1回：開始と終了を1つずつ、1年先まで。別の日に終わる場合は複数日の1つのイベント。繰り返し・日付を選ぶ：各日付が別々のイベントで、参加も日付ごと。最大26日。',
  );
  String get infoWhere => _t(
    'In person needs a location. Online needs a meeting link that starts with https://. Hybrid needs both.',
    'Bersemuka perlukan lokasi. Dalam talian perlukan pautan sesi bermula https://. Hibrid perlukan kedua-dua.',
    '対面は場所、オンラインは https:// で始まるミーティングリンク、ハイブリッドは両方が必要です。',
  );
  String get infoRegCloses => _t(
    'When it starts, at a set time before the start, or never (people can join until it ends). For repeating events, pick a gap before each date, from 1 hour to 1 week.',
    'Bila bermula, pada masa ditetapkan sebelum mula, atau tidak ditutup (boleh sertai sehingga tamat). Untuk acara berulang, pilih jarak sebelum setiap tarikh, dari 1 jam hingga 1 minggu.',
    '開始時、開始前の指定日時、または締切なし（終了まで参加可）。繰り返しイベントは、各日程の何時間前に締め切るかを1時間〜1週間から選べます。',
  );
  String get infoLocation => _t(
    'A place people know, like Dewan Aspirasi.',
    'Tempat yang orang kenal, seperti Dewan Aspirasi.',
    'みんなが知っている場所（例：Dewan Aspirasi）。',
  );
  String get infoAudience => _t(
    "Only a label on the event page. It doesn't stop anyone from joining.",
    'Hanya label pada halaman acara. Ia tidak menghalang sesiapa daripada menyertai.',
    'イベントページの表示だけで、参加を制限するものではありません。',
  );
  String get infoButtons => _t(
    'Up to 2 buttons. Each label is up to 24 characters. Links must start with https:// or be an app link like /event/... A form you attach becomes a Fill in form button.',
    'Sehingga 2 butang. Setiap label sehingga 24 aksara. Pautan mesti bermula https:// atau pautan aplikasi seperti /event/... Borang yang dilampirkan menjadi butang Isi borang.',
    'ボタンは2つまで。ラベルは24文字まで。リンクは https:// で始まるか、/event/... のようなアプリ内リンク。添付したフォームは「フォームに入力」ボタンになります。',
  );
  String get infoPic => _t(
    'Optional. Everyone who opens the event can see this, so only add a number you are happy to share.',
    'Pilihan. Semua yang buka acara boleh nampak, jadi masukkan nombor yang anda sanggup kongsi sahaja.',
    '任意。イベントを開いた全員に見えるので、公開してよい番号だけにしてください。',
  );
  String get infoCoOrganiser => _t(
    'Type a club name, or @ for a person. Shown on the event page.',
    'Taip nama kelab, atau @ untuk orang. Dipaparkan pada halaman acara.',
    'クラブ名、または @ で人を入力。イベントページに表示されます。',
  );
  String get infoContacts => _t(
    'Filled channels show as buttons on the event page. Leave one blank to hide it.',
    'Saluran yang diisi dipaparkan sebagai butang pada halaman acara. Biarkan kosong untuk sembunyikan.',
    '入力した連絡方法はイベントページにボタンで表示されます。空欄にすると非表示になります。',
  );
}
