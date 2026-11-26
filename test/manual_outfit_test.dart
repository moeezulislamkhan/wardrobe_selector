import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_recommender_app/app/app.dart';
import 'package:wardrobe_recommender_app/core/errors/app_error.dart';
import 'package:wardrobe_recommender_app/core/preferences/preferences_provider.dart';
import 'package:wardrobe_recommender_app/features/outfits/data/manual_outfit_repository.dart';
import 'package:wardrobe_recommender_app/features/outfits/domain/rule_based_outfit_engine.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/domain/guest_wardrobe_item.dart';

void main() {
  group('LocalManualOutfitRepository', () {
    test(
      'creates, edits, duplicates, and reloads pending local outfits',
      () async {
        SharedPreferences.setMockInitialValues({});
        final preferences = await SharedPreferences.getInstance();
        final repository = LocalManualOutfitRepository(preferences);

        final created = await repository.save(
          name: 'Work outfit',
          items: _completeOutfit(),
        );
        expect(
          created.id,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
        expect(created.needsCloudSync, isTrue);
        expect(repository.load().single.id, created.id);
        expect(repository.load().single.name, created.name);

        final edited = await repository.save(
          id: created.id,
          name: 'Updated work outfit',
          items: [..._completeOutfit(), _layer()],
        );
        expect(edited.id, created.id);
        expect(edited.createdAt, created.createdAt);
        expect(edited.name, 'Updated work outfit');
        expect(edited.items, hasLength(4));
        expect(edited.needsCloudSync, isTrue);

        final duplicate = await repository.duplicate(edited.id);
        expect(duplicate.id, isNot(edited.id));
        expect(duplicate.name, 'Updated work outfit (copy)');
        expect(
          duplicate.items.map((item) => item.id),
          edited.items.map((item) => item.id),
        );
        expect(repository.load(), hasLength(2));
        expect(repository.findById(duplicate.id)?.needsCloudSync, isTrue);
        expect(repository.pendingSync(), hasLength(2));

        await repository.markSynced(duplicate.id);
        expect(repository.findById(duplicate.id)?.needsCloudSync, isFalse);
        expect(repository.pendingSync(), hasLength(1));
      },
    );

    test(
      'rejects invalid names, incomplete slots, and duplicate selections',
      () async {
        SharedPreferences.setMockInitialValues({});
        final repository = LocalManualOutfitRepository(
          await SharedPreferences.getInstance(),
        );

        await expectLater(
          repository.save(name: ' ', items: _completeOutfit()),
          throwsA(isA<AppError>()),
        );
        await expectLater(
          repository.save(name: 'Missing shoes', items: [_top(), _bottom()]),
          throwsA(isA<AppError>()),
        );
        await expectLater(
          repository.save(
            name: 'Repeated item',
            items: [_top(), _top(), _bottom(), _shoes()],
          ),
          throwsA(isA<AppError>()),
        );
        expect(repository.load(), isEmpty);
      },
    );
  });

  testWidgets(
    'manual outfit editor surfaces name and required-slot validation errors',
    (tester) async {
      await _openManualEditor(tester, [
        _wardrobeItem('top-1', 'Navy shirt', 'Tops', color: 'navy'),
        _wardrobeItem('bottom-1', 'Black jeans', 'Bottoms', color: 'black'),
        _wardrobeItem('shoe-1', 'Black sneakers', 'Shoes', color: 'black'),
      ]);

      final saveButton = tester.widget<FilledButton>(
        find.byKey(const ValueKey('save-manual-outfit')),
      );
      saveButton.onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Enter a name for this outfit.'), findsOneWidget);
      expect(find.text('Select a top from your wardrobe.'), findsOneWidget);

      tester
              .widget<TextFormField>(
                find.byKey(const ValueKey('manual-outfit-name')),
              )
              .controller!
              .text =
          'Work outfit';
      await tester.pumpAndSettle();
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('save-manual-outfit')),
          )
          .onPressed!();
      await tester.pumpAndSettle();
      expect(find.text('Select a top from your wardrobe.'), findsOneWidget);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('manual_outfits_v1'), isNull);
    },
  );

  testWidgets('manual editor saves optional slots from active wardrobe items', (
    tester,
  ) async {
    await _openManualEditor(tester, [
      _wardrobeItem('top-1', 'Navy shirt', 'Tops', color: 'navy'),
      _wardrobeItem('bottom-1', 'Black jeans', 'Bottoms', color: 'black'),
      _wardrobeItem('shoe-1', 'Black sneakers', 'Shoes', color: 'black'),
      _wardrobeItem('layer-1', 'Navy jacket', 'Outerwear', color: 'navy'),
      _wardrobeItem('bag-1', 'Canvas tote', 'Accessories'),
      _wardrobeItem('archived-top', 'Archived top', 'Tops', archived: true),
    ]);
    await tester.enterText(
      find.byKey(const ValueKey('manual-outfit-name')),
      'Work outfit',
    );
    await _chooseItem(
      tester,
      'manual-slot-top',
      'Navy shirt · Tops · navy',
      expectAbsent: 'Archived top · Tops',
    );
    await _chooseItem(
      tester,
      'manual-slot-bottom',
      'Black jeans · Bottoms · black',
    );
    await _chooseItem(
      tester,
      'manual-slot-shoes',
      'Black sneakers · Shoes · black',
    );
    await _chooseItem(
      tester,
      'manual-slot-layer',
      'Navy jacket · Outerwear · navy',
    );
    await _chooseItem(
      tester,
      'manual-slot-accessory',
      'Canvas tote · Accessories',
    );
    expect(find.text('Saved color labels coordinate.'), findsOneWidget);
    await _scrollTo(tester, find.byKey(const ValueKey('save-manual-outfit')));
    await tester.tap(find.byKey(const ValueKey('save-manual-outfit')));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    final savedOutfits = jsonDecode(
      preferences.getString('manual_outfits_v1')!,
    ) as List<dynamic>;
    expect(savedOutfits, hasLength(1));
    final saved = savedOutfits.single as Map<String, dynamic>;
    expect(saved['name'], 'Work outfit');
    expect(saved['needsCloudSync'], isTrue);
    expect(saved['items'], hasLength(5));
    expect(
      (saved['items'] as List<dynamic>)
          .map((item) => (item as Map<String, dynamic>)['id'])
          .toSet(),
      {'top-1', 'bottom-1', 'shoe-1', 'layer-1', 'bag-1'},
    );
    expect(find.text('Saved locally · sync pending'), findsOneWidget);
  });

  testWidgets('manual outfits can be edited and duplicated', (tester) async {
    await _openManualEditor(tester, [
      _wardrobeItem('top-1', 'Navy shirt', 'Tops', color: 'navy'),
      _wardrobeItem('bottom-1', 'Black jeans', 'Bottoms', color: 'black'),
      _wardrobeItem('shoe-1', 'Black sneakers', 'Shoes', color: 'black'),
    ]);
    await tester.enterText(
      find.byKey(const ValueKey('manual-outfit-name')),
      'Work outfit',
    );
    await _chooseItem(tester, 'manual-slot-top', 'Navy shirt · Tops · navy');
    await _chooseItem(
      tester,
      'manual-slot-bottom',
      'Black jeans · Bottoms · black',
    );
    await _chooseItem(
      tester,
      'manual-slot-shoes',
      'Black sneakers · Shoes · black',
    );
    await _scrollTo(tester, find.byKey(const ValueKey('save-manual-outfit')));
    await tester.tap(find.byKey(const ValueKey('save-manual-outfit')));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    var outfits = jsonDecode(
      preferences.getString('manual_outfits_v1')!,
    ) as List<dynamic>;
    final id = (outfits.single as Map<String, dynamic>)['id'] as String;

    await tester.tap(find.byKey(ValueKey('edit-manual-outfit-$id')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('manual-outfit-name')),
      'Office uniform',
    );
    await _scrollTo(tester, find.byKey(const ValueKey('save-manual-outfit')));
    await tester.tap(find.byKey(const ValueKey('save-manual-outfit')));
    await tester.pumpAndSettle();
    outfits = jsonDecode(
      preferences.getString('manual_outfits_v1')!,
    ) as List<dynamic>;
    expect(outfits, hasLength(1));
    expect((outfits.single as Map<String, dynamic>)['id'], id);
    expect((outfits.single as Map<String, dynamic>)['name'], 'Office uniform');

    await tester.tap(find.byKey(ValueKey('duplicate-manual-outfit-$id')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('manual-outfit-name')),
          )
          .controller!
          .text,
      'Office uniform (copy)',
    );
    await _scrollTo(tester, find.byKey(const ValueKey('save-manual-outfit')));
    await tester.tap(find.byKey(const ValueKey('save-manual-outfit')));
    await tester.pumpAndSettle();
    outfits = jsonDecode(
      preferences.getString('manual_outfits_v1')!,
    ) as List<dynamic>;
    expect(outfits, hasLength(2));
    expect(
      outfits.map((outfit) => (outfit as Map<String, dynamic>)['id']).toSet(),
      hasLength(2),
    );
  });
}

