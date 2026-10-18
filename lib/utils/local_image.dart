import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

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
String imageContentType(Uint8List bytes) {
  bool starts(List<int> sig, [int offset = 0]) =>
      bytes.length >= offset + sig.length &&
      List.generate(sig.length, (i) => bytes[offset + i] == sig[i]).every((m) => m);
  if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image/png';
  if (starts([0x47, 0x49, 0x46])) return 'image/gif';
  if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) return 'image/webp';
  return 'image/jpeg';
}
