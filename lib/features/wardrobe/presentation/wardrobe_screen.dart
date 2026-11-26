import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../../auth/presentation/auth_providers.dart';
import '../data/local_wardrobe_repository.dart';
import '../data/wardrobe_sync_service.dart';
import '../domain/guest_wardrobe_item.dart';
import 'wardrobe_photo.dart';

enum _CollectionMode { active, favorites, archived }

enum _GalleryLayout { grid, list }

class WardrobeScreen extends ConsumerStatefulWidget {
  const WardrobeScreen({super.key});

  @override
  ConsumerState<WardrobeScreen> createState() => _WardrobeScreenState();
}

class _WardrobeScreenState extends ConsumerState<WardrobeScreen> {
  final _searchController = TextEditingController();
  _CollectionMode _mode = _CollectionMode.active;
  _GalleryLayout _layout = _GalleryLayout.grid;
  String? _category;
  Set<String> _colors = {};
  Set<String> _occasions = {};
  Set<String> _seasons = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(authSessionProvider);
    ref.listen(authSessionProvider, (previous, next) {
      final session = next.asData?.value;
      if (session == null ||
          previous?.asData?.value?.userId == session.userId) {
        return;
      }
      unawaited(_syncPendingAfterSignIn(session.userId));
    });
    final items = ref.watch(wardrobeItemsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My wardrobe'),
        actions: [
          IconButton(
            tooltip: 'Grid view',
            onPressed: () => setState(() => _layout = _GalleryLayout.grid),
            isSelected: _layout == _GalleryLayout.grid,
            icon: const Icon(Icons.grid_view_outlined),
            selectedIcon: const Icon(Icons.grid_view),
          ),
          IconButton(
            tooltip: 'List view',
            onPressed: () => setState(() => _layout = _GalleryLayout.list),
            isSelected: _layout == _GalleryLayout.list,
            icon: const Icon(Icons.view_list_outlined),
            selectedIcon: const Icon(Icons.view_list),
          ),
          IconButton(
            tooltip: 'Add wardrobe item',
            onPressed: () => context.pushNamed('wardrobe-item-add'),
            icon: const Icon(Icons.add_a_photo_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: items.when(
        loading: () => const Center(
          child: CircularProgressIndicator(semanticsLabel: 'Loading wardrobe'),
        ),
        error: (error, stackTrace) => _LoadError(
          message: _loadErrorMessage(error),
          onRetry: () => ref.invalidate(wardrobeItemsProvider),
        ),
        data: (loadedItems) => _buildGallery(context, loadedItems),
      ),
    );
  }

  Widget _buildGallery(BuildContext context, List<GuestWardrobeItem> items) {
    if (items.isEmpty) {
      return Center(
        child: _EmptyGallery(
          hasItems: false,
          hasActiveFilters: false,
          mode: _CollectionMode.active,
          onClear: _clearFilters,
          onAdd: () => context.pushNamed('wardrobe-item-add'),
        ),
      );
    }

    final collection = items.where((item) {
      return switch (_mode) {
        _CollectionMode.active => !item.isArchived,
        _CollectionMode.favorites => !item.isArchived && item.isFavorite,
        _CollectionMode.archived => item.isArchived,
      };
    }).toList();
    final categories = _values(collection.map((item) => item.category));
    final visibleItems = collection.where(_matchesFilters).toList()
      ..sort((first, second) => second.createdAt.compareTo(first.createdAt));

    return CustomScrollView(
      key: const ValueKey('wardrobe-gallery'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Text(
                '${collection.length} ${collection.length == 1 ? 'piece' : 'pieces'}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('wardrobe-search'),
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Search your wardrobe',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.close),
                        ),
                  filled: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ModeSelector(
                selected: _mode,
                onChanged: (mode) => setState(() {
                  _mode = mode;
                  _category = null;
                }),
              ),
              if (categories.isNotEmpty) ...[
                const SizedBox(height: 16),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _CategoryChip(
                        label: 'All',
                        selected: _category == null,
                        onSelected: () => setState(() => _category = null),
                      ),
                      for (final category in categories)
                        _CategoryChip(
                          label: category,
                          selected: _category == category,
                          onSelected: () =>
                              setState(() => _category = category),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('wardrobe-filters'),
                    onPressed: () => _openFilters(collection),
                    icon: Badge(
                      isLabelVisible: _activeFilterCount > 0,
                      label: Text('$_activeFilterCount'),
                      child: const Icon(Icons.tune),
                    ),
                    label: const Text('Filters'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final value in _colors)
                            _ActiveFilterChip(
                              label: value,
                              onDeleted: () =>
                                  setState(() => _colors.remove(value)),
                            ),
                          for (final value in _occasions)
                            _ActiveFilterChip(
                              label: value,
                              onDeleted: () =>
                                  setState(() => _occasions.remove(value)),
                            ),
                          for (final value in _seasons)
                            _ActiveFilterChip(
                              label: value,
                              onDeleted: () =>
                                  setState(() => _seasons.remove(value)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ]),
          ),
        ),
        if (items.any((item) => item.needsCloudSync))
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _PendingSyncBanner(
                count: items.where((item) => item.needsCloudSync).length,
                signedIn:
                    ref.read(authGatewayProvider)?.currentSession != null,
                onRetry: _retryPendingUploads,
              ),
            ),
          ),
        if (visibleItems.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyGallery(
              hasItems: items.isNotEmpty,
              hasActiveFilters: _hasActiveFilters,
              mode: _mode,
              onClear: _clearFilters,
              onAdd: () => context.pushNamed('wardrobe-item-add'),
            ),
          )
        else if (_layout == _GalleryLayout.grid)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisExtent: 300,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) => _WardrobeGridCard(
                  item: visibleItems[index],
                  onTap: () => _openItem(visibleItems[index]),
                  onFavorite: () => _setFavorite(visibleItems[index]),
                  onArchive: () => _setArchived(visibleItems[index]),
                ),
                childCount: visibleItems.length,
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverList.separated(
              itemCount: visibleItems.length,
              itemBuilder: (context, index) => _WardrobeListTile(
                item: visibleItems[index],
                onTap: () => _openItem(visibleItems[index]),
                onFavorite: () => _setFavorite(visibleItems[index]),
                onArchive: () => _setArchived(visibleItems[index]),
              ),
              separatorBuilder: (context, index) => const SizedBox(height: 10),
            ),
          ),
      ],
    );
  }

  bool _matchesFilters(GuestWardrobeItem item) {
    final query = _searchController.text.trim().toLowerCase();
    final searchable = [
      item.name,
      item.category,
      item.color ?? '',
      item.brand ?? '',
      item.size ?? '',
      ...item.occasionValues,
      ...item.seasonValues,
      ...item.styleTags,
      item.subcategory ?? '',
      item.secondaryColor ?? '',
    ].join(' ').toLowerCase();

    return (_category == null || item.category == _category) &&
        (_colors.isEmpty ||
            (_colors.contains(item.primaryColor) ||
                _colors.contains(item.secondaryColor))) &&
        (_occasions.isEmpty ||
            item.occasionValues.any(_occasions.contains)) &&
        (_seasons.isEmpty || item.seasonValues.any(_seasons.contains)) &&
        (query.isEmpty || searchable.contains(query));
  }

  Future<void> _openFilters(List<GuestWardrobeItem> items) async {
    final selection = await showModalBottomSheet<_FilterSelection>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _FilterSheet(
        colors: _values(
          items.expand((item) => [item.primaryColor, item.secondaryColor]),
        ),
        occasions: _values(items.expand((item) => item.occasionValues)),
        seasons: _values(items.expand((item) => item.seasonValues)),
        initialColors: _colors,
        initialOccasions: _occasions,
        initialSeasons: _seasons,
      ),
    );
    if (selection == null || !mounted) return;
    setState(() {
      _colors = selection.colors;
      _occasions = selection.occasions;
      _seasons = selection.seasons;
    });
  }

  Future<void> _setFavorite(GuestWardrobeItem item) async {
    await _updateItem(
      () => ref
          .read(wardrobeRepositoryProvider)
          .setFavorite(item.localId, !item.isFavorite),
    );
  }

  Future<void> _setArchived(GuestWardrobeItem item) async {
    await _updateItem(
      () => ref
          .read(wardrobeRepositoryProvider)
          .setArchived(item.localId, !item.isArchived),
    );
  }

  Future<void> _retryPendingUploads() async {
    final userId = ref.read(authGatewayProvider)?.currentSession?.userId;
    if (userId == null) {
      context.push('/account/sign-in');
      return;
    }
    try {
      final result = await ref
          .read(wardrobeSyncServiceProvider)
          .syncPending(userId);
      if (!mounted) return;
      ref.invalidate(wardrobeItemsProvider);
      final message = result.failed == 0
          ? 'Synced ${result.synced} wardrobe items.'
          : '${result.failed} items remain queued. Check your connection and '
                'retry.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_loadErrorMessage(error))));
    }
  }

  Future<void> _syncPendingAfterSignIn(String userId) async {
    try {
      final result = await ref
          .read(wardrobeSyncServiceProvider)
          .syncPending(userId);
      if (!mounted) return;
      ref.invalidate(wardrobeItemsProvider);
      if (result.failed == 0) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${result.failed} wardrobe items remain queued. Retry when online.',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_loadErrorMessage(error))));
    }
  }

  Future<void> _updateItem(Future<void> Function() update) async {
    try {
      await update();
      ref.invalidate(wardrobeItemsProvider);
    } on Exception catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_loadErrorMessage(error))));
    }
  }

  void _openItem(GuestWardrobeItem item) {
    context.pushNamed(
      'wardrobe-item-detail',
      pathParameters: {'itemId': item.localId},
    );
  }

  int get _activeFilterCount =>
      _colors.length + _occasions.length + _seasons.length;

  bool get _hasActiveFilters =>
      _activeFilterCount > 0 ||
      _category != null ||
      _searchController.text.trim().isNotEmpty;

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      _category = null;
      _colors = {};
      _occasions = {};
      _seasons = {};
    });
  }
}

