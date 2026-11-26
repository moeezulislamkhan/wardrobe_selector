import 'dart:io';
import 'dart:typed_data';

import '../../../core/errors/app_error.dart';

Future<Uint8List> readLocalPhoto(String path) async {
  try {
    return await File(path).readAsBytes();
  } on FileSystemException catch (error) {
    throw AppError('Could not read the cached wardrobe photo.', cause: error);
  }
}
