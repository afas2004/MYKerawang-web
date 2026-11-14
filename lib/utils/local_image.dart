import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;

import 'photo_rules.dart';

/// Platform-agnostic picked image.
///
/// Wraps the picked [XFile] together with its bytes so the image can be
/// displayed with `Image.memory` / `MemoryImage` and uploaded with
/// `uploadBinary` on every platform, including web (where dart:io `File`
/// does not exist).
class LocalImage {
  final XFile file;
  final Uint8List bytes;

  LocalImage(this.file, this.bytes);

  static Future<LocalImage> fromXFile(XFile file) async =>
      LocalImage(file, await file.readAsBytes());
}

/// Picker limits for uploaded photos. On web the picker's canvas resize
/// keeps the original format, so ImageCompressor then turns big PNGs
/// (posters, screenshots) into JPEGs as well.
const double kPhotoMaxDimension = 1600;
const int kPhotoQuality = 80;

/// MIME type sniffed from the file signature, so uploads aren't mislabelled
/// (the picker may hand back PNG/WebP, not just JPEG).
///
/// One definition of the magic numbers lives in [photoMime]; anything that is
/// not one of those formats has already been refused by [checkPhoto] before
/// this is called, and JPEG is the fallback for the compressor's output.
String imageContentType(Uint8List bytes) => photoMime(bytes) ?? 'image/jpeg';

/// Every uploaded photo gets a unique, timestamped path and is never
/// overwritten, so browsers may keep it for a year instead of asking the
/// server again each time it scrolls into view.
const kPhotoCacheControl = '31536000';

/// Upload options for a photo: the sniffed type plus the long cache.
FileOptions photoUploadOptions(Uint8List bytes) =>
    FileOptions(contentType: imageContentType(bytes), cacheControl: kPhotoCacheControl);
