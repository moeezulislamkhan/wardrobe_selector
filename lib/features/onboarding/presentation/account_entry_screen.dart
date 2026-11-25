import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../../../features/auth/domain/auth_failure.dart';
import '../../../features/auth/presentation/auth_providers.dart';
import '../../../features/wardrobe/data/guest_wardrobe_migration.dart';

class AccountEntryScreen extends ConsumerStatefulWidget {
  const AccountEntryScreen({required this.createAccount, super.key});

  final bool createAccount;

  @override
  ConsumerState<AccountEntryScreen> createState() => _AccountEntryScreenState();
}

class _AccountEntryScreenState extends ConsumerState<AccountEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isResettingPassword = false;
  bool _showPassword = false;
  bool _needsMigration = false;
  String? _pendingMigrationUserId;
  String? _message;
  bool _messageIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _emailValidator(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty || !email.contains('@') || email.endsWith('@')) {
      return 'Enter a valid email address.';
    }
    return '';
  }

  String? _passwordValidator(String? value) {
    if (_isResettingPassword) return null;
    final password = value ?? '';
    if (password.isEmpty) return 'Enter your password.';
    if (widget.createAccount && password.length < 8) {
      return 'Use at least 8 characters.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (_isLoading || !(_formKey.currentState?.validate() ?? false)) return;
    final gateway = ref.read(authGatewayProvider);
    if (gateway == null) {
      _setMessage(_configurationMessage, isError: true);
      return;
    }

    setState(() {
      _isLoading = true;
      _message = null;
      _needsMigration = false;
      _pendingMigrationUserId = null;
    });

    try {
      if (_isResettingPassword) {
        await gateway.sendPasswordReset(_emailController.text.trim());
        _setMessage(
          'If an account exists for this email, a password reset link has '
          'been sent.',
        );
        return;
      }

      final session = widget.createAccount
          ? await gateway.register(
              email: _emailController.text,
              password: _passwordController.text,
            )
          : await gateway.signIn(
              email: _emailController.text,
              password: _passwordController.text,
            );
      if (session == null) {
        _setMessage(
          'Check your email for a verification link, then return here to sign '
          'in.',
        );
        return;
      }
      await _migrateGuestWardrobe(session.userId);
      if (_needsMigration) return;
      if (mounted) context.go('/settings');
    } on AuthFailure catch (error) {
      _setMessage(error.message, isError: true);
    } on AppError catch (error) {
      _setMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _migrateGuestWardrobe(String userId) async {
    try {
      await ref.read(guestWardrobeMigratorProvider).migrate(userId);
      _pendingMigrationUserId = null;
      _needsMigration = false;
    } on AppError catch (error) {
      _pendingMigrationUserId = userId;
      _needsMigration = true;
      _setMessage(error.message, isError: true);
    }
  }

  Future<void> _retryMigration() async {
    final userId = _pendingMigrationUserId;
    if (userId == null || _isLoading) return;
    setState(() {
      _isLoading = true;
      _message = null;
    });
    try {
      await ref.read(guestWardrobeMigratorProvider).migrate(userId);
      _pendingMigrationUserId = null;
      _needsMigration = false;
      if (mounted) context.go('/settings');
    } on AppError catch (error) {
      _setMessage(error.message, isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String get _configurationMessage =>
      ref.read(authConfigurationErrorProvider) ??
      'Account services are not configured yet. You can continue using the app '
          'as a guest.';

  void _setMessage(String message, {bool isError = false}) {
    if (mounted) {
      setState(() {
        _message = message;
        _messageIsError = isError;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gatewayAvailable = ref.watch(authGatewayProvider) != null;
    final title = _isResettingPassword
        ? 'Reset password'
        : widget.createAccount
            ? 'Create account'
            : 'Sign in';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Back to onboarding',
          onPressed: () => context.go('/onboarding'),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(title),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(
                      _isResettingPassword
                          ? Icons.lock_reset
                          : Icons.account_circle_outlined,
                      size: 52,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your wardrobe works without an account. Sign in only '
                      'if you want to sync it securely.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (!gatewayAvailable) ...[
                      const SizedBox(height: 20),
                      _MessageCard(
                        message: _configurationMessage,
                        isError: true,
                      ),
                    ],
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: _isResettingPassword
                          ? TextInputAction.done
                          : TextInputAction.next,
                      autofillHints: const [AutofillHints.email],
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        hintText: 'you@example.com',
                        prefixIcon: Icon(Icons.email_outlined),
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final message = _emailValidator(value);
                        return message.isEmpty ? null : message;
                      },
                      onChanged: (_) {
                        if (_message != null) {
                          setState(() => _message = null);
                        }
                      },
                    ),
                    if (!_isResettingPassword) ...[
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _passwordController,
                        enabled: !_isLoading,
                        obscureText: !_showPassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: [
                          widget.createAccount
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip:
                                _showPassword ? 'Hide password' : 'Show password',
                            onPressed: _isLoading
                                ? null
                                : () => setState(
                                      () => _showPassword = !_showPassword,
                                    ),
                            icon: Icon(
                              _showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: _passwordValidator,
                        onChanged: (_) {
                          if (_message != null) {
                            setState(() => _message = null);
                          }
                        },
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 16),
                      _MessageCard(
                        message: _message!,
                        isError: _messageIsError,
                      ),
                    ],
                    if (_needsMigration) ...[
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: _isLoading ? null : _retryMigration,
                        child: const Text('Retry wardrobe sync'),
                      ),
                      OutlinedButton(
                        onPressed: _isLoading
                            ? null
                            : () => context.go('/settings'),
                        child: const Text('Continue without syncing'),
                      ),
                    ] else ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton(
                          onPressed: _isLoading
                              ? null
                              : () {
                                  if (_isResettingPassword &&
                                      widget.createAccount) {
                                    context.go('/account/sign-in');
                                    return;
                                  }
                                  setState(() {
                                    _isResettingPassword =
                                        !_isResettingPassword;
                                    _message = null;
                                  });
                                },
                          child: Text(
                            _isResettingPassword
                                ? 'Back to sign in'
                                : 'Forgot password?',
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 54,
                        child: FilledButton(
                          onPressed:
                              _isLoading || !gatewayAvailable ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isResettingPassword
                                      ? 'Send reset link'
                                      : widget.createAccount
                                          ? 'Create account'
                                          : 'Sign in',
                                ),
                        ),
                      ),
                    ],
                    if (!_isResettingPassword && !_needsMigration)
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () => context.go(
                                  widget.createAccount
                                      ? '/account/sign-in'
                                      : '/account/create',
                                ),
                        child: Text(
                          widget.createAccount
                              ? 'Already have an account? Sign in'
                              : 'New here? Create an account',
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isLoading ? null : () => context.go('/'),
                      child: const Text('Continue as Guest'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  const _MessageCard({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isError ? colors.errorContainer : colors.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          message,
          style: TextStyle(
            color: isError ? colors.onErrorContainer : colors.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}
