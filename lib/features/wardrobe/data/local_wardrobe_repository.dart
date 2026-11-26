import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/preferences/preferences_provider.dart';
import '../domain/guest_wardrobe_item.dart';
import 'guest_wardrobe_contracts.dart';
import 'local_photo_storage.dart';
import 'wardrobe_photo_storage.dart';

const _wardrobeItemsKey = 'wardrobe_items_v1';
const _maxPhotoBytes = 3 * 1024 * 1024;

final localWardrobeRepositoryProvider = Provider<LocalWardrobeRepository>(
  (ref) => LocalWardrobeRepository(ref.watch(sharedPreferencesProvider)),
);

final wardrobeRepositoryProvider = Provider<WardrobeRepository>(
  (ref) => ref.watch(localWardrobeRepositoryProvider),
);

final guestWardrobeSourceProvider = Provider<GuestWardrobeSource>(
  (ref) => ref.watch(wardrobeRepositoryProvider),
);

final wardrobeItemsProvider = FutureProvider<List<GuestWardrobeItem>>(
  (ref) => ref.watch(wardrobeRepositoryProvider).loadItems(),
);

final wardrobePhotoProvider = FutureProvider.family<Uint8List, String>(
  (ref, path) => ref.watch(guestWardrobeSourceProvider).readImage(path),
);

class LocalWardrobeRepository implements WardrobeRepository {
  LocalWardrobeRepository(
    this._preferences, {
    WardrobePhotoStorage? photoStorage,
  }) : _photoStorage = photoStorage ?? createLocalPhotoStorage(_preferences);

  final SharedPreferences _preferences;
  final WardrobePhotoStorage _photoStorage;

  @override
  Future<List<GuestWardrobeItem>> loadItems() async {
    final encodedItems = _preferences.getString(_wardrobeItemsKey);
    if (encodedItems == null || encodedItems.isEmpty) return const [];

    try {
      final decoded = jsonDecode(encodedItems);
      if (decoded is! List) {
        throw const FormatException('Wardrobe data is not a list.');
      }

      return List<GuestWardrobeItem>.unmodifiable(
        decoded.map((value) {
          if (value is! Map) {
            throw const FormatException('Wardrobe item is not an object.');
          }
          return GuestWardrobeItem.fromJson(Map<String, Object?>.from(value));
        }),
      );
    } on FormatException catch (error) {
      throw AppError('Saved wardrobe data could not be read.', cause: error);
    } on TypeError catch (error) {
      throw AppError('Saved wardrobe data could not be read.', cause: error);
    }
  }

  @override
  Future<Uint8List> readImage(String localImagePath) {
    return _photoStorage.read(localImagePath);
  }

