import 'dart:convert';

class SupabaseConfig {
  const SupabaseConfig({
    required this.url,
    required this.publishableKey,
    required this.authRedirectUrl,
  });

  final String url;
  final String publishableKey;
  final String authRedirectUrl;

  static const _url = String.fromEnvironment('SUPABASE_URL');
  static const _publishableKey =
      String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static const _legacyAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _authRedirectUrl = String.fromEnvironment(
    'SUPABASE_AUTH_REDIRECT_URL',
    defaultValue: 'wardrobe://auth-callback',
  );

  static SupabaseConfig? fromEnvironment() {
    final key = _publishableKey.isNotEmpty ? _publishableKey : _legacyAnonKey;
    return parse(
      url: _url,
      publishableKey: key,
      authRedirectUrl: _authRedirectUrl,
    );
  }

  static SupabaseConfig? parse({
    required String url,
    required String publishableKey,
    String authRedirectUrl = 'wardrobe://auth-callback',
  }) {
    if (url.isEmpty && publishableKey.isEmpty) return null;
    if (url.isEmpty || publishableKey.isEmpty) {
      throw const FormatException(
        'Set both SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY.',
      );
    }

    final uri = Uri.tryParse(url);
    final isLocalDevelopmentHost = uri != null &&
        const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
    final isSecureUrl = uri != null &&
        uri.scheme == 'https' &&
        uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty;
    final isLocalHttpUrl = uri != null &&
        uri.scheme == 'http' &&
        uri.hasAuthority &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        isLocalDevelopmentHost;
    if (!isSecureUrl && !isLocalHttpUrl) {
      throw const FormatException(
        'SUPABASE_URL must use HTTPS. HTTP is allowed only for localhost '
        'development.',
      );
    }
    final redirectUri = Uri.tryParse(authRedirectUrl);
    if (redirectUri == null ||
        !redirectUri.hasScheme ||
        authRedirectUrl.trim().isEmpty) {
      throw const FormatException(
        'SUPABASE_AUTH_REDIRECT_URL must be an absolute URI.',
      );
    }
    if (_isServiceRoleKey(publishableKey)) {
      throw const FormatException(
        'A Supabase publishable/anon key is required. Service-role keys are '
        'not allowed in the app.',
      );
    }
    return SupabaseConfig(
      url: url,
      publishableKey: publishableKey,
      authRedirectUrl: authRedirectUrl,
    );
  }

  static bool _isServiceRoleKey(String key) {
    if (key.startsWith('sb_secret_')) return true;

    final sections = key.split('.');
    if (sections.length != 3) return false;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(sections[1]))),
      );
      return payload is Map && payload['role'] == 'service_role';
    } on FormatException {
      return false;
    }
  }
}
