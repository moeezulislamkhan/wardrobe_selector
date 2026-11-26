import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_recommender_app/app/app.dart';
import 'package:wardrobe_recommender_app/core/preferences/preferences_provider.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/local_wardrobe_repository.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/guest_wardrobe_contracts.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/domain/guest_wardrobe_item.dart';

void main() {
  final blouse = GuestWardrobeItem(
    localId: 'item-blouse',
    name: 'Linen blouse',
    category: 'Tops',
    color: 'Blue',
    brand: 'Atelier',
    createdAt: DateTime.utc(2025, 5, 10),
    occasions: ['Work'],
    seasons: ['Spring'],
  );
  final jeans = GuestWardrobeItem(
    localId: 'item-jeans',
    name: 'Straight jeans',
    category: 'Bottoms',
    color: 'Black',
    createdAt: DateTime.utc(2025, 1, 10),
    occasions: ['Casual'],
    seasons: ['Winter'],
  );

  test('local repository is empty until real saved items exist', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = LocalWardrobeRepository(preferences);

    expect(await repository.loadItems(), isEmpty);
  });

  test('local repository persists favorites and archive state', () async {
    SharedPreferences.setMockInitialValues({
      'wardrobe_items_v1': jsonEncode([blouse.toJson()]),
    });
    final preferences = await SharedPreferences.getInstance();
    final repository = LocalWardrobeRepository(preferences);

    await repository.setFavorite(blouse.localId, true);
    await repository.setArchived(blouse.localId, true);

    final savedItems = await repository.loadItems();
    expect(savedItems.single.isFavorite, isTrue);
    expect(savedItems.single.isArchived, isTrue);
  });

  test(
    'local repository reads cached photo bytes without network access',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final directory = await Directory.systemTemp.createTemp('wardrobe-photo');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}${Platform.pathSeparator}photo.jpg');
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      await file.writeAsBytes(bytes);

      final result = await LocalWardrobeRepository(preferences)
          .readImage(file.path);

      expect(result, bytes);
    },
  );

  testWidgets('gallery filters real local records and opens item details', (
    tester,
  ) async {
    final preferences = await _createPreferences();
    final repository = _MemoryWardrobeRepository([blouse, jeans]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          wardrobeRepositoryProvider.overrideWithValue(repository),
        ],
        child: const WardrobeApp(),
      ),
    );

    await _openWardrobe(tester);
    expect(find.text('Linen blouse'), findsOneWidget);
    expect(find.text('Straight jeans'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('category-Tops')));
    await tester.pumpAndSettle();
    expect(find.text('Linen blouse'), findsOneWidget);
    expect(find.text('Straight jeans'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('category-All')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('wardrobe-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Color'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilterChip, 'Blue'));
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    expect(find.text('Linen blouse'), findsOneWidget);
    expect(find.text('Straight jeans'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('wardrobe-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear'));
    await tester.tap(find.text('Show results'));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const ValueKey('wardrobe-gallery')),
      const Offset(0, -250),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Linen blouse'));
    await tester.pumpAndSettle();
    expect(find.text('Item details'), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('wardrobe-item-detail')),
      const Offset(0, -600),
    );
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Spring'), findsOneWidget);
  });

  testWidgets('gallery supports search, favorites, archive, and list layout', (
    tester,
  ) async {
    final preferences = await _createPreferences();
    final repository = _MemoryWardrobeRepository([
      blouse.copyWith(isFavorite: true),
      jeans,
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          wardrobeRepositoryProvider.overrideWithValue(repository),
        ],
        child: const WardrobeApp(),
      ),
    );
    await _openWardrobe(tester);

    await tester.tap(find.text('Favorites'));
    await tester.pumpAndSettle();
    expect(find.text('Linen blouse'), findsOneWidget);
    expect(find.text('Straight jeans'), findsNothing);

    await tester.tap(find.text('All pieces'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('wardrobe-search')),
      'winter',
    );
    await tester.pumpAndSettle();
    expect(find.text('Straight jeans'), findsOneWidget);
    expect(find.text('Linen blouse'), findsNothing);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('List view'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Item actions'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Item actions').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(
      repository.items
          .singleWhere((item) => item.localId == jeans.localId)
          .isArchived,
      isTrue,
    );

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    expect(find.text('Straight jeans'), findsOneWidget);
  });

  testWidgets('empty repository shows an explicit no-inventory state', (
    tester,
  ) async {
    final preferences = await _createPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          wardrobeRepositoryProvider.overrideWithValue(
            _MemoryWardrobeRepository([]),
          ),
        ],
        child: const WardrobeApp(),
      ),
    );
    await _openWardrobe(tester);

    expect(find.text('Your wardrobe is empty'), findsOneWidget);
    expect(find.textContaining('No sample inventory is shown'), findsOneWidget);
  });
}

Future<SharedPreferences> _createPreferences() async {
  SharedPreferences.setMockInitialValues({'onboarding_completed': true});
  return SharedPreferences.getInstance();
}

Future<void> _openWardrobe(WidgetTester tester) async {
  await tester.tap(
    find.descendant(
      of: find.byType(NavigationBar),
      matching: find.text('Wardrobe'),
    ),
  );
  await tester.pumpAndSettle();
}

class _MemoryWardrobeRepository implements WardrobeRepository {
  _MemoryWardrobeRepository(this.items);

  List<GuestWardrobeItem> items;

  @override
  Future<List<GuestWardrobeItem>> loadItems() async => List.unmodifiable(items);

  @override
  Future<Uint8List> readImage(String localImagePath) async {
    throw StateError('Test items do not contain photos.');
  }

  @override
  Future<void> setFavorite(String localId, bool isFavorite) async {
    _update(localId, (item) => item.copyWith(isFavorite: isFavorite));
  }

  @override
  Future<void> setArchived(String localId, bool isArchived) async {
    _update(localId, (item) => item.copyWith(isArchived: isArchived));
  }

  void _update(
    String localId,
    GuestWardrobeItem Function(GuestWardrobeItem) update,
  ) {
    final index = items.indexWhere((item) => item.localId == localId);
    if (index == -1) throw StateError('Test item not found.');
    items = [...items]..[index] = update(items[index]);
  }
}
