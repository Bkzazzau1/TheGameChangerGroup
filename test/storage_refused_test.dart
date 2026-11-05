import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/election/daily_reminder.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_crypto.dart';

/// A browser that refuses this site its storage: every use of it throws, as
/// "SecurityError: Failed to read the 'localStorage' property" does.
class _RefusedStorage extends FlutterSecureStorage {
  const _RefusedStorage();

  static Never _refuse() => throw StateError(
    "SecurityError: Failed to read the 'localStorage' property from 'Window': "
    'Access is denied for this document.',
  );

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _refuse();

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _refuse();

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => _refuse();
}

void main() {
  // (As in a browser: the visit-only fallback is the browser's.)
  test('a browser that refuses its storage keeps the sign-in for the visit', () async {
    final tokens = SecureTokenStore(const _RefusedStorage(), true);
    expect(await tokens.read(), isNull);
    await tokens.write(access: 'A', refresh: 'R');
    expect(await tokens.read(), (access: 'A', refresh: 'R'));
    await tokens.clear();
    expect(await tokens.read(), isNull);
  });

  test('so does the daily reminder', () async {
    final log = DeviceReminderLog(const _RefusedStorage(), true);
    expect(await log.lastShown('TGCG-000001'), isNull);
    final at = DateTime.utc(2026, 11, 5, 9);
    await log.shown('TGCG-000001', at);
    expect(await log.lastShown('TGCG-000001'), at);
  });

  test('off the web a storage error stands, so signing out never leaves tokens behind', () async {
    final tokens = SecureTokenStore(const _RefusedStorage());
    await expectLater(tokens.write(access: 'A', refresh: 'R'), throwsStateError);
    await expectLater(tokens.clear(), throwsStateError);
    await expectLater(DeviceReminderLog(const _RefusedStorage()).lastShown('x'), throwsStateError);
  }, skip: kIsWeb);

  // A browser's queue gets a key for the visit instead; only a browser runs that.
  test("on a phone a refused offline key stays an error: the queue outlives the visit", () async {
    await expectLater(
      OfflineCrypto(secureStorage: const _RefusedStorage()).initialize(),
      throwsStateError,
    );
  }, skip: kIsWeb);
}
