import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_error.dart';
import '../../../core/errors/error_snackbar.dart';
import '../../../core/preferences/theme_mode_provider.dart';
import '../../auth/domain/auth_session.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../wardrobe/data/guest_wardrobe_migration.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('Appearance', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text('Choose how Wardrobe looks on this device.'),
          const SizedBox(height: 16),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(
                value: ThemeMode.system,
                icon: Icon(Icons.settings_suggest_outlined),
                label: Text('System'),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('Light'),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
            ],
            selected: {themeMode},
            onSelectionChanged: (selection) async {
              try {
                await ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(selection.single);
              } catch (error) {
                if (context.mounted) {
                  context.showAppError(error);
                }
              }
            },
          ),
          const SizedBox(height: 32),
          Text('Account', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const _AccountSettingsSection(),
        ],
      ),
    );
  }
}

class _AccountSettingsSection extends ConsumerStatefulWidget {
  const _AccountSettingsSection();

  @override
  ConsumerState<_AccountSettingsSection> createState() =>
      _AccountSettingsSectionState();
}

class _AccountSettingsSectionState
    extends ConsumerState<_AccountSettingsSection> {
  bool _isSigningOut = false;
  bool _isDeleting = false;
  bool _isSyncing = false;
  String? _errorMessage;
  String? _syncMessage;

  Future<void> _signOut() async {
    final gateway = ref.read(authGatewayProvider);
    if (gateway == null || _isSigningOut || _isDeleting || _isSyncing) return;
    setState(() {
      _isSigningOut = true;
      _errorMessage = null;
    });
    try {
      await gateway.signOut();
    } on AppError catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  Future<void> _deleteAccount() async {
    final gateway = ref.read(authGatewayProvider);
    if (gateway == null || _isDeleting || _isSigningOut || _isSyncing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete your account?'),
        content: const Text(
          'This permanently deletes your cloud account, wardrobe records, '
          'plans, and stored photos. Your local wardrobe and photos remain on '
          'this device and will be available in guest mode.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete account'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _isDeleting = true;
      _errorMessage = null;
      _syncMessage = null;
    });
    try {
      await gateway.deleteAccount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Cloud account deleted. Your local wardrobe remains on this device.',
            ),
          ),
        );
      }
    } on AppError catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  Future<void> _syncGuestWardrobe() async {
    final session = ref.read(authSessionProvider).asData?.value;
    if (session == null || _isSyncing || _isSigningOut || _isDeleting) return;
    setState(() {
      _isSyncing = true;
      _errorMessage = null;
      _syncMessage = null;
    });
    try {
      final count = await ref
          .read(guestWardrobeMigratorProvider)
          .migrate(session.userId);
      if (mounted) {
        setState(() {
          _syncMessage = count == 0
              ? 'No guest wardrobe items need syncing.'
              : 'Synced $count wardrobe items.';
        });
      }
    } on AppError catch (error) {
      if (mounted) setState(() => _errorMessage = error.message);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final gatewayAvailable = ref.watch(authGatewayProvider) != null;
    final sessionValue = ref.watch(authSessionProvider);

    return sessionValue.when(
      loading: () => const ListTile(
        contentPadding: EdgeInsets.zero,
        leading: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        title: Text('Restoring account session…'),
      ),
      error: (error, stackTrace) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.cloud_off_outlined),
            title: Text('Account session unavailable'),
            subtitle: Text(
              'Your local wardrobe is still available. You can try signing in '
              'again later.',
            ),
          ),
          _AccountActionButtons(enabled: gatewayAvailable),
        ],
      ),
      data: (session) => session == null
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.person_outline),
                  title: const Text('Using guest mode'),
                  subtitle: Text(
                    gatewayAvailable
                        ? 'Your wardrobe works without an account. Sign in '
                              'only if you want to sync it.'
                        : 'Account services are not configured. Guest mode '
                              'remains available.',
                  ),
                ),
                _AccountActionButtons(enabled: gatewayAvailable),
              ],
            )
          : _SignedInAccount(
              session: session,
              isSigningOut: _isSigningOut,
              isDeleting: _isDeleting,
              isSyncing: _isSyncing,
              errorMessage: _errorMessage,
              syncMessage: _syncMessage,
              onSync: _syncGuestWardrobe,
              onSignOut: _signOut,
              onDeleteAccount: _deleteAccount,
            ),
    );
  }
}

class _AccountActionButtons extends StatelessWidget {
  const _AccountActionButtons({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: enabled ? () => context.push('/account/sign-in') : null,
          icon: const Icon(Icons.login),
          label: const Text('Sign in'),
        ),
        TextButton(
          onPressed: enabled ? () => context.push('/account/create') : null,
          child: const Text('Create account'),
        ),
      ],
    );
  }
}

class _SignedInAccount extends StatelessWidget {
  const _SignedInAccount({
    required this.session,
    required this.isSigningOut,
    required this.isDeleting,
    required this.isSyncing,
    required this.errorMessage,
    required this.syncMessage,
    required this.onSync,
    required this.onSignOut,
    required this.onDeleteAccount,
  });

  final AuthSession session;
  final bool isSigningOut;
  final bool isDeleting;
  final bool isSyncing;
  final String? errorMessage;
  final String? syncMessage;
  final VoidCallback onSync;
  final VoidCallback onSignOut;
  final VoidCallback onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Signed in'),
          subtitle: Text(session.email ?? 'Account connected'),
        ),
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              errorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (syncMessage != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(syncMessage!),
          ),
        OutlinedButton.icon(
          onPressed: isSyncing || isSigningOut || isDeleting ? null : onSync,
          icon: isSyncing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.cloud_upload_outlined),
          label: Text(isSyncing ? 'Syncing…' : 'Sync guest wardrobe'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: isSigningOut || isSyncing || isDeleting ? null : onSignOut,
          icon: isSigningOut
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.logout),
          label: Text(isSigningOut ? 'Signing out…' : 'Sign out'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: isDeleting || isSigningOut || isSyncing
              ? null
              : onDeleteAccount,
          icon: isDeleting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.delete_forever_outlined),
          label: Text(isDeleting ? 'Deleting account…' : 'Delete account'),
        ),
      ],
    );
  }
}
