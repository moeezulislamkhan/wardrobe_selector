import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import 'guest_wardrobe_contracts.dart';
import '../domain/guest_wardrobe_item.dart';
import 'local_wardrobe_repository.dart';
import 'supabase_wardrobe_cloud_store.dart';

final wardrobeSyncServiceProvider = Provider<WardrobeSyncService>(
  (ref) => WardrobeSyncService(
    repository: ref.watch(wardrobeRepositoryProvider),
    cloudStore: ref.watch(guestWardrobeCloudStoreProvider),
  ),
);

class WardrobeSyncResult {
  const WardrobeSyncResult({required this.synced, required this.failed});

  final int synced;
  final int failed;
}

class WardrobeSyncService {
  const WardrobeSyncService({
    required this.repository,
    required this.cloudStore,
  });

  final WardrobeRepository repository;
  final GuestWardrobeCloudStore cloudStore;

  Future<void> syncItem(String userId, String localId) async {
    if (userId.trim().isEmpty) {
      throw const AppError('Sign in before syncing this wardrobe item.');
    }

    final items = await repository.loadItems();
    final item = items.where((value) => value.localId == localId).firstOrNull;
    if (item == null) {
      throw const AppError('This wardrobe item is no longer available.');
    }
    if (item.isDeleted) {
      throw const AppError('This wardrobe item is queued for deletion.');
    }
    final localImagePath = item.localImagePath;
    final contentType = item.imageContentType;
    if (localImagePath == null ||
        localImagePath.isEmpty ||
        contentType == null ||
        contentType.isEmpty) {
      throw const AppError('This wardrobe item has no local photo to sync.');
    }

    await repository.setCloudSyncState(localId, pending: true);
    try {
      final bytes = await repository.readImage(localImagePath);
      if (bytes.isEmpty) {
        throw const AppError('The cached wardrobe photo is empty.');
      }
      final remoteImagePath = await cloudStore.uploadImage(
        userId: userId,
        localId: localId,
        bytes: bytes,
        contentType: contentType,
      );
      await cloudStore.upsertItem(
        userId: userId,
        item: item,
        imagePath: remoteImagePath,
      );
      await repository.setCloudSyncState(
        localId,
        pending: false,
        hasCloudCopy: true,
      );
    } on Exception catch (error) {
      final message = error is AppError
          ? error.message
          : 'Cloud upload failed. Your local item is safe; retry when online.';
      try {
        await repository.setCloudSyncState(
          localId,
          pending: true,
          error: message,
        );
      } on Exception catch (saveError) {
        throw AppError(
          'Cloud sync failed and its retry status could not be saved.',
          cause: saveError,
        );
      }
      if (error is AppError) rethrow;
      throw AppError(message, cause: error);
    }
  }

  Future<void> syncDeletedItem(String userId, String localId) async {
    if (userId.trim().isEmpty) {
      throw const AppError('Sign in before syncing this deletion.');
    }
    final items = await repository.loadItems();
    final item = items.where((value) => value.localId == localId).firstOrNull;
    if (item == null) return;
    if (!item.isDeleted) {
      throw const AppError('This wardrobe item is not queued for deletion.');
    }

    await repository.setCloudSyncState(localId, pending: true);
    try {
      await cloudStore.deleteItem(userId: userId, item: item);
      await repository.finalizeDelete(localId);
    } on Exception catch (error) {
      final message = error is AppError
          ? error.message
          : 'Cloud deletion failed. The item is hidden locally; retry online.';
      try {
        await repository.setCloudSyncState(
          localId,
          pending: true,
          error: message,
        );
      } on Exception catch (saveError) {
        throw AppError(
          'Cloud deletion failed and its retry status could not be saved.',
          cause: saveError,
        );
      }
      if (error is AppError) rethrow;
      throw AppError(message, cause: error);
    }
  }

  Future<WardrobeSyncResult> syncPending(String userId) async {
    final pendingItems = (await repository.loadItems())
        .where((item) => item.needsCloudSync)
        .toList();
    var synced = 0;
    var failed = 0;
    for (final GuestWardrobeItem item in pendingItems) {
      try {
        if (item.isDeleted) {
          await syncDeletedItem(userId, item.localId);
        } else {
          await syncItem(userId, item.localId);
        }
        synced++;
      } on Exception {
        failed++;
      }
    }
    return WardrobeSyncResult(synced: synced, failed: failed);
  }
}
