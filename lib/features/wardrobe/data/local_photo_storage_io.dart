import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_error.dart';
import 'wardrobe_photo_storage.dart';

WardrobePhotoStorage createLocalPhotoStorage(
  SharedPreferences preferences,
) {
  return _FileWardrobePhotoStorage();
}

class _FileWardrobePhotoStorage implements WardrobePhotoStorage {
  @override
  Future<String> save(String localId, Uint8List bytes) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(localId)) {
      throw const AppError('This wardrobe photo has an invalid identifier.');
    }
    try {
      final directory = await _photoDirectory();
      final file = File(
        '${directory.path}${Platform.pathSeparator}$localId.jpg',
      );
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } on AppError {
      rethrow;
    } on Exception catch (error) {
      throw AppError('Could not save the photo on this device.', cause: error);
    }
  }

  @override
  Future<Uint8List> read(String path) async {
    try {
      return await File(path).readAsBytes();
    } on Exception catch (error) {
      throw AppError('Could not read the cached wardrobe photo.', cause: error);
    }
  }

  @override
  Future<void> delete(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on Exception catch (error) {
      throw AppError('Could not remove the temporary wardrobe photo.', cause: error);
    }
  }

  Future<Directory> _photoDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(
      '${documents.path}${Platform.pathSeparator}wardrobe_photos',
    );
    await directory.create(recursive: true);
    return directory;
  }
}
