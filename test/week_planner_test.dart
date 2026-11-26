import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wardrobe_recommender_app/core/preferences/preferences_provider.dart';
import 'package:wardrobe_recommender_app/features/outfits/data/week_plan_repository.dart';
import 'package:wardrobe_recommender_app/features/outfits/domain/outfit_plan.dart';
import 'package:wardrobe_recommender_app/features/outfits/domain/rule_based_outfit_engine.dart';
import 'package:wardrobe_recommender_app/features/outfits/presentation/week_planner_screen.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/domain/guest_wardrobe_item.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('Sunday starts the upcoming Monday-to-Sunday planning week', () {
    expect(planDateKey(nextWeekMonday(DateTime(2026, 11, 29))), '2026-11-30');
    expect(planDateKey(nextWeekMonday(DateTime(2026, 11, 30))), '2026-12-07');
  });

  test('upgrading a v1 database backfills immutable plan history', () async {
    final directory = await Directory.systemTemp.createTemp('week-planner-');
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'legacy.db');
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: _createLegacyWeekPlanTables,
      ),
    );
    await legacy.insert('week_plans', {
      'id': 'legacy-plan',
      'planned_date': '2026-11-23',
      'occasion': 'Work',
      'outfit_name': 'Legacy outfit',
      'items_json': _itemsJson(),
      'created_at': '2026-11-01T00:00:00.000Z',
      'updated_at': '2026-11-22T12:00:00.000Z',
      'sync_state': 'synced',
      'sync_error': null,
    });
    await legacy.close();

    final upgraded = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 2,
        onUpgrade: upgradeWeekPlanTables,
      ),
    );
    addTearDown(upgraded.close);
    final repository = SqliteWeekPlanRepository(Future.value(upgraded));
    final history = await repository.loadHistoryEvents(DateTime(2026, 11, 30));

    expect(history, hasLength(1));
    expect(history.single.planId, 'legacy-plan');
    expect(history.single.status, OutfitPlanStatus.planned);
    expect(history.single.items.map((item) => item.title), [
      'Blue shirt',
      'Black jeans',
      'Black sneakers',
    ]);
    expect(
      (await repository.loadHistory(DateTime(2026, 11, 30))).single.id,
      'legacy-plan',
    );
  });

  test('cloud history timestamps preserve the planned calendar date', () {
    final entry = _historyEntry(
      _plan(DateTime(2026, 11, 23), 'Old outfit'),
      OutfitPlanStatus.planned,
      'history-entry',
    );

    expect(
      entry.toCloudRow('user-id')['planned_for'],
      '2026-11-23T00:00:00.000Z',
    );
  });

  test(
    'SQLite reloads all seven offline plans without replacing history',
    () async {
      final database = await _openDatabase();
      addTearDown(database.close);
      final repository = SqliteWeekPlanRepository(Future.value(database));
      final items = _outfit();
      final previous = await repository.save(
        plannedFor: DateTime(2026, 11, 23),
        occasion: 'Work',
        outfitName: 'Previous week outfit',
        items: items,
      );

      for (var day = 0; day < 7; day++) {
        await repository.save(
          plannedFor: DateTime(2026, 11, 30 + day),
          occasion: day == 6 ? 'Formal' : 'Casual',
          outfitName: 'Week outfit $day',
          items: items,
        );
      }

      final reloaded = SqliteWeekPlanRepository(Future.value(database));
      final week = await reloaded.loadWeek(DateTime(2026, 11, 30));
      expect(week, hasLength(7));
      expect(week.map((plan) => planDateKey(plan.plannedFor)), [
        for (var day = 0; day < 7; day++)
          planDateKey(DateTime(2026, 11, 30 + day)),
      ]);
      expect(week.last.occasion, 'Formal');
      expect(
        week.every((plan) => plan.syncState == OutfitPlanSyncState.pending),
        isTrue,
      );

      final history = await reloaded.loadHistory(DateTime(2026, 11, 30));
      expect(history, hasLength(1));
      expect(history.single.id, previous.id);
      expect(history.single.outfitName, 'Previous week outfit');
      expect(
        (await reloaded.loadHistoryEvents(DateTime(2026, 11, 30)))
            .single
            .status,
        OutfitPlanStatus.planned,
      );

      final worn = await reloaded.markStatus(
        previous.id,
        OutfitPlanStatus.worn,
      );
      expect(worn.status, OutfitPlanStatus.worn);
      final previousEvents = await reloaded.historyForPlan(previous.id);
      expect(previousEvents.map((event) => event.status), [
        OutfitPlanStatus.planned,
        OutfitPlanStatus.worn,
      ]);
      expect(previousEvents.first.items.first.title, 'Blue shirt');

      final edited = await reloaded.save(
        id: week.first.id,
        plannedFor: week.first.plannedFor,
        occasion: 'Work',
        outfitName: 'Edited Monday outfit',
        items: [
          const OutfitItem(
            id: 'top-1',
            title: 'Updated blue shirt',
            category: 'Tops',
          ),
          ...items.skip(1),
        ],
      );
      expect(edited.id, week.first.id);
      expect(edited.createdAt, week.first.createdAt);
      expect(edited.status, OutfitPlanStatus.modified);
      final editedEvents = await reloaded.historyForPlan(edited.id);
      expect(editedEvents.map((event) => event.status), [
        OutfitPlanStatus.planned,
        OutfitPlanStatus.modified,
      ]);
      expect(editedEvents.first.items.first.title, 'Blue shirt');
      expect(editedEvents.last.items.first.title, 'Updated blue shirt');
      expect(
        (await reloaded.loadHistory(DateTime(2026, 11, 30))).single.id,
        previous.id,
      );

      await reloaded.markSynced(
        edited.id,
        action: OutfitPlanSyncAction.upsert,
        expectedUpdatedAt: DateTime.utc(2000),
      );
      expect(
        (await reloaded.pendingSync()).any(
          (operation) =>
              operation.planId == edited.id &&
              operation.action == OutfitPlanSyncAction.upsert,
        ),
        isTrue,
      );
      await reloaded.markSynced(
        edited.id,
        action: OutfitPlanSyncAction.upsert,
        expectedUpdatedAt: edited.updatedAt,
      );

      await reloaded.remove(week.last.id);
      expect(await reloaded.loadWeek(DateTime(2026, 11, 30)), hasLength(6));
      expect(
        (await reloaded.pendingSync()).any(
          (operation) =>
              operation.planId == week.last.id &&
              operation.action == OutfitPlanSyncAction.delete,
        ),
        isTrue,
      );
      await reloaded.markSynced(
        week.last.id,
        action: OutfitPlanSyncAction.delete,
      );
      expect(
        (await reloaded.pendingSync()).any(
          (operation) => operation.planId == week.last.id,
        ),
        isFalse,
      );
    },
  );

  testWidgets('Sunday can plan offline and access Monday through Sunday', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'wardrobe_items_v1': jsonEncode([
        _wardrobeItem('top-1', 'Blue shirt', 'Tops').toJson(),
        _wardrobeItem('bottom-1', 'Black jeans', 'Bottoms').toJson(),
        _wardrobeItem('shoes-1', 'Black sneakers', 'Shoes').toJson(),
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final oldPlan = _plan(
      DateTime(2026, 11, 23),
      'Old outfit',
    ).copyWith(status: OutfitPlanStatus.worn);
    final repository = _MemoryWeekPlanRepository(
      [
        for (var day = 0; day < 7; day++)
          _plan(DateTime(2026, 11, 30 + day), 'Week outfit $day'),
        oldPlan,
      ],
      [
        for (final status in OutfitPlanStatus.values)
          _historyEntry(oldPlan, status, 'history-${status.name}'),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          weekPlanRepositoryProvider.overrideWithValue(repository),
          plannerTodayProvider.overrideWithValue(DateTime(2026, 11, 29)),
        ],
        child: const MaterialApp(home: WeekPlannerScreen()),
      ),
    );
    await _pumpUntil(tester, find.byKey(const ValueKey('plan-day-2026-11-30')));

    final plannerScrollable = find
        .descendant(
          of: find.byKey(const ValueKey('week-planner-list')),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(find.textContaining('Monday,'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('plan-day-2026-12-06')),
      240,
      scrollable: plannerScrollable,
    );
    expect(find.byKey(const ValueKey('plan-day-2026-12-06')), findsOneWidget);
    expect(find.text('Week outfit 6'), findsOneWidget);
    expect(await repository.loadWeek(DateTime(2026, 11, 30)), hasLength(7));

    final scrollPosition = tester
        .state<ScrollableState>(plannerScrollable)
        .position;
    scrollPosition.jumpTo(scrollPosition.maxScrollExtent);
    await tester.pumpAndSettle();
    final sundayStatusButton = find.byKey(
      const ValueKey('plan-status-worn-2026-12-06'),
    );
    await tester.tap(sundayStatusButton);
    await _pumpUntil(tester, find.text('Status: Worn'));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('planner-history')),
      240,
      scrollable: plannerScrollable,
    );
    await tester.tap(find.byKey(const ValueKey('planner-history')));
    for (final status in OutfitPlanStatus.values) {
      final filter = find.byKey(ValueKey('history-filter-${status.name}'));
      await _pumpUntil(tester, filter);
      await tester.ensureVisible(filter);
      await tester.pumpAndSettle();
      await tester.tap(filter);
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('plan-history-event-history-${status.name}')),
        findsOneWidget,
      );
      for (final otherStatus in OutfitPlanStatus.values) {
        if (otherStatus == status) continue;
        expect(
          find.byKey(
            ValueKey('plan-history-event-history-${otherStatus.name}'),
          ),
          findsNothing,
        );
      }
    }
  });
}