class _ModeSelector extends StatelessWidget {
  const _ModeSelector({required this.selected, required this.onChanged});

  final _CollectionMode selected;
  final ValueChanged<_CollectionMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ModeChip(
            label: 'All pieces',
            icon: Icons.checkroom_outlined,
            selected: selected == _CollectionMode.active,
            onTap: () => onChanged(_CollectionMode.active),
          ),
          const SizedBox(width: 8),
          _ModeChip(
            label: 'Favorites',
            icon: Icons.favorite_border,
            selected: selected == _CollectionMode.favorites,
            onTap: () => onChanged(_CollectionMode.favorites),
          ),
          const SizedBox(width: 8),
          _ModeChip(
            label: 'Archived',
            icon: Icons.archive_outlined,
            selected: selected == _CollectionMode.archived,
            onTap: () => onChanged(_CollectionMode.archived),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  const _ModeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      avatar: Icon(icon, size: 18),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        key: ValueKey('category-$label'),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _ActiveFilterChip extends StatelessWidget {
  const _ActiveFilterChip({required this.label, required this.onDeleted});

  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: InputChip(label: Text(label), onDeleted: onDeleted),
    );
  }
}

class _WardrobeGridCard extends StatelessWidget {
  const _WardrobeGridCard({
    required this.item,
    required this.onTap,
    required this.onFavorite,
    required this.onArchive,
  });

