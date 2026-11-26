import 'auth_session.dart';

abstract interface class AuthGateway {
  AuthSession? get currentSession;

  Stream<AuthSession?> get sessionChanges;

  Stream<bool> get passwordRecoveryChanges;

  Future<AuthSession?> register({
    required String email,
    required String password,
  });

  Future<AuthSession?> signIn({
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> updatePassword(String password);

  Future<void> signOut();

  Future<void> deleteAccount();
}
