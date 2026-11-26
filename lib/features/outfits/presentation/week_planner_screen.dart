import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_providers.dart';
import '../data/local_outfit_collection_repository.dart';
import '../data/manual_outfit_repository.dart';
import '../data/week_plan_repository.dart';
import '../data/week_plan_sync_service.dart';
import '../domain/manual_outfit.dart';
import '../domain/outfit_plan.dart';
import '../domain/rule_based_outfit_engine.dart';
import '../../wardrobe/data/local_wardrobe_repository.dart';
import '../../wardrobe/domain/guest_wardrobe_item.dart';
import '../../../core/preferences/preferences_provider.dart';

const _planOccasions = [
  'Casual',
  'Work',
  'Formal',
  'Date night',
  'Travel',
  'Workout',
];

final plannerTodayProvider = Provider<DateTime>((ref) => DateTime.now());

class WeekPlannerScreen extends ConsumerStatefulWidget {
  const WeekPlannerScreen({super.key});

  @override
  ConsumerState<WeekPlannerScreen> createState() => _WeekPlannerScreenState();
}

class _WeekPlannerScreenState extends ConsumerState<WeekPlannerScreen> {
  late final DateTime _weekStart;
  List<OutfitPlan> _plans = const [];
  List<OutfitPlan> _history = const [];
  List<OutfitPlanHistoryEntry> _historyEvents = const [];
  List<ManualOutfit> _manualOutfits = const [];
  List<LocalOutfitCollectionRecord> _savedOutfits = const [];
  final Map<String, String> _occasionOverrides = {};
  OutfitPlanStatus? _historyFilter;
  bool _isLoading = true;
  String? _error;
  final Set<String> _activeSyncUsers = {};

  @override
  void initState() {
    super.initState();
    _weekStart = nextWeekMonday(ref.read(plannerTodayProvider));
    unawaited(_reload());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authSessionProvider, (previous, next) {
      final userId = next.asData?.value?.userId;
      if (userId != null) unawaited(_syncInBackground(userId));
    });

