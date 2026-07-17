import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ImageCompressor {
  /// Compresses image bytes to a target quality (default 75%).
  /// Also resizes if it exceeds 1920x1080.
  ///
  /// Works on all platforms. On web, compression is skipped (the
  /// native compressor is not available there) and the original
  /// bytes are returned unchanged.
  static Future<Uint8List> compressBytes(Uint8List bytes) async {
    if (kIsWeb) return bytes;
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
}
