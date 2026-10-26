import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_database_stub.dart' as memory_db;
import 'package:tgcg_emcop/tgcg/offline/offline_persistence.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_controller.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_worker.dart';
import 'package:tgcg_emcop/tgcg/ui/app_on_screen.dart';

/// Always the middle of the spread, so waits are exact.
class _Middle implements math.Random {
  @override
  double nextDouble() => 0.5;
  @override
  bool nextBool() => false;
  @override
  int nextInt(int max) => 0;
}

/// Answers each push with the next of [answers], then acknowledges.
class _Transport implements SyncTransport {
  _Transport(this.answers);

  final List<SyncPushResult> answers;
  var pushes = 0;

  @override
  bool supports(String entityType) => true;

  @override
  Future<SyncPushResult> push({required SyncOutboxItem mutation, required Map<String, Object?> payload}) async {
    pushes += 1;
    return answers.isEmpty ? const SyncPushResult.acknowledged(serverVersion: 1) : answers.removeAt(0);
  }
}

Future<OfflinePersistenceController> _offlineWithOneRecord() async {
  FlutterSecureStorage.setMockInitialValues({});
  final offline = OfflinePersistenceController(openDatabase: memory_db.openOfflineDatabaseBackend);
  await offline.initialize();
  await offline.persistMutation(
    entityType: 'location_ping',
    entityId: 'location_ping-1',
    mutationType: SyncMutationType.create,
    payload: const {'latitude': 11.08, 'longitude': 7.72},
  );
  return offline;
}

void main() {
  const busy = SyncPushResult.retryLater(message: 'The TGCG server is busy.');

  test('after server trouble the phone waits longer each time, and Sync now does not wait', () async {
    var now = DateTime(2027, 2, 20, 9);
    final transport = _Transport([busy, busy, busy]);
    final sync = SyncController(
      persistence: await _offlineWithOneRecord(),
      transport: transport,
      interval: const Duration(seconds: 45),
      debounce: const Duration(hours: 1),
      random: _Middle(),
      clock: () => now,
    );
    addTearDown(sync.dispose);
    sync.setEnabled(true);
    await pumpEventQueue();
    expect(transport.pushes, 1);
    expect(sync.nextTry, DateTime(2027, 2, 20, 9, 0, 45));

    // Before the wait is over, automatic tries do nothing.
    now = now.add(const Duration(seconds: 30));
    await sync.syncNow();
    expect(transport.pushes, 1);

    // Then it tries, fails again, and waits twice as long.
    now = DateTime(2027, 2, 20, 9, 0, 46);
    await sync.syncNow();
    expect(transport.pushes, 2);
    expect(sync.nextTry, now.add(const Duration(seconds: 90)));
    expect(sync.problem, 'The TGCG server is busy.');

    // The person can always try at once; success clears the wait.
    await sync.syncNow(manual: true);
    expect(transport.pushes, 3);
    await sync.syncNow(manual: true);
    expect(transport.pushes, 4);
    expect(sync.nextTry, isNull);
    expect(sync.waiting, 0);
  });

  test('the wait grows to at most the longest wait, and never sooner than the server asked', () async {
    var now = DateTime(2027, 2, 20, 9);
    final transport = _Transport([
      for (var i = 0; i < 8; i++) busy,
      const SyncPushResult.retryLater(message: 'Busy.', retryAfter: Duration(minutes: 40)),
    ]);
    final sync = SyncController(
      persistence: await _offlineWithOneRecord(),
      transport: transport,
      interval: const Duration(seconds: 45),
      debounce: const Duration(hours: 1),
      random: _Middle(),
      clock: () => now,
    );
    addTearDown(sync.dispose);
    sync.setEnabled(true);
    await pumpEventQueue();
    for (var i = 0; i < 7; i++) {
      now = sync.nextTry!;
      await sync.syncNow();
    }
    expect(transport.pushes, 8);
    expect(sync.nextTry, now.add(const Duration(minutes: 15)));
    now = sync.nextTry!;
    await sync.syncNow();
    expect(sync.nextTry, now.add(const Duration(minutes: 40)));
  });

  test('a record waiting for another to go first is no reason to wait longer', () async {
    final transport = _Transport([
      const SyncPushResult.retryLater(message: 'Waiting for the incident.', serverTrouble: false),
    ]);
    final sync = SyncController(
      persistence: await _offlineWithOneRecord(),
      transport: transport,
      debounce: const Duration(hours: 1),
      random: _Middle(),
    );
    addTearDown(sync.dispose);
    sync.setEnabled(true);
    await pumpEventQueue();
    expect(transport.pushes, 1);
    expect(sync.nextTry, isNull);
  });

  test('a busy server says how long to wait', () async {
    final client = ApiClient(
      baseUrl: 'https://api.tgcg.test',
      tokens: MemoryTokenStore(),
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': 'Request was throttled.'}),
          429,
          headers: {'content-type': 'application/json', 'retry-after': '120'},
        ),
      ),
    );
    await expectLater(
      client.get('tracking/pings/'),
      throwsA(isA<ApiException>().having((error) => error.retryAfter, 'retryAfter', const Duration(minutes: 2))),
    );
  });

  testWidgets('screens refresh only while the app can be seen', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(appOnScreen, isTrue);
    // A visible window without focus, such as a wall display.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(appOnScreen, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(appOnScreen, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    expect(appOnScreen, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(appOnScreen, isTrue);
  });
}
