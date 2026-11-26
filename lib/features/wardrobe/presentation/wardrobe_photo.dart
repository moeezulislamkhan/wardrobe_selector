import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_wardrobe_repository.dart';

class WardrobePhoto extends ConsumerWidget {
  const WardrobePhoto({required this.path, this.compact = false, super.key});

  final String? path;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoPath = path;
    if (photoPath == null || photoPath.isEmpty) {
      return _PhotoPlaceholder(label: 'No photo', compact: compact);
    }

    return ref
        .watch(wardrobePhotoProvider(photoPath))
        .when(
          loading: () => _PhotoPlaceholder(loading: true, compact: compact),
          error: (error, stackTrace) =>
              _PhotoPlaceholder(label: 'Photo unavailable', compact: compact),
          data: (bytes) => Image.memory(
            bytes,
            key: ValueKey('wardrobe-photo-$photoPath'),
            fit: BoxFit.cover,
            width: double.infinity,
            errorBuilder: (context, error, stackTrace) =>
                _PhotoPlaceholder(label: 'Photo unavailable', compact: compact),
          ),
        );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder({
    this.label,
    this.loading = false,
    this.compact = false,
  });

  final String? label;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.image_not_supported_outlined,
                    color: colors.onSurfaceVariant,
                    size: compact ? 22 : 28,
                  ),
                  if (label != null && !compact) ...[
                    const SizedBox(height: 4),
                    Text(label!, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ],
              ),
      ),
    );
  }
}
