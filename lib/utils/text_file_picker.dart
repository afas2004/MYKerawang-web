import 'text_file_picker_stub.dart'
    if (dart.library.js_interop) 'text_file_picker_web.dart' as impl;

/// Whether this platform can open a text file picker (the web only, for now).
bool get canPickTextFile => impl.canPick;

/// Lets the user choose a .csv / .txt file and returns its text, or null when
/// nothing was chosen.
Future<String?> pickTextFile() => impl.pickTextFile();
