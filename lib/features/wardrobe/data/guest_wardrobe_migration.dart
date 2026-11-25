import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../domain/guest_wardrobe_item.dart';
import 'guest_wardrobe_contracts.dart';
import 'supabase_wardrobe_cloud_store.dart';

final guestWardrobeCloudStoreProvider = Provider<GuestWardrobeCloudStore>(
  (ref) => SupabaseWardrobeCloudStore(),
);

final guestWardrobeMigratorProvider = Provider<GuestWardrobeMigrator>((ref) {
  return GuestWardrobeMigrator(
    source: ref.watch(guestWardrobeSourceProvider),
    cloudStore: ref.watch(guestWardrobeCloudStoreProvider),
  );
});

class GuestWardrobeMigrator {
  const GuestWardrobeMigrator({
    required this.source,
    required this.cloudStore,
  });

  static const maxImageBytes = 10 * 1024 * 1024;
  static const _supportedImageTypes = {
    'image/jpeg',
    'image/png',
    'image/webp',
  };

  final GuestWardrobeSource source;
  final GuestWardrobeCloudStore cloudStore;

  Future<int> migrate(String userId) async {
    if (userId.trim().isEmpty) {
      throw const AppError('Sign in before syncing your wardrobe.');
    }

    late final List<GuestWardrobeItem> items;
    try {
      items = await source.loadItems();
    } on AppError {
      rethrow;
    } on Exception catch (error) {
      throw AppError(
        'Could not read the local wardrobe. Your local data is unchanged.',
        cause: error,
      );
    }
    final seenIds = <String>{};
    for (final item in items) {
      _validateItem(item, seenIds);
    }

    var migratedCount = 0;
    for (final item in items) {
      try {
        String? remoteImagePath;
        if (item.localImagePath != null) {
          final imageType = item.imageContentType;
          if (imageType == null || !_supportedImageTypes.contains(imageType)) {
            throw const AppError(
              'A wardrobe image has an unsupported file type.',
            );
          }
          final bytes = await source.readImage(item.localImagePath!);
          if (bytes.isEmpty || bytes.length > maxImageBytes) {
            throw const AppError(
              'A wardrobe image is empty or larger than 10 MB.',
            );
          }
          remoteImagePath = await cloudStore.uploadImage(
            userId: userId,
            localId: item.localId,
            bytes: bytes,
            contentType: imageType,
          );
        }

        await cloudStore.upsertItem(
          userId: userId,
          item: item,
          imagePath: remoteImagePath,
        );
        migratedCount++;
      } on AppError {
        rethrow;
      } on Exception catch (error) {
        throw AppError(
          'Could not sync wardrobe item ${migratedCount + 1} of '
          '${items.length}. Your local wardrobe is unchanged; retry to '
          'continue safely.',
          cause: error,
        );
      }
    }
    return migratedCount;
  }

  static void _validateItem(
    GuestWardrobeItem item,
    Set<String> seenIds,
  ) {
    final localId = item.localId.trim();
    if (localId.isEmpty || localId.length > 128) {
      throw const AppError('A wardrobe item has an invalid local identifier.');
    }
    if (!seenIds.add(localId)) {
      throw const AppError(
        'Duplicate local wardrobe identifiers were found. No items were '
        'synced; try again after fixing the local data.',
      );
    }
    if (item.name.trim().isEmpty ||
        item.name.length > 200 ||
        item.category.trim().isEmpty ||
        item.category.length > 80) {
      throw const AppError('A wardrobe item has invalid details.');
    }
    if ((item.localImagePath == null) != (item.imageContentType == null)) {
      throw const AppError('A wardrobe image is missing file details.');
    }
  }
}