  final GuestWardrobeItem item;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  WardrobePhoto(path: item.localImagePath),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _OverlayButton(
                      key: ValueKey('favorite-${item.localId}'),
                      tooltip: item.isFavorite
                          ? 'Remove from favorites'
                          : 'Add to favorites',
                      icon: item.isFavorite
                          ? Icons.favorite
                          : Icons.favorite_border,
                      onPressed: onFavorite,
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: _OverlayButton(
                      key: ValueKey('archive-${item.localId}'),
                      tooltip: item.isArchived
                          ? 'Restore item'
                          : 'Archive item',
                      icon: item.isArchived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                      onPressed: onArchive,
                    ),
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _CategoryLabel(category: item.category),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _itemSubtitle(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WardrobeListTile extends StatelessWidget {
  const _WardrobeListTile({
    required this.item,
    required this.onTap,
    required this.onFavorite,
    required this.onArchive,
  });

  final GuestWardrobeItem item;
  final VoidCallback onTap;
  final VoidCallback onFavorite;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: SizedBox(
          width: 64,
          height: 72,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: WardrobePhoto(path: item.localImagePath, compact: true),
          ),
        ),
        title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${item.category} · ${_itemSubtitle(item)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Item actions',
          onSelected: (action) {
            if (action == 'favorite') onFavorite();
            if (action == 'archive') onArchive();
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              value: 'favorite',
              child: Text(
                item.isFavorite ? 'Remove favorite' : 'Add to favorites',
              ),
            ),
            PopupMenuItem(
              value: 'archive',
              child: Text(item.isArchived ? 'Restore' : 'Archive'),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({required this.category});

  final String category;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(category, style: Theme.of(context).textTheme.labelSmall),
      ),
    );
  }
}

class _EmptyGallery extends StatelessWidget {
  const _EmptyGallery({
    required this.hasItems,
    required this.hasActiveFilters,
    required this.mode,
    required this.onClear,
    required this.onAdd,
  });

