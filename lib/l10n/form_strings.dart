import 'app_strings.dart';

/// Copy for event forms (the KI report survey, its editor and its answers).
///
/// Same three languages as [AppStrings]; Japanese falls back to English, as the
/// other feature files do. Kept beside AppStrings so the editor's wording is in
/// one place — call sites read `s.formEditorTitle`.
extension FormStrings on AppStrings {
  String _t(String en, String ms, String ja) =>
      identical(this, AppStrings.ms) ? ms : identical(this, AppStrings.ja) ? ja : en;

  // ---- naming ----
  String get formKiReport => _t("KI report", "Laporan KI", "KI report");
  String get formCreateReport =>
      _t("Create KI report", "Buat laporan KI", "Create KI report");
  String get formEdit => _t("Edit form", "Sunting borang", "Edit form");
  String get formEditorTitle => _t("Program form", "Borang program", "Program form");
  String get formOpenAnswers =>
      _t("Responses", "Jawapan", "Responses");

  // ---- start chooser ----
  String get formStartTitle => _t("Start from", "Mula dengan", "Start from");
  String get formStartBlank => _t("Blank form", "Borang kosong", "Blank form");
  String get formStartBlankSub => _t(
      "Write the questions yourself.",
      "Tulis soalan sendiri.",
      "Write the questions yourself.");
  String get formStartTemplate => _t("KI template", "Templat KI", "KI template");
  String get formStartTemplateSub => _t(
      "The standard survey: 7 KI elements before and after, plus feedback.",
      "Borang piawai: 7 elemen KI sebelum dan selepas, serta maklum balas.",
      "The standard survey: 7 KI elements before and after, plus feedback.");
  String get formStartPaste => _t("Paste a question list", "Tampal senarai soalan", "Paste a question list");
  String get formStartPasteSub => _t(
      "One question per line: kind, label, required, options, analysis, KI code.",
      "Satu soalan setiap baris: jenis, label, wajib, pilihan, analisis, kod KI.",
      "One question per line: kind, label, required, options, analysis, KI code.");

  // ---- paste dialog ----
  String get formPasteTitle => _t("Paste questions", "Tampal soalan", "Paste questions");
  String get formPasteHint => _t(
      "short_text,Nama penuh,yes\nrating,KI1 Komunikasi,yes,1-5,ki_pre,1",
      "short_text,Nama penuh,ya\nrating,KI1 Komunikasi,ya,1-5,ki_pre,1",
      "short_text,Full name,yes\nrating,KI1 Communication,yes,1-5,ki_pre,1");
  String get formPasteHelp => _t(
      "Comma or tab separated. Choices are A|B|C; a rating scale is 1-5. "
      "Analysis is ki_pre, ki_post or feedback.",
      "Pisah dengan koma atau tab. Pilihan: A|B|C; skala penilaian: 1-5. "
      "Analisis: ki_pre, ki_post atau feedback.",
      "Comma or tab separated. Choices are A|B|C; a rating scale is 1-5. "
      "Analysis is ki_pre, ki_post or feedback.");
  String get formPasteEmpty =>
      _t("No questions found in that text.", "Tiada soalan ditemui.", "No questions found.");

  // ---- editor ----
  String get formAddField => _t("Add question", "Tambah soalan", "Add question");
  String get formNoFields => _t(
      "No questions yet. Add one, or start from the KI template.",
      "Belum ada soalan. Tambah satu, atau mula dengan templat KI.",
      "No questions yet.");
  String get formFieldLabel => _t("Question", "Soalan", "Question");
  String get formFieldHelp => _t("Help text (optional)", "Teks bantuan (pilihan)", "Help text (optional)");
  String get formFieldKind => _t("Answer type", "Jenis jawapan", "Answer type");
  String get formFieldRequired => _t("Required", "Wajib", "Required");
  String get formFieldChoices => _t("Options", "Pilihan", "Options");
  String get formFieldChoicesHint => _t(
      "One option per line.", "Satu pilihan setiap baris.", "One option per line.");
  String get formFieldScale => _t("Scale", "Skala", "Scale");
  String get formFieldAnalysis => _t("Counted as", "Dikira sebagai", "Counted as");
  String get formFieldKiCode => _t("KI element", "Elemen KI", "KI element");
  String get formTagNone => _t("Not counted", "Tidak dikira", "Not counted");
  String get formTagKiPre => _t("KI before the programme", "KI sebelum program", "KI before");
  String get formTagKiPost => _t("KI after the programme", "KI selepas program", "KI after");
  String get formTagFeedback => _t("Programme feedback", "Maklum balas program", "Programme feedback");
  String get formMoveUp => _t("Move up", "Naik", "Move up");
  String get formMoveDown => _t("Move down", "Turun", "Move down");
  String get formTitleLabel => _t("Form title", "Tajuk borang", "Form title");
  String get formIntroLabel => _t("Introduction (optional)", "Pengenalan (pilihan)", "Introduction (optional)");
  String get formRequireRsvp => _t(
      "Only people who joined the event may answer",
      "Hanya peserta yang mendaftar boleh menjawab",
      "Only people who joined the event may answer");
  String get formAfterCheckin => _t(
      "Offer this form after a successful check-in",
      "Tawarkan borang ini selepas daftar masuk berjaya",
      "Offer this form after a successful check-in");

