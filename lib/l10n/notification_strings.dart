import 'app_strings.dart';

/// Copy for notifications v2: the bell's sentences, Settings →
/// Notifications and the "turn on" prompts. The push sender keeps the same
/// wording in worker/push.py.
extension NotificationStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  String _pick(int n, String one, String many) => n > 1 ? many : one;

  // ---- bell sentences ({who} = latest person, n = how many) ----
  String nCommentPost(String who, int n) => _pick(n,
      _t('$who commented on your post', '$who mengulas siaran anda', '$whoさんがあなたの投稿にコメントしました'),
      _t('$who and ${n - 1} others commented on your post', '$who dan ${n - 1} lagi mengulas siaran anda',
          '$whoさん他${n - 1}人があなたの投稿にコメントしました'));
  String nCommentEvent(String who, int n) => _pick(n,
      _t('$who commented on your event', '$who mengulas acara anda', '$whoさんがあなたのイベントにコメントしました'),
      _t('$who and ${n - 1} others commented on your event', '$who dan ${n - 1} lagi mengulas acara anda',
          '$whoさん他${n - 1}人があなたのイベントにコメントしました'));
  String nAlsoCommented(String who, int n) => _pick(n,
      _t('$who also commented on a post you commented on', '$who turut mengulas siaran yang anda ulas',
          '$whoさんもあなたがコメントした投稿にコメントしました'),
      _t('$who and ${n - 1} others also commented', '$who dan ${n - 1} lagi turut mengulas',
          '$whoさん他${n - 1}人もコメントしました'));
  String nFormAnswer(int n) => _pick(n,
      _t('New answer to your form', 'Jawapan baharu untuk borang anda', 'フォームに新しい回答があります'),
      _t('$n new answers to your form', '$n jawapan baharu untuk borang anda', 'フォームに$n件の新しい回答があります'));
  String nEventJoin(String who, int n) => _pick(n,
      _t('$who joined your event', '$who menyertai acara anda', '$whoさんがあなたのイベントに参加しました'),
      _t('$who and ${n - 1} others joined your event', '$who dan ${n - 1} lagi menyertai acara anda',
          '$whoさん他${n - 1}人があなたのイベントに参加しました'));
  String get nEventChanged => _t('Event changed', 'Acara dikemas kini', 'イベントが変更されました');
  String get nEventCancelled => _t('Event cancelled', 'Acara dibatalkan', 'イベントが中止されました');
  String get nStartingSoon => _t('Starting soon', 'Akan bermula', 'まもなく開始');
  String get nNewEvent => _t('New event', 'Acara baharu', '新しいイベント');
  String nMention(String who) =>
      _t('$who mentioned you', '$who menyebut anda', '$whoさんがあなたをメンションしました');
  String nFollow(String who) =>
      _t('$who followed you', '$who mengikuti anda', '$whoさんがあなたをフォローしました');
  String get nView => _t('View', 'Lihat', '見る');
  String get nSomeone => _t('Someone', 'Seseorang', '誰か');
  String nStartsAt(String time) => _t('starts $time', 'mula $time', '$time開始');
  String nNowAt(String time) => _t('Now $time', 'Kini $time', '$timeに変更');
  String nNowPlace(String place) => _t('Now at $place', 'Kini di $place', '場所: $place');
  String nLatestFrom(String who) => _t('Latest: $who', 'Terkini: $who', '最新: $who');

  // ---- filter chips ----
  String get nfAll => _t('All', 'Semua', 'すべて');
  String get nfMentions => _t('Comments & mentions', 'Ulasan & sebutan', 'コメント・メンション');
  String get nfEvents => _t('Events', 'Acara', 'イベント');
  String get nfForms => _t('Forms', 'Borang', 'フォーム');
  String get nfAccount => _t('Account', 'Akaun', 'アカウント');
  String get nfEmpty => _t('Nothing here yet', 'Belum ada apa-apa', 'まだありません');

  // ---- turn-on prompts ----
  String get pushBannerTitle => _t('Get these on your phone', 'Terima di telefon anda', 'スマホで受け取る');
  String get pushBannerBody => _t(
      'Event reminders and replies, even when MYKerawang is closed.',
      'Peringatan acara dan balasan, walaupun MYKerawang ditutup.',
      'MYKerawangを閉じていても、イベントのリマインダーや返信が届きます。');
  String get pushTurnOn => _t('Turn on', 'Hidupkan', 'オンにする');
  String get pushTurnOnFull => _t('Turn on notifications', 'Hidupkan pemberitahuan', '通知をオンにする');
  String get pushNotNow => _t('Not now', 'Nanti dulu', 'あとで');
  String get pushAskEventTitle => _t('Remind you before it starts?', 'Ingatkan anda sebelum bermula?', '開始前にお知らせしますか？');
  String pushAskEventBody(String title) => _t(
      "We'll send a notification to this phone about an hour before $title.",
      'Kami akan hantar pemberitahuan ke telefon ini kira-kira sejam sebelum $title.',
      '$titleの約1時間前にこの端末へ通知します。');
  String get pushPoint1 => _t('Event reminders and changes', 'Peringatan dan perubahan acara', 'イベントのリマインダーと変更');
  String get pushPoint2 => _t('Comments and mentions', 'Ulasan dan sebutan', 'コメントとメンション');
  String get pushPoint3 => _t('Quiet from 11 pm to 7 am — change anytime in Settings',
      'Senyap dari 11 malam hingga 7 pagi — tukar bila-bila masa di Tetapan',
      '23時〜7時は通知しません（設定でいつでも変更可）');
  String get pushIosTitle => _t('Get reminders on your iPhone', 'Terima peringatan di iPhone anda', 'iPhoneでリマインダーを受け取る');
  String get pushIosBody => _t(
      'iPhone only allows notifications from apps on your Home Screen. It takes 10 seconds:',
      'iPhone hanya benarkan pemberitahuan daripada aplikasi di Skrin Utama. Ambil masa 10 saat:',
      'iPhoneではホーム画面に追加したアプリだけが通知を受け取れます。10秒で終わります：');
  String get pushIosStep1 => _t('Tap Share at the bottom of Safari', 'Ketik Kongsi di bawah Safari', 'Safari下部の共有をタップ');
  String get pushIosStep2 => _t('Choose Add to Home Screen', 'Pilih Tambah ke Skrin Utama', '「ホーム画面に追加」を選択');
  String get pushIosStep3 => _t('Open MYKerawang from the new icon and tap Turn on',
      'Buka MYKerawang dari ikon baharu dan ketik Hidupkan', '新しいアイコンからMYKerawangを開き「オンにする」をタップ');
  String get pushGotIt => _t('Got it', 'Faham', 'わかった');
  String get pushEnabled => _t('Notifications are on for this device', 'Pemberitahuan dihidupkan untuk peranti ini', 'この端末の通知をオンにしました');
  String get pushDenied => _t('Notifications are blocked — you can allow them in your browser settings',
      'Pemberitahuan disekat — benarkan dalam tetapan pelayar anda', '通知がブロックされています。ブラウザの設定で許可できます');
  String get pushFailed => _t("Couldn't turn on notifications. Try again later.",
      'Tidak dapat menghidupkan pemberitahuan. Cuba lagi nanti.', '通知をオンにできませんでした。後でもう一度お試しください。');

  // ---- settings ----
  String get nsTitle => _t('Notifications', 'Pemberitahuan', '通知');
  String get nsOpenList => _t('See all notifications', 'Lihat semua pemberitahuan', 'すべての通知を見る');
  String get nsDeviceOn => _t('On for this device', 'Hidup untuk peranti ini', 'この端末でオン');
  String get nsDeviceOff => _t('Off for this device', 'Mati untuk peranti ini', 'この端末でオフ');
  String get nsDeviceOffBody => _t('Turn on to get notifications even when MYKerawang is closed.',
      'Hidupkan untuk terima pemberitahuan walaupun MYKerawang ditutup.', 'MYKerawangを閉じていても通知を受け取れます。');
  String get nsTurnOffDevice => _t('Turn off for this device', 'Matikan untuk peranti ini', 'この端末でオフにする');
  String get nsBlocked => _t('Blocked in your browser', 'Disekat dalam pelayar anda', 'ブラウザでブロックされています');
  String get nsBlockedBody => _t(
      "Open your browser's site settings for kerawang.my and allow Notifications, then come back.",
      'Buka tetapan laman untuk kerawang.my dalam pelayar dan benarkan Pemberitahuan, kemudian kembali.',
      'ブラウザのkerawang.myのサイト設定で通知を許可してから戻ってください。');
  String get nsUnsupported => _t("This browser can't show phone notifications. The bell still works.",
      'Pelayar ini tidak boleh papar pemberitahuan. Loceng masih berfungsi.', 'このブラウザは通知に対応していません。ベルは引き続き使えます。');
  String get nsComingSoon => _t('Phone notifications are coming soon. The bell already works.',
      'Pemberitahuan telefon akan datang. Loceng sudah berfungsi.', 'スマホ通知は近日対応予定です。ベルはすでに使えます。');
  String get nsIos => _t('On iPhone, add MYKerawang to your Home Screen first',
      'Di iPhone, tambah MYKerawang ke Skrin Utama dahulu', 'iPhoneではまずMYKerawangをホーム画面に追加してください');
  String get nsWhatToSend => _t('What to send', 'Apa yang dihantar', '送る内容');
  String get nsLegend => _t('Phone = phone + bell · Bell = in the app only · Off',
      'Telefon = telefon + loceng · Loceng = dalam aplikasi sahaja · Mati', 'スマホ＝スマホ＋ベル・ベル＝アプリ内のみ・オフ');
  String get nsPhone => _t('Phone', 'Telefon', 'スマホ');
  String get nsBell => _t('Bell', 'Loceng', 'ベル');
  String get nsOff => _t('Off', 'Mati', 'オフ');
  String get nsReminders => _t('Event reminders', 'Peringatan acara', 'イベントのリマインダー');
  String get nsRemindersSub => _t('About an hour before events you joined', 'Kira-kira sejam sebelum acara yang anda sertai', '参加したイベントの約1時間前');
  String get nsEventChanges => _t('Event changes', 'Perubahan acara', 'イベントの変更');
  String get nsEventChangesSub => _t('Time, place, cancelled', 'Masa, tempat, dibatalkan', '時間・場所・中止');
  String get nsComments => _t('Comments', 'Ulasan', 'コメント');
  String get nsCommentsSub => _t('On your posts and events, and posts you commented on',
      'Pada siaran dan acara anda, dan siaran yang anda ulas', 'あなたの投稿・イベント、コメントした投稿');
  String get nsMentions => _t('Mentions', 'Sebutan', 'メンション');
  String get nsMentionsSub => _t('When someone @mentions you', 'Apabila seseorang @sebut anda', '誰かがあなたを@メンションしたとき');
  String get nsFormAnswers => _t('Form answers', 'Jawapan borang', 'フォームの回答');
  String get nsFormAnswersSub => _t('Grouped, at most every 15 minutes', 'Dikumpul, paling kerap setiap 15 minit', 'まとめて、最大15分ごと');
  String get nsJoins => _t('People joining your event', 'Orang menyertai acara anda', 'イベントへの参加');
  String get nsJoinsSub => _t('Grouped', 'Dikumpul', 'まとめて');
  String get nsFollows => _t('New followers', 'Pengikut baharu', '新しいフォロワー');
  String get nsNewEvents => _t('New events in MYKerawang', 'Acara baharu di MYKerawang', 'MYKerawangの新しいイベント');
  String get nsAccount => _t('Account & safety', 'Akaun & keselamatan', 'アカウントと安全');
  String get nsAccountSub => _t('Reports, warnings. Always on.', 'Laporan, amaran. Sentiasa hidup.', '報告・警告。常にオン。');
  String get nsQuiet => _t('Quiet hours', 'Waktu senyap', 'おやすみ時間');
  String get nsQuietSub => _t('Phone stays silent; the bell still fills', 'Telefon senyap; loceng tetap terisi', 'スマホは鳴りません。ベルには届きます');
  String get nsFrom => _t('From', 'Dari', '開始');
  String get nsUntil => _t('Until', 'Hingga', '終了');
  String get nsDevices => _t('Devices', 'Peranti', '端末');
  String get nsThisDevice => _t('This device', 'Peranti ini', 'この端末');
  String get nsRemove => _t('Remove', 'Buang', '削除');
  String get nsNoDevices => _t('No devices yet', 'Belum ada peranti', 'まだ端末はありません');
  String get nsSaveFailed => _t("Couldn't save. Check your connection.", 'Tidak dapat simpan. Semak sambungan anda.', '保存できませんでした。接続を確認してください。');
}
