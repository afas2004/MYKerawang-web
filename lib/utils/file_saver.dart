import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:gal/gal.dart';

import 'file_saver_stub.dart'
    if (dart.library.js_interop) 'file_saver_web.dart' as impl;

/// Saves an image the way each platform expects:
/// * web / PWA  → triggers a real browser download (no new tab, no
///   "right-click to save" instructions)
/// * Android/iOS → writes to the photo gallery via `gal`
///
/// Returns true on success.
Future<bool> saveImageBytes(Uint8List bytes, {String filename = 'image.jpg'}) async {
  try {
    if (kIsWeb) {
      impl.downloadBytes(bytes, filename);
      return true;
    }
    await Gal.putImageBytes(bytes);
    return true;
  } catch (_) {
    return false;
  }
}
