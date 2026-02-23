import 'package:cloudinary_public/cloudinary_public.dart';
import 'dart:io';

class CloudinaryService {
  late CloudinaryPublic _cloudinary;

  // Constructor that automatically initializes Cloudinary
  CloudinaryService() {
    initialize();
  }

  void initialize() {
    // Replace with your actual Cloudinary credentials
    _cloudinary = CloudinaryPublic('djmes6yky', 'ec_preset', cache: false);
  }

  Future<String?> uploadImage(File imageFile) async {
    try {
      // Upload the image to Cloudinary
      CloudinaryResponse response = await _cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          imageFile.path,
          resourceType: CloudinaryResourceType.Image,
          // Optional: Add folder to organize your uploads
          folder: 'event_banners',
        ),
      );

      // Return the secure URL of the uploaded image
      return response.secureUrl;
    } catch (e) {
      print('Error uploading to Cloudinary: $e');
      return null;
    }
  }

  // Helper method to transform images (e.g., resize, crop)
  String getOptimizedImageUrl(String originalUrl, {int? width, int? height}) {
    if (originalUrl.isEmpty) return originalUrl;

    try {
      final parts = originalUrl.split('/upload/');
      if (parts.length != 2) return originalUrl;

      final transformations = [];

      // Add responsive sizing for better performance
      if (width != null) transformations.add('w_$width');
      if (height != null) transformations.add('h_$height');

      // Add auto-format and quality optimizations
      transformations.add('f_auto');
      transformations.add('q_auto');

      final transformString = transformations.join(',');
      return '${parts[0]}/upload/$transformString/${parts[1]}';
    } catch (e) {
      print('Error transforming image URL: $e');
      return originalUrl;
    }
  }
}