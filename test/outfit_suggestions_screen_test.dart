import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_recommender_app/app/app.dart';
import 'package:wardrobe_recommender_app/core/preferences/preferences_provider.dart';
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
}

GuestWardrobeItem _item(
  String id,
  String title,
  String category, {
  String? color,
}) {
  return GuestWardrobeItem(
    localId: id,
    title: title,
    category: category,
    primaryColor: color,
    createdAt: DateTime.utc(2026, 11, 26),
  );
}
