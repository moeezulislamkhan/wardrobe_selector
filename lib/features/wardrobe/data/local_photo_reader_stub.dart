import 'dart:typed_data';

import '../../../core/errors/app_error.dart';

Future<Uint8List> readLocalPhoto(String path) {
  throw const AppError('Local wardrobe photos are unavailable on this device.');
}
