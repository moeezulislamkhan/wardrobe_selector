import 'dart:typed_data';

abstract interface class WardrobePhotoStorage {
  Future<String> save(String localId, Uint8List bytes);

  Future<Uint8List> read(String path);

  Future<void> delete(String path);
}
