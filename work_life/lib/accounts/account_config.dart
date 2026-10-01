import 'dart:convert';

import 'package:crypto/crypto.dart';

class AccountConfig {
  const AccountConfig({required this.url, required this.publishableKey});
  static const redirectUrl = 'com.worklife.app://auth-callback';
  final String url, publishableKey;

  static AccountConfig? fromEnvironment() => parse(
    const String.fromEnvironment('SUPABASE_URL'),
    const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );

  static AccountConfig? parse(String url, String key) {
    if (url.isEmpty && key.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException('Use the HTTPS Supabase project URL.');
    }
    var publicKey = key.startsWith('sb_publishable_') && key.length > 20;
    if (!publicKey) {
      try {
        final parts = key.split('.');
        if (parts.length == 3) {
          final claims = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
          ) as Map<String, dynamic>;
          publicKey = claims['role'] == 'anon';
        }
      } catch (_) {
        publicKey = false;
      }
    }
    if (!publicKey) {
      throw const FormatException(
        'Use a publishable or legacy anon key, never a server secret.',
      );
    }
    return AccountConfig(url: uri.origin, publishableKey: key);
  }

  String get namespace => sha256.convert(utf8.encode(url)).toString();
  static bool isAuthCallback(Uri uri) =>
      uri.scheme == 'com.worklife.app' &&
      uri.host == 'auth-callback' &&
      (uri.path.isEmpty || uri.path == '/') &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasFragment &&
      ((uri.queryParameters['code']?.isNotEmpty ?? false) ||
          uri.queryParameters.containsKey('error') ||
          uri.queryParameters.containsKey('error_description')) &&
      !uri.queryParameters.containsKey('access_token') &&
      !uri.queryParameters.containsKey('refresh_token');
}

String accountDatabaseName(String namespace, String? userId) {
  if (userId == null) return 'work_life.db';
  if (userId.isEmpty) throw ArgumentError('Empty account identity');
  final digest = sha256.convert(utf8.encode('$namespace:$userId'));
  return 'work_life_account_$digest.db';
}
