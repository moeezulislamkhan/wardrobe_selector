import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/auth_failure.dart';
import '../domain/auth_gateway.dart';
import '../domain/auth_session.dart';

class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client, {required this.passwordResetRedirect});

  final SupabaseClient _client;
  final String passwordResetRedirect;

  @override
  AuthSession? get currentSession => _toSession(_client.auth.currentSession);

  @override
  Stream<AuthSession?> get sessionChanges => _client.auth.onAuthStateChange.map(
    (authState) => _toSession(authState.session),
  );

  @override
  Stream<bool> get passwordRecoveryChanges => _client.auth.onAuthStateChange
      .where((authState) => authState.event == AuthChangeEvent.passwordRecovery)
      .map((_) => true);

  @override
  Future<AuthSession?> register({
    required String email,
    required String password,
  }) {
    return _run('create your account', () async {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
      );
      return _toSession(response.session);
    });
  }

  @override
  Future<AuthSession?> signIn({
    required String email,
    required String password,
  }) {
    return _run('sign in', () async {
      final response = await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      return _toSession(response.session);
    });
  }

  @override
  Future<void> sendPasswordReset(String email) {
    return _run('send a password reset email', () {
      return _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: passwordResetRedirect,
      );
    });
  }

  @override
  Future<void> updatePassword(String password) {
    return _run('update your password', () {
      return _client.auth.updateUser(UserAttributes(password: password));
    });
  }

  @override
  Future<void> signOut() {
    return _run('sign out', _client.auth.signOut);
  }

  @override
  Future<void> deleteAccount() {
    return _run('delete your account', () async {
      if (_client.auth.currentSession == null) {
        throw const AuthFailure('Sign in before deleting your account.');
      }
      await _client.functions.invoke('delete-account');
      await _client.auth.signOut(scope: SignOutScope.local);
    });
  }

  AuthFailure _failureFor(String action, AuthException error) {
    final code = error.code?.toLowerCase();
    final message = error.message.toLowerCase();

    if (code == 'invalid_credentials' ||
        message.contains('invalid login credentials')) {
      return const AuthFailure('The email or password is incorrect.');
    }
    if (code == 'email_exists' || message.contains('already registered')) {
      return const AuthFailure(
        'An account with this email already exists. Try signing in instead.',
      );
    }
    if (code == 'weak_password' || error is AuthWeakPasswordException) {
      return const AuthFailure('Choose a stronger password and try again.');
    }
    if (code == 'email_not_confirmed') {
      return const AuthFailure('Verify your email address before signing in.');
    }
    if (error is AuthRetryableFetchException || error.statusCode == '429') {
      return const AuthFailure(
        'The service is temporarily unavailable. Check your connection and '
        'try again.',
      );
    }
    return AuthFailure('We couldn’t $action. Please try again.');
  }

  Future<T> _run<T>(String action, Future<T> Function() operation) async {
    try {
      return await operation();
    } on AuthException catch (error) {
      throw _failureFor(action, error);
    } on Exception catch (error) {
      throw AuthFailure(
        'We couldn’t $action. Check your connection and try again.',
        cause: error,
      );
    }
  }

  static AuthSession? _toSession(Session? session) {
    final user = session?.user;
    if (user == null) return null;
    return AuthSession(userId: user.id, email: user.email);
  }
}
