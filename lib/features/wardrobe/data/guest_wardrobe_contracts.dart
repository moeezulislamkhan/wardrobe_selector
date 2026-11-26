import 'dart:typed_data';

import '../../../core/errors/app_error.dart';
import '../domain/guest_wardrobe_item.dart';

abstract interface class GuestWardrobeSource {
  Future<List<GuestWardrobeItem>> loadItems();

  Future<Uint8List> readImage(String localImagePath);
}

abstract interface class WardrobeRepository implements GuestWardrobeSource {
  Future<GuestWardrobeItem> createItem(
    GuestWardrobeItem item,
    Uint8List photoBytes,
  );

  Future<GuestWardrobeItem> updateItem(
    GuestWardrobeItem item, {
    Uint8List? replacementPhotoBytes,
  });

  Future<void> setFavorite(String localId, bool isFavorite);

  Future<void> setArchived(String localId, bool isArchived);

  Future<void> markDeleted(String localId);

  Future<void> finalizeDelete(String localId);

  Future<void> setCloudSyncState(
    String localId, {
    required bool pending,
    String? error,
    bool? hasCloudCopy,
  });
}

class EmptyGuestWardrobeSource implements GuestWardrobeSource {
  const EmptyGuestWardrobeSource();

  @override
  Future<List<GuestWardrobeItem>> loadItems() async => const [];

  @override
  Future<Uint8List> readImage(String localImagePath) {
    throw const AppError('No local wardrobe image source is configured.');
  }
}

abstract interface class GuestWardrobeCloudStore {
  Future<String> uploadImage({
    required String userId,
    required String localId,
    required Uint8List bytes,
    required String contentType,
  });

  Future<void> upsertItem({
    required String userId,
    required GuestWardrobeItem item,
    required String? imagePath,
  });

  Future<void> deleteItem({
    required String userId,
    required GuestWardrobeItem item,
  });
}
