import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';

import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart' as impl;

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

/// One CSV cell: quoted, inner quotes doubled. Null becomes empty.
String csvCell(Object? value) {
  final s = value == null ? '' : '$value';
  return '"${s.replaceAll('"', '""')}"';
}
