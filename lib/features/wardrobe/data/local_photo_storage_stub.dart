import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_error.dart';
import 'wardrobe_photo_storage.dart';

WardrobePhotoStorage createLocalPhotoStorage(
  SharedPreferences preferences,
) {
  return _UnsupportedPhotoStorage();
}

class _UnsupportedPhotoStorage implements WardrobePhotoStorage {
  @override
  Future<void> delete(String path) async {
    throw const AppError('Local photo storage is unavailable on this device.');
  }

  @override
  Future<Uint8List> read(String path) async {
    throw const AppError('Local photo storage is unavailable on this device.');
  }

  @override
  Future<String> save(String localId, Uint8List bytes) async {
    throw const AppError('Local photo storage is unavailable on this device.');
  }
}
