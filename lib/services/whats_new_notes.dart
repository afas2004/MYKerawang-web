import '../l10n/app_strings.dart';
import 'feature_flags.dart';

/// The release notes behind "What's new" (the pop-up after an update,
/// Settings › What's new, and the owner's Updates tab).
///
/// HOW TO ADD A RELEASE: when you bump `UpdateService.appVersion` and
/// pubspec.yaml for a deploy, add a [ReleaseNote] for that version at the
/// TOP of [kReleaseNotes]. One plain line per highlight, in English,
/// Malay and Japanese. A release with no entry shows no pop-up, so small
/// fixes can simply be left out.
///
/// A line for an area the owner can switch off names it in `needs:` and
/// is hidden while that switch is off.
class NoteLine {
  final String en, ms, ja;
  final AppFeature? needs;
  const NoteLine(this.en, this.ms, this.ja, {this.needs});

  String of(AppStrings s) =>
      identical(s, AppStrings.ms) ? ms : identical(s, AppStrings.ja) ? ja : en;

  bool get visible => needs == null || FeatureFlags.isOn(needs!);
}

class ReleaseNote {
  /// `major.minor.patch`, as in pubspec.yaml (no build number).
  final String version;
  final DateTime date;
  final List<NoteLine> lines;
  const ReleaseNote(this.version, this.date, this.lines);

  /// The lines people can see right now (switched-off areas left out).
  List<NoteLine> get visibleLines => [for (final l in lines) if (l.visible) l];
}

