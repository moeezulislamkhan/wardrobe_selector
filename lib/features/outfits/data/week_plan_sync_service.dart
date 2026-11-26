import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_error.dart';
import '../domain/outfit_plan.dart';
import 'week_plan_repository.dart';

final weekPlanSyncServiceProvider = Provider<WeekPlanSyncService>(
  (ref) => SupabaseWeekPlanSyncService(ref.watch(weekPlanRepositoryProvider)),
);

abstract interface class WeekPlanSyncService {
  Future<void> syncPending(String userId, {void Function()? onStatusChanged});
}

class SupabaseWeekPlanSyncService implements WeekPlanSyncService {
  const SupabaseWeekPlanSyncService(this._repository, {this.client});

  final WeekPlanRepository _repository;
  final SupabaseClient? client;

  @override
  Future<void> syncPending(
    String userId, {
    void Function()? onStatusChanged,
  }) async {
    final syncOperations = await _repository.pendingSync();
    if (syncOperations.isEmpty) return;

    try {
      final supabase = _client;
      if (supabase.auth.currentUser?.id != userId) {
        throw const AppError('Sign in before syncing your week plan.');
      }

      for (final operation in syncOperations) {
        if (operation.action == OutfitPlanSyncAction.delete) {
          await _deletePlan(supabase, userId, operation.planId);
          await _repository.markSynced(
            operation.planId,
            action: OutfitPlanSyncAction.delete,
          );
          onStatusChanged?.call();
          continue;
        }

        final plan = operation.plan;
        if (plan == null) {
          await _repository.markSyncFailed(operation.planId);
          onStatusChanged?.call();
          continue;
        }
        await _repository.markSyncing(plan.id);
        onStatusChanged?.call();
        try {
          await _upsertPlan(supabase, userId, plan);
          await _repository.markSynced(
            plan.id,
            action: OutfitPlanSyncAction.upsert,
            expectedUpdatedAt: plan.updatedAt,
          );
          onStatusChanged?.call();
        } on Exception {
          await _repository.markSyncFailed(
            plan.id,
            expectedUpdatedAt: plan.updatedAt,
          );
          onStatusChanged?.call();
        }
      }
    } on Exception {
      for (final operation in syncOperations) {
        if (operation.action == OutfitPlanSyncAction.upsert) {
          await _repository.markSyncFailed(
            operation.planId,
            expectedUpdatedAt: operation.plan?.updatedAt,
          );
          onStatusChanged?.call();
        }
      }
    }
  }

  SupabaseClient get _client {
    if (client != null) return client!;
    try {
      return Supabase.instance.client;
    } on AssertionError {
      throw const AppError('Cloud sync is not configured.');
    }
  }

  Future<void> _upsertPlan(
    SupabaseClient supabase,
    String userId,
    OutfitPlan plan,
  ) async {
    final itemIds = <String, String>{};
    for (final item in plan.items) {
      final row = await supabase
          .from('wardrobe_items')
          .select('id')
          .eq('user_id', userId)
          .eq('local_id', item.id)
          .maybeSingle();
      final cloudId = row?['id'];
      if (cloudId is! String) {
        throw const AppError(
          'Sync the wardrobe items in this outfit before syncing the plan.',
        );
      }
      itemIds[item.id] = cloudId;
    }

    await supabase.from('outfits').upsert({
      'id': plan.id,
      'user_id': userId,
      'name': plan.outfitName,
      'occasion': plan.occasion,
      'notes': 'Planned for ${planDateKey(plan.plannedFor)}',
    }, onConflict: 'id');
    await supabase
        .from('outfit_items')
        .delete()
        .eq('user_id', userId)
        .eq('outfit_id', plan.id);
    await supabase.from('outfit_items').insert([
      for (var index = 0; index < plan.items.length; index++)
        {
          'user_id': userId,
          'outfit_id': plan.id,
          'wardrobe_item_id': itemIds[plan.items[index].id],
          'position': index,
        },
    ]);
    await supabase.from('outfit_plans').upsert({
      'id': plan.id,
      'user_id': userId,
      'outfit_id': plan.id,
      'status': plan.status.name,
      'planned_for': DateTime.utc(
        plan.plannedFor.year,
        plan.plannedFor.month,
        plan.plannedFor.day,
      ).toIso8601String(),
      'notes': plan.occasion,
    }, onConflict: 'id');

    final history = await _repository.historyForPlan(plan.id);
    if (history.isNotEmpty) {
      await supabase
          .from('outfit_plan_history')
          .upsert(
            history.map((entry) => entry.toCloudRow(userId)).toList(),
            onConflict: 'id',
          );
    }
  }

  Future<void> _deletePlan(
    SupabaseClient supabase,
    String userId,
    String planId,
  ) async {
    await supabase
        .from('outfit_plans')
        .delete()
        .eq('id', planId)
        .eq('user_id', userId);
    await supabase
        .from('outfits')
        .delete()
        .eq('id', planId)
        .eq('user_id', userId);
  }
}
