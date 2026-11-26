import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wardrobe_recommender_app/app/app.dart';
import 'package:wardrobe_recommender_app/core/config/supabase_config.dart';
import 'package:wardrobe_recommender_app/core/errors/app_error.dart';
import 'package:wardrobe_recommender_app/core/preferences/preferences_provider.dart';
import 'package:wardrobe_recommender_app/features/auth/domain/auth_failure.dart';
import 'package:wardrobe_recommender_app/features/auth/domain/auth_gateway.dart';
import 'package:wardrobe_recommender_app/features/auth/domain/auth_session.dart';
import 'package:wardrobe_recommender_app/features/auth/presentation/auth_providers.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/guest_wardrobe_contracts.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/data/guest_wardrobe_migration.dart';
import 'package:wardrobe_recommender_app/features/wardrobe/domain/guest_wardrobe_item.dart';

void main() {
  group('auth session state', () {
    test(
      'restores a session and publishes sign-in and sign-out changes',
      () async {
        const restored = AuthSession(
          userId: '4c4a8f3d-bded-44ee-821d-1d8ce5a77504',
          email: 'style@example.com',
        );
        final gateway = _FakeAuthGateway(initialSession: restored);
        final container = ProviderContainer(
          overrides: [authGatewayProvider.overrideWithValue(gateway)],
        );
        final subscription = container.listen(
          authSessionProvider,
          (previous, next) {},
          fireImmediately: true,
        );
        addTearDown(subscription.close);
        addTearDown(container.dispose);
        addTearDown(gateway.dispose);

        await Future<void>.delayed(Duration.zero);
        expect(container.read(authSessionProvider).asData?.value, restored);

        await gateway.signIn(email: 'style@example.com', password: 'password');
        await Future<void>.delayed(Duration.zero);
        expect(
          container.read(authSessionProvider).asData?.value,
          const AuthSession(
            userId: '4c4a8f3d-bded-44ee-821d-1d8ce5a77504',
            email: 'style@example.com',
          ),
        );

        await gateway.signOut();
        await Future<void>.delayed(Duration.zero);
        expect(container.read(authSessionProvider).asData?.value, isNull);
      },
    );

    test('password reset is an explicit gateway operation', () async {
      final gateway = _FakeAuthGateway();
      await gateway.sendPasswordReset('style@example.com');

      expect(gateway.passwordResetEmail, 'style@example.com');
      await gateway.dispose();
    });
  });

  group('guest wardrobe migration', () {
    const userId = '4c4a8f3d-bded-44ee-821d-1d8ce5a77504';

    test('empty guest wardrobe is a safe no-op', () async {
      final cloud = _FakeCloudStore();
      final migrator = GuestWardrobeMigrator(
        source: _MemoryGuestSource(const [], const {}),
        cloudStore: cloud,
      );

      expect(await migrator.migrate(userId), 0);
      expect(cloud.uploads, 0);
      expect(cloud.items, isEmpty);
    });

    test(
      'duplicate local identifiers are rejected before any upload',
      () async {
        final duplicateItem = _item('same-id', image: true);
        final source = _MemoryGuestSource(
          [duplicateItem, duplicateItem],
          {
            '/private/coat.jpg': Uint8List.fromList([1, 2, 3]),
          },
        );
        final cloud = _FakeCloudStore();

        await expectLater(
          GuestWardrobeMigrator(
            source: source,
            cloudStore: cloud,
          ).migrate(userId),
          throwsA(isA<AppError>()),
        );
        expect(cloud.uploads, 0);
        expect(cloud.items, isEmpty);
        expect(source.items, hasLength(2));
      },
    );

    test(
      'partial failure can be retried without duplicate cloud objects',
      () async {
        final source = _MemoryGuestSource(
          [_item('local-1', image: true), _item('local-2', image: true)],
          {
            '/private/local-1.jpg': Uint8List.fromList([1, 2, 3]),
            '/private/local-2.jpg': Uint8List.fromList([4, 5, 6]),
          },
        );
        final cloud = _FakeCloudStore(failOnceForLocalId: 'local-2');
        final migrator = GuestWardrobeMigrator(
          source: source,
          cloudStore: cloud,
        );

        await expectLater(migrator.migrate(userId), throwsA(isA<AppError>()));
        expect(source.items, hasLength(2));
        expect(source.images, hasLength(2));

        expect(await migrator.migrate(userId), 2);
        expect(cloud.items, hasLength(2));
        expect(cloud.uploads, 4);
        expect(cloud.objectPaths, hasLength(2));
        expect(cloud.upsertAttempts, 4);
      },
    );

    test(
      'unsupported or oversized images never create wardrobe records',
      () async {
        final source = _MemoryGuestSource(
          [_item('bad-image', image: true, imageType: 'image/svg+xml')],
          {
            '/private/bad.svg': Uint8List.fromList([1]),
          },
        );
        final cloud = _FakeCloudStore();

        await expectLater(
          GuestWardrobeMigrator(
            source: source,
            cloudStore: cloud,
          ).migrate(userId),
          throwsA(isA<AppError>()),
        );
        expect(cloud.uploads, 0);
        expect(cloud.items, isEmpty);

        final largeSource = _MemoryGuestSource(
          [_item('large-image', image: true)],
          {
            '/private/large.jpg': Uint8List(
              GuestWardrobeMigrator.maxImageBytes + 1,
            ),
          },
        );
        await expectLater(
          GuestWardrobeMigrator(
            source: largeSource,
            cloudStore: cloud,
          ).migrate(userId),
          throwsA(isA<AppError>()),
        );
        expect(cloud.uploads, 0);
        expect(cloud.items, isEmpty);
      },
    );
  });

  group('Supabase client configuration', () {
    test('missing configuration keeps the app in guest mode', () {
      expect(SupabaseConfig.parse(url: '', publishableKey: ''), isNull);
    });

    test('service-role keys are rejected without echoing the key', () {
      const serviceKey = 'sb_secret_do_not_embed';
      expect(
        () => SupabaseConfig.parse(
          url: 'https://wardrobe.supabase.co',
          publishableKey: serviceKey,
        ),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            isNot(contains(serviceKey)),
          ),
        ),
      );

      final payload = base64Url
          .encode(utf8.encode(jsonEncode({'role': 'service_role'})))
          .replaceAll('=', '');
      final jwtServiceKey = 'header.$payload.signature';
      expect(
        () => SupabaseConfig.parse(
          url: 'https://wardrobe.supabase.co',
          publishableKey: jwtServiceKey,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts a publishable key and valid endpoint', () {
      final config = SupabaseConfig.parse(
        url: 'https://wardrobe.supabase.co',
        publishableKey: 'sb_publishable_public_key',
      );

      expect(config?.url, 'https://wardrobe.supabase.co');
      expect(config?.publishableKey, 'sb_publishable_public_key');
    });

    test('rejects insecure remote endpoints but permits local development', () {
      expect(
        () => SupabaseConfig.parse(
          url: 'http://wardrobe.example.com',
          publishableKey: 'public-key',
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        SupabaseConfig.parse(
          url: 'http://localhost:54321',
          publishableKey: 'public-key',
        ),
        isNotNull,
      );
    });
  });

  testWidgets('registration restores signed-in settings and supports logout', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    final preferences = await SharedPreferences.getInstance();
    final gateway = _FakeAuthGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authGatewayProvider.overrideWithValue(gateway),
        ],
        child: const WardrobeApp(),
      ),
    );
    addTearDown(gateway.dispose);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'style@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'wardrobe-pass-123',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(find.text('style@example.com'), findsOneWidget);
    expect(preferences.getKeys(), {'onboarding_completed'});
    await tester.tap(find.widgetWithText(OutlinedButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Using guest mode'), findsOneWidget);
  });

  testWidgets('account deletion requires confirmation and signs out', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'wardrobe_items_v1': jsonEncode([
        _item('local-item', image: false).toJson(),
      ]),
    });
    final preferences = await SharedPreferences.getInstance();
    final gateway = _FakeAuthGateway(
      initialSession: const AuthSession(
        userId: '4c4a8f3d-bded-44ee-821d-1d8ce5a77504',
        email: 'style@example.com',
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authGatewayProvider.overrideWithValue(gateway),
        ],
        child: const WardrobeApp(),
      ),
    );
    addTearDown(gateway.dispose);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Signed in'), findsOneWidget);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    expect(find.text('Delete your account?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(gateway.deleteAccountCalls, 0);
    expect(find.text('Signed in'), findsOneWidget);

    await tester.tap(find.text('Delete account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete account').last);
    await tester.pumpAndSettle();
    expect(gateway.deleteAccountCalls, 1);
    expect(find.text('Using guest mode'), findsOneWidget);
    expect(preferences.getString('wardrobe_items_v1'), isNotNull);
  });

  testWidgets('password reset reports success and auth errors are visible', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    final preferences = await SharedPreferences.getInstance();
    final gateway = _FakeAuthGateway();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(preferences),
          authGatewayProvider.overrideWithValue(gateway),
        ],
        child: const WardrobeApp(),
      ),
    );
    addTearDown(gateway.dispose);

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Settings'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'style@example.com',
    );
    await tester.tap(find.text('Send reset link'));
    await tester.pumpAndSettle();

    expect(gateway.passwordResetEmail, 'style@example.com');
    expect(
      find.textContaining('If an account exists for this email'),
      findsOneWidget,
    );

    await tester.tap(find.text('Back to sign in'));
    await tester.pumpAndSettle();
    gateway.nextFailure = const AuthFailure(
      'The email or password is incorrect.',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'style@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'incorrect-password',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('The email or password is incorrect.'), findsOneWidget);

    gateway.emitPasswordRecovery();
    await tester.pumpAndSettle();
    expect(find.text('Set a new password'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'New password'),
      'new-wardrobe-pass',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Confirm new password'),
      'new-wardrobe-pass',
    );
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(gateway.updatedPassword, 'new-wardrobe-pass');
    expect(find.text('Signed in'), findsOneWidget);
  });
}