/// Newest first.
final kReleaseNotes = <ReleaseNote>[
  ReleaseNote('1.18.3', DateTime(2026, 11, 14), const [
    NoteLine('Every form now has its own QR code. It can be shown or saved from the form editor and from My forms, ready to be printed or displayed.', 'Setiap borang kini mempunyai kod QR tersendiri. Ia boleh dipaparkan atau disimpan dari penyunting borang dan Borang saya, sedia untuk dicetak atau dipaparkan.', 'すべてのフォームに専用のQRコードが付きました。フォーム編集画面と「マイフォーム」から表示・保存でき、印刷や画面表示に使えます。'),
    NoteLine('Shared messages no longer end with "Check this out on MYKerawang!". Only the title, link and description are sent.', 'Mesej yang dikongsi tidak lagi diakhiri dengan "Tengok ni kat MYKerawang!". Hanya tajuk, pautan dan keterangan dihantar.', '共有メッセージの末尾に「MYKerawangでチェック！」が付かなくなりました。タイトル、リンク、説明だけが送られます。'),
    NoteLine('Links to kerawang.my can now be opened in the installed app on supported devices.', 'Pautan ke kerawang.my kini boleh dibuka dalam aplikasi yang dipasang pada peranti yang menyokongnya.', '対応する端末では、kerawang.myへのリンクをインストール済みのアプリで開けるようになりました。'),
  ]),
  ReleaseNote('1.18.2', DateTime(2026, 11, 14), const [
    NoteLine('A Next button has been added to the pin bar. When a pin is opened, the following pin can be viewed without swiping.', 'Butang Seterusnya telah ditambah pada bar pin. Apabila pin dibuka, pin seterusnya boleh dilihat tanpa perlu meleret.', 'ピンバーに「次へ」ボタンが追加されました。ピンを開いたまま、スワイプせずに次のピンを表示できます。'),
    NoteLine('The pattern on the pin bar is now drawn more efficiently, so Home scrolls more smoothly.', 'Corak pada bar pin kini dilukis dengan lebih cekap, menjadikan laman Utama lebih lancar ketika ditatal.', 'ピンバーの模様がより効率よく描画されるようになり、ホームのスクロールがなめらかになりました。'),
  ]),
  ReleaseNote('1.18.1', DateTime(2026, 11, 14), const [
    NoteLine('Unused files have been removed, so the app now loads faster, especially on mobile data.', 'Fail yang tidak digunakan telah dibuang. Aplikasi kini dibuka lebih cepat, terutamanya dengan data mudah alih.', '使われていないファイルが削除され、特にモバイルデータでアプリの起動が速くなりました。'),
    NoteLine('Posts, events and Market items without images are now shown with a lighter placeholder pattern, so those pages scroll more smoothly.', 'Post, acara dan barangan tanpa gambar dipaparkan dengan corak yang kini dilukis dengan lebih ringan. Laman Pasar dan Acara kini lebih lancar.', '画像のない投稿・イベント・マーケットの商品は、より軽い模様で表示されるようになり、スクロールがなめらかになりました。'),
    NoteLine('All uploaded images are now compressed in the same way before they are saved, so uploads and downloads are faster.', 'Gambar yang dimuat naik akan dimampatkan sebelum disimpan, menjadikan muat naik dan muat turun lebih cepat.', 'アップロードされた画像は保存前に同じ方法で圧縮されるようになり、アップロードと表示が速くなりました。'),
  ]),
  ReleaseNote('1.18.0', DateTime(2026, 11, 14), const [
    NoteLine('Import a Google Form: paste its link and get the same questions as a MYKerawang form you can edit.',
        'Import Borang Google: tampal pautannya dan dapatkan soalan yang sama sebagai borang MYKerawang yang boleh disunting.',
        'Googleフォームを取り込めます。リンクを貼るだけで、同じ質問のMYKerawangフォームができ、編集もできます。'),
    NoteLine('Links to trusted sites like Google Forms, WhatsApp groups and Instagram can now be tapped in posts, comments and events.',
        'Pautan ke laman dipercayai seperti Borang Google, kumpulan WhatsApp dan Instagram kini boleh diketik dalam post, ulasan dan acara.',
        'Googleフォーム、WhatsAppグループ、Instagramなど信頼できるサイトへのリンクを、投稿・コメント・イベントでタップできるようになりました。'),
  ]),
  ReleaseNote('1.17.1', DateTime(2026, 11, 13), const [
    NoteLine("Taking attendance can also show your form's own QR, so guests without an account can answer it.",
        'Semasa mengambil kehadiran, QR borang anda juga boleh dipaparkan supaya tetamu tanpa akaun boleh menjawabnya.',
        '出欠を取るとき、フォームのQRも表示できます。アカウントのないゲストも回答できます。'),
    NoteLine('Shared posts, events and items now put the kerawang.my link right under the title, so chat apps show the MYKerawang preview.',
        'Post, acara dan barang yang dikongsi kini letak pautan kerawang.my terus di bawah tajuk, jadi aplikasi chat tunjuk pratonton MYKerawang.',
        '共有した投稿・イベント・商品は、タイトルのすぐ下にkerawang.myのリンクが入り、チャットアプリでMYKerawangのプレビューが表示されます。'),
  ]),
  ReleaseNote('1.17.0', DateTime(2026, 11, 13), const [
    NoteLine('Phone notifications: get event reminders, comments and form answers even when MYKerawang is closed. Turn them on in Settings › Notifications.',
        'Pemberitahuan telefon: terima peringatan acara, ulasan dan jawapan borang walaupun MYKerawang ditutup. Hidupkan di Tetapan › Pemberitahuan.',
        'スマホ通知：MYKerawangを閉じていても、イベントのリマインダー、コメント、フォームの回答が届きます。設定 › 通知でオンにできます。'),
    NoteLine('A reminder about an hour before events you joined, and a notice when their time or place changes.',
        'Peringatan kira-kira sejam sebelum acara yang awak sertai, dan notis bila masa atau tempatnya berubah.',
        '参加したイベントの約1時間前にリマインダーが届き、時間や場所が変わったときもお知らせします。'),
    NoteLine('New notifications for comments on your posts and events, answers to your forms and people joining your events, grouped so they never pile up.',
        'Pemberitahuan baharu untuk ulasan pada post dan acara awak, jawapan borang dan orang yang sertai acara awak, dikumpul supaya tak bertimbun.',
        'あなたの投稿やイベントへのコメント、フォームの回答、イベントへの参加をまとめてお知らせします。'),
    NoteLine('Tap a notification to go straight to that comment, event or form. Choose what reaches your phone and set quiet hours in Settings.',
        'Ketik pemberitahuan untuk terus ke ulasan, acara atau borang itu. Pilih apa yang sampai ke telefon dan tetapkan waktu senyap di Tetapan.',
        '通知をタップすると、そのコメント・イベント・フォームに直接移動します。スマホに届く内容とおやすみ時間は設定で選べます。'),
  ]),
  ReleaseNote('1.16.4', DateTime(2026, 11, 13), const [
    NoteLine("Taking attendance can ask any of your forms after check-in, not only the event's own form.",
        'Ambil kehadiran boleh minta mana-mana borang awak selepas daftar masuk, bukan hanya borang acara itu sendiri.',
        '出席を取るとき、イベント専用のフォームだけでなく、自分のどのフォームでもチェックイン後に依頼できます。'),
  ]),
  ReleaseNote('1.16.3', DateTime(2026, 11, 13), const [
    NoteLine('The New form page shows your recent forms, with See all to open My forms.',
        'Halaman Borang baharu tunjuk borang terkini awak, dengan Lihat semua untuk buka Borang saya.',
        '新しいフォームのページに最近のフォームが表示され、「すべて表示」でマイフォームを開けます。'),
  ]),
  ReleaseNote('1.16.2', DateTime(2026, 11, 13), const [
    NoteLine('Page tips can be turned off in Settings, or turned back on to see them again.',
        'Tip halaman boleh dimatikan di Tetapan, atau dihidupkan semula untuk lihat sekali lagi.',
        'ページのヒントは設定でオフにできます。オンに戻すともう一度見られます。'),
  ]),
  ReleaseNote('1.16.1', DateTime(2026, 11, 13), const [
    NoteLine('Shorter post cards: long posts show 5 lines with Read more, and photos are smaller, so more posts fit on your screen.',
        'Kad post lebih pendek: post panjang tunjuk 5 baris dengan Baca lagi, dan gambar lebih kecil, jadi lebih banyak post muat di skrin.',
        '投稿カードが短くなりました。長い投稿は5行まで表示して「Read more」が付き、写真も小さくなったので、画面により多くの投稿が入ります。'),
  ]),
  ReleaseNote('1.16.0', DateTime(2026, 11, 13), const [
    NoteLine('Short tips show the first time you open Market, an event, or the Create pages. Bring them back in Settings.',
        'Tip ringkas muncul kali pertama awak buka Pasar, aktiviti, atau halaman Cipta. Boleh tunjuk semula di Tetapan.',
        'マーケット、イベント、作成ページを初めて開いたときに短いヒントが出ます。設定からもう一度表示できます。'),
    NoteLine('Create event has (i) icons that explain each field and its limits.',
        'Cipta aktiviti ada ikon (i) yang terangkan setiap ruangan dan hadnya.',
        'イベント作成の各項目に、使い方と制限を説明する (i) アイコンが付きました。'),
  ]),
  ReleaseNote('1.15.0', DateTime(2026, 11, 13), const [
    NoteLine('Events can repeat weekly or run on dates you pick, and you join each date on its own.',
        'Aktiviti boleh berulang setiap minggu atau ikut tarikh yang dipilih, dan awak sertai setiap tarikh secara berasingan.',
        'イベントを毎週くり返したり、日付を選んで開いたりできます。参加は日付ごとに申し込みます。'),
    NoteLine('Organisers can set when registration closes.',
        'Penganjur boleh tetapkan bila pendaftaran ditutup.',
        '主催者は登録の締め切り時間を設定できます。'),
    NoteLine('Online and hybrid events show a Join online link.',
        'Aktiviti dalam talian dan hibrid ada link Sertai dalam talian.',
        'オンラインやハイブリッドのイベントには「オンラインで参加」リンクがあります。'),
  ]),
  ReleaseNote('1.14.6', DateTime(2026, 11, 12), const [
    NoteLine('Forms get short links that are easy to share.',
        'Borang kini ada link pendek yang senang dikongsi.',
        'フォームに共有しやすい短いリンクが付きました。'),
    NoteLine('Shared form links show a preview card in WhatsApp.',
        'Link borang yang dikongsi kini tunjuk kad pratonton dalam WhatsApp.',
        '共有したフォームのリンクがWhatsAppでプレビュー表示されます。'),
  ]),
  ReleaseNote('1.14.5', DateTime(2026, 11, 12), const [
    NoteLine('Forms can be public, so anyone can answer without an account.',
        'Borang boleh dibuka kepada umum, jadi sesiapa boleh jawab tanpa akaun.',
        'フォームを公開でき、アカウントなしでも回答できます。'),
  ]),
  ReleaseNote('1.14.4', DateTime(2026, 11, 12), const [
    NoteLine('New accounts get a short welcome tour. Replay it any time in Settings.',
        'Akaun baharu dapat lawatan ringkas. Boleh ulang bila-bila masa di Tetapan.',
        '新しいアカウントには短い紹介ツアーがあります。設定からいつでも見直せます。'),
  ]),
  ReleaseNote('1.14.3', DateTime(2026, 11, 11), const [
    NoteLine('Shared listings, events and posts show a preview card with a picture.',
        'Barang, aktiviti dan hantaran yang dikongsi kini tunjuk kad pratonton bergambar.',
        '共有した出品・イベント・投稿が画像付きのプレビューで表示されます。'),
  ]),
  ReleaseNote('1.13.0', DateTime(2026, 11, 5), const [
    NoteLine('Pins you closed can come back if you change your mind.',
        'Pin yang awak tutup boleh dibuka semula kalau ubah fikiran.',
        '閉じたピンを後から元に戻せます。'),
  ]),
  ReleaseNote('1.11.0', DateTime(2026, 10, 31), const [
    NoteLine('Important posts stay pinned in a bar at the top of Home.',
        'Hantaran penting kekal dipin di bar atas Laman Utama.',
        '大事な投稿はホーム上部のバーに固定されます。'),
  ]),
  ReleaseNote('1.10.5', DateTime(2026, 10, 29), const [
    NoteLine('Anyone can make a form, starting from 16 ready-made templates.',
        'Sesiapa boleh buat borang, bermula dengan 16 templat sedia ada.',
        'だれでもフォームを作れます。16種類のテンプレートから始められます。'),
  ]),
  ReleaseNote('1.10.0', DateTime(2026, 10, 29), const [
    NoteLine('A new look in Kerawang plum and marigold.',
        'Rupa baharu dalam warna ungu manggis dan kuning Kerawang.',
        'ケラワンらしいプラムとマリーゴールドの新デザイン。'),
  ]),
  ReleaseNote('1.6.0', DateTime(2026, 10, 24), const [
    NoteLine('Register for events and check in with a QR code.',
        'Daftar aktiviti dan daftar masuk dengan kod QR.',
        'イベントに登録して、QRコードでチェックインできます。'),
  ]),
  ReleaseNote('1.5.0', DateTime(2026, 10, 24), const [
    NoteLine("Ask to join a club and see who's in it.",
        'Mohon sertai kelab dan tengok siapa ahlinya.',
        'クラブへの参加を申し込み、メンバーを確認できます。',
        needs: AppFeature.clubs),
    NoteLine('UiTM students can ask to be verified.',
        'Pelajar UiTM boleh mohon pengesahan.',
        'UiTMの学生は認証を申請できます。',
        needs: AppFeature.studentFeatures),
  ]),
  ReleaseNote('1.4.0', DateTime(2026, 10, 22), const [
    NoteLine('Official announcements from clubs and the college, in their own tab.',
        'Pengumuman rasmi dari kelab dan kolej, dalam tab sendiri.',
        'クラブやカレッジからの公式なお知らせを専用タブで。',
        needs: AppFeature.announcements),
  ]),
  ReleaseNote('1.3.0', DateTime(2026, 10, 22), const [
    NoteLine('Look around without an account: guests can browse and read posts.',
        'Tengok-tengok tanpa akaun: tetamu boleh layari dan baca hantaran.',
        'アカウントなしでも投稿を閲覧できます。'),
  ]),
  ReleaseNote('1.2.0', DateTime(2026, 10, 21), const [
    NoteLine('A cleaner design and simpler navigation, with one Create button.',
        'Reka bentuk lebih kemas dan navigasi lebih mudah, dengan satu butang Cipta.',
        'すっきりしたデザインと、作成ボタンひとつのシンプルな操作。'),
  ]),
  ReleaseNote('1.0.2', DateTime(2026, 10, 18), const [
    NoteLine('MYKerawang on the web: Market, events, posts, follows, search and notifications.',
        'MYKerawang di web: Pasar, aktiviti, hantaran, ikut, carian dan notifikasi.',
        'Web版MYKerawang:マーケット、イベント、投稿、フォロー、検索、通知。'),
  ]),
];

/// -1, 0 or 1, comparing `x.y.z` strings number by number.
int compareVersions(String a, String b) {
  List<int> parts(String v) =>
      v.split('+').first.split('.').map((p) => int.tryParse(p) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0).compareTo(i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

/// Releases to show someone who last saw [seen] and now runs [current]:
/// those after [seen] up to [current], newest first, with something
/// visible. With no [seen] (first run on this device), only [current]'s.
List<ReleaseNote> releasesSince(String? seen, String current,
    {List<ReleaseNote>? notes}) {
  final all = notes ?? kReleaseNotes;
  return [
    for (final r in all)
      if (compareVersions(r.version, current) <= 0 &&
          (seen == null
              ? compareVersions(r.version, current) == 0
              : compareVersions(r.version, seen) > 0) &&
          r.visibleLines.isNotEmpty)
        r,
  ];
}
