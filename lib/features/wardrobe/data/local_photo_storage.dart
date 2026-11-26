import 'package:shared_preferences/shared_preferences.dart';

import 'wardrobe_photo_storage.dart';
import 'local_photo_storage_stub.dart'
    if (dart.library.io) 'local_photo_storage_io.dart'
    if (dart.library.js_interop) 'local_photo_storage_web.dart' as platform;

WardrobePhotoStorage createLocalPhotoStorage(
  SharedPreferences preferences,
) {
  return platform.createLocalPhotoStorage(preferences);
}