Future<Database> _openDatabase() => databaseFactoryFfi.openDatabase(
  inMemoryDatabasePath,
  options: OpenDatabaseOptions(version: 2, onCreate: createWeekPlanTables),
);

Future<void> _createLegacyWeekPlanTables(Database database, int version) async {
  await database.execute('''
    CREATE TABLE week_plans (
      id TEXT PRIMARY KEY NOT NULL,
      planned_date TEXT NOT NULL UNIQUE,
      occasion TEXT NOT NULL,
      outfit_name TEXT NOT NULL,
      items_json TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_state TEXT NOT NULL,
      sync_error TEXT
    )
  ''');
  await database.execute('''
    CREATE TABLE week_plan_sync_queue (
      plan_id TEXT PRIMARY KEY NOT NULL,
      operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
      payload TEXT,
      queued_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
}

String _itemsJson() => jsonEncode([
  for (final item in _outfit())
    {
      'id': item.id,
      'title': item.title,
      'category': item.category,
      'subcategory': item.subcategory,
      'imagePath': item.imagePath,
      'primaryColor': item.primaryColor,
      'secondaryColor': item.secondaryColor,
      'occasions': item.occasions,
      'seasons': item.seasons,
      'styleTags': item.styleTags,
    },
]);

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
  }
  expect(finder, findsOneWidget);
}

List<OutfitItem> _outfit() => const [
  OutfitItem(id: 'top-1', title: 'Blue shirt', category: 'Tops'),
  OutfitItem(id: 'bottom-1', title: 'Black jeans', category: 'Bottoms'),
  OutfitItem(id: 'shoes-1', title: 'Black sneakers', category: 'Shoes'),
];

OutfitPlan _plan(DateTime date, String name) => OutfitPlan(
  id: planDateKey(date),
  plannedFor: date,
  occasion: 'Casual',
  outfitName: name,
  items: _outfit(),
  status: OutfitPlanStatus.planned,
  createdAt: DateTime.utc(2026, 11, 1),
  updatedAt: DateTime.utc(2026, 11, 1),
  syncState: OutfitPlanSyncState.pending,
);

OutfitPlanHistoryEntry _historyEntry(
  OutfitPlan plan,
  OutfitPlanStatus status,
  String id,
) => OutfitPlanHistoryEntry(
  id: id,
  planId: plan.id,
  plannedFor: plan.plannedFor,
  status: status,
  occasion: plan.occasion,
  outfitName: plan.outfitName,
  items: plan.items,
  recordedAt: plan.updatedAt,
);

class _MemoryWeekPlanRepository implements WeekPlanRepository {
  _MemoryWeekPlanRepository(this.plans, this.events);

  final List<OutfitPlan> plans;
  final List<OutfitPlanHistoryEntry> events;

  @override
  Future<List<OutfitPlan>> loadWeek(DateTime monday) async => plans
      .where(
        (plan) =>
            !plan.plannedFor.isBefore(monday) &&
            plan.plannedFor.isBefore(monday.add(const Duration(days: 7))),
      )
      .toList();

  @override
  Future<List<OutfitPlan>> loadHistory(DateTime before) async =>
      plans.where((plan) => plan.plannedFor.isBefore(before)).toList();

  @override
  Future<List<OutfitPlanHistoryEntry>> loadHistoryEvents(
    DateTime before,
  ) async =>
      events.where((event) => event.plannedFor.isBefore(before)).toList();

  @override
  Future<List<OutfitPlanHistoryEntry>> historyForPlan(String planId) async =>
      events.where((event) => event.planId == planId).toList();

  @override
  Future<OutfitPlan> save({
    String? id,
    required DateTime plannedFor,
    required String occasion,
    required String outfitName,
    required List<OutfitItem> items,
  }) => throw UnimplementedError();

  @override
  Future<void> remove(String id) => throw UnimplementedError();

  @override
  Future<OutfitPlan> markStatus(String id, OutfitPlanStatus status) async {
    final index = plans.indexWhere((plan) => plan.id == id);
    final updated = plans[index].copyWith(status: status);
    plans[index] = updated;
    events.add(_historyEntry(updated, status, 'event-${events.length}'));
    return updated;
  }

  @override
  Future<List<OutfitPlanSyncOperation>> pendingSync() async => const [];

  @override
  Future<void> markSyncing(String id) => throw UnimplementedError();

  @override
  Future<void> markSynced(
    String id, {
    required OutfitPlanSyncAction action,
    DateTime? expectedUpdatedAt,
  }) => throw UnimplementedError();

  @override
  Future<void> markSyncFailed(String id, {DateTime? expectedUpdatedAt}) =>
      throw UnimplementedError();
}

GuestWardrobeItem _wardrobeItem(String id, String title, String category) =>
    GuestWardrobeItem(
      localId: id,
      title: title,
      category: category,
      createdAt: DateTime.utc(2026, 11, 26),
    );
