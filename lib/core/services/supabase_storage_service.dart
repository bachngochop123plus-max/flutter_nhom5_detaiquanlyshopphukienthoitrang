import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

class SupabaseStorageService {
  SupabaseStorageService({ImagePicker? imagePicker})
    : _imagePicker = imagePicker ?? ImagePicker();

  final ImagePicker _imagePicker;

  static const String _bucketName = 'Img_products';
  static const String _folderName = 'Img_Product';

  bool get _usesSupabase => SupabaseConfig.instance.isConfigured;

  Future<XFile?> pickSingleImage() {
    return _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
  }

  Future<String?> uploadProductImage({
    required String productId,
    required XFile file,
  }) async {
    if (!_usesSupabase) {
      return null;
    }

    final bytes = await file.readAsBytes();
    final mimeType = _guessMimeType(file.name);
    final extension = _extensionForFile(file.name);
    final fileName = '${DateTime.now().millisecondsSinceEpoch}$extension';
    final storagePath = '$_folderName/$productId/$fileName';

    try {
      await Supabase.instance.client.storage
          .from(_bucketName)
          .uploadBinary(
            storagePath,
            bytes,
            fileOptions: FileOptions(
              cacheControl: '3600',
              upsert: true,
              contentType: mimeType,
            ),
          );

      return Supabase.instance.client.storage
          .from(_bucketName)
          .getPublicUrl(storagePath);
    } on StorageException catch (error) {
      if (error.statusCode == '403') {
        throw Exception(
          'Khong co quyen upload anh (RLS 403). Vui long dang nhap dung tai khoan duoc cap quyen hoac cap nhat Storage policy cho bucket $_bucketName.',
        );
      }
      rethrow;
    }
  }

  String _extensionForFile(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.webp')) return '.webp';
    if (lowerName.endsWith('.png')) return '.png';
    if (lowerName.endsWith('.gif')) return '.gif';
    if (lowerName.endsWith('.jpeg')) return '.jpeg';
    if (lowerName.endsWith('.jpg')) return '.jpg';
    return '.jpg';
  }

  String _guessMimeType(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.webp')) return 'image/webp';
    if (lowerName.endsWith('.png')) return 'image/png';
    if (lowerName.endsWith('.gif')) return 'image/gif';
    if (lowerName.endsWith('.jpeg') || lowerName.endsWith('.jpg')) {
      return 'image/jpeg';
    }
    return 'image/jpeg';
  }
}