  @override
  Future<GuestWardrobeItem> createItem(
    GuestWardrobeItem item,
    Uint8List photoBytes,
  ) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(item.localId)) {
      throw const AppError('This wardrobe item has an invalid identifier.');
    }
    if (item.title.trim().isEmpty || item.category.trim().isEmpty) {
      throw const AppError('Add a title and category before saving.');
    }
    if (photoBytes.isEmpty) {
      throw const AppError('Choose a photo before saving this item.');
    }
    if (photoBytes.length > _maxPhotoBytes) {
      throw const AppError('The compressed photo must be 3 MB or smaller.');
    }

    final items = await loadItems();
    if (items.any((savedItem) => savedItem.localId == item.localId)) {
      throw const AppError('This wardrobe item already exists.');
    }

    final imagePath = await _photoStorage.save(item.localId, photoBytes);
    final savedItem = item.copyWith(
      localImagePath: imagePath,
      imageContentType: 'image/jpeg',
      needsCloudSync: true,
      clearCloudSyncError: true,
    );
    try {
      await _saveItems([...items, savedItem]);
    } on Exception {
      try {
        await _photoStorage.delete(imagePath);
      } on Exception catch (cleanupError) {
        throw AppError(
          'The item could not be saved, and its temporary photo could not be '
          'removed.',
          cause: cleanupError,
        );
      }
      rethrow;
    }
    return savedItem;
  }

  @override
  Future<GuestWardrobeItem> updateItem(
    GuestWardrobeItem item, {
    Uint8List? replacementPhotoBytes,
  }) async {
    final items = await loadItems();
    final index = items.indexWhere(
      (savedItem) => savedItem.localId == item.localId,
    );
    if (index == -1 || items[index].isDeleted) {
      throw const AppError('This wardrobe item is no longer available.');
    }
    if (item.title.trim().isEmpty || item.category.trim().isEmpty) {
      throw const AppError('Add a title and category before saving.');
    }
    if (replacementPhotoBytes != null &&
        (replacementPhotoBytes.isEmpty ||
            replacementPhotoBytes.length > _maxPhotoBytes)) {
      throw const AppError('Choose a compressed photo no larger than 3 MB.');
    }

    final currentItem = items[index];
    String? replacementPath;
    if (replacementPhotoBytes != null) {
      final fileId = '${item.localId}-${DateTime.now().microsecondsSinceEpoch}';
      replacementPath = await _photoStorage.save(fileId, replacementPhotoBytes);
    }
    final updatedItem = item.copyWith(
      localImagePath: replacementPath ?? currentItem.localImagePath,
      imageContentType: replacementPhotoBytes == null
          ? currentItem.imageContentType
          : 'image/jpeg',
      isDeleted: false,
      needsCloudSync: true,
      hasCloudCopy: currentItem.hasCloudCopy,
      clearCloudSyncError: true,
    );
    final updatedItems = [...items]..[index] = updatedItem;
    try {
      await _saveItems(updatedItems);
    } on Exception {
      if (replacementPath != null) {
        try {
          await _photoStorage.delete(replacementPath);
        } on Exception catch (cleanupError) {
          throw AppError(
            'The edit was not saved and its temporary photo could not be '
            'removed.',
            cause: cleanupError,
          );
        }
      }
      rethrow;
    }

    final oldPhotoPath = currentItem.localImagePath;
    if (replacementPath != null &&
        oldPhotoPath != null &&
        oldPhotoPath != replacementPath) {
      try {
        await _photoStorage.delete(oldPhotoPath);
      } on Exception catch (error) {
        throw AppError(
          'Changes were saved locally, but the replaced photo could not be '
          'removed.',
          cause: error,
        );
      }
    }
    return updatedItem;
  }

  @override
  Future<void> setFavorite(String localId, bool isFavorite) {
    return _updateItem(
      localId,
      (item) => item.copyWith(
        isFavorite: isFavorite,
        needsCloudSync: true,
        clearCloudSyncError: true,
      ),
    );
  }

  @override
  Future<void> setArchived(String localId, bool isArchived) {
    return _updateItem(
      localId,
      (item) => item.copyWith(
        isArchived: isArchived,
        needsCloudSync: true,
        clearCloudSyncError: true,
      ),
    );
  }

  @override
  Future<void> markDeleted(String localId) {
    return _updateItem(
      localId,
      (item) => item.copyWith(
        isDeleted: true,
        needsCloudSync: true,
        clearCloudSyncError: true,
      ),
    );
  }

  @override
  Future<void> finalizeDelete(String localId) async {
    final items = await loadItems();
    final index = items.indexWhere((item) => item.localId == localId);
    if (index == -1) return;

    final photoPath = items[index].localImagePath;
    if (photoPath != null) await _photoStorage.delete(photoPath);
    final updatedItems = [...items]..removeAt(index);
    await _saveItems(updatedItems);
  }

  @override
  Future<void> setCloudSyncState(
    String localId, {
    required bool pending,
    String? error,
    bool? hasCloudCopy,
  }) {
    return _updateItem(
      localId,
      (item) => item.copyWith(
        needsCloudSync: pending,
        hasCloudCopy: hasCloudCopy,
        cloudSyncError: error,
        clearCloudSyncError: error == null,
      ),
    );
  }

  Future<void> _updateItem(
    String localId,
    GuestWardrobeItem Function(GuestWardrobeItem) update,
  ) async {
    final items = await loadItems();
    final index = items.indexWhere((item) => item.localId == localId);
    if (index == -1) {
      throw const AppError('This wardrobe item is no longer available.');
    }

    final updatedItems = [...items];
    updatedItems[index] = update(updatedItems[index]);
    await _saveItems(updatedItems);
  }

  Future<void> _saveItems(List<GuestWardrobeItem> items) async {
    late final bool saved;
    try {
      saved = await _preferences.setString(
        _wardrobeItemsKey,
        jsonEncode(items.map((item) => item.toJson()).toList()),
      );
    } on Exception catch (error) {
      throw AppError('Could not save your wardrobe changes.', cause: error);
    }
    if (!saved) {
      throw const AppError('Could not save your wardrobe changes.');
    }
  }
}
