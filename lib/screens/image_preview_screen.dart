import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart'; // Ensure you have this package
import 'package:cached_network_image/cached_network_image.dart';
import '../language_cubit.dart';
import '../theme/app_themes.dart';

class ImagePreviewScreen extends StatelessWidget {
  final Uint8List? imageBytes;
  final String? imageUrl;

  const ImagePreviewScreen({super.key, this.imageBytes, this.imageUrl});

  @override
  Widget build(BuildContext context) {
    // 1. Determine which ImageProvider to use
    // If we have local bytes, use MemoryImage. Otherwise, try CachedNetworkImage.
    final ImageProvider? provider = imageBytes != null
        ? MemoryImage(imageBytes!)
        : (imageUrl != null ? CachedNetworkImageProvider(imageUrl!) : null);

    return Scaffold(
      backgroundColor: photoScrim(1),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: kOnPhoto),
        elevation: 0,
      ),
      body: Center(
        child: provider == null
            ? Text(context.l10n.imageUnavailable, style: const TextStyle(color: kOnPhoto))
            : PhotoView(
                // 2. Pass the dynamic provider here
                imageProvider: provider,
                
                // 3. Min/Max Scale for zooming
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2.5,
                
                // 4. Error Handling (Works for both File and Network failures)
                errorBuilder: (context, error, stackTrace) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image, color: kOnPhoto, size: 50),
                      const SizedBox(height: 10),
                      Text(context.l10n.imageUnavailable, style: const TextStyle(color: kOnPhoto)),
                    ],
                  );
                },
                
                // 5. Loading Indicator
                loadingBuilder: (context, event) => const Center(
                  child: CircularProgressIndicator(color: kOnPhoto),
                ),
              ),
      ),
    );
  }
}