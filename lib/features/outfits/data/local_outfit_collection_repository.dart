import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/rule_based_outfit_engine.dart';

const _outfitCollectionKey = 'outfit_collection_v1';

class LocalOutfitCollectionRecord {
  const LocalOutfitCollectionRecord({
    required this.combinationKey,
    required this.items,
    required this.isSaved,
    required this.isFavorite,
    this.plannedFor,
  });

  final String combinationKey;
  final List<OutfitItem> items;
  final bool isSaved;
  final bool isFavorite;
  final DateTime? plannedFor;

  LocalOutfitCollectionRecord copyWith({
    bool? isSaved,
    bool? isFavorite,
    DateTime? plannedFor,
    bool clearPlannedFor = false,
  }) {
    return LocalOutfitCollectionRecord(
      combinationKey: combinationKey,
      items: items,
      isSaved: isSaved ?? this.isSaved,
      isFavorite: isFavorite ?? this.isFavorite,
      plannedFor: clearPlannedFor ? null : plannedFor ?? this.plannedFor,
    );
  }

  Map<String, Object?> toJson() => {
    'items': items.map(_itemToJson).toList(),
    'isSaved': isSaved,
    'isFavorite': isFavorite,
    'plannedFor': plannedFor?.toIso8601String(),
  };

  factory LocalOutfitCollectionRecord.fromJson(
    String combinationKey,
    Map<String, Object?> json,
  ) {
    final itemsValue = json['items'];
    if (itemsValue is! List || itemsValue.any((item) => item is! Map)) {
      throw const FormatException('Saved outfit has invalid item data.');
    }
    final savedValue = json['isSaved'];
    final favoriteValue = json['isFavorite'];
    if (savedValue is! bool || favoriteValue is! bool) {
      throw const FormatException('Saved outfit has invalid state.');
    }
    final plannedValue = json['plannedFor'];
    final plannedFor = switch (plannedValue) {
      null => null,
      String value => DateTime.tryParse(value),
      _ => throw const FormatException('Saved outfit has an invalid date.'),
    };
    if (plannedValue != null && plannedFor == null) {
      throw const FormatException('Saved outfit has an invalid date.');
    }

    return LocalOutfitCollectionRecord(
      combinationKey: combinationKey,
      items: List.unmodifiable(
        itemsValue.map(
          (item) => _itemFromJson(Map<String, Object?>.from(item as Map)),
        ),
      ),
      isSaved: savedValue,
      isFavorite: favoriteValue,
      plannedFor: plannedFor,
    );
  }
}

class LocalOutfitCollectionRepository {
  const LocalOutfitCollectionRepository(this._preferences);

  final SharedPreferences _preferences;

  Map<String, LocalOutfitCollectionRecord> load() {
    final encoded = _preferences.getString(_outfitCollectionKey);
    if (encoded == null || encoded.isEmpty) return const {};

    final decoded = jsonDecode(encoded);
    if (decoded is! Map) {
      throw const FormatException('Saved outfit collection must be a map.');
    }
    final records = <String, LocalOutfitCollectionRecord>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException(
          'Saved outfit collection has invalid data.',
        );
      }
      final key = entry.key as String;
      records[key] = LocalOutfitCollectionRecord.fromJson(
        key,
        Map<String, Object?>.from(entry.value as Map),
      );
    }
    return Map.unmodifiable(records);
  }

  Future<LocalOutfitCollectionRecord?> update(
    OutfitSuggestion suggestion, {
    bool? isSaved,
    bool? isFavorite,
    DateTime? plannedFor,
  }) async {
    final records = Map<String, LocalOutfitCollectionRecord>.of(load());
    final key = suggestion.combinationKey;
    final current =
        records[key] ??
        LocalOutfitCollectionRecord(
          combinationKey: key,
          items: List.unmodifiable(suggestion.items),
          isSaved: false,
          isFavorite: false,
        );
    final updated = current.copyWith(
      isSaved: isSaved,
      isFavorite: isFavorite,
      plannedFor: plannedFor,
    );

    if (!updated.isSaved && !updated.isFavorite && updated.plannedFor == null) {
      records.remove(key);
    } else {
      records[key] = updated;
    }
    final saved = await _preferences.setString(
      _outfitCollectionKey,
      jsonEncode(
        records.map((recordKey, record) {
          return MapEntry(recordKey, record.toJson());
        }),
      ),
    );
    if (!saved) throw StateError('Could not save your outfit collection.');
    return records[key];
  }
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
  id: _stringValue(json, 'id'),
  title: _stringValue(json, 'title'),
  category: _stringValue(json, 'category'),
  subcategory: _optionalStringValue(json, 'subcategory'),
  imagePath: _optionalStringValue(json, 'imagePath'),
  primaryColor: _optionalStringValue(json, 'primaryColor'),
  secondaryColor: _optionalStringValue(json, 'secondaryColor'),
  occasions: _stringListValue(json, 'occasions'),
  seasons: _stringListValue(json, 'seasons'),
  styleTags: _stringListValue(json, 'styleTags'),
);

String _stringValue(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Saved outfit item has an invalid $key.');
  }
  return value;
}

String? _optionalStringValue(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is! String) {
    throw FormatException('Saved outfit item has an invalid $key.');
  }
  return value;
}

List<String> _stringListValue(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List || value.any((element) => element is! String)) {
    throw FormatException('Saved outfit item has invalid $key.');
  }
  return List.unmodifiable(value.cast<String>());
}
