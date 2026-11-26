import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../core/errors/app_error.dart';
import '../domain/outfit_plan.dart';
import '../domain/rule_based_outfit_engine.dart';

final weekPlanDatabaseProvider = Provider<Future<Database>>((ref) async {
  final directory = await getDatabasesPath();
  return openDatabase(
    p.join(directory, 'wardrobe_week_plans.db'),
    version: 2,
    onCreate: createWeekPlanTables,
    onUpgrade: upgradeWeekPlanTables,
  );
});

final weekPlanRepositoryProvider = Provider<WeekPlanRepository>(
  (ref) => SqliteWeekPlanRepository(ref.watch(weekPlanDatabaseProvider)),
);

abstract interface class WeekPlanRepository {
  Future<List<OutfitPlan>> loadWeek(DateTime monday);

  Future<List<OutfitPlan>> loadHistory(DateTime before);

  Future<List<OutfitPlanHistoryEntry>> loadHistoryEvents(DateTime before);

  Future<List<OutfitPlanHistoryEntry>> historyForPlan(String planId);

  Future<OutfitPlan> save({
    String? id,
    required DateTime plannedFor,
    required String occasion,
    required String outfitName,
    required List<OutfitItem> items,
  });

  Future<OutfitPlan> markStatus(String id, OutfitPlanStatus status);

  Future<void> remove(String id);

  Future<List<OutfitPlanSyncOperation>> pendingSync();

  Future<void> markSyncing(String id);

  Future<void> markSynced(
    String id, {
    required OutfitPlanSyncAction action,
    DateTime? expectedUpdatedAt,
  });

  Future<void> markSyncFailed(String id, {DateTime? expectedUpdatedAt});
}

enum OutfitPlanSyncAction { upsert, delete }

class OutfitPlanSyncOperation {
  const OutfitPlanSyncOperation({
    required this.planId,
    required this.action,
    this.plan,
  });

  final String planId;
  final OutfitPlanSyncAction action;
  final OutfitPlan? plan;
}

class SqliteWeekPlanRepository implements WeekPlanRepository {
  const SqliteWeekPlanRepository(this._databaseFuture);

  final Future<Database> _databaseFuture;

  @override
  Future<List<OutfitPlan>> loadWeek(DateTime monday) async {
    final database = await _databaseFuture;
    final rows = await database.query(
      'week_plans',
      where: 'planned_date >= ? AND planned_date < ?',
      whereArgs: [
        planDateKey(monday),
        planDateKey(monday.add(const Duration(days: 7))),
      ],
      orderBy: 'planned_date ASC',
    );
    return List.unmodifiable(rows.map(_planFromRow));
  }

  @override
  Future<List<OutfitPlan>> loadHistory(DateTime before) async {
    final database = await _databaseFuture;
    final rows = await database.query(
      'week_plans',
      where: 'planned_date < ?',
      whereArgs: [planDateKey(before)],
      orderBy: 'planned_date DESC',
    );
    return List.unmodifiable(rows.map(_planFromRow));
  }

  @override
  Future<List<OutfitPlanHistoryEntry>> loadHistoryEvents(
    DateTime before,
  ) async {
    final database = await _databaseFuture;
    final rows = await database.query(
      'week_plan_history',
      where: 'planned_date < ?',
      whereArgs: [planDateKey(before)],
      orderBy: 'recorded_at DESC',
    );
    return List.unmodifiable(rows.map(_historyEntryFromRow));
  }

  @override
  Future<List<OutfitPlanHistoryEntry>> historyForPlan(String planId) async {
    final database = await _databaseFuture;
    final rows = await database.query(
      'week_plan_history',
      where: 'plan_id = ?',
      whereArgs: [planId],
      orderBy: 'recorded_at ASC',
    );
    return List.unmodifiable(rows.map(_historyEntryFromRow));
  }

