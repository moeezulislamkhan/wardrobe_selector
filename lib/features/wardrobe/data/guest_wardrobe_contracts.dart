import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../domain/guest_wardrobe_item.dart';

final guestWardrobeSourceProvider = Provider<GuestWardrobeSource>(
  (ref) => const EmptyGuestWardrobeSource(),
);

abstract interface class GuestWardrobeSource {
  Future<List<GuestWardrobeItem>> loadItems();

  Future<Uint8List> readImage(String localImagePath);
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
}
