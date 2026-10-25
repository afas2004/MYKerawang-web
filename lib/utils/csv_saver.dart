import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';

import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart' as impl;
import 'text_rules.dart';

/// Web: downloads the file. Mobile: opens the share sheet with it.
/// Same split as [saveIcs]; CSV is what the eMerit application wants.
Future<void> saveCsv(String csv, String filename) async {
  final bytes = Uint8List.fromList(utf8.encode(csv));
  if (kIsWeb) {
    impl.downloadBytes(bytes, filename);
    return;
  }
  await SharePlus.instance.share(ShareParams(
    files: [XFile.fromData(bytes, name: filename, mimeType: 'text/csv')],
    fileNameOverrides: [filename],
  ));
}

/// One CSV cell: formula-neutralised, quoted, inner quotes doubled. Null
/// becomes empty. This helper had no callers, but it is the shape a new
/// exporter would copy, so it applies [csvSafe] like every live one does.
String csvCell(Object? value) {
  final s = value == null ? '' : csvSafe('$value');
  return '"${s.replaceAll('"', '""')}"';
}
