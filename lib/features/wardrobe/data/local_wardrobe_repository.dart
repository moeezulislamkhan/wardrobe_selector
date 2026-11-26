import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/preferences/preferences_provider.dart';
import '../domain/guest_wardrobe_item.dart';
import 'guest_wardrobe_contracts.dart';
import 'local_photo_reader.dart';

const _wardrobeItemsKey = 'wardrobe_items_v1';

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
  const LocalWardrobeRepository(this._preferences);

  final SharedPreferences _preferences;

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
    return readLocalPhoto(localImagePath);
  }

  @override
  Future<void> setFavorite(String localId, bool isFavorite) {
    return _updateItem(
      localId,
      (item) => item.copyWith(isFavorite: isFavorite),
    );
  }

  @override
  Future<void> setArchived(String localId, bool isArchived) {
    return _updateItem(
      localId,
      (item) => item.copyWith(isArchived: isArchived),
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
    final saved = await _preferences.setString(
      _wardrobeItemsKey,
      jsonEncode(updatedItems.map((item) => item.toJson()).toList()),
    );
    if (!saved) {
      throw const AppError('Could not save your wardrobe changes.');
    }
  }
}
