import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

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

/// Picker limits for uploaded photos. On web the native compressor is
/// unavailable (see ImageCompressor), so the picker's own canvas resize is
/// the only thing stopping 4–12 MB phone photos going up over mobile data
/// and then down again to every viewer.
const double kPhotoMaxDimension = 1600;
const int kPhotoQuality = 80;

/// MIME type sniffed from the file signature, so uploads aren't mislabelled
/// (the picker may hand back PNG/WebP, not just JPEG).
///
/// One definition of the magic numbers lives in [photoMime]; anything that is
/// not one of those formats has already been refused by [checkPhoto] before
/// this is called, and JPEG is the fallback for the compressor's output.
String imageContentType(Uint8List bytes) => photoMime(bytes) ?? 'image/jpeg';
