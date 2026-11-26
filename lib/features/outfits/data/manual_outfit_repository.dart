import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/preferences/preferences_provider.dart';
import '../domain/manual_outfit.dart';
import '../domain/rule_based_outfit_engine.dart';

const _manualOutfitsKey = 'manual_outfits_v1';
const _maxOutfitNameLength = 80;

final manualOutfitRepositoryProvider = Provider<ManualOutfitRepository>(
  (ref) => LocalManualOutfitRepository(ref.watch(sharedPreferencesProvider)),
);

abstract interface class ManualOutfitRepository {
  List<ManualOutfit> load();

  List<ManualOutfit> pendingSync();

  ManualOutfit? findById(String id);

  Future<ManualOutfit> save({
    String? id,
    required String name,
    required List<OutfitItem> items,
  });

  Future<ManualOutfit> duplicate(String sourceId);

  Future<void> markSynced(String id);
}

class LocalManualOutfitRepository implements ManualOutfitRepository {
  const LocalManualOutfitRepository(this._preferences);

  final SharedPreferences _preferences;

  @override
  List<ManualOutfit> load() {
    final encoded = _preferences.getString(_manualOutfitsKey);
    if (encoded == null || encoded.isEmpty) return const [];

    final decoded = jsonDecode(encoded);
    if (decoded is! List || decoded.any((record) => record is! Map)) {
      throw const FormatException('Saved manual outfits have invalid data.');
    }
    final outfits = decoded
        .map((record) => _fromJson(Map<String, Object?>.from(record as Map)))
        .toList();
    outfits.sort(
      (first, second) => second.updatedAt.compareTo(first.updatedAt),
    );
    return List.unmodifiable(outfits);
  }

  @override
  List<ManualOutfit> pendingSync() =>
      List.unmodifiable(load().where((outfit) => outfit.needsCloudSync));

  @override
  ManualOutfit? findById(String id) {
    for (final outfit in load()) {
      if (outfit.id == id) return outfit;
    }
    return null;
  }

  @override
  Future<ManualOutfit> save({
    String? id,
    required String name,
    required List<OutfitItem> items,
  }) async {
    final normalizedName = name.trim();
    _validate(normalizedName, items);
    final outfits = List<ManualOutfit>.of(load());
    final existingIndex = id == null
        ? -1
        : outfits.indexWhere((outfit) => outfit.id == id);
    if (id != null && existingIndex < 0) {
      throw const AppError('This manual outfit is no longer available.');
    }

    final now = DateTime.now().toUtc();
    final existing = existingIndex < 0 ? null : outfits[existingIndex];
    final outfit = ManualOutfit(
      id: existing?.id ?? _newUuid(),
      name: normalizedName,
      items: List.unmodifiable(items),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      needsCloudSync: true,
    );
    if (existingIndex < 0) {
      outfits.add(outfit);
    } else {
      outfits[existingIndex] = outfit;
    }
    await _persist(outfits);
    return outfit;
  }

  @override
  Future<ManualOutfit> duplicate(String sourceId) async {
    final source = findById(sourceId);
    if (source == null) {
      throw const AppError('This manual outfit is no longer available.');
    }
    final copySuffix = ' (copy)';
    final availableNameLength = _maxOutfitNameLength - copySuffix.length;
    final baseName = source.name.length > availableNameLength
        ? source.name.substring(0, availableNameLength)
        : source.name;
    return save(name: '$baseName$copySuffix', items: source.items);
  }

  @override
  Future<void> markSynced(String id) async {
    final outfits = List<ManualOutfit>.of(load());
    final index = outfits.indexWhere((outfit) => outfit.id == id);
    if (index < 0) {
      throw const AppError('This manual outfit is no longer available.');
    }
    final outfit = outfits[index];
    if (!outfit.needsCloudSync) return;
    outfits[index] = ManualOutfit(
      id: outfit.id,
      name: outfit.name,
      items: outfit.items,
      createdAt: outfit.createdAt,
      updatedAt: outfit.updatedAt,
      needsCloudSync: false,
    );
    await _persist(outfits);
  }