  @override
  Future<OutfitPlan> save({
    String? id,
    required DateTime plannedFor,
    required String occasion,
    required String outfitName,
    required List<OutfitItem> items,
  }) async {
    _validate(occasion, outfitName, items);
    final database = await _databaseFuture;
    final dateKey = planDateKey(plannedFor);

    return database.transaction((transaction) async {
      final sameDate = await transaction.query(
        'week_plans',
        where: 'planned_date = ?',
        whereArgs: [dateKey],
        limit: 1,
      );
      final existing = sameDate.isEmpty ? null : sameDate.single;
      if (id != null && existing?['id'] != id) {
        throw const AppError(
          'This plan changed elsewhere. Reload the week and try again.',
        );
      }

      final now = DateTime.now().toUtc();
      final plan = OutfitPlan(
        id: existing?['id'] as String? ?? id ?? _newUuid(),
        plannedFor: DateTime(plannedFor.year, plannedFor.month, plannedFor.day),
        occasion: occasion.trim(),
        outfitName: outfitName.trim(),
        items: List.unmodifiable(items),
        status: existing == null
            ? OutfitPlanStatus.planned
            : OutfitPlanStatus.modified,
        createdAt: existing == null
            ? now
            : DateTime.parse(existing['created_at'] as String),
        updatedAt: now,
        syncState: OutfitPlanSyncState.pending,
      );
      final row = _planToRow(plan);
      if (existing == null) {
        await transaction.insert('week_plans', row);
      } else {
        await transaction.update(
          'week_plans',
          row..remove('id'),
          where: 'id = ?',
          whereArgs: [plan.id],
        );
      }
      await transaction.insert('week_plan_sync_queue', {
        'plan_id': plan.id,
        'operation': 'upsert',
        'payload': jsonEncode(plan.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _insertHistoryEntry(transaction, plan);
      return plan;
    });
  }

  @override
  Future<OutfitPlan> markStatus(String id, OutfitPlanStatus status) async {
    final database = await _databaseFuture;
    return database.transaction((transaction) async {
      final rows = await transaction.query(
        'week_plans',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (rows.isEmpty) {
        throw const AppError('This plan is no longer available.');
      }

      final current = _planFromRow(rows.single);
      if (current.status == status) return current;
      final updated = current.copyWith(
        status: status,
        updatedAt: DateTime.now().toUtc(),
        syncState: OutfitPlanSyncState.pending,
      );
      await transaction.update(
        'week_plans',
        {
          'status': status.name,
          'updated_at': updated.updatedAt.toUtc().toIso8601String(),
          'sync_state': OutfitPlanSyncState.pending.name,
          'sync_error': null,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      await transaction.insert('week_plan_sync_queue', {
        'plan_id': id,
        'operation': 'upsert',
        'payload': jsonEncode(updated.toJson()),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _insertHistoryEntry(transaction, updated);
      return updated;
    });
  }

  @override
  Future<void> remove(String id) async {
    final database = await _databaseFuture;
    await database.transaction((transaction) async {
      final rows = await transaction.query(
        'week_plans',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [id],
      );
      if (rows.isEmpty) return;
      await transaction.delete('week_plans', where: 'id = ?', whereArgs: [id]);
      await transaction.delete(
        'week_plan_history',
        where: 'plan_id = ?',
        whereArgs: [id],
      );
      await transaction.insert('week_plan_sync_queue', {
        'plan_id': id,
        'operation': 'delete',
        'payload': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  @override
  Future<List<OutfitPlanSyncOperation>> pendingSync() async {
    final database = await _databaseFuture;
    final rows = await database.query(
      'week_plan_sync_queue',
      orderBy: 'queued_at ASC',
    );
    return List.unmodifiable(
      rows.map((row) {
        final payload = row['payload'] as String?;
        return OutfitPlanSyncOperation(
          planId: row['plan_id'] as String,
          action: OutfitPlanSyncAction.values.byName(
            row['operation'] as String,
          ),
          plan: payload == null
              ? null
              : OutfitPlan.fromJson(
                  Map<String, Object?>.from(jsonDecode(payload) as Map),
                ),
        );
      }),
    );
  }

  @override
  Future<void> markSyncing(String id) async {
    final database = await _databaseFuture;
    await database.update(
      'week_plans',
      {'sync_state': OutfitPlanSyncState.syncing.name, 'sync_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<void> markSynced(
    String id, {
    required OutfitPlanSyncAction action,
    DateTime? expectedUpdatedAt,
  }) async {
    final database = await _databaseFuture;
    await database.transaction((transaction) async {
      final queueRows = await transaction.query(
        'week_plan_sync_queue',
        columns: ['payload'],
        where: 'plan_id = ? AND operation = ?',
        whereArgs: [id, action.name],
        limit: 1,
      );
      if (queueRows.isEmpty) return;

      if (action == OutfitPlanSyncAction.upsert) {
        final payload = queueRows.single['payload'] as String?;
        if (payload == null ||
            expectedUpdatedAt == null ||
            OutfitPlan.fromJson(
                  Map<String, Object?>.from(jsonDecode(payload) as Map),
                ).updatedAt.toUtc().toIso8601String() !=
                expectedUpdatedAt.toUtc().toIso8601String()) {
          return;
        }
        await transaction.update(
          'week_plans',
          {'sync_state': OutfitPlanSyncState.synced.name, 'sync_error': null},
          where: 'id = ? AND updated_at = ?',
          whereArgs: [id, expectedUpdatedAt.toUtc().toIso8601String()],
        );
      }

      await transaction.delete(
        'week_plan_sync_queue',
        where: 'plan_id = ? AND operation = ?',
        whereArgs: [id, action.name],
      );
    });
  }

  @override
  Future<void> markSyncFailed(String id, {DateTime? expectedUpdatedAt}) async {
    final database = await _databaseFuture;
    await database.update(
      'week_plans',
      {
        'sync_state': OutfitPlanSyncState.failed.name,
        'sync_error': 'Sync will retry when your account is available.',
      },
      where: expectedUpdatedAt == null ? 'id = ?' : 'id = ? AND updated_at = ?',
      whereArgs: expectedUpdatedAt == null
          ? [id]
          : [id, expectedUpdatedAt.toUtc().toIso8601String()],
    );
  }
}

Future<void> createWeekPlanTables(Database database, int version) async {
  await database.execute('''
    CREATE TABLE week_plans (
      id TEXT PRIMARY KEY NOT NULL,
      planned_date TEXT NOT NULL UNIQUE,
      occasion TEXT NOT NULL,
      outfit_name TEXT NOT NULL,
      items_json TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'planned'
        CHECK (status IN ('planned', 'worn', 'skipped', 'modified')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      sync_state TEXT NOT NULL,
      sync_error TEXT
    )
  ''');
  await database.execute('''
    CREATE INDEX week_plans_planned_date_idx ON week_plans(planned_date)
  ''');
  await _createWeekPlanHistoryTable(database);
  await database.execute('''
    CREATE TABLE week_plan_sync_queue (
      plan_id TEXT PRIMARY KEY NOT NULL,
      operation TEXT NOT NULL CHECK (operation IN ('upsert', 'delete')),
      payload TEXT,
      queued_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
  ''');
}

Future<void> upgradeWeekPlanTables(
  Database database,
  int oldVersion,
  int newVersion,
) async {
  if (oldVersion < 2) {
    await database.execute(
      "ALTER TABLE week_plans ADD COLUMN status TEXT NOT NULL DEFAULT 'planned' "
      "CHECK (status IN ('planned', 'worn', 'skipped', 'modified'))",
    );
    await _createWeekPlanHistoryTable(database);

    final existingPlans = await database.query('week_plans');
    for (final row in existingPlans) {
      await _insertHistoryEntry(database, _planFromRow(row));
    }
  }
}

Future<void> _createWeekPlanHistoryTable(DatabaseExecutor database) async {
  await database.execute('''
    CREATE TABLE week_plan_history (
      id TEXT PRIMARY KEY NOT NULL,
      plan_id TEXT NOT NULL,
      planned_date TEXT NOT NULL,
      status TEXT NOT NULL
        CHECK (status IN ('planned', 'worn', 'skipped', 'modified')),
      occasion TEXT NOT NULL,
      outfit_name TEXT NOT NULL,
      items_json TEXT NOT NULL,
      recorded_at TEXT NOT NULL
    )
  ''');
  await database.execute('''
    CREATE INDEX week_plan_history_date_idx
      ON week_plan_history(planned_date DESC, recorded_at DESC)
  ''');
  await database.execute('''
    CREATE INDEX week_plan_history_plan_idx
      ON week_plan_history(plan_id, recorded_at)
  ''');
}

Future<void> _insertHistoryEntry(
  DatabaseExecutor database,
  OutfitPlan plan,
) async {
  final entry = OutfitPlanHistoryEntry(
    id: _newUuid(),
    planId: plan.id,
    plannedFor: plan.plannedFor,
    status: plan.status,
    occasion: plan.occasion,
    outfitName: plan.outfitName,
    items: plan.items,
    recordedAt: plan.updatedAt,
  );
  await database.insert('week_plan_history', _historyEntryToRow(entry));
}

Map<String, Object?> _planToRow(OutfitPlan plan) => {
  'id': plan.id,
  'planned_date': planDateKey(plan.plannedFor),
  'occasion': plan.occasion,
  'outfit_name': plan.outfitName,
  'items_json': jsonEncode(plan.items.map(_itemToJson).toList()),
  'status': plan.status.name,
  'created_at': plan.createdAt.toUtc().toIso8601String(),
  'updated_at': plan.updatedAt.toUtc().toIso8601String(),
  'sync_state': plan.syncState.name,
  'sync_error': plan.syncError,
};

OutfitPlan _planFromRow(Map<String, Object?> row) {
  final decodedItems = jsonDecode(row['items_json'] as String);
  if (decodedItems is! List || decodedItems.any((item) => item is! Map)) {
    throw const FormatException('Saved plan has invalid outfit data.');
  }
  return OutfitPlan(
    id: row['id'] as String,
    plannedFor: DateTime.parse(row['planned_date'] as String),
    occasion: row['occasion'] as String,
    outfitName: row['outfit_name'] as String,
    items: List.unmodifiable(
      decodedItems.map(
        (item) => _itemFromJson(Map<String, Object?>.from(item as Map)),
      ),
    ),
    status: OutfitPlanStatus.values.byName(row['status'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
    updatedAt: DateTime.parse(row['updated_at'] as String),
    syncState: OutfitPlanSyncState.values.byName(row['sync_state'] as String),
    syncError: row['sync_error'] as String?,
  );
}

Map<String, Object?> _historyEntryToRow(OutfitPlanHistoryEntry entry) => {
  'id': entry.id,
  'plan_id': entry.planId,
  'planned_date': planDateKey(entry.plannedFor),
  'status': entry.status.name,
  'occasion': entry.occasion,
  'outfit_name': entry.outfitName,
  'items_json': jsonEncode(entry.items.map(_itemToJson).toList()),
  'recorded_at': entry.recordedAt.toUtc().toIso8601String(),
};

OutfitPlanHistoryEntry _historyEntryFromRow(Map<String, Object?> row) {
  final decodedItems = jsonDecode(row['items_json'] as String);
  if (decodedItems is! List || decodedItems.any((item) => item is! Map)) {
    throw const FormatException('Plan history has invalid outfit data.');
  }
  return OutfitPlanHistoryEntry(
    id: row['id'] as String,
    planId: row['plan_id'] as String,
    plannedFor: DateTime.parse(row['planned_date'] as String),
    status: OutfitPlanStatus.values.byName(row['status'] as String),
    occasion: row['occasion'] as String,
    outfitName: row['outfit_name'] as String,
    items: List.unmodifiable(
      decodedItems.map(
        (item) => _itemFromJson(Map<String, Object?>.from(item as Map)),
      ),
    ),
    recordedAt: DateTime.parse(row['recorded_at'] as String),
  );
}

Map<String, Object?> _itemToJson(OutfitItem item) => {
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
};

OutfitItem _itemFromJson(Map<String, Object?> json) => OutfitItem(
  id: json['id'] as String,
  title: json['title'] as String,
  category: json['category'] as String,
  subcategory: json['subcategory'] as String?,
  imagePath: json['imagePath'] as String?,
  primaryColor: json['primaryColor'] as String?,
  secondaryColor: json['secondaryColor'] as String?,
  occasions: List<String>.from(json['occasions'] as List),
  seasons: List<String>.from(json['seasons'] as List),
  styleTags: List<String>.from(json['styleTags'] as List),
);

void _validate(String occasion, String outfitName, List<OutfitItem> items) {
  if (occasion.trim().isEmpty || outfitName.trim().isEmpty || items.isEmpty) {
    throw const AppError('Choose an occasion and outfit before saving.');
  }
  if (items.any(
        (item) => item.id.trim().isEmpty || item.title.trim().isEmpty,
      ) ||
      items.map((item) => item.id).toSet().length != items.length) {
    throw const AppError('The selected outfit contains invalid items.');
  }
}

String _newUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
