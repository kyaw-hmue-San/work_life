import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:work_life/accounts/account_config.dart';
import 'package:work_life/accounts/secure_auth_storage.dart';
import 'package:work_life/captures/capture.dart';
import 'package:work_life/workspace/workspace_repository.dart';

class MemorySecureStore implements SecureValueStore {
  final values = <String, String>{};
  Completer<void>? writeBarrier;
  bool failWrites = false, failDeletes = false;
  @override Future<String?> read(String key) async => values[key];
  @override Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('Secure storage unavailable');
    await writeBarrier?.future;
    values[key] = value;
  }
  @override Future<void> delete(String key) async {
    if (failDeletes) throw StateError('Secure storage unavailable');
    values.remove(key);
  }
}

void main() {
  sqfliteFfiInit();
  test('only public configuration is accepted; callbacks require the PKCE code', () {
    expect(AccountConfig.parse('', ''), isNull);
    final config = AccountConfig.parse('https://example.supabase.co/', 'sb_publishable_example_public_key')!;
    expect(config.url, 'https://example.supabase.co');
    expect(() => AccountConfig.parse('http://example.supabase.co', 'sb_publishable_example_public_key'), throwsFormatException);
    final secretJwt = 'header.${base64Url.encode(utf8.encode(jsonEncode({'role': 'service_role'})))}.signature';
    expect(() => AccountConfig.parse(config.url, secretJwt), throwsFormatException);
    expect(() => AccountConfig.parse(config.url, 'sb_secret_do_not_use_in_client'), throwsFormatException);
    expect(AccountConfig.isAuthCallback(Uri.parse('${AccountConfig.redirectUrl}?code=valid')), isTrue);
    for (final uri in ['com.worklife.app://evil?code=x', '${AccountConfig.redirectUrl}/wrong?code=x', '${AccountConfig.redirectUrl}#access_token=x', '${AccountConfig.redirectUrl}?access_token=x', '${AccountConfig.redirectUrl}?code=x&refresh_token=bad', 'https://auth-callback?code=x']) {
      expect(AccountConfig.isAuthCallback(Uri.parse(uri)), isFalse);
    }
  });
  test('guest, account A and B persist independently across reopen', () async {
    final directory = await Directory.systemTemp.createTemp('work_life_accounts_');
    final repositories = <SqliteWorkspaceRepository>[];
    SqliteWorkspaceRepository open(String? user, {String namespace = 'project-one'}) {
      final name = accountDatabaseName(namespace, user);
      final repo = SqliteWorkspaceRepository(factory: databaseFactoryFfi, databasePath: '${directory.path}/$name');
      repositories.add(repo);
      return repo;
    }
    try {
      await open(null).save(Capture.create('Guest note'));
      await open('alice').save(Capture.create('Alice note'));
      await open('bob').save(Capture.create('Bob note'));
      for (final repo in List.of(repositories)) { await repo.close(); }
      expect((await open(null).load()).single.originalText, 'Guest note');
      expect((await open('alice').load()).single.originalText, 'Alice note');
      expect((await open('bob').load()).single.originalText, 'Bob note');
      expect(await open('alice', namespace: 'different-project').load(), isEmpty);
      expect(accountDatabaseName('x', '../../bad'), matches(r'^work_life_account_[a-f0-9]{64}\.db$'));
    } finally {
      for (final repo in repositories) { await repo.close(); }
      await directory.delete(recursive: true);
    }
  });
  test('sign-out follows pending secure writes and blocks late persistence', () async {
    final store = MemorySecureStore()..writeBarrier = Completer<void>();
    final vault = SecureAuthStorage('project', storage: store);
    final write = vault.persistSession('test-session');
    await Future<void>.delayed(Duration.zero);
    final signout = vault.clearForSignOut();
    store.writeBarrier!.complete();
    await Future.wait([write, signout]);
    await vault.persistSession('late-session');
    expect(await vault.accessToken(), isNull);
    vault.beginSignIn();
    await vault.persistSession('new-session');
    expect(await vault.accessToken(), 'new-session');
    expect(await SecureAuthStorage('other', storage: store).accessToken(), isNull);
  });
  test('secure failures are visible and failed sign-out deletion throws', () async {
    final store = MemorySecureStore()..failWrites = true;
    final vault = SecureAuthStorage('project', storage: store);
    await vault.persistSession('test-session');
    expect(vault.problem.value, isTrue);
    store.failDeletes = true;
    await expectLater(vault.clearForSignOut(), throwsStateError);
  });
}
