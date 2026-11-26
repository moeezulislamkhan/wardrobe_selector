import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_error.dart';
import 'wardrobe_photo_storage.dart';

const _pathPrefix = 'wardrobe-cache://';
const _storageKeyPrefix = 'wardrobe_photo_cache_';

WardrobePhotoStorage createLocalPhotoStorage(
  SharedPreferences preferences,
) {
  return _WebWardrobePhotoStorage(preferences);
}

class _WebWardrobePhotoStorage implements WardrobePhotoStorage {
  const _WebWardrobePhotoStorage(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<String> save(String localId, Uint8List bytes) async {
    final saved = await _preferences.setString(
      '$_storageKeyPrefix$localId',
      base64Encode(bytes),
    );
    if (!saved) {
      throw const AppError('Could not cache the photo in this browser.');
    }
    return '$_pathPrefix$localId';
  }

  @override
  Future<Uint8List> read(String path) async {
    final key = _keyForPath(path);
    final encoded = _preferences.getString(key);
    if (encoded == null) {
      throw const AppError('The cached wardrobe photo is unavailable.');
    }
    try {
      return Uint8List.fromList(base64Decode(encoded));
    } on FormatException catch (error) {
      throw AppError('The cached wardrobe photo is invalid.', cause: error);
    }
  }

  @override
  Future<void> delete(String path) async {
    await _preferences.remove(_keyForPath(path));
  }

  String _keyForPath(String path) {
    if (!path.startsWith(_pathPrefix)) {
      throw const AppError('The cached wardrobe photo path is invalid.');
    }
    return '$_storageKeyPrefix${path.substring(_pathPrefix.length)}';
  }
}