GuestWardrobeItem _item(
  String localId, {
  required bool image,
  String imageType = 'image/jpeg',
}) {
  return GuestWardrobeItem(
    localId: localId,
    name: 'Denim jacket',
    category: 'Outerwear',
    color: 'Blue',
    brand: 'Example',
    size: 'M',
    createdAt: DateTime.utc(2025, 1, 1),
    localImagePath: image ? '/private/$localId.jpg' : null,
    imageContentType: image ? imageType : null,
  );
}

class _MemoryGuestSource implements GuestWardrobeSource {
  _MemoryGuestSource(this.items, this.images);

  final List<GuestWardrobeItem> items;
  final Map<String, Uint8List> images;

  @override
  Future<List<GuestWardrobeItem>> loadItems() async => List.unmodifiable(items);

  @override
  Future<Uint8List> readImage(String localImagePath) async {
    final image = images[localImagePath];
    if (image == null) throw const AppError('Local image is unavailable.');
    return image;
  }
}

class _FakeCloudStore implements GuestWardrobeCloudStore {
  _FakeCloudStore({this.failOnceForLocalId});

  final String? failOnceForLocalId;
  final objectPaths = <String>{};
  final items = <String, GuestWardrobeItem>{};
  final attemptedPaths = <String>[];
  int uploads = 0;
  int upsertAttempts = 0;
  bool _hasFailed = false;

