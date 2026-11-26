import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_error.dart';
import '../data/local_wardrobe_repository.dart';
import '../domain/guest_wardrobe_item.dart';
import 'wardrobe_photo.dart';

class WardrobeItemDetailScreen extends ConsumerWidget {
  const WardrobeItemDetailScreen({required this.itemId, super.key});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(wardrobeItemsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Item details')),
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
              .where((candidate) => candidate.localId == itemId)
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
        Text(item.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(item.category, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (item.color case final color?) _DetailChip(label: color),
            if (item.brand case final brand?) _DetailChip(label: brand),
            if (item.size case final size?) _DetailChip(label: 'Size $size'),
            for (final occasion in item.occasions) _DetailChip(label: occasion),
            for (final season in item.seasons) _DetailChip(label: season),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Added ${_formatDate(item.createdAt)}',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
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
          onPressed: () => _update(
            context,
            ref,
            () => ref
                .read(wardrobeRepositoryProvider)
                .setArchived(item.localId, !item.isArchived),
          ),
          icon: Icon(
            item.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
          ),
          label: Text(item.isArchived ? 'Restore item' : 'Archive item'),
        ),
      ],
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
