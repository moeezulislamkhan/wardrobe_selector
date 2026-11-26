import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/app_error.dart';

final wardrobeImagePickerProvider = Provider<WardrobeImagePicker>(
  (ref) => PluginWardrobeImagePicker(),
);

abstract interface class WardrobeImagePicker {
  Future<Uint8List?> pick(ImageSource source);
}

class PluginWardrobeImagePicker implements WardrobeImagePicker {
  PluginWardrobeImagePicker({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<Uint8List?> pick(ImageSource source) async {
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 3000,
        maxHeight: 3000,
        imageQuality: 100,
      );
      if (file == null) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw const AppError('The selected photo is empty.');
      return bytes;
    } on PlatformException catch (error) {
      throw AppError(
        'Could not open the camera or photo library.',
        cause: error,
      );
    } on AppError {
      rethrow;
    } on Exception catch (error) {
      throw AppError('Could not read the selected photo.', cause: error);
    }
  }
}
