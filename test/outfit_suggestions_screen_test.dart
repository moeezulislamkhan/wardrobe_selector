import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_recommender_app/app/app.dart';
import 'package:wardrobe_recommender_app/core/preferences/preferences_provider.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/local_wardrobe_repository.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/domain/guest_wardrobe_item.dart';

void main() {
  testWidgets(
    'outfits screen suggests complete combinations from saved items',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'onboarding_completed': true,
        'wardrobe_items_v1': jsonEncode([
          _item('top-a', 'Blue shirt', 'Tops', color: 'blue').toJson(),
          _item('top-b', 'White tee', 'Tops', color: 'white').toJson(),
          _item('bottom-a', 'Black jeans', 'Bottoms', color: 'black').toJson(),
          _item(
            'bottom-b',
            'Beige trousers',
            'Bottoms',
            color: 'beige',
          ).toJson(),
          _item('shoe-a', 'Black sneakers', 'Shoes', color: 'black').toJson(),
        ]),
      });
      final preferences = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
          child: const WardrobeApp(),
        ),
      );
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Outfits'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Outfit 1'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Outfit 1'), findsOneWidget);

      for (final label in ['Outfit 2', 'Outfit 3', 'Outfit 4']) {
        await tester.scrollUntilVisible(
          find.text(label),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(label), findsOneWidget);
      }

      await tester.scrollUntilVisible(
        find.text('Blue shirt'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Blue shirt'), findsWidgets);
      expect(find.text('Black jeans'), findsWidgets);
      expect(find.text('Black sneakers'), findsWidgets);

      await tester.scrollUntilVisible(
        find.text('Mark as worn').first,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Mark as worn').first);
      await tester.tap(find.text('Mark as worn').first);
      await tester.pumpAndSettle();
      final wearHistory = jsonDecode(
        preferences.getString('outfit_last_worn_at_v1')!,
      ) as Map<String, dynamic>;
      expect(wearHistory.keys, hasLength(3));
      expect(
        wearHistory.keys,
        everyElement(anyOf('top-a', 'top-b', 'bottom-a', 'bottom-b', 'shoe-a')),
      );
      expect(find.text('Outfit marked as recently worn.'), findsOneWidget);
    },
  );

  testWidgets('empty wardrobe does not show invented outfit ideas', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
        child: const WardrobeApp(),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Outfits'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Add your own wardrobe items'),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Add your own wardrobe items'), findsOneWidget);
    expect(find.text('Outfit 1'), findsNothing);
    expect(find.text('Add a wardrobe item'), findsOneWidget);
  });

  testWidgets('outfit cards save, favorite, schedule, swap, and show photos', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'wardrobe_items_v1': jsonEncode([
        _item(
          'top-a',
          'Blue shirt',
          'Tops',
          color: 'blue',
          imagePath: 'offline/top-a.jpg',
        ).toJson(),
        _item(
          'top-b',
          'White tee',
          'Tops',
          color: 'white',
          imagePath: 'offline/top-b.jpg',
        ).toJson(),
        _item(
          'top-c',
          'Green sweater',
          'Tops',
          color: 'green',
          imagePath: 'offline/top-c.jpg',
        ).toJson(),
        _item(
          'bottom-a',
          'Black jeans',
          'Bottoms',
          color: 'black',
          imagePath: 'offline/bottom-a.jpg',
        ).toJson(),
        _item(
          'bottom-b',
          'Beige trousers',
          'Bottoms',
          color: 'beige',
          imagePath: 'offline/bottom-b.jpg',
        ).toJson(),
        _item(
          'shoe-a',
          'Black sneakers',
          'Shoes',
          color: 'black',
          imagePath: 'offline/shoe-a.jpg',
        ).toJson(),
        _item(
          'shoe-b',
          'White flats',
          'Shoes',
          color: 'white',
          imagePath: 'offline/shoe-b.jpg',
        ).toJson(),
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          wardrobePhotoProvider.overrideWith(
            (ref, path) async => Uint8List.fromList([1, 2, 3]),
          ),
        ],
        child: const WardrobeApp(),
      ),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Outfits'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Outfit 1'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    expect(find.text('Tops'), findsWidgets);

    await tester.ensureVisible(find.text('Save outfit').first);
    await tester.tap(find.text('Save outfit').first);
    await tester.pumpAndSettle();
    var collection = jsonDecode(
      preferences.getString('outfit_collection_v1')!,
    ) as Map<String, dynamic>;
    final combinationKey = collection.keys.single;
    expect(collection[combinationKey]['isSaved'], isTrue);

    final favoriteButton = find.byKey(ValueKey('favorite-$combinationKey'));
    await tester.ensureVisible(favoriteButton);
    await tester.pumpAndSettle();
    await tester.tap(favoriteButton);
    await tester.pumpAndSettle();
    collection = jsonDecode(
      preferences.getString('outfit_collection_v1')!,
    ) as Map<String, dynamic>;
    expect(collection[combinationKey]['isFavorite'], isTrue);

    await tester.ensureVisible(find.text('Schedule').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Schedule').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    collection = jsonDecode(
      preferences.getString('outfit_collection_v1')!,
    ) as Map<String, dynamic>;
    expect(collection[combinationKey]['plannedFor'], isA<String>());

    final topId = combinationKey.split('|').first;
    final swapButton = find.byKey(ValueKey('swap-$topId'));
    await tester.ensureVisible(swapButton);
    await tester.pumpAndSettle();
    await tester.tap(swapButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Green sweater'));
    await tester.pumpAndSettle();
    expect(find.text('Green sweater'), findsWidgets);

    await tester.ensureVisible(find.text('View details').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('View details').first);
    await tester.pumpAndSettle();
    expect(find.text('Outfit details'), findsOneWidget);
    expect(find.text('Why this was recommended'), findsOneWidget);
  });
}

GuestWardrobeItem _item(
  String id,
  String title,
  String category, {
  String? color,
  String? imagePath,
}) {
  return GuestWardrobeItem(
    localId: id,
    title: title,
    category: category,
    primaryColor: color,
    localImagePath: imagePath,
    createdAt: DateTime.utc(2026, 11, 26),
  );
}