  final bool hasItems;
  final bool hasActiveFilters;
  final _CollectionMode mode;
  final VoidCallback onClear;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final hasNoInventory = !hasItems;
    final title = hasNoInventory
        ? 'Your wardrobe is empty'
        : hasActiveFilters
        ? 'No pieces match'
        : switch (mode) {
            _CollectionMode.active => 'No active pieces',
            _CollectionMode.favorites => 'No favorites yet',
            _CollectionMode.archived => 'Nothing archived',
          };
    final message = hasNoInventory
        ? 'Items saved on this device will appear here. No sample inventory is shown.'
        : hasActiveFilters
        ? 'Try another search or clear your filters.'
        : switch (mode) {
            _CollectionMode.active =>
              'Archived items are kept in your collection.',
            _CollectionMode.favorites =>
              'Tap the heart on a piece to save it here.',
            _CollectionMode.archived => 'Items you archive will appear here.',
          };

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasNoInventory ? Icons.checkroom_outlined : Icons.search_off,
              size: 48,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            if (hasActiveFilters) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: onClear,
                child: const Text('Clear search and filters'),
              ),
            ],
            if (hasNoInventory) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_a_photo_outlined),
                label: const Text('Add an item'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PendingSyncBanner extends StatelessWidget {
  const _PendingSyncBanner({
    required this.count,
    required this.signedIn,
    required this.onRetry,
  });

  final int count;
  final bool signedIn;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.cloud_upload_outlined, color: colors.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$count ${count == 1 ? 'item is' : 'items are'} waiting to '
                '${signedIn ? 'sync' : 'sync after sign-in'}.',
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(signedIn ? 'Retry' : 'Sign in'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _FilterSelection {
  const _FilterSelection({
    required this.colors,
    required this.occasions,
    required this.seasons,
  });

  final Set<String> colors;
  final Set<String> occasions;
  final Set<String> seasons;
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({
    required this.colors,
    required this.occasions,
    required this.seasons,
    required this.initialColors,
    required this.initialOccasions,
    required this.initialSeasons,
  });

  final List<String> colors;
  final List<String> occasions;
  final List<String> seasons;
  final Set<String> initialColors;
  final Set<String> initialOccasions;
  final Set<String> initialSeasons;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late final Set<String> _colors = {...widget.initialColors};
  late final Set<String> _occasions = {...widget.initialOccasions};
  late final Set<String> _seasons = {...widget.initialSeasons};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Filter wardrobe',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _colors.clear();
                      _occasions.clear();
                      _seasons.clear();
                    }),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _FilterGroup(
                    title: 'Color',
                    values: widget.colors,
                    selected: _colors,
                    onChanged: (value) => _toggle(_colors, value),
                  ),
                  _FilterGroup(
                    title: 'Occasion',
                    values: widget.occasions,
                    selected: _occasions,
                    onChanged: (value) => _toggle(_occasions, value),
                  ),
                  _FilterGroup(
                    title: 'Season',
                    values: widget.seasons,
                    selected: _seasons,
                    onChanged: (value) => _toggle(_seasons, value),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    _FilterSelection(
                      colors: Set.unmodifiable(_colors),
                      occasions: Set.unmodifiable(_occasions),
                      seasons: Set.unmodifiable(_seasons),
                    ),
                  ),
                  child: const Text('Show results'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _toggle(Set<String> values, String value) {
    setState(() {
      if (!values.add(value)) values.remove(value);
    });
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({
    required this.title,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final String title;
  final List<String> values;
  final Set<String> selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: Text(title),
      subtitle: values.isEmpty
          ? const Text('No saved values')
          : Text('${values.length} available'),
      childrenPadding: const EdgeInsets.only(bottom: 12),
      children: [
        if (values.isEmpty)
          const Text('Add items with this detail to use this filter.')
        else
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final value in values)
                  FilterChip(
                    label: Text(value),
                    selected: selected.contains(value),
                    onSelected: (_) => onChanged(value),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

List<String> _values(Iterable<String?> values) {
  return values
      .whereType<String>()
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList()
    ..sort(
      (first, second) => first.toLowerCase().compareTo(second.toLowerCase()),
    );
}

String _itemSubtitle(GuestWardrobeItem item) {
  final details = [
    item.primaryColor,
    item.secondaryColor,
    item.brand,
  ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
  return details.isEmpty ? item.category : details.join(' · ');
}

String _loadErrorMessage(Object error) {
  return error is AppError
      ? error.message
      : 'Could not load your wardrobe. Try again.';
}
