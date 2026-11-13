import 'app_strings.dart';

/// Copy for "a form after check-in": the start pop-up's choices, the door's
/// neutral totals and exports, and the success screen's offer. KI wording
/// (access_strings / form_strings) is kept for KI-template forms only.
extension AttendanceFormStrings on AppStrings {
  String _t(String en, String ms, String ja) => identical(this, AppStrings.ms)
      ? ms
      : identical(this, AppStrings.ja)
      ? ja
      : en;

  // ---- the start pop-up
  String get afQuestion => _t(
      'Ask a form after check-in?',
      'Minta borang selepas daftar masuk?',
      'チェックイン後にフォームを依頼しますか？');
  String get afNone => _t('No form', 'Tiada borang', 'フォームなし');
  String get afNoneHint => _t(
      'People just check in.',
      'Orang hanya daftar masuk.',
      'チェックインのみです。');
  String afOwn(String title) => _t(
      "This event's form: $title",
      'Borang acara ini: $title',
      'このイベントのフォーム: $title');
  String get afPick => _t(
      'One of my forms', 'Salah satu borang saya', '自分のフォームから選ぶ');
  String get afPickHint => _t(
      'Choose a form from My forms.',
      'Pilih borang daripada Borang saya.',
      'マイフォームから選びます。');
  String get afChange => _t('Change', 'Tukar', '変更');
  String get afMakeOwn => _t(
      'Make a form for this event',
      'Buat borang untuk acara ini',
      'このイベントのフォームを作る');
  String get afNeedsUpdate => _t(
      'Other forms need a server update first. Check-in still works.',
      'Borang lain memerlukan kemas kini pelayan dahulu. Daftar masuk tetap berfungsi.',
      '他のフォームにはサーバー更新が必要です。チェックインは使えます。');
  String get afNotSaved => _t(
      'Could not save the form choice. Check-in still works.',
      'Tidak dapat simpan pilihan borang. Daftar masuk tetap berfungsi.',
      'フォームの選択を保存できませんでした。チェックインは使えます。');

  // ---- the door
  String get afResponses =>
      _t('Form responses', 'Jawapan borang', 'フォームの回答');
  String get afExportResponses =>
      _t('Responses CSV', 'CSV jawapan', '回答CSV');

  // ---- the success screen
  String get afAnswerNow =>
      _t('Answer the form', 'Jawab borang', 'フォームに回答');
}
