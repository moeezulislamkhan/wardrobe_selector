import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../../wardrobe/data/local_wardrobe_repository.dart';
import '../../wardrobe/domain/guest_wardrobe_item.dart';
import '../data/manual_outfit_repository.dart';
import '../domain/manual_outfit.dart';
import '../domain/rule_based_outfit_engine.dart';

class ManualOutfitEditorScreen extends ConsumerStatefulWidget {
  const ManualOutfitEditorScreen({
    this.outfitId,
    this.duplicate = false,
    super.key,
  }) : assert(!duplicate || outfitId != null);

  final String? outfitId;
  final bool duplicate;

  @override
  ConsumerState<ManualOutfitEditorScreen> createState() =>
      _ManualOutfitEditorScreenState();
}

class _ManualOutfitEditorScreenState
    extends ConsumerState<ManualOutfitEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _scrollController = ScrollController();
  final Map<OutfitItemRole, String?> _selectedIds = {};
  ManualOutfit? _sourceOutfit;
  bool _isLoadingOutfit = false;
  bool _isSaving = false;
  String? _loadError;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    if (widget.outfitId case final outfitId?) {
      _isLoadingOutfit = true;
      unawaited(_loadOutfit(outfitId));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.duplicate
        ? 'Duplicate outfit'
        : widget.outfitId == null
        ? 'Create outfit'
        : 'Edit outfit';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: _isLoadingOutfit
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading saved outfit',
              ),
            )
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_loadError!),
              ),
            )
          : ref
                .watch(wardrobeItemsProvider)
                .when(
                  loading: () => const Center(
                    child: CircularProgressIndicator(
                      semanticsLabel: 'Loading your wardrobe',
                    ),
                  ),
                  error: (error, stackTrace) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Your wardrobe could not be loaded.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: () =>
                                ref.invalidate(wardrobeItemsProvider),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  data: (items) => _buildForm(
                    context,
                    items.where((item) => !item.isArchived && !item.isDeleted),
                  ),
                ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    Iterable<GuestWardrobeItem> wardrobe,
  ) {
    final availableItems = wardrobe
        .map(_toOutfitItem)
        .where(
          (item) =>
              const RuleBasedOutfitEngine().roleOf(item) !=
              OutfitItemRole.other,
        )
        .toList();
    final selectedItems = [
      for (final item in availableItems)
        if (_selectedIds.values.contains(item.id)) item,
    ];
    final availableIds = availableItems.map((item) => item.id).toSet();
    final unavailableSourceItems =
        _sourceOutfit?.items
            .where((item) => !availableIds.contains(item.id))
            .toList() ??
        const <OutfitItem>[];
    final sourceHasMissingRequiredItem = unavailableSourceItems.any((item) {
      final role = const RuleBasedOutfitEngine().roleOf(item);
      if (role != OutfitItemRole.top &&
          role != OutfitItemRole.bottom &&
          role != OutfitItemRole.shoes) {
        return false;
      }
      final replacementId = _selectedIds[role];
      return replacementId == null || !availableIds.contains(replacementId);
    });
    final sourceHasUnavailableOptionalItem = unavailableSourceItems.any((item) {
      final role = const RuleBasedOutfitEngine().roleOf(item);
      return role == OutfitItemRole.layer || role == OutfitItemRole.accessory;
    });
    final hints = const RuleBasedOutfitEngine().compatibilityHints(
      selectedItems,
    );

    return Form(
      key: _formKey,
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_saveError case final error?) ...[
              _EditorNotice(message: error, isError: true),
              const SizedBox(height: 12),
            ],
            TextFormField(
              key: const ValueKey('manual-outfit-name'),
              controller: _nameController,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) => setState(() => _saveError = null),
              decoration: const InputDecoration(
                labelText: 'Outfit name',
                hintText: 'e.g. Weekend errands',
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter a name for this outfit.';
                }
                if (value.trim().length > 80) {
                  return 'Use 80 characters or fewer.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Required pieces',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _slotSelector(
              role: OutfitItemRole.top,
              label: 'Top',
              options: availableItems,
              required: true,
            ),
            const SizedBox(height: 12),
            _slotSelector(
              role: OutfitItemRole.bottom,
              label: 'Bottom',
              options: availableItems,
              required: true,
            ),
            const SizedBox(height: 12),
            _slotSelector(
              role: OutfitItemRole.shoes,
              label: 'Shoes',
              options: availableItems,
              required: true,
            ),
            const SizedBox(height: 20),
            Text(
              'Optional pieces',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            _slotSelector(
              role: OutfitItemRole.layer,
              label: 'Layer',
              options: availableItems,
            ),
            const SizedBox(height: 12),
            _slotSelector(
              role: OutfitItemRole.accessory,
              label: 'Accessory',
              options: availableItems,
            ),
            if (sourceHasMissingRequiredItem ||
                sourceHasUnavailableOptionalItem) ...[
              const SizedBox(height: 16),
              _EditorNotice(
                message: sourceHasMissingRequiredItem
                    ? 'A required item in this saved outfit is no longer active. '
                          'Choose a current wardrobe item in that slot before saving.'
                    : 'An optional item is no longer active and will be removed '
                          'unless you choose a current replacement.',
                isError: sourceHasMissingRequiredItem,
              ),
            ],
            const SizedBox(height: 20),
            Text(
              'Compatibility hints',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            for (final hint in hints)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(hint),
              ),
            const SizedBox(height: 16),
            FilledButton.icon(
              key: const ValueKey('save-manual-outfit'),
              onPressed: _isSaving
                  ? null
                  : () => _save(availableItems, sourceHasMissingRequiredItem),
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(
                _isSaving
                    ? 'Saving locally…'
                    : widget.outfitId != null && !widget.duplicate
                    ? 'Save changes'
                    : 'Save outfit',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saved on this device first. Sync status stays pending until cloud sync is available.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _slotSelector({
    required OutfitItemRole role,
    required String label,
    required List<OutfitItem> options,
    bool required = false,
  }) {
    final roleItems = options
        .where((item) => const RuleBasedOutfitEngine().roleOf(item) == role)
        .toList();
    final selectedId = _selectedIds[role];
    final currentValue =
        selectedId != null && roleItems.any((item) => item.id == selectedId)
        ? selectedId
        : '';
    return DropdownButtonFormField<String>(
      key: ValueKey('manual-slot-${role.name}'),
      initialValue: currentValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: roleItems.isEmpty
            ? 'No active wardrobe items in this category.'
            : null,
      ),
      items: [
        DropdownMenuItem<String>(
          value: '',
          child: Text(required ? 'Select $label' : 'None'),
        ),
        for (final item in roleItems)
          DropdownMenuItem<String>(
            value: item.id,
            child: Text(
              [
                item.title,
                item.category,
                if (item.primaryColor != null) item.primaryColor!,
              ].join(' · '),
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      validator: required
          ? (value) => value == null || value.isEmpty
                ? 'Select a ${label.toLowerCase()} from your wardrobe.'
                : null
          : null,
      onChanged: (value) => setState(() {
        _selectedIds[role] = value == null || value.isEmpty ? null : value;
        _saveError = null;
      }),
    );
  }

  Future<void> _loadOutfit(String outfitId) async {
    try {
      final outfit = ref
          .read(manualOutfitRepositoryProvider)
          .findById(outfitId);
      if (outfit == null) {
        throw const AppError('This manual outfit is no longer available.');
      }
      if (!mounted) return;
      setState(() {
        _sourceOutfit = outfit;
        _nameController.text = widget.duplicate
            ? _copyName(outfit.name)
            : outfit.name;
        for (final item in outfit.items) {
          _selectedIds[const RuleBasedOutfitEngine().roleOf(item)] = item.id;
        }
        _isLoadingOutfit = false;
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error is AppError
            ? error.message
            : 'Could not load this outfit from local storage.';
        _isLoadingOutfit = false;
      });
    }
  }

  Future<void> _save(
    List<OutfitItem> availableItems,
    bool sourceHasMissingRequiredItem,
  ) async {
    if (!_formKey.currentState!.validate()) return;
    if (sourceHasMissingRequiredItem) {
      setState(() {
        _saveError = 'Replace unavailable items before saving this outfit.';
      });
      return;
    }
    final selected = <OutfitItem>[];
    for (final role in OutfitItemRole.values) {
      final id = _selectedIds[role];
      if (id == null) continue;
      for (final item in availableItems) {
        if (item.id == id) {
          selected.add(item);
          break;
        }
      }
    }

    setState(() {
      _isSaving = true;
      _saveError = null;
    });
    try {
      final saved = await ref
          .read(manualOutfitRepositoryProvider)
          .save(
            id: widget.outfitId != null && !widget.duplicate
                ? widget.outfitId
                : null,
            name: _nameController.text,
            items: selected,
          );
      if (!mounted) return;
      context.pop(saved.id);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        _saveError = error is AppError
            ? error.message
            : 'The outfit could not be saved locally. Try again.';
        _isSaving = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  String _copyName(String name) {
    const suffix = ' (copy)';
    final baseName = name.length > 80 - suffix.length
        ? name.substring(0, 80 - suffix.length)
        : name;
    return '$baseName$suffix';
  }
}

OutfitItem _toOutfitItem(GuestWardrobeItem item) => OutfitItem(
  id: item.localId,
  title: item.title,
  category: item.category,
  subcategory: item.subcategory,
  imagePath: item.localImagePath,
  primaryColor: item.primaryColor,
  secondaryColor: item.secondaryColor,
  occasions: item.occasionValues,
  seasons: item.seasonValues,
  styleTags: item.styleTags,
  isFavorite: item.isFavorite,
  isArchived: item.isArchived,
  isDeleted: item.isDeleted,
);

class _EditorNotice extends StatelessWidget {
  const _EditorNotice({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: isError ? colors.errorContainer : colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          message,
          style: TextStyle(
            color: isError
                ? colors.onErrorContainer
                : colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
