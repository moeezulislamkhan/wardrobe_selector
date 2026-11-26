import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../wardrobe/data/local_wardrobe_repository.dart';
import '../../wardrobe/domain/guest_wardrobe_item.dart';
import '../../wardrobe/presentation/wardrobe_photo.dart';
import '../../../core/preferences/preferences_provider.dart';
import '../data/local_outfit_collection_repository.dart';
import '../data/manual_outfit_repository.dart';
import '../domain/manual_outfit.dart';
import '../domain/rule_based_outfit_engine.dart';

const _wearHistoryKey = 'outfit_last_worn_at_v1';
const _seasons = ['Any season', 'Spring', 'Summer', 'Autumn', 'Winter'];
const _occasions = [
  'Any occasion',
  'Work',
  'Casual',
  'Formal',
  'Date night',
  'Travel',
  'Workout',
];

class OutfitsScreen extends ConsumerStatefulWidget {
  const OutfitsScreen({super.key});

  @override
  ConsumerState<OutfitsScreen> createState() => _OutfitsScreenState();
}

class _OutfitsScreenState extends ConsumerState<OutfitsScreen> {
  final _preferredColorsController = TextEditingController();
  final _preferredCategoriesController = TextEditingController();
  final _preferredStylesController = TextEditingController();
  String _occasion = _occasions.first;
  String _season = _seasons.first;
  bool _rainy = false;
  bool _isLoadingWearHistory = true;
  String? _wearHistoryError;
  Map<String, DateTime> _lastWornAt = const {};
  Map<String, LocalOutfitCollectionRecord> _collectionEntries = const {};
  String? _collectionError;
  List<ManualOutfit> _manualOutfits = const [];
  String? _manualOutfitsError;
  Set<String> _excludedCombinationKeys = const {};
  final Map<String, OutfitSuggestion> _suggestionOverrides = {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadWearHistory());
    unawaited(_loadCollection());
    unawaited(_loadManualOutfits());
  }

  @override
  void dispose() {
    _preferredColorsController.dispose();
    _preferredCategoriesController.dispose();
    _preferredStylesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wardrobe = ref.watch(wardrobeItemsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Outfit ideas')),
      body: wardrobe.when(
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
                  onPressed: () => ref.invalidate(wardrobeItemsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (items) => _buildSuggestions(context, items),
      ),
    );
  }

  Widget _buildSuggestions(
    BuildContext context,
    List<GuestWardrobeItem> wardrobe,
  ) {
    final activeItems = wardrobe
        .where((item) => !item.isArchived && !item.isDeleted)
        .toList();
    final request = _request();
    final result = const RuleBasedOutfitEngine().generate(
      activeItems.map(_toOutfitItem),
      request: request,
    );
    final suggestions = [
      for (final suggestion in result.suggestions)
        _suggestionOverrides[suggestion.combinationKey] ?? suggestion,
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'Outfit ideas from your own wardrobe',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(
          'Suggestions use local styling rules only. No items are invented or '
          'sent to an AI service.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.icon(
              key: const ValueKey('create-manual-outfit'),
              onPressed: _createManualOutfit,
              icon: const Icon(Icons.add),
              label: const Text('Create outfit'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('open-week-planner'),
              onPressed: () => context.pushNamed('week-planner'),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('Plan my week'),
            ),
          ],
        ),
        if (_manualOutfitsError case final error?) ...[
          const SizedBox(height: 12),
          _InfoMessage(message: error, isError: true),
        ],
        if (_manualOutfits.isNotEmpty) ...[
          const SizedBox(height: 20),
          Text('My outfits', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final outfit in _manualOutfits)
            _ManualOutfitCard(
              outfit: outfit,
              onEdit: () => _editManualOutfit(outfit),
              onDuplicate: () => _duplicateManualOutfit(outfit),
            ),
        ],
        const SizedBox(height: 20),
        _DropdownFilter(
          label: 'Occasion',
          value: _occasion,
          options: _occasions,
          onChanged: (value) => _changeFilters(() => _occasion = value),
        ),
        const SizedBox(height: 12),
        _DropdownFilter(
          label: 'Season',
          value: _season,
          options: _seasons,
          onChanged: (value) => _changeFilters(() => _season = value),
        ),
        const SizedBox(height: 8),
        FilterChip(
          label: const Text('Rainy weather'),
          avatar: const Icon(Icons.umbrella_outlined, size: 18),
          selected: _rainy,
          onSelected: (value) => _changeFilters(() => _rainy = value),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _preferredColorsController,
          onChanged: (_) => _changeFilters(() {}),
          decoration: const InputDecoration(
            labelText: 'Preferred colors',
            hintText: 'e.g. navy, cream',
            helperText: 'Optional; separate values with commas.',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _preferredCategoriesController,
          onChanged: (_) => _changeFilters(() {}),
          decoration: const InputDecoration(
            labelText: 'Preferred categories',
            hintText: 'e.g. tops, shoes',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _preferredStylesController,
          onChanged: (_) => _changeFilters(() {}),
          decoration: const InputDecoration(
            labelText: 'Preferred style tags',
            hintText: 'e.g. minimal, classic',
          ),
        ),
        if (_isLoadingWearHistory) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          const Text('Loading recent-wear history…'),
        ],
        if (_wearHistoryError case final error?) ...[
          const SizedBox(height: 12),
          _InfoMessage(message: error, isError: true),
        ],
        if (_collectionError case final error?) ...[
          const SizedBox(height: 12),
          _InfoMessage(message: error, isError: true),
        ],
        const SizedBox(height: 20),
        if (activeItems.isEmpty)
          _NoWardrobeItems(
            onAddItem: () => context.pushNamed('wardrobe-item-add'),
          )
        else if (result.suggestions.isEmpty)
          _InfoMessage(
            message:
                result.fallbackExplanation ??
                'No unseen combinations remain. Regenerate to start again.',
          )
        else ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'Suggested combinations',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton.icon(
                key: const ValueKey('regenerate-outfits'),
                onPressed: () =>
                    _regenerate(activeItems, result.suggestions, suggestions),
                icon: const Icon(Icons.refresh),
                label: const Text('Regenerate'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < suggestions.length; index++)
            _SuggestionCard(
              key: ValueKey('outfit-card-${suggestions[index].combinationKey}'),
              number: index + 1,
              suggestion: suggestions[index],
              isSaved:
                  _collectionEntries[suggestions[index].combinationKey]
                      ?.isSaved ??
                  false,
              isFavorite:
                  _collectionEntries[suggestions[index].combinationKey]
                      ?.isFavorite ??
                  false,
              plannedFor: _collectionEntries[suggestions[index].combinationKey]
                  ?.plannedFor,
              onMarkWorn: () => _markWorn(suggestions[index]),
              onSave: () => _toggleSaved(suggestions[index]),
              onFavorite: () => _toggleFavorite(suggestions[index]),
              onSchedule: () => _schedule(suggestions[index]),
              onSwap: (item) => _swapItem(
                context,
                suggestions[index],
                activeItems,
                originalKey: result.suggestions[index].combinationKey,
                currentItem: item,
              ),
              onViewDetails: () => _viewDetails(context, suggestions[index]),
              onOpenItem: (item) => context.pushNamed(
                'wardrobe-item-detail',
                pathParameters: {'itemId': item.id},
              ),
            ),
          if (result.fallbackExplanation case final explanation?) ...[
            const SizedBox(height: 8),
            _InfoMessage(message: explanation),
          ],
        ],
      ],
    );
  }

  Future<void> _loadManualOutfits() async {
    try {
      final outfits = ref.read(manualOutfitRepositoryProvider).load();
      if (!mounted) return;
      setState(() {
        _manualOutfits = outfits;
        _manualOutfitsError = null;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _manualOutfitsError =
            'Saved manual outfits could not be loaded from this device.';
      });
    }
  }

  Future<void> _createManualOutfit() async {
    final savedId = await context.pushNamed<String>('manual-outfit-create');
    await _afterManualEditor(savedId);
  }

  Future<void> _editManualOutfit(ManualOutfit outfit) async {
    final savedId = await context.pushNamed<String>(
      'manual-outfit-edit',
      pathParameters: {'outfitId': outfit.id},
    );
    await _afterManualEditor(savedId);
  }

  Future<void> _duplicateManualOutfit(ManualOutfit outfit) async {
    final savedId = await context.pushNamed<String>(
      'manual-outfit-duplicate',
      pathParameters: {'outfitId': outfit.id},
    );
    await _afterManualEditor(savedId);
  }

  Future<void> _afterManualEditor(String? savedId) async {
    if (savedId == null || !mounted) return;
    await _loadManualOutfits();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Outfit saved locally · sync pending.')),
    );
  }

  OutfitRequest _request({Set<String>? excludedCombinationKeys}) {
    return OutfitRequest(
      occasion: _occasion == _occasions.first ? null : _occasion,
      season: _season == _seasons.first ? null : _season,
      weather: _rainy ? const OutfitWeather(rainy: true) : null,
      preferences: OutfitPreferences(
        preferredColors: _splitValues(_preferredColorsController.text),
        preferredCategories: _splitValues(_preferredCategoriesController.text),
        styleTags: _splitValues(_preferredStylesController.text),
      ),
      lastWornAt: _lastWornAt,
      excludedCombinationKeys:
          excludedCombinationKeys ?? _excludedCombinationKeys,
    );
  }

  void _changeFilters(VoidCallback change) {
    setState(() {
      change();
      _excludedCombinationKeys = const {};
      _suggestionOverrides.clear();
    });
  }

  void _regenerate(
    List<GuestWardrobeItem> activeItems,
    List<OutfitSuggestion> generatedSuggestions,
    List<OutfitSuggestion> visibleSuggestions,
  ) {
    final currentKeys = <String>{
      for (final suggestion in generatedSuggestions) suggestion.combinationKey,
      for (final suggestion in visibleSuggestions) suggestion.combinationKey,
    };
    final available = const RuleBasedOutfitEngine().generate(
      activeItems.map(_toOutfitItem),
      request: _request(excludedCombinationKeys: currentKeys),
    );
    if (available.suggestions.isEmpty) {
      setState(() {
        _excludedCombinationKeys = const {};
        _suggestionOverrides.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You have seen every combination. Starting again.'),
        ),
      );
      return;
    }

    setState(() {
      _excludedCombinationKeys = currentKeys;
      _suggestionOverrides.clear();
    });
  }

  Future<void> _loadCollection() async {
    try {
      final records = LocalOutfitCollectionRepository(
        ref.read(sharedPreferencesProvider),
      ).load();
      if (!mounted) return;
      setState(() {
        _collectionEntries = records;
        _collectionError = null;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _collectionError =
            'Saved outfits could not be loaded. Existing local data was left '
            'unchanged.';
      });
    }
  }

  Future<void> _toggleSaved(OutfitSuggestion suggestion) async {
    final current = _collectionEntries[suggestion.combinationKey];
    final saved = await _updateCollection(
      suggestion,
      isSaved: !(current?.isSaved ?? false),
    );
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          current?.isSaved == true
              ? 'Outfit removed from saved.'
              : 'Outfit saved offline.',
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(OutfitSuggestion suggestion) async {
    final current = _collectionEntries[suggestion.combinationKey];
    await _updateCollection(
      suggestion,
      isFavorite: !(current?.isFavorite ?? false),
    );
  }

  Future<void> _schedule(OutfitSuggestion suggestion) async {
    final today = DateUtils.dateOnly(DateTime.now());
    final existing = _collectionEntries[suggestion.combinationKey]?.plannedFor;
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: existing != null && !existing.isBefore(today)
          ? DateUtils.dateOnly(existing)
          : today,
      firstDate: today,
      lastDate: DateTime(today.year + 5),
      helpText: 'Schedule this outfit',
    );
    if (selectedDate == null || !mounted) return;
    final saved = await _updateCollection(
      suggestion,
      plannedFor: DateUtils.dateOnly(selectedDate),
    );
    if (!saved || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Outfit scheduled offline for '
          '${MaterialLocalizations.of(context).formatMediumDate(selectedDate)}.',
        ),
      ),
    );
  }

  Future<bool> _updateCollection(
    OutfitSuggestion suggestion, {
    bool? isSaved,
    bool? isFavorite,
    DateTime? plannedFor,
  }) async {
    try {
      final record =
          await LocalOutfitCollectionRepository(
            ref.read(sharedPreferencesProvider),
          ).update(
            suggestion,
            isSaved: isSaved,
            isFavorite: isFavorite,
            plannedFor: plannedFor,
          );
      if (!mounted) return false;
      setState(() {
        final updated = Map<String, LocalOutfitCollectionRecord>.of(
          _collectionEntries,
        );
        if (record == null) {
          updated.remove(suggestion.combinationKey);
        } else {
          updated[suggestion.combinationKey] = record;
        }
        _collectionEntries = Map.unmodifiable(updated);
        _collectionError = null;
      });
      return true;
    } on Exception {
      if (mounted) {
        setState(() {
          _collectionError = 'That outfit change could not be saved locally. Please try again.';
        });
      }
      return false;
    }
  }

  Future<void> _swapItem(
    BuildContext context,
    OutfitSuggestion suggestion,
    List<GuestWardrobeItem> wardrobe, {
    required String originalKey,
    required OutfitItem currentItem,
  }) async {
    final usedIds = suggestion.items.map((item) => item.id).toSet();
    final selectedItem = await showModalBottomSheet<GuestWardrobeItem>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final alternatives = wardrobe.where((item) {
          return !item.isArchived &&
              !item.isDeleted &&
              !usedIds.contains(item.localId) &&
              item.category.toLowerCase() == currentItem.category.toLowerCase();
        }).toList();
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.65,
            child: alternatives.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No other items in this category to swap in.',
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Choose a replacement',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      for (final item in alternatives)
                        ListTile(
                          leading: SizedBox(
                            width: 52,
                            height: 52,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: WardrobePhoto(
                                path: item.localImagePath,
                                compact: true,
                              ),
                            ),
                          ),
                          title: Text(item.title),
                          subtitle: Text(item.category),
                          onTap: () => Navigator.pop(context, item),
                        ),
                    ],
                  ),
          ),
        );
      },
    );
    if (selectedItem == null || !mounted) return;

    final replacement = _toOutfitItem(selectedItem);
    final swapped = _replaceItem(suggestion, currentItem, replacement);
    setState(() {
      _suggestionOverrides[originalKey] = swapped;
    });
  }

  OutfitSuggestion _replaceItem(
    OutfitSuggestion suggestion,
    OutfitItem currentItem,
    OutfitItem replacement,
  ) {
    OutfitItem replace(OutfitItem current) =>
        current.id == currentItem.id ? replacement : current;
    return OutfitSuggestion(
      top: replace(suggestion.top),
      bottom: replace(suggestion.bottom),
      shoes: replace(suggestion.shoes),
      layer: suggestion.layer == null ? null : replace(suggestion.layer!),
      accessory: suggestion.accessory == null
          ? null
          : replace(suggestion.accessory!),
      reasons: [
        'You swapped an item; other recommendation reasons may no longer apply.',
      ],
      score: suggestion.score,
    );
  }

  Future<void> _viewDetails(
    BuildContext context,
    OutfitSuggestion suggestion,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.75,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Outfit details',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('Why this was recommended'),
              for (final reason in suggestion.reasons)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(reason),
                ),
              const Divider(),
              for (final item in suggestion.items)
                ListTile(
                  leading: SizedBox(
                    width: 48,
                    height: 48,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: WardrobePhoto(path: item.imagePath, compact: true),
                    ),
                  ),
                  title: Text(item.title),
                  subtitle: Text(
                    [
                      item.category,
                      if (item.subcategory != null) item.subcategory!,
                      if (item.primaryColor != null) item.primaryColor!,
                    ].join(' · '),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    context.pushNamed(
                      'wardrobe-item-detail',
                      pathParameters: {'itemId': item.id},
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadWearHistory() async {
    try {
      final encoded = ref
          .read(sharedPreferencesProvider)
          .getString(_wearHistoryKey);
      if (encoded == null) {
        if (mounted) setState(() => _isLoadingWearHistory = false);
        return;
      }

      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        throw const FormatException('Recent-wear history must be a map.');
      }
      final lastWornAt = <String, DateTime>{};
      for (final entry in decoded.entries) {
        if (entry.key is! String || entry.value is! String) {
          throw const FormatException('Recent-wear history has invalid data.');
        }
        final date = DateTime.tryParse(entry.value as String);
        if (date == null) {
          throw const FormatException(
            'Recent-wear history has an invalid date.',
          );
        }
        lastWornAt[entry.key as String] = date;
      }
      if (mounted) {
        setState(() {
          _lastWornAt = Map.unmodifiable(lastWornAt);
          _isLoadingWearHistory = false;
        });
      }
    } on Exception {
      if (!mounted) return;
      setState(() {
        _isLoadingWearHistory = false;
        _wearHistoryError =
            'Recent-wear history could not be read. Suggestions will not '
            'include the wear penalty until it is available again.';
      });
    }
  }

  Future<void> _markWorn(OutfitSuggestion suggestion) async {
    final now = DateTime.now();
    final updated = Map<String, DateTime>.of(_lastWornAt);
    for (final item in suggestion.items) {
      updated[item.id] = now;
    }

    try {
      final persisted = await ref
          .read(sharedPreferencesProvider)
          .setString(
            _wearHistoryKey,
            jsonEncode(
              updated.map(
                (id, date) => MapEntry(id, date.toUtc().toIso8601String()),
              ),
            ),
          );
      if (!persisted) {
        throw StateError('Recent-wear history could not be saved.');
      }
      if (!mounted) return;
      setState(() {
        _lastWornAt = Map.unmodifiable(updated);
        _wearHistoryError = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Outfit marked as recently worn.')),
      );
    } on Exception {
      if (!mounted) return;
      setState(() {
        _wearHistoryError =
            'Could not save recent-wear history. The wear penalty was not '
            'updated.';
      });
    }
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

List<String> _splitValues(String value) => List.unmodifiable(
  value
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toSet(),
);

class _DropdownFilter extends StatelessWidget {
  const _DropdownFilter({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: [
            for (final option in options)
              DropdownMenuItem(value: option, child: Text(option)),
          ],
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ),
    );
  }
}

class _ManualOutfitCard extends StatelessWidget {
  const _ManualOutfitCard({
    required this.outfit,
    required this.onEdit,
    required this.onDuplicate,
  });

  final ManualOutfit outfit;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: ValueKey('manual-outfit-card-${outfit.id}'),
      margin: const EdgeInsets.symmetric(vertical: 5),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(outfit.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              outfit.items
                  .map((item) => '${item.category}: ${item.title}')
                  .join(' · '),
            ),
            const SizedBox(height: 4),
            Text(
              outfit.needsCloudSync ? 'Saved locally · sync pending' : 'Synced',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                TextButton.icon(
                  key: ValueKey('edit-manual-outfit-${outfit.id}'),
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Edit'),
                ),
                TextButton.icon(
                  key: ValueKey('duplicate-manual-outfit-${outfit.id}'),
                  onPressed: onDuplicate,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('Duplicate'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    required this.number,
    required this.suggestion,
    required this.isSaved,
    required this.isFavorite,
    required this.plannedFor,
    required this.onMarkWorn,
    required this.onSave,
    required this.onFavorite,
    required this.onSchedule,
    required this.onSwap,
    required this.onViewDetails,
    required this.onOpenItem,
    super.key,
  });

  final int number;
  final OutfitSuggestion suggestion;
  final bool isSaved;
  final bool isFavorite;
  final DateTime? plannedFor;
  final VoidCallback onMarkWorn;
  final VoidCallback onSave;
  final VoidCallback onFavorite;
  final VoidCallback onSchedule;
  final ValueChanged<OutfitItem> onSwap;
  final VoidCallback onViewDetails;
  final ValueChanged<OutfitItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Outfit $number', style: textTheme.titleMedium),
                ),
                IconButton(
                  key: ValueKey('favorite-${suggestion.combinationKey}'),
                  tooltip: isFavorite
                      ? 'Remove outfit from favorites'
                      : 'Favorite outfit',
                  onPressed: onFavorite,
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _OutfitPiece(
              label: 'Top',
              item: suggestion.top,
              onSwap: onSwap,
              onOpenItem: onOpenItem,
            ),
            _OutfitPiece(
              label: 'Bottom',
              item: suggestion.bottom,
              onSwap: onSwap,
              onOpenItem: onOpenItem,
            ),
            _OutfitPiece(
              label: 'Shoes',
              item: suggestion.shoes,
              onSwap: onSwap,
              onOpenItem: onOpenItem,
            ),
            if (suggestion.layer case final layer?)
              _OutfitPiece(
                label: 'Layer',
                item: layer,
                onSwap: onSwap,
                onOpenItem: onOpenItem,
              ),
            if (suggestion.accessory case final accessory?)
              _OutfitPiece(
                label: 'Accessory',
                item: accessory,
                onSwap: onSwap,
                onOpenItem: onOpenItem,
              ),
            const SizedBox(height: 12),
            Text('Why this outfit', style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final reason in suggestion.reasons)
                  Chip(
                    avatar: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(reason),
                  ),
              ],
            ),
            if (plannedFor case final planned?) ...[
              const SizedBox(height: 4),
              Chip(
                avatar: const Icon(Icons.event_available_outlined, size: 18),
                label: Text(
                  'Scheduled for '
                  '${MaterialLocalizations.of(context).formatMediumDate(planned)}',
                ),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  key: ValueKey('save-${suggestion.combinationKey}'),
                  onPressed: onSave,
                  icon: Icon(isSaved ? Icons.bookmark : Icons.bookmark_border),
                  label: Text(isSaved ? 'Saved' : 'Save outfit'),
                ),
                TextButton.icon(
                  onPressed: onSchedule,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(plannedFor == null ? 'Schedule' : 'Reschedule'),
                ),
                TextButton.icon(
                  onPressed: onViewDetails,
                  icon: const Icon(Icons.info_outline),
                  label: const Text('View details'),
                ),
                TextButton.icon(
                  onPressed: onMarkWorn,
                  icon: const Icon(Icons.checkroom_outlined),
                  label: const Text('Mark as worn'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OutfitPiece extends StatelessWidget {
  const _OutfitPiece({
    required this.label,
    required this.item,
    required this.onSwap,
    required this.onOpenItem,
  });

  final String label;
  final OutfitItem item;
  final ValueChanged<OutfitItem> onSwap;
  final ValueChanged<OutfitItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            height: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: WardrobePhoto(path: item.imagePath, compact: true),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: InkWell(
              onTap: () => onOpenItem(item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: textTheme.labelMedium),
                    Text(item.title, style: textTheme.titleSmall),
                    Text(
                      [
                        item.category,
                        if (item.subcategory != null) item.subcategory!,
                      ].join(' · '),
                      style: textTheme.bodySmall,
                    ),
                    if (item.primaryColor case final color?)
                      Text(color, style: textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            key: ValueKey('swap-${item.id}'),
            tooltip: 'Swap $label',
            onPressed: () => onSwap(item),
            icon: const Icon(Icons.swap_horiz),
          ),
        ],
      ),
    );
  }
}

class _NoWardrobeItems extends StatelessWidget {
  const _NoWardrobeItems({required this.onAddItem});

  final VoidCallback onAddItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.checkroom_outlined, size: 44),
        const SizedBox(height: 12),
        Text(
          'Add your own wardrobe items',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Outfit ideas are made only from items you save. There is no sample '
          'or invented inventory.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: onAddItem,
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Add a wardrobe item'),
        ),
      ],
    );
  }
}

class _InfoMessage extends StatelessWidget {
  const _InfoMessage({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      color: isError ? colors.errorContainer : colors.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.info_outline,
              color: isError
                  ? colors.onErrorContainer
                  : colors.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