  void _validate(String name, List<OutfitItem> items) {
    if (name.isEmpty) {
      throw const AppError('Enter a name for this outfit.');
    }
    if (name.length > _maxOutfitNameLength) {
      throw const AppError('Outfit names must be 80 characters or fewer.');
    }
    if (items.length < 3 || items.length > 5) {
      throw const AppError(
        'Choose a top, bottom, and shoes, with at most one layer and accessory.',
      );
    }
    final ids = items.map((item) => item.id).toList();
    if (ids.any((id) => id.trim().isEmpty) ||
        ids.toSet().length != ids.length) {
      throw const AppError(
        'Each outfit slot must use a different wardrobe item.',
      );
    }
    if (items.any(
      (item) =>
          item.title.trim().isEmpty ||
          item.isArchived ||
          item.isDeleted ||
          const RuleBasedOutfitEngine().roleOf(item) == OutfitItemRole.other,
    )) {
      throw const AppError(
        'Choose active items with a supported outfit category.',
      );
    }

    final roleCounts = <OutfitItemRole, int>{};
    for (final item in items) {
      final role = const RuleBasedOutfitEngine().roleOf(item);
      roleCounts.update(role, (count) => count + 1, ifAbsent: () => 1);
    }
    if (roleCounts[OutfitItemRole.top] != 1 ||
        roleCounts[OutfitItemRole.bottom] != 1 ||
        roleCounts[OutfitItemRole.shoes] != 1 ||
        (roleCounts[OutfitItemRole.layer] ?? 0) > 1 ||
        (roleCounts[OutfitItemRole.accessory] ?? 0) > 1) {
      throw const AppError(
        'Choose exactly one top, bottom, and shoes. Layers and accessories are optional.',
      );
    }
  }

  Future<void> _persist(List<ManualOutfit> outfits) async {
    final saved = await _preferences.setString(
      _manualOutfitsKey,
      jsonEncode(outfits.map(_toJson).toList()),
    );
    if (!saved) {
      throw const AppError('Could not save this outfit on your device.');
    }
  }
}

Map<String, Object?> _toJson(ManualOutfit outfit) => {
  'id': outfit.id,
  'name': outfit.name,
  'items': outfit.items.map(_itemToJson).toList(),
  'createdAt': outfit.createdAt.toIso8601String(),
  'updatedAt': outfit.updatedAt.toIso8601String(),
  'needsCloudSync': outfit.needsCloudSync,
};

ManualOutfit _fromJson(Map<String, Object?> json) {
  final itemsValue = json['items'];
  if (itemsValue is! List || itemsValue.any((item) => item is! Map)) {
    throw const FormatException('Manual outfit has invalid item data.');
  }
  final needsCloudSync = json['needsCloudSync'];
  if (needsCloudSync is! bool) {
    throw const FormatException('Manual outfit has invalid sync state.');
  }
  return ManualOutfit(
    id: _requiredString(json, 'id'),
    name: _requiredString(json, 'name'),
    items: List.unmodifiable(
      itemsValue.map(
        (item) => _itemFromJson(Map<String, Object?>.from(item as Map)),
      ),
    ),
    createdAt: _dateTimeValue(json, 'createdAt'),
    updatedAt: _dateTimeValue(json, 'updatedAt'),
    needsCloudSync: needsCloudSync,
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
  'isArchived': item.isArchived,
  'isDeleted': item.isDeleted,
};

OutfitItem _itemFromJson(Map<String, Object?> json) => OutfitItem(
  id: _requiredString(json, 'id'),
  title: _requiredString(json, 'title'),
  category: _requiredString(json, 'category'),
  subcategory: _optionalString(json, 'subcategory'),
  imagePath: _optionalString(json, 'imagePath'),
  primaryColor: _optionalString(json, 'primaryColor'),
  secondaryColor: _optionalString(json, 'secondaryColor'),
  occasions: _stringList(json, 'occasions'),
  seasons: _stringList(json, 'seasons'),
  styleTags: _stringList(json, 'styleTags'),
  isArchived: _optionalBool(json, 'isArchived'),
  isDeleted: _optionalBool(json, 'isDeleted'),
);

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Manual outfit has an invalid $key.');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Manual outfit has an invalid $key.');
  }
  return value;
}

DateTime _dateTimeValue(Map<String, Object?> json, String key) {
  final value = json[key];
  final date = value is String ? DateTime.tryParse(value) : null;
  if (date == null) {
    throw FormatException('Manual outfit has an invalid $key.');
  }
  return date;
}

List<String> _stringList(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List || value.any((element) => element is! String)) {
    throw FormatException('Manual outfit has invalid $key.');
  }
  return List.unmodifiable(value.cast<String>());
}

bool _optionalBool(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return false;
  if (value is! bool) {
    throw FormatException('Manual outfit has an invalid $key.');
  }
  return value;
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
