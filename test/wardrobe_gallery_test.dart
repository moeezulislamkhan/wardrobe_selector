import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_recommender_app/app/app.dart';
import 'package:wardrobe_recommender_app/core/errors/app_error.dart';
import 'package:wardrobe_recommender_app/core/preferences/preferences_provider.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/guest_wardrobe_contracts.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/local_wardrobe_repository.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/wardrobe_image_picker.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/wardrobe_image_processor.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/wardrobe_photo_storage.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/wardrobe_sync_service.dart';
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

  test(
    'image processor outputs bounded JPEG data and rejects invalid input',
    () async {
      final compressed = await const WardrobeImageProcessor().compress(
        _tinyPng(),
      );

      expect(img.decodeImage(compressed), isNotNull);
      expect(
        compressed.length,
        lessThanOrEqualTo(WardrobeImageProcessor.maxOutputBytes),
      );
      await expectLater(
        const WardrobeImageProcessor().compress(Uint8List.fromList([0, 1, 2])),
        throwsA(isA<AppError>()),
      );
    },
  );

  test('failed private photo save does not create a local record', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final repository = LocalWardrobeRepository(
      preferences,
      photoStorage: _MemoryPhotoStorage(failSave: true),
    );

    await expectLater(
      repository.createItem(blouse, Uint8List.fromList([1, 2, 3])),
      throwsA(isA<AppError>()),
    );
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

  test('offline cloud failure keeps the local item queued for retry', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final photoStorage = _MemoryPhotoStorage();
    final repository = LocalWardrobeRepository(
      preferences,
      photoStorage: photoStorage,
    );
    final item = GuestWardrobeItem(
      localId: 'item-rain-jacket',
      title: 'Rain jacket',
      category: 'Outerwear',
      subcategory: 'Rainwear',
      createdAt: DateTime.utc(2025, 6, 12),
      primaryColor: 'Green',
      secondaryColor: 'Black',
      styleTags: const ['Minimal', 'Waterproof'],
      occasion: 'Travel',
      season: 'Winter',
      notes: 'Lightweight shell',
      isFavorite: true,
    );
    final savedItem = await repository.createItem(item, _tinyPng());
    final cloudStore = _FakeCloudStore(failUpload: true);
    final syncService = WardrobeSyncService(
      repository: repository,
      cloudStore: cloudStore,
    );

    await expectLater(
      syncService.syncItem('user-1', savedItem.localId),
      throwsA(isA<AppError>()),
    );
    final queued = (await repository.loadItems()).single;
    expect(queued.needsCloudSync, isTrue);
    expect(queued.cloudSyncError, contains('offline'));
    expect(queued.styleTags, item.styleTags);
    expect(queued.occasionValues, ['Travel']);
    expect(
      await repository.readImage(queued.localImagePath!),
      photoStorage.images[savedItem.localId],
    );

    cloudStore.failUpload = false;
    cloudStore.failMetadata = true;
    await expectLater(
      syncService.syncItem('user-1', savedItem.localId),
      throwsA(isA<AppError>()),
    );
    final metadataQueued = (await repository.loadItems()).single;
    expect(metadataQueued.needsCloudSync, isTrue);
    expect(metadataQueued.cloudSyncError, contains('metadata'));

    cloudStore.failMetadata = false;
    await syncService.syncItem('user-1', savedItem.localId);
    final synced = (await repository.loadItems()).single;
    expect(synced.needsCloudSync, isFalse);
    expect(synced.cloudSyncError, isNull);
    expect(cloudStore.syncedItem?.title, item.title);
    expect(cloudStore.syncedItem?.secondaryColor, item.secondaryColor);
  });

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

  testWidgets('camera/gallery import saves compressed item locally first', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = await _createPreferences();
    final repository = _MemoryWardrobeRepository([]);
    final picker = _MemoryImagePicker(_tinyPng());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          wardrobeRepositoryProvider.overrideWithValue(repository),
          wardrobeImagePickerProvider.overrideWithValue(picker),
          wardrobeImageProcessorProvider.overrideWithValue(
            _FakeImageProcessor(),
          ),
        ],
        child: const WardrobeApp(),
      ),
    );
    await _openWardrobe(tester);
    await tester.tap(find.text('Add an item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gallery'));
    await tester.pumpAndSettle();

    await _enterVisibleField(tester, 'Title', 'Rain jacket');
    await _enterVisibleField(tester, 'Category', 'Outerwear');
    await _enterVisibleField(tester, 'Subcategory', 'Rainwear');
    await _enterVisibleField(tester, 'Primary color', 'Green');
    await _enterVisibleField(tester, 'Style tags', 'Minimal, Waterproof');
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Save item'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Save item'));
    await tester.pumpAndSettle();

    expect(picker.lastSource, ImageSource.gallery);
    expect(repository.items.single.title, 'Rain jacket');
    expect(repository.items.single.localImagePath, isNotNull);
    expect(repository.items.single.needsCloudSync, isTrue);
    expect(repository.items.single.subcategory, 'Rainwear');
    expect(repository.items.single.primaryColor, 'Green');
    expect(repository.items.single.styleTags, ['Minimal', 'Waterproof']);

    await tester.scrollUntilVisible(
      find.text('Done'),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Rain jacket'), findsOneWidget);
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

Future<void> _enterVisibleField(
  WidgetTester tester,
  String label,
  String value,
) async {
  final field = find.byKey(ValueKey('wardrobe-field-$label'));
  await tester.scrollUntilVisible(
    field,
    160,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.enterText(field, value);
}

class _MemoryWardrobeRepository implements WardrobeRepository {
  _MemoryWardrobeRepository(this.items);

  List<GuestWardrobeItem> items;

  @override
  Future<GuestWardrobeItem> createItem(
    GuestWardrobeItem item,
    Uint8List photoBytes,
  ) async {
    final saved = item.copyWith(
      localImagePath: 'memory://${item.localId}',
      imageContentType: 'image/jpeg',
      needsCloudSync: true,
    );
    items = [...items, saved];
    return saved;
  }

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

  @override
  Future<void> setCloudSyncState(
    String localId, {
    required bool pending,
    String? error,
  }) async {
    _update(
      localId,
      (item) => item.copyWith(
        needsCloudSync: pending,
        cloudSyncError: error,
        clearCloudSyncError: error == null,
      ),
    );
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

Uint8List _tinyPng() {
  final image = img.Image(width: 4, height: 4);
  img.fill(image, color: img.ColorRgb8(160, 70, 90));
  return Uint8List.fromList(img.encodePng(image));
}

class _MemoryPhotoStorage implements WardrobePhotoStorage {
  _MemoryPhotoStorage({this.failSave = false});

  final bool failSave;
  final Map<String, Uint8List> images = {};

  @override
  Future<String> save(String localId, Uint8List bytes) async {
    if (failSave) throw const AppError('Photo storage is unavailable.');
    images[localId] = Uint8List.fromList(bytes);
    return 'memory://$localId';
  }

  @override
  Future<Uint8List> read(String path) async {
    final localId = path.replaceFirst('memory://', '');
    final bytes = images[localId];
    if (bytes == null) throw const AppError('Photo is missing.');
    return bytes;
  }

  @override
  Future<void> delete(String path) async {
    images.remove(path.replaceFirst('memory://', ''));
  }
}

class _FakeCloudStore implements GuestWardrobeCloudStore {
  _FakeCloudStore({this.failUpload = false});

  bool failUpload;
  bool failMetadata = false;
  GuestWardrobeItem? syncedItem;
  Uint8List? uploadedBytes;

  @override
  Future<String> uploadImage({
    required String userId,
    required String localId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    if (failUpload) throw const AppError('offline');
    uploadedBytes = bytes;
    return '$userId/$localId/photo.jpg';
  }

  @override
  Future<void> upsertItem({
    required String userId,
    required GuestWardrobeItem item,
    required String? imagePath,
  }) async {
    if (failMetadata) throw const AppError('metadata sync failed');
    syncedItem = item;
  }
}

class _MemoryImagePicker implements WardrobeImagePicker {
  _MemoryImagePicker(this.bytes);

  final Uint8List bytes;
  ImageSource? lastSource;

  @override
  Future<Uint8List?> pick(ImageSource source) async {
    lastSource = source;
    return bytes;
  }
}

class _FakeImageProcessor extends WardrobeImageProcessor {
  @override
  Future<Uint8List> compress(Uint8List input) async => input;
}
