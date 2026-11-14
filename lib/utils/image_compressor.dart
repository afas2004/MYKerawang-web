import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'image_shrink_stub.dart' if (dart.library.js_interop) 'image_shrink_web.dart' as browser;
import 'photo_rules.dart' show photoMime;

class ImageCompressor {
  /// Longest side of an uploaded photo on the web (matches the picker's
  /// kPhotoMaxDimension). Big enough for a full-screen view on a phone or
  /// laptop.
  static const webMaxSide = 1600;

  /// A JPEG this small has already been scaled and re-saved by the picker;
  /// saving it again would only lose quality.
  static const webJpegSkipBytes = 600 * 1024;

  /// Shrinks a photo before upload. Never throws: if anything fails, the
  /// original bytes are returned.
  ///
  /// - Web: the picker scales photos but keeps their format, so a PNG
  ///   poster or screenshot still goes up at 2–4 MB. The browser's canvas
  ///   scales to [webMaxSide] and saves a JPEG instead. GIFs are left alone
  ///   (that would drop the animation), and so is anything the re-save
  ///   would make bigger.
  /// - Phones/desktop: the native compressor, 75% quality, about 1080p.
  static Future<Uint8List> compressBytes(Uint8List bytes) async {
    if (kIsWeb) {
      final mime = photoMime(bytes);
      if (mime == 'image/gif') return bytes;
      if (mime == 'image/jpeg' && bytes.length < webJpegSkipBytes) return bytes;
      final out = await browser.shrinkInBrowser(bytes, maxSide: webMaxSide, quality: 0.8);
      return keepSmaller(bytes, out);
    }
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        quality: 75, // Good balance of size vs quality
        minWidth: 1920, // Resize 4K images down to 1080p
        minHeight: 1080,
      );
      return result;
    } catch (e) {
      // If error (e.g. file type not supported), return original
      return bytes;
    }
  }

  /// The shrunk bytes, unless shrinking failed or didn't actually help.
  @visibleForTesting
  static Uint8List keepSmaller(Uint8List original, Uint8List? shrunk) =>
      (shrunk == null || shrunk.isEmpty || shrunk.length >= original.length) ? original : shrunk;
}
