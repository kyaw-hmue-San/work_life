import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class SecureValueStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecureValueStore implements SecureValueStore {
  const PlatformSecureValueStore();
  static const _storage = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) => _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Keeps SDK session writes ordered so a late write cannot race sign-out deletion.
class SecureAuthStorage extends LocalStorage {
  SecureAuthStorage(this.namespace, {SecureValueStore? storage}) : storage = storage ?? const PlatformSecureValueStore();
  final String namespace;
  final SecureValueStore storage;
  final problem = ValueNotifier<bool>(false);
  Future<void> _tail = Future.value();
  bool _signedOut = false;
  String get _key => 'work_life.$namespace.session';

  Future<void> _ordered(Future<void> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.catchError((Object _) {});
    return next;
  }

  void beginSignIn() {
    _signedOut = false;
    problem.value = false;
  }

  @override
  Future<void> initialize() async {
    await storage.read(_key);
  }

  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<String?> accessToken() async {
    await _tail;
    return storage.read(_key);
  }

  @override
  Future<void> persistSession(String value) async {
    try {
      await _ordered(() async {
        if (!_signedOut) await storage.write(_key, value);
      });
    } catch (_) {
      problem.value = true;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    _signedOut = true;
    try {
      await _ordered(() => storage.delete(_key));
    } catch (_) {
      problem.value = true;
    }
  }

  /// Explicit sign-out must confirm secure deletion before reporting success.
  Future<void> clearForSignOut() async {
    _signedOut = true;
    await _ordered(() => storage.delete(_key));
    problem.value = false;
  }
}

class SecurePkceStorage extends GotrueAsyncStorage {
  const SecurePkceStorage(this.storage, this.namespace);
  final SecureValueStore storage;
  final String namespace;
  String _key(String key) => 'work_life.$namespace.pkce.$key';
  @override
  Future<String?> getItem({required String key}) =>
      storage.read(_key(key));
  @override
  Future<void> setItem({required String key, required String value}) =>
      storage.write(_key(key), value);
  @override
  Future<void> removeItem({required String key}) =>
      storage.delete(_key(key));
}