  @override
  Future<String> uploadImage({
    required String userId,
    required String localId,
    required Uint8List bytes,
    required String contentType,
  }) async {
    uploads++;
    final encodedId = base64Url
        .encode(utf8.encode(localId))
        .replaceAll('=', '');
    final path = '$userId/$encodedId/photo.jpg';
    objectPaths.add(path);
    return path;
  }

  @override
  Future<void> upsertItem({
    required String userId,
    required GuestWardrobeItem item,
    required String? imagePath,
  }) async {
    upsertAttempts++;
    attemptedPaths.add(imagePath ?? '');
    if (!_hasFailed && item.localId == failOnceForLocalId) {
      _hasFailed = true;
      throw const AppError('Temporary cloud failure.');
    }
    items['$userId:${item.localId}'] = item;
  }

  @override
  Future<void> deleteItem({
    required String userId,
    required GuestWardrobeItem item,
  }) async {
    items.remove('$userId:${item.localId}');
  }
}

class _FakeAuthGateway implements AuthGateway {
  _FakeAuthGateway({AuthSession? initialSession}) : _session = initialSession;

  final _events = StreamController<AuthSession?>.broadcast(sync: true);
  final _recoveryEvents = StreamController<bool>.broadcast(sync: true);
  AuthSession? _session;
  String? passwordResetEmail;
  String? updatedPassword;
  int deleteAccountCalls = 0;
  AuthFailure? nextFailure;

  @override
  AuthSession? get currentSession => _session;

  @override
  Stream<AuthSession?> get sessionChanges => _events.stream;

  @override
  Stream<bool> get passwordRecoveryChanges => _recoveryEvents.stream;

  @override
  Future<AuthSession?> register({
    required String email,
    required String password,
  }) async {
    return signIn(email: email, password: password);
  }

  @override
  Future<AuthSession?> signIn({
    required String email,
    required String password,
  }) async {
    final failure = nextFailure;
    nextFailure = null;
    if (failure != null) throw failure;
    _session = AuthSession(
      userId: '4c4a8f3d-bded-44ee-821d-1d8ce5a77504',
      email: email,
    );
    _events.add(_session);
    return _session;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    passwordResetEmail = email;
  }

  @override
  Future<void> updatePassword(String password) async {
    updatedPassword = password;
    _session ??= const AuthSession(
      userId: '4c4a8f3d-bded-44ee-821d-1d8ce5a77504',
      email: 'style@example.com',
    );
    _events.add(_session);
  }

  @override
  Future<void> signOut() async {
    _session = null;
    _events.add(null);
  }

  @override
  Future<void> deleteAccount() async {
    deleteAccountCalls++;
    _session = null;
    _events.add(null);
  }

  void emitPasswordRecovery() {
    _session = const AuthSession(
      userId: '4c4a8f3d-bded-44ee-821d-1d8ce5a77504',
      email: 'style@example.com',
    );
    _events.add(_session);
    _recoveryEvents.add(true);
  }

  Future<void> dispose() async {
    await _events.close();
    await _recoveryEvents.close();
  }
}