  // ---- kinds ----
  String formKindLabel(String kind) => switch (kind) {
        'short_text' => _t("Short text", "Teks pendek", "Short text"),
        'long_text' => _t("Long text", "Teks panjang", "Long text"),
        'rating' => _t("Rating 1-5", "Penilaian 1-5", "Rating 1-5"),
        'single_choice' => _t("One choice", "Satu pilihan", "One choice"),
        'multi_choice' => _t("Several choices", "Beberapa pilihan", "Several choices"),
        'number' => _t("Number", "Nombor", "Number"),
        'date' => _t("Date", "Tarikh", "Date"),
        'email' => _t("Email", "Emel", "Email"),
        'phone' => _t("Phone", "Telefon", "Phone"),
        'student_id' => _t("Matric number", "Nombor matrik", "Matric number"),
        'consent' => _t("Agreement", "Persetujuan", "Agreement"),
        'heading' => _t("Section heading", "Tajuk bahagian", "Section heading"),
        _ => kind,
      };

  // ---- actions / status ----
  String get formSave => _t("Save", "Simpan", "Save");
  String get formSaved => _t("Form saved", "Borang disimpan", "Form saved");
  String get formPublish => _t("Publish", "Terbitkan", "Publish");
  String get formPublishConfirmTitle =>
      _t("Publish this form?", "Terbitkan borang ini?", "Publish this form?");
  String get formPublishConfirmBody => _t(
      "Students will see it and can start answering. Questions that already "
      "have answers can no longer be changed or removed.",
      "Pelajar akan nampak dan boleh mula menjawab. Soalan yang sudah ada "
      "jawapan tidak boleh diubah atau dibuang.",
      "Students will see it and can start answering.");
  String get formPublished => _t("Form published", "Borang diterbitkan", "Form published");
  String get formDraft => _t("Draft", "Draf", "Draft");
  String get formOpen => _t("Open", "Dibuka", "Open");
  String get formClosed => _t("Closed", "Ditutup", "Closed");
  String formResponses(int n) => _t("$n responses", "$n jawapan", "$n responses");

  // ---- problems ----
  String formIssueText(String code) => switch (code) {
        'label_required' => _t("A question needs a label.", "Soalan perlu label.", "A question needs a label."),
        'label_too_long' => _t("That label is too long.", "Label terlalu panjang.", "That label is too long."),
        'choices_needed' => _t("Give at least two options.", "Beri sekurang-kurangnya dua pilihan.", "Give at least two options."),
        'bad_scale' => _t("The scale must run low to high, 1-10.", "Skala mesti dari rendah ke tinggi, 1-10.", "The scale must run low to high, 1-10."),
        'analysis_needs_rating' => _t(
            "Only a rating can be counted in the report.",
            "Hanya penilaian boleh dikira dalam laporan.",
            "Only a rating can be counted."),
        'ki_code_needed' => _t(
            "Choose which KI element this question measures.",
            "Pilih elemen KI untuk soalan ini.",
            "Choose which KI element this question measures."),
        'too_many_fields' => _t("A form holds at most 40 questions.", "Borang boleh ada 40 soalan sahaja.", "At most 40 questions."),
        'too_many_ki' => _t(
            "At most seven KI questions before and seven after.",
            "Paling banyak tujuh soalan KI sebelum dan tujuh selepas.",
            "At most seven KI questions per phase."),
        'empty_form' => _t("Add at least one question first.", "Tambah sekurang-kurangnya satu soalan.", "Add at least one question."),
        'heading_required' => _t("A heading cannot be required.", "Tajuk bahagian tidak boleh wajib.", "A heading cannot be required."),
        'unknown_kind' => _t("Unknown answer type.", "Jenis jawapan tidak dikenali.", "Unknown answer type."),
        _ => _t("Something is not right with that question.", "Ada yang tidak kena dengan soalan itu.", "Something is not right."),
      };
}
