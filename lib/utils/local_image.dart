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
