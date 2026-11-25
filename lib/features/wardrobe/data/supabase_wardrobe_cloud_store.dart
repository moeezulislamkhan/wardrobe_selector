import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../domain/guest_wardrobe_item.dart';
import 'guest_wardrobe_contracts.dart';

class SupabaseWardrobeCloudStore implements GuestWardrobeCloudStore {
  SupabaseWardrobeCloudStore({this.client});

  final SupabaseClient? client;

  SupabaseClient get _supabaseClient {
    if (client != null) return client!;
    try {
      return Supabase.instance.client;
    } on AssertionError {
      throw const AppError(
        'Cloud sync is not configured. Your local wardrobe is unchanged.',
      );
    }
  }

  @override
  Future<String> uploadImage({
    required String userId,
    required String localId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final client = _supabaseClient;
    _requireCurrentUser(client, userId);

    final extension = switch (contentType) {
      'image/jpeg' => 'jpg',
      'image/png' => 'png',
      'image/webp' => 'webp',
      _ => throw const AppError('This image type cannot be synced.'),
    };
    final encodedLocalId = base64Url
        .encode(utf8.encode(localId))
        .replaceAll('=', '');
    final path = '$userId/$encodedLocalId/photo.$extension';

    try {
      await client.storage
          .from('wardrobe-images')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType, upsert: true),
          );
      return path;
    } on StorageException catch (error) {
      throw AppError(
        'Could not upload a wardrobe image. Your local copy is unchanged.',
        cause: error,
      );
    } on Exception catch (error) {
      throw AppError(
        'Could not upload a wardrobe image. Check your connection and retry.',
        cause: error,
      );
    }
  }

  @override
  Future<void> upsertItem({
    required String userId,
    required GuestWardrobeItem item,
    required String? imagePath,
  }) async {
    final client = _supabaseClient;
    _requireCurrentUser(client, userId);
    final row = <String, Object?>{
      'user_id': userId,
      'local_id': item.localId,
      'name': item.name,
      'category': item.category,
      'color': item.color,
      'brand': item.brand,
      'size': item.size,
      'created_at': item.createdAt.toUtc().toIso8601String(),
      'image_path': imagePath,
    };

    try {
      await client
          .from('wardrobe_items')
          .upsert(row, onConflict: 'user_id,local_id');
    } on PostgrestException catch (error) {
      throw AppError(
        'Could not sync wardrobe details. Your local copy is unchanged.',
        cause: error,
      );
    } on Exception catch (error) {
      throw AppError(
        'Could not sync wardrobe details. Check your connection and retry.',
        cause: error,
      );
    }
  }

  static void _requireCurrentUser(SupabaseClient client, String userId) {
    final isUuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(userId);
    if (!isUuid || client.auth.currentUser?.id != userId) {
      throw const AppError(
        'Your account changed before sync finished. Sign in again to retry.',
      );
    }
  }
}
