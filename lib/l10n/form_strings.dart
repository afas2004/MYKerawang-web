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
  String get formTagKiPreShort => _t("KI before", "KI sebelum", "KI before");
  String get formTagKiPostShort => _t("KI after", "KI selepas", "KI after");
  String get formTagFeedbackShort => _t("Feedback", "Maklum balas", "Feedback");
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

  // ---- editor: the row's own vocabulary ----
  String get formOptional => _t("Optional", "Pilihan", "Optional");
  String get formDuplicate => _t("Duplicate", "Salin", "Duplicate");
  String get formDragHint =>
      _t("Drag to reorder", "Seret untuk susun", "Drag to reorder");
  String get formAddHelp => _t("Add help", "Tambah bantuan", "Add help");
  String get formOnlyRatingsCounted => _t(
      "Only ratings are counted in S1, S2 and S3",
      "Hanya penilaian dikira dalam S1, S2 dan S3",
      "Only ratings count.");
  String get formSection => _t("Section", "Bahagian", "Section");
  String get formQuestionsShort => _t("questions", "soalan", "questions");
  String get formElementLabel => _t("Element", "Elemen", "Element");
  String get formAgree => _t("I agree", "Saya setuju", "I agree");
  String get formAddOption => _t("Add option", "Tambah pilihan", "Add option");
  String get formCountedBeforeShort =>
      _t("counted before", "dikira sebelum", "counted before");
  String get formCountedAfterShort =>
      _t("counted after", "dikira selepas", "counted after");
  String get formCountedFeedbackShort =>
      _t("counted as feedback", "dikira sebagai maklum balas", "counted as feedback");
  String formScaleSummary(int max) =>
      _t("1–$max scale", "skala 1–$max", "1–$max scale");

  // ---- editor: the coverage rail ----
  String get formMeasuresTitle =>
      _t("What this form measures", "Apa yang borang ini ukur", "What this form measures");
  String get formMeasuresSub => _t(
      "Read from the tags on each row.",
      "Dibaca daripada tag pada setiap baris.",
      "Read from the tags on each row.");
  String get formChecksTitle =>
      _t("Before you publish", "Sebelum terbitkan", "Before you publish");
  String get formChecksSub => _t(
      "Checked as you type, not on submit.",
      "Disemak semasa menaip, bukan semasa hantar.",
      "Checked as you type, not on submit.");
  String get formCheckLabels =>
      _t("Every question has a label", "Setiap soalan ada label", "Every question has a label");
  String get formCheckDupes => _t(
      "Each KI element is counted once per phase",
      "Setiap elemen KI dikira sekali per fasa",
      "Each KI element counts once per phase");
  String get formCheckPairs => _t(
      "Every after-rating has a before-rating",
      "Setiap penilaian selepas ada pasangan sebelum",
      "Every after-rating has a before-rating");
  String formCheckBudget(int n) =>
      _t("$n of 40 questions used", "$n daripada 40 soalan digunakan", "$n of 40 used");
  String formCheckMissingLabels(int n) => _t(
      n == 1 ? "1 question missing a label" : "$n questions missing a label",
      "$n soalan tiada label",
      "$n questions missing a label");
  String formCheckDupesCount(int n) => _t(
      n == 1
          ? "1 row counts a KI element twice"
          : "$n rows count the same KI element twice",
      "$n baris mengira elemen KI sama dua kali",
      "$n rows count a KI element twice");
  String formCheckOrphan(String codes) => _t(
      "KI$codes counted after but not before",
      "KI$codes dikira selepas tetapi tidak sebelum",
      "KI$codes counted after but not before");
  String get formPairsLabel =>
      _t("S1 pairs complete", "Pasangan S1 lengkap", "S1 pairs complete");
  String get formReadyToPublish =>
      _t("Ready to publish", "Sedia diterbitkan", "Ready to publish");

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

  // ---- answering ----
  String get formAnswerTitle => _t("Program form", "Borang program", "Program form");
  String get formAnswerKiNow =>
      _t("Answer the KI form", "Jawab borang KI", "Answer the KI form");
  String get formAskAfterCheckin => _t(
      "Ask the KI form after check-in",
      "Minta borang KI selepas daftar masuk",
      "Ask the KI form after check-in");
  String get formAskAfterCheckinHint => _t(
      "Students see it once, right after they check in.",
      "Pelajar nampak sekali, selepas mereka daftar masuk.",
      "Students see it once, right after they check in.");
  String get formNoOpenFormToAsk => _t(
      "Publish a form first, then you can offer it after check-in.",
      "Terbitkan borang dahulu, kemudian boleh tawarkan selepas daftar masuk.",
      "Publish a form first.");
  String get formAnswerSend => _t("Submit", "Hantar", "Submit");
  String get formAnswerUpdate => _t("Update answers", "Kemas kini jawapan", "Update answers");
  String get formAnswerThanks => _t(
      "Thanks — your answers are saved.",
      "Terima kasih — jawapan anda disimpan.",
      "Thanks — your answers are saved.");
  String get formAnswerAlready => _t(
      "You have answered this form. You can change it until it closes.",
      "Anda sudah menjawab borang ini. Boleh ubah sehingga ditutup.",
      "You have answered this form.");
  String get formAnswerClosed =>
      _t("This form is closed.", "Borang ini sudah ditutup.", "This form is closed.");
  String get formAnswerJoinFirst => _t(
      "Only people who joined this event can answer. Join it first, then come back.",
      "Hanya peserta acara ini boleh menjawab. Sertai dahulu, kemudian kembali.",
      "Only people who joined this event can answer.");
  String get formAnswerFull =>
      _t("This form is full.", "Borang ini sudah penuh.", "This form is full.");
  String get formAnswerSignIn =>
      _t("Sign in to answer", "Log masuk untuk menjawab", "Sign in to answer");
  String get formAnswerRequired =>
      _t("Please answer the required questions.", "Sila jawab soalan wajib.", "Please answer the required questions.");
  String formAnswerProgress(int done, int total) =>
      _t("$done of $total answered", "$done daripada $total dijawab", "$done of $total answered");
  String formRequiredLeft(int n) =>
      _t("$n required left", "$n wajib tinggal", "$n required left");
  String get formAllAnswered =>
      _t("All questions answered", "Semua soalan dijawab", "All questions answered");
  String get formAnswerSentTitle =>
      _t("Answers sent", "Jawapan dihantar", "Answers sent");
  String get formAnswerSentBody => _t(
      "The organiser can see them now, and they count towards S1, S2 and S3 in the report.",
      "Penganjur boleh lihat sekarang, dan ia dikira dalam S1, S2 dan S3 laporan.",
      "The organiser can see them now.");
  String get formEditAnswers =>
      _t("Edit my answers", "Ubah jawapan saya", "Edit my answers");
  String formAnswerMissing(int n) => _t(
      n == 1 ? "1 question still needs an answer" : "$n questions still need an answer",
      "$n soalan belum dijawab",
      "$n questions still need an answer");

  /// One field's problem, phrased the way the form guidance asks: what is
  /// wrong, in the fewest words that tell the user what to do.
  String formAnswerIssueText(String code) => switch (code) {
        'required' => _t("This one is required", "Yang ini wajib diisi", "This one is required"),
        'rating' => _t("Pick a value on the scale", "Pilih nilai pada skala", "Pick a value on the scale"),
        'choice' => _t("Choose one of the options", "Pilih salah satu pilihan", "Choose one of the options"),
        'too_long' => _t("That is too long", "Terlalu panjang", "That is too long"),
        'matric' => _t("A matric number is 6-12 digits", "Nombor matrik 6-12 digit", "A matric number is 6-12 digits"),
        'number' => _t("Use digits only", "Guna angka sahaja", "Use digits only"),
        'date' => _t("Pick a date", "Pilih tarikh", "Pick a date"),
        'email' => _t("That does not look like an email", "Itu bukan emel yang sah", "That does not look like an email"),
        _ => _t("Check this answer", "Semak jawapan ini", "Check this answer"),
      };
  String get formNotAvailable =>
      _t("This event has no form yet.", "Acara ini belum ada borang.", "This event has no form yet.");
  String get formEditThis => _t("Edit form", "Sunting borang", "Edit form");

  // ---- the analysis (S1 / S2 / S3) ----
  String get formResponsesTitle => _t("Responses", "Jawapan", "Responses");
  String get formNoResponses => _t(
      "No answers yet. Share the form with participants.",
      "Belum ada jawapan. Kongsi borang dengan peserta.",
      "No answers yet.");
  String get formS1Title => _t(
      "S1 — Participants, KI before and after",
      "S1 — Peserta, KI sebelum dan selepas",
      "S1 — Participants, before and after");
  String get formS2Title =>
      _t("S2 — Organisers, KI after the programme", "S2 — Penganjur, KI selepas program", "S2 — Organisers");
  String get formS3Title =>
      _t("S3 — Programme feedback", "S3 — Maklum balas program", "S3 — Programme feedback");
  String get formBefore => _t("Before", "Sebelum", "Before");
  String get formAfter => _t("After", "Selepas", "After");
  String get formMean => _t("Mean", "Min", "Mean");
  String get formDelta => _t("Change", "Beza", "Change");
  String get formCopyTable => _t("Copy table", "Salin jadual", "Copy table");
  String get formCopied => _t("Copied to the clipboard", "Disalin ke papan klip", "Copied");
  String get formExportCsv => _t("Export CSV", "Eksport CSV", "Export CSV");
  String get formCsvSaved => _t("CSV downloaded", "CSV dimuat turun", "CSV downloaded");
  String get formRespondents =>
      _t("Who answered", "Siapa yang menjawab", "Who answered");
  String get formSuggestions =>
      _t("Suggestions and comments", "Cadangan dan maklum balas", "Suggestions and comments");
  String get formPeople => _t("people", "orang", "people");
  String get formPeserta => _t("Participant", "Peserta", "Participant");
  String get formPenganjur => _t("Organiser", "Penganjur", "Organiser");

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
