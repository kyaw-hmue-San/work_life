import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_config.dart';
import 'secure_auth_storage.dart';

class AccountIdentity {
  const AccountIdentity({required this.id, required this.email});
  final String id, email;
}

abstract class AccountService extends ChangeNotifier {
  bool get configured;
  String get namespace;
  AccountIdentity? get user;
  bool get recovering;
  String? get notice;
  Future<void> signIn(String email, String password);
  Future<bool> signUp(String email, String password);
  Future<void> google();
  Future<void> resendConfirmation(String email);
  Future<void> resetPassword(String email);
  Future<void> updatePassword(String password);
  Future<void> signOut();
}

class AccountFailure implements Exception {
  const AccountFailure(this.message);
  final String message;
}

class UnconfiguredAccounts extends AccountService {
  UnconfiguredAccounts({this.notice});
  @override
  final String? notice;
  @override
  bool get configured => false;
  @override
  String get namespace => 'unconfigured';
  @override
  AccountIdentity? get user => null;
  @override
  bool get recovering => false;
  Never _unavailable() => throw const AccountFailure(
    'Accounts are not available in this build yet. You can keep using your local workspace.',
  );
  @override
  Future<void> signIn(String email, String password) async => _unavailable();
  @override
  Future<bool> signUp(String email, String password) async => _unavailable();
  @override
  Future<void> google() async => _unavailable();
  @override
  Future<void> resendConfirmation(String email) async => _unavailable();
  @override
  Future<void> resetPassword(String email) async => _unavailable();
  @override
  Future<void> updatePassword(String password) async => _unavailable();
  @override
  Future<void> signOut() async => _unavailable();
}

class SupabaseAccounts extends AccountService {
  SupabaseAccounts(this.client, this.config, this.vault) {
    _subscription = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
        if (state.event == AuthChangeEvent.signedOut) _recovering = false;
        _notice = null;
        notifyListeners();
      },
      onError: (Object error, StackTrace trace) {
        _notice = 'Sign-in could not be refreshed. Your current local workspace remains available. Try signing in again from Account.';
        notifyListeners();
      },
    );
    vault.problem.addListener(_storageChanged);
  }
  final SupabaseClient client;
  final AccountConfig config;
  final SecureAuthStorage vault;
  late final StreamSubscription<AuthState> _subscription;
  bool _recovering = false;
  String? _notice;
  @override
  bool get configured => true;
  @override
  String get namespace => config.namespace;
  @override
  bool get recovering => _recovering;
  @override
  String? get notice => vault.problem.value
      ? 'Couldn’t securely save sign-in on this device. Open Account and sign in again before relying on session restoration.'
      : _notice;
  @override
  AccountIdentity? get user {
    final value = client.auth.currentUser;
    return value == null
        ? null
        : AccountIdentity(
            id: value.id,
            email: value.email ?? 'Signed-in account',
          );
  }

  void _storageChanged() => notifyListeners();

  Future<T> _request<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on AuthException catch (error) {
      throw AccountFailure(switch (error.code) {
        'invalid_credentials' => 'Email or password is incorrect. You can also try Google if that is how you signed up.',
        'email_not_confirmed' => 'Confirm your email before signing in. You can resend the confirmation below.',
        'weak_password' =>
          'Choose a stronger password with at least 8 characters.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' =>
          'Too many attempts. Wait a little before trying again.',
        'provider_disabled' =>
          'Google sign-in is not available yet. Try email sign-in.',
        'same_password' => 'Choose a different password.',
        _ => 'Couldn’t complete sign-in. Check your details or request a fresh email link and try again.',
      });
    } on AccountFailure {
      rethrow;
    } catch (_) {
      throw const AccountFailure(
        'Couldn’t reach the account service. Check your connection and try again.',
      );
    }
  }

  @override
  Future<void> signIn(String email, String password) => _request(() async {
    vault.beginSignIn();
    await client.auth.signInWithPassword(
      email: email.trim(),
      password: password,
    );
  });
  @override
  Future<bool> signUp(String email, String password) => _request(() async {
    vault.beginSignIn();
    final response = await client.auth.signUp(
      email: email.trim(),
      password: password,
      emailRedirectTo: AccountConfig.redirectUrl,
    );
    return response.session != null;
  });
  @override
  Future<void> google() => _request(() async {
    vault.beginSignIn();
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: AccountConfig.redirectUrl,
      authScreenLaunchMode: LaunchMode.externalApplication,
      queryParams: {'prompt': 'select_account'},
    );
    if (!launched) {
      throw const AccountFailure(
        'Couldn’t open Google sign-in. Please try again.',
      );
    }
  });
  @override
  Future<void> resendConfirmation(String email) => _request(() async {
    vault.beginSignIn();
    await client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: AccountConfig.redirectUrl,
    );
  });
  @override
  Future<void> resetPassword(String email) => _request(() async {
    vault.beginSignIn();
    await client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: AccountConfig.redirectUrl,
    );
  });
  @override
  Future<void> updatePassword(String password) => _request(() async {
    await client.auth.updateUser(UserAttributes(password: password));
    _recovering = false;
    notifyListeners();
  });
  @override
  Future<void> signOut() async {
    try {
      await vault.clearForSignOut();
    } catch (_) {
      throw const AccountFailure(
        'Couldn’t clear secure sign-in storage. Please retry sign-out.',
      );
    }
    try {
      await client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // The SDK clears this device's session before attempting server revocation.
      if (client.auth.currentSession != null) {
        throw const AccountFailure('Couldn’t sign out. Please try again.');
      }
      _notice = 'Signed out on this device. Server session revocation could not be confirmed; reconnect before using another shared device.';
    }
    _recovering = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_subscription.cancel());
    vault.problem.removeListener(_storageChanged);
    super.dispose();
  }
}

Future<AccountService> initializeAccounts() async {
  try {
    final config = AccountConfig.fromEnvironment();
    if (config == null) return UnconfiguredAccounts();
    final vault = SecureAuthStorage(config.namespace);
    final instance = await Supabase.initialize(
      url: config.url,
      publishableKey: config.publishableKey,
      debug: false,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        localStorage: vault,
        pkceAsyncStorage: SecurePkceStorage(vault.storage, config.namespace),
        detectSessionInUriPredicate: AccountConfig.isAuthCallback,
      ),
    );
    return SupabaseAccounts(instance.client, config, vault);
  } catch (_) {
    return UnconfiguredAccounts(
      notice: 'Accounts could not start safely. Your guest workspace is still available. Close and reopen the app to retry.',
    );
  }
}
