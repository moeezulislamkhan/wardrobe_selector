import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/local_wardrobe_repository.dart';
import '../data/wardrobe_sync_service.dart';
import '../domain/guest_wardrobe_item.dart';
import 'wardrobe_photo.dart';

class WardrobeItemDetailScreen extends ConsumerWidget {
  const WardrobeItemDetailScreen({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(wardrobeItemsProvider);
    final itemForActions = items.maybeWhen(
      data: (allItems) => allItems
          .where(
            (candidate) =>
                candidate.localId == itemId && !candidate.isDeleted,
          )
          .firstOrNull,
      orElse: () => null,
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Item details'),
        actions: [
          if (itemForActions != null) ...[
            IconButton(
              tooltip: 'Edit item',
              onPressed: () => context.pushNamed(
                'wardrobe-item-edit',
                pathParameters: {'itemId': itemForActions.localId},
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete item',
              onPressed: () =>
                  _deleteWardrobeItem(context, ref, itemForActions),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ],
      ),
      body: items.when(
        loading: () => const Center(
          child: CircularProgressIndicator(
            semanticsLabel: 'Loading wardrobe item',
          ),
        ),
        error: (error, stackTrace) => _DetailMessage(
          message: error is AppError
              ? error.message
              : 'Could not load this wardrobe item.',
        ),
        data: (allItems) {
          final item = allItems
              .where(
                (candidate) =>
                    candidate.localId == itemId && !candidate.isDeleted,
              )
              .firstOrNull;
          if (item == null) {
            return const _DetailMessage(
              message: 'This wardrobe item is no longer available.',
            );
          }
          return _ItemDetails(item: item);
        },
      ),
    );
  }
}

class _ItemDetails extends ConsumerWidget {
  const _ItemDetails({required this.item});

  final GuestWardrobeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      key: const ValueKey('wardrobe-item-detail'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: AspectRatio(
            aspectRatio: 0.9,
            child: WardrobePhoto(path: item.localImagePath),
          ),
        ),
        const SizedBox(height: 20),
        Text(item.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(
          [
            item.category,
            if (item.subcategory != null) item.subcategory!,
          ].join(' · '),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (item.primaryColor case final color?) _DetailChip(label: color),
            if (item.secondaryColor case final color?)
              _DetailChip(label: color),
            if (item.brand case final brand?) _DetailChip(label: brand),
            if (item.size case final size?) _DetailChip(label: 'Size $size'),
            for (final tag in item.styleTags) _DetailChip(label: tag),
            for (final occasion in item.occasionValues)
              _DetailChip(label: occasion),
            for (final season in item.seasonValues) _DetailChip(label: season),
          ],
        ),
        if (item.notes case final notes? when notes.trim().isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(notes, style: Theme.of(context).textTheme.bodyLarge),
        ],
        const SizedBox(height: 20),
        Text(
          'Added ${_formatDate(item.createdAt)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        _CloudSyncStatus(item: item),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => _update(
            context,
            ref,
            () => ref
                .read(wardrobeRepositoryProvider)
                .setFavorite(item.localId, !item.isFavorite),
          ),
          icon: Icon(item.isFavorite ? Icons.favorite : Icons.favorite_border),
          label: Text(
            item.isFavorite ? 'Remove from favorites' : 'Add to favorites',
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _toggleArchive(context, ref),
          icon: Icon(
            item.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
          ),
          label: Text(item.isArchived ? 'Restore item' : 'Archive item'),
        ),
      ],
    );
  }

  Future<void> _toggleArchive(BuildContext context, WidgetRef ref) async {
    if (!item.isArchived) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Archive this item?'),
          content: const Text(
            'You can restore it later. Existing outfit history will remain.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Archive'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      if (!context.mounted) return;
    }
    await _update(
      context,
      ref,
      () => ref
          .read(wardrobeRepositoryProvider)
          .setArchived(item.localId, !item.isArchived),
    );
  }

  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    Future<void> Function() update,
  ) async {
    try {
      await update();
      ref.invalidate(wardrobeItemsProvider);
    } on Exception catch (error) {
      if (!context.mounted) return;
      final message = error is AppError
          ? error.message
          : 'Could not save your wardrobe changes.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

Future<void> _deleteWardrobeItem(
  BuildContext context,
  WidgetRef ref,
  GuestWardrobeItem item,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete this item?'),
      content: const Text(
        'The item will be removed from your wardrobe. Outfit history keeps '
        'its saved item snapshot.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(wardrobeRepositoryProvider).markDeleted(item.localId);
    ref.invalidate(wardrobeItemsProvider);
    final userId = ref.read(authGatewayProvider)?.currentSession?.userId;
    var message = 'Item deleted from this device.';
    if (userId == null) {
      message += ' Cloud deletion will sync after you sign in.';
    } else {
      try {
        await ref
            .read(wardrobeSyncServiceProvider)
            .syncDeletedItem(userId, item.localId);
        message = 'Item deleted.';
      } on Exception catch (error) {
        final detail = error is AppError
            ? error.message
            : 'Cloud deletion remains queued for retry.';
        message = 'Item deleted locally. $detail';
      }
    }
    if (!context.mounted) return;
    context.pop();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  } on Exception catch (error) {
    if (!context.mounted) return;
    final message = error is AppError
        ? error.message
        : 'The item could not be deleted.';
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CloudSyncStatus extends ConsumerWidget {
  const _CloudSyncStatus({required this.item});

  final GuestWardrobeItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(authSessionProvider);
    final userId = ref.read(authGatewayProvider)?.currentSession?.userId;
    final title = item.needsCloudSync
        ? item.hasCloudCopy
              ? 'Cloud sync pending'
              : 'Upload pending'
        : item.hasCloudCopy
        ? 'Synced to your account'
        : 'Local copy only';
    final status = item.needsCloudSync
        ? item.hasCloudCopy
              ? 'Changes are waiting to sync to your account.'
              : 'This item is saved locally and waiting to upload.'
        : item.hasCloudCopy
        ? 'This item is synced to your account.'
        : 'This item is saved on this device only.';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_upload_outlined),
                const SizedBox(width: 8),
                Text(title),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.cloudSyncError ?? status),
            if (item.needsCloudSync || !item.hasCloudCopy) ...[
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: userId == null
                    ? () => context.push('/account/sign-in')
                    : () => _retry(context, ref, userId),
                child: Text(
                  userId == null
                      ? 'Sign in to sync'
                      : item.hasCloudCopy
                      ? 'Retry sync'
                      : 'Upload to account',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _retry(
    BuildContext context,
    WidgetRef ref,
    String userId,
  ) async {
    try {
      await ref
          .read(wardrobeSyncServiceProvider)
          .syncItem(userId, item.localId);
      if (!context.mounted) return;
      ref.invalidate(wardrobeItemsProvider);
    } on Exception catch (error) {
      if (!context.mounted) return;
      final message = error is AppError
          ? error.message
          : 'Cloud upload failed. Retry when you are online.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }
}

class _DetailChip extends StatelessWidget {
  const _DetailChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

String _formatDate(DateTime date) {
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