Future<void> _openManualEditor(
  WidgetTester tester,
  List<GuestWardrobeItem> items,
) async {
  SharedPreferences.setMockInitialValues({
    'onboarding_completed': true,
    'wardrobe_items_v1': jsonEncode(
      items.map((item) => item.toJson()).toList(),
    ),
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
  await tester.tap(find.byKey(const ValueKey('create-manual-outfit')));
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('manual-outfit-name')), findsOneWidget);
}

Future<void> _chooseItem(
  WidgetTester tester,
  String fieldKey,
  String itemLabel, {
  String? expectAbsent,
}) async {
  final field = find.byKey(ValueKey(fieldKey));
  await _scrollTo(tester, field);
  await tester.tap(field);
  await tester.pumpAndSettle();
  if (expectAbsent != null) {
    expect(find.text(expectAbsent), findsNothing);
  }
  expect(find.text(itemLabel), findsOneWidget);
  await tester.tap(find.text(itemLabel));
  await tester.pumpAndSettle();
}

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final scrollable = find.byType(SingleChildScrollView).last;
  for (var attempt = 0; attempt < 10; attempt++) {
    final viewport = tester.getRect(scrollable);
    final target = tester.getRect(finder);
    if (target.top >= viewport.top && target.bottom <= viewport.bottom) return;
    final delta = target.bottom > viewport.bottom
        ? const Offset(0, -250)
        : const Offset(0, 250);
    await tester.drag(scrollable, delta);
    await tester.pumpAndSettle();
  }
}

List<OutfitItem> _completeOutfit() => [_top(), _bottom(), _shoes()];

OutfitItem _top() => const OutfitItem(
  id: 'top-1',
  title: 'Navy shirt',
  category: 'Tops',
  primaryColor: 'navy',
);

OutfitItem _bottom() => const OutfitItem(
  id: 'bottom-1',
  title: 'Black jeans',
  category: 'Bottoms',
  primaryColor: 'black',
);

OutfitItem _shoes() => const OutfitItem(
  id: 'shoe-1',
  title: 'Black sneakers',
  category: 'Shoes',
  primaryColor: 'black',
);

OutfitItem _layer() => const OutfitItem(
  id: 'layer-1',
  title: 'Navy jacket',
  category: 'Outerwear',
  primaryColor: 'navy',
);

GuestWardrobeItem _wardrobeItem(
  String id,
  String title,
  String category, {
  String? color,
  bool archived = false,
}) {
  return GuestWardrobeItem(
    localId: id,
    title: title,
    category: category,
    primaryColor: color,
    isArchived: archived,
    createdAt: DateTime.utc(2026, 11, 26),
  );
}
