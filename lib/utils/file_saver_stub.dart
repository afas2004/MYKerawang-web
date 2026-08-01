import 'dart:typed_data';

/// Native builds never reach this — `saveImageBytes` uses `gal` there.
void downloadBytes(Uint8List bytes, String filename) {
  throw UnsupportedError('Browser download is only available on web');
}
