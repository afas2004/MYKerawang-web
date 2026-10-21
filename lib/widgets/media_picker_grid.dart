import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';

import '../language_cubit.dart';
import '../screens/gallery_view_screen.dart';
import '../theme/app_themes.dart';
import '../utils/adaptive.dart';
import '../utils/local_image.dart';
import 'tap_card.dart';

/// Photo strip for the create/edit forms (listing, event).
///
/// [items] holds existing URLs (`String`) and freshly picked [LocalImage]s;
/// index 0 is always the cover. The list is edited in place and
/// [onChanged] is called after every change so the form can `setState`.
class MediaPickerGrid extends StatelessWidget {
  final List<dynamic> items;
  final VoidCallback onChanged;

  const MediaPickerGrid({
    super.key,
    required this.items,
    required this.onChanged,
  });

  static const double _tileHeight = 140;

  Future<void> _pick(ImageSource source) async {
    final picker = ImagePicker();
    try {
      if (source == ImageSource.camera) {
        final picked = await picker.pickImage(
            source: ImageSource.camera,
            maxWidth: kPhotoMaxDimension,
            maxHeight: kPhotoMaxDimension,
            imageQuality: kPhotoQuality);
        if (picked == null) return;
        items.add(await LocalImage.fromXFile(picked));
      } else {
        final pickedList = await picker.pickMultiImage(
            maxWidth: kPhotoMaxDimension,
            maxHeight: kPhotoMaxDimension,
            imageQuality: kPhotoQuality);
        if (pickedList.isEmpty) return;
        items.addAll(await Future.wait(pickedList.map(LocalImage.fromXFile)));
      }
      onChanged();
    } catch (e) {
      debugPrint("Error picking image: $e");
    }
  }

  void _showAddOptions(BuildContext context) {
    final s = context.l10nRead;
    showAdaptiveSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            // Desktop browsers can't capture; phone PWAs can (see canUseCamera)
            if (canUseCamera(context))
              ListTile(
                leading: const Icon(AppIcons.camera),
                title: Text(s.takePhoto),
                onTap: () {
                  Navigator.pop(sheet);
                  _pick(ImageSource.camera);
                },
              ),
            ListTile(
              leading: const Icon(AppIcons.photo),
              title: Text(s.chooseFromGallery),
              onTap: () {
                Navigator.pop(sheet);
                _pick(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showImageMenu(BuildContext context, int index) {
    final s = context.l10nRead;
    final error = Theme.of(context).colorScheme.error;
    showAdaptiveSheet(
      context: context,
      builder: (sheet) => SafeArea(
        child: Wrap(
          children: [
            if (index != 0)
              ListTile(
                leading: const Icon(_kCoverIcon),
                title: Text(s.setAsCover),
                onTap: () {
                  Navigator.pop(sheet);
                  items.insert(0, items.removeAt(index));
                  onChanged();
                },
              ),
            ListTile(
              leading: const Icon(AppIcons.visible),
              title: Text(s.viewFullscreen),
              onTap: () {
                Navigator.pop(sheet);
                showGallery(context, items: items, initialIndex: index);
              },
            ),
            ListTile(
              leading: Icon(AppIcons.delete, color: error),
              title: Text(s.removePhoto, style: TextStyle(color: error)),
              onTap: () {
                Navigator.pop(sheet);
                _remove(index);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _remove(int index) {
    items.removeAt(index);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = context.l10n;
    final tileBorder =
        BorderSide(color: theme.dividerColor.withValues(alpha: 0.2));

    if (items.isEmpty) {
      return TapCard(
        onTap: () => _showAddOptions(context),
        color: scheme.surfaceContainer,
        border: tileBorder,
        child: SizedBox(
          height: 150,
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(AppIcons.camera, size: 36, color: scheme.primary),
              const SizedBox(height: 8),
              Text(s.addPhotos,
                  style: TextStyle(
                      color: scheme.primary, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _tileHeight,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: items.length + 1, // +1 for "add more"
            itemBuilder: (context, index) {
              if (index == items.length) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: TapCard(
                    onTap: () => _showAddOptions(context),
                    color: scheme.surfaceContainer,
                    border: tileBorder,
                    child: SizedBox(
                      width: 100,
                      height: _tileHeight,
                      child: Icon(AppIcons.create,
                          size: 32, color: scheme.onSurfaceVariant),
                    ),
                  ),
                );
              }

              final item = items[index];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TapCard(
                  onTap: () => _showImageMenu(context, index),
                  child: SizedBox(
                    width: _tileHeight,
                    height: _tileHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        item is LocalImage
                            ? Image.memory(item.bytes, fit: BoxFit.cover)
                            : Image.network(item as String, fit: BoxFit.cover),
                        if (index == 0)
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              color: photoScrim(),
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Text(
                                s.cover.toUpperCase(),
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(
                                    color: kOnPhoto,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        // Quick remove (×)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Material(
                            color: scheme.error,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: () => _remove(index),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(AppIcons.close,
                                    size: 12, color: scheme.onError),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(s.photoTip,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

/// "Set as cover". Not in AppIcons yet (lib/theme is shared); add it
/// there and use AppIcons.cover when it is.
const IconData _kCoverIcon = LucideIcons.star;