    final wardrobe = ref.watch(wardrobeItemsProvider).asData?.value ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Week planner')),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                semanticsLabel: 'Loading week plans',
              ),
            )
          : _error != null
          ? _loadError()
          : _buildWeek(wardrobe),
    );
  }

  Widget _loadError() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _reload, child: const Text('Retry')),
        ],
      ),
    ),
  );

  Widget _buildWeek(List<GuestWardrobeItem> wardrobe) {
    final localizations = MaterialLocalizations.of(context);
    final weekEnd = _weekStart.add(const Duration(days: 6));
    return ListView(
      key: const ValueKey('week-planner-list'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text(
          'Plan your week',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${localizations.formatMediumDate(_weekStart)} – '
          '${localizations.formatMediumDate(weekEnd)}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose an occasion and outfit for each day. Every date saves on '
          'this device immediately; cloud sync runs in the background.',
        ),
        const SizedBox(height: 16),
        for (var offset = 0; offset < 7; offset++)
          _dayCard(_weekStart.add(Duration(days: offset)), wardrobe),
        if (_history.isNotEmpty || _historyEvents.isNotEmpty) ...[
          const SizedBox(height: 12),
          ExpansionTile(
            key: const ValueKey('planner-history'),
            title: const Text('Plan history'),
            subtitle: const Text('Duplicate an outfit from a previous date.'),
            children: [
              _historyFilters(),
              if (_filteredHistoryEvents.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No history matches this filter.'),
                )
              else
                for (final event in _filteredHistoryEvents)
                  _historyEventTile(event),
            ],
          ),
        ],
      ],
    );
  }

  Widget _dayCard(DateTime date, List<GuestWardrobeItem> wardrobe) {
    final key = planDateKey(date);
    final plan = _planForDate(date);
    final occasion = _occasionOverrides[key] ?? plan?.occasion ?? 'Casual';
    final localizations = MaterialLocalizations.of(context);
    return Card(
      key: ValueKey('plan-day-$key'),
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${_weekday(date.weekday)}, '
              '${localizations.formatMediumDate(date)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              key: ValueKey('plan-occasion-$key'),
              initialValue: occasion,
              decoration: const InputDecoration(labelText: 'Occasion'),
              items: [
                for (final value in _planOccasions)
                  DropdownMenuItem(value: value, child: Text(value)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _occasionOverrides[key] = value);
              },
            ),
            if (plan != null) ...[
              const SizedBox(height: 10),
              Text(
                plan.outfitName,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(_itemSummary(plan.items)),
              const SizedBox(height: 4),
              Text('Status: ${_statusLabel(plan.status)}'),
              _syncStatus(plan),
              Wrap(
                spacing: 2,
                runSpacing: 0,
                children: [
                  for (final status in OutfitPlanStatus.values)
                    TextButton(
                      key: ValueKey('plan-status-${status.name}-$key'),
                      onPressed: plan.status == status
                          ? null
                          : () => _changeStatus(plan, status),
                      child: Text(_statusActionLabel(status)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 4,
              runSpacing: 0,
              children: [
                TextButton.icon(
                  key: ValueKey('plan-select-$key'),
                  onPressed: () => _chooseOutfit(date, wardrobe),
                  icon: Icon(plan == null ? Icons.add : Icons.edit_outlined),
                  label: Text(plan == null ? 'Choose or generate' : 'Edit'),
                ),
                TextButton.icon(
                  key: ValueKey('plan-history-$key'),
                  onPressed: _history.isEmpty
                      ? null
                      : () => _duplicateFromHistory(date),
                  icon: const Icon(Icons.history),
                  label: const Text('Duplicate from history'),
                ),
                if (plan != null)
                  TextButton.icon(
                    key: ValueKey('plan-remove-$key'),
                    onPressed: () => _confirmRemove(plan),
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _syncStatus(OutfitPlan plan) {
    final canRetry =
        plan.syncState == OutfitPlanSyncState.failed &&
        ref.read(authSessionProvider).asData?.value != null;
    final label = switch (plan.syncState) {
      OutfitPlanSyncState.pending => 'Pending sync',
      OutfitPlanSyncState.syncing => 'Syncing in background…',
      OutfitPlanSyncState.synced => 'Synced',
      OutfitPlanSyncState.failed => 'Sync failed · will retry',
    };
    final icon = switch (plan.syncState) {
      OutfitPlanSyncState.pending => Icons.cloud_upload_outlined,
      OutfitPlanSyncState.syncing => Icons.sync,
      OutfitPlanSyncState.synced => Icons.cloud_done_outlined,
      OutfitPlanSyncState.failed => Icons.cloud_off_outlined,
    };
    return Row(
      children: [
        Icon(icon, size: 16),
        const SizedBox(width: 4),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        if (canRetry)
          TextButton(
            onPressed: _startBackgroundSync,
            child: const Text('Retry'),
          ),
      ],
    );
  }

  List<OutfitPlanHistoryEntry> get _filteredHistoryEvents {
    final filter = _historyFilter;
    if (filter == null) return _historyEvents;
    return _historyEvents.where((event) => event.status == filter).toList();
  }

  Widget _historyFilters() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          key: const ValueKey('history-filter-all'),
          label: const Text('All'),
          selected: _historyFilter == null,
          onSelected: (_) => setState(() => _historyFilter = null),
        ),
        for (final status in OutfitPlanStatus.values)
          ChoiceChip(
            key: ValueKey('history-filter-${status.name}'),
            label: Text(_statusLabel(status)),
            selected: _historyFilter == status,
            onSelected: (_) => setState(() => _historyFilter = status),
          ),
      ],
    ),
  );

  Widget _historyEventTile(OutfitPlanHistoryEntry event) {
    final localizations = MaterialLocalizations.of(context);
    final plan = _planById(event.planId);
    return ListTile(
      key: ValueKey('plan-history-event-${event.id}'),
      isThreeLine: true,
      title: Text(
        '${localizations.formatMediumDate(event.plannedFor)} · '
        '${event.outfitName}',
      ),
      subtitle: Text(
        '${_statusLabel(event.status)} · ${event.occasion}\n'
        '${_itemSummary(event.items)}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<OutfitPlanStatus>(
            key: ValueKey('history-status-menu-${event.id}'),
            tooltip: 'Change plan status',
            onSelected: (status) => _changeStatusForPlan(event.planId, status),
            itemBuilder: (context) => [
              for (final status in OutfitPlanStatus.values)
                PopupMenuItem(
                  value: status,
                  child: Text(_statusActionLabel(status)),
                ),
            ],
          ),
          IconButton(
            key: ValueKey('delete-history-plan-${event.id}'),
            tooltip: 'Delete plan and history',
            onPressed: plan == null ? null : () => _confirmRemove(plan),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Future<void> _changeStatus(OutfitPlan plan, OutfitPlanStatus status) =>
      _changeStatusForPlan(plan.id, status);

  Future<void> _changeStatusForPlan(
    String planId,
    OutfitPlanStatus status,
  ) async {
    try {
      await ref.read(weekPlanRepositoryProvider).markStatus(planId, status);
      await _reload();
      _startBackgroundSync();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Plan status could not be saved.')),
        );
      }
    }
  }

  Future<void> _chooseOutfit(
    DateTime date,
    List<GuestWardrobeItem> wardrobe,
  ) async {
    await _showOutfitPicker(date, wardrobe, historyOnly: false);
  }

  Future<void> _duplicateFromHistory(DateTime date) async {
    final shouldReplace =
        _planForDate(date) == null || await _confirmReplace(date);
    if (!shouldReplace || !mounted) return;
    await _showOutfitPicker(
      date,
      ref.read(wardrobeItemsProvider).asData?.value ?? const [],
      historyOnly: true,
    );
  }

  Future<bool> _confirmReplace(DateTime date) async {
    final localizations = MaterialLocalizations.of(context);
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Replace this day’s plan?'),
            content: Text(
              'The current plan for ${localizations.formatMediumDate(date)} '
              'will be replaced. Previous weeks will remain unchanged.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Replace'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showOutfitPicker(
    DateTime date,
    List<GuestWardrobeItem> wardrobe, {
    required bool historyOnly,
  }) async {
    final existing = _planForDate(date);
    var occasion =
        _occasionOverrides[planDateKey(date)] ?? existing?.occasion ?? 'Casual';
    final activeItems = wardrobe
        .where((item) => !item.isArchived && !item.isDeleted)
        .map(_toOutfitItem)
        .toList();
    final choice = await showModalBottomSheet<_OutfitChoice>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, updateSheet) {
          final currentGenerated = const RuleBasedOutfitEngine().generate(
            activeItems,
            request: OutfitRequest(occasion: occasion),
          );
          final choices = historyOnly
              ? [
                  for (final plan in _history)
                    _OutfitChoice(
                      name: plan.outfitName,
                      items: plan.items,
                      occasion: plan.occasion,
                    ),
                ]
              : [
                  for (
                    var index = 0;
                    index < currentGenerated.suggestions.length;
                    index++
                  )
                    _OutfitChoice(
                      name: 'Generated outfit ${index + 1}',
                      items: currentGenerated.suggestions[index].items,
                      occasion: occasion,
                    ),
                  for (final outfit in _manualOutfits)
                    _OutfitChoice(
                      name: outfit.name,
                      items: outfit.items,
                      occasion: occasion,
                    ),
                  for (final outfit in _savedOutfits)
                    if (outfit.isSaved || outfit.isFavorite)
                      _OutfitChoice(
                        name: 'Saved outfit',
                        items: outfit.items,
                        occasion: occasion,
                      ),
                ];

          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.78,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: Text(
                      historyOnly
                          ? 'Duplicate from history'
                          : 'Choose an outfit',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (!historyOnly)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('picker-occasion'),
                        initialValue: occasion,
                        decoration: const InputDecoration(
                          labelText: 'Occasion',
                        ),
                        items: [
                          for (final value in _planOccasions)
                            DropdownMenuItem(value: value, child: Text(value)),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          updateSheet(() => occasion = value);
                        },
                      ),
                    ),
                  if (!historyOnly && currentGenerated.suggestions.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                      child: Text(
                        currentGenerated.fallbackExplanation ?? 'Add more wardrobe items to generate a complete outfit.',
                      ),
                    ),
                  Expanded(
                    child: choices.isEmpty
                        ? Center(
                            child: Text(
                              historyOnly
                                  ? 'There are no previous plans to duplicate.'
                                  : 'No outfits are available yet. Add wardrobe '
                                        'items or save a manual outfit first.',
                              textAlign: TextAlign.center,
                            ),
                          )
                        : ListView.builder(
                            itemCount: choices.length,
                            itemBuilder: (context, index) {
                              final candidate = choices[index];
                              return ListTile(
                                key: ValueKey(
                                  'planner-choice-$index-${candidate.name}',
                                ),
                                title: Text(candidate.name),
                                subtitle: Text(_itemSummary(candidate.items)),
                                trailing: const Icon(Icons.add_circle_outline),
                                onTap: () => Navigator.pop(context, candidate),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (choice == null || !mounted) return;
    await _savePlan(date, choice, existing?.id);
  }

  Future<void> _savePlan(
    DateTime date,
    _OutfitChoice choice,
    String? existingId,
  ) async {
    try {
      final saved = await ref
          .read(weekPlanRepositoryProvider)
          .save(
            id: existingId,
            plannedFor: date,
            occasion: choice.occasion,
            outfitName: choice.name,
            items: choice.items,
          );
      if (!mounted) return;
      setState(() => _occasionOverrides.remove(planDateKey(date)));
      await _reload();
      _startBackgroundSync();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${saved.outfitName} saved for this date.')),
        );
      }
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This day could not be saved locally.')),
      );
    }
  }

  Future<void> _confirmRemove(OutfitPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this plan?'),
        content: Text(
          'Remove ${plan.outfitName} from '
          '${MaterialLocalizations.of(context).formatMediumDate(plan.plannedFor)} '
          'and delete its history? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(weekPlanRepositoryProvider).remove(plan.id);
      await _reload();
      _startBackgroundSync();
    } on Exception {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This plan could not be removed.')),
        );
      }
    }
  }

  Future<void> _reload() async {
    try {
      final repository = ref.read(weekPlanRepositoryProvider);
      final weekPlans = await repository.loadWeek(_weekStart);
      final historyPlans = await repository.loadHistory(_weekStart);
      final historyEvents = await repository.loadHistoryEvents(_weekStart);
      final manual = ref.read(manualOutfitRepositoryProvider).load();
      final savedRecords = LocalOutfitCollectionRepository(
        ref.read(sharedPreferencesProvider),
      ).load().values.toList();
      if (!mounted) return;
      setState(() {
        _plans = weekPlans;
        _history = historyPlans;
        _historyEvents = historyEvents;
        _manualOutfits = manual;
        _savedOutfits = savedRecords;
        _error = null;
        _isLoading = false;
      });
    } on Exception {
      if (!mounted) return;
      setState(() {
        _error = 'Week plans could not be loaded from this device.';
        _isLoading = false;
      });
    }
  }

  void _startBackgroundSync() {
    final session = ref.read(authSessionProvider).asData?.value;
    if (session != null) unawaited(_syncInBackground(session.userId));
  }

  Future<void> _syncInBackground(String userId) async {
    if (!_activeSyncUsers.add(userId)) return;
    try {
      await ref
          .read(weekPlanSyncServiceProvider)
          .syncPending(
            userId,
            onStatusChanged: () {
              if (mounted) unawaited(_reload());
            },
          );
      await _reload();
    } on Exception {
      if (mounted) {
        setState(() {
          _error = 'Background sync status could not be updated.';
        });
      }
    } finally {
      _activeSyncUsers.remove(userId);
    }
  }

  OutfitPlan? _planForDate(DateTime date) {
    for (final plan in _plans) {
      if (planDateKey(plan.plannedFor) == planDateKey(date)) return plan;
    }
    return null;
  }

  OutfitPlan? _planById(String id) {
    for (final plan in [..._plans, ..._history]) {
      if (plan.id == id) return plan;
    }
    return null;
  }
}

class _OutfitChoice {
  const _OutfitChoice({
    required this.name,
    required this.items,
    required this.occasion,
  });

  final String name;
  final List<OutfitItem> items;
  final String occasion;
}

String _weekday(int weekday) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][weekday - 1];

String _itemSummary(List<OutfitItem> items) =>
    items.map((item) => '${item.category}: ${item.title}').join(' · ');

String _statusLabel(OutfitPlanStatus status) => switch (status) {
  OutfitPlanStatus.planned => 'Planned',
  OutfitPlanStatus.worn => 'Worn',
  OutfitPlanStatus.skipped => 'Skipped',
  OutfitPlanStatus.modified => 'Modified',
};

String _statusActionLabel(OutfitPlanStatus status) => switch (status) {
  OutfitPlanStatus.planned => 'Mark as Planned',
  OutfitPlanStatus.worn => 'Mark Worn',
  OutfitPlanStatus.skipped => 'Mark Skipped',
  OutfitPlanStatus.modified => 'Mark Modified',
};

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
