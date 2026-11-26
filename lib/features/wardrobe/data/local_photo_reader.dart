import 'dart:typed_data';

import 'local_photo_reader_stub.dart'
    if (dart.library.io) 'local_photo_reader_io.dart'
    as platform;

Future<Uint8List> readLocalPhoto(String path) {
  return platform.readLocalPhoto(path);
}
