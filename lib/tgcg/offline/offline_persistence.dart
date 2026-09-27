import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../sync/sync_models.dart';
import 'offline_crypto.dart';
import 'offline_database.dart';

export '../sync/sync_models.dart';

enum OfflinePersistenceState {
  idle,
  initializing,
  ready,
  failed,
}

class DurableMutationReceipt {
  const DurableMutationReceipt({
    required this.outbox,
    required this.entityVersion,
    required this.durable,
  });

  final SyncOutboxItem outbox;
  final int entityVersion;
  final bool durable;
}

class OfflinePersistenceController extends ChangeNotifier {
  OfflinePersistenceController({OfflineCrypto? crypto})
      : _crypto = crypto ?? OfflineCrypto();

  final OfflineCrypto _crypto;
  OfflineDatabaseBackend? _database;
  OfflinePersistenceState _state = OfflinePersistenceState.idle;
  String? _lastError;
  List<StoredOutboxMutation> _storedOutbox = const [];
  Future<void>? _initializationFuture;

  OfflinePersistenceState get state => _state;
  bool get isReady => _state == OfflinePersistenceState.ready;
  bool get isDurable => _database?.isDurable == true;
  String? get lastError => _lastError;

  List<SyncOutboxItem> get outbox =>
      List.unmodifiable(_storedOutbox.map((entry) => entry.item));

  List<SyncOutboxItem> get pendingOutbox => outbox
      .where((item) =>
          item.state == SyncState.queued ||
          item.state == SyncState.failed ||
          item.state == SyncState.conflict)
      .toList(growable: false);

  Future<void> initialize() {
    if (isReady) return Future.value();
    final running = _initializationFuture;
    if (running != null) return running;

    final future = _initializeInternal();
    _initializationFuture = future;
    return future.whenComplete(() {
      if (identical(_initializationFuture, future)) {
        _initializationFuture = null;
      }
    });
  }

  Future<void> _initializeInternal() async {
    _state = OfflinePersistenceState.initializing;
    _lastError = null;
    notifyListeners();

    OfflineDatabaseBackend? database;
    try {
      database = await openOfflineDatabase();
      await database.initialize();
      await _crypto.initialize();
      _database = database;
      await _refreshOutbox();
      _state = OfflinePersistenceState.ready;
    } catch (error) {
      await database?.close();
      _database = null;
      _lastError = error.toString();
      _state = OfflinePersistenceState.failed;
    }
    notifyListeners();
  }

  Future<DurableMutationReceipt> persistMutation({
    required String entityType,
    required String entityId,
    required SyncMutationType mutationType,
    required Map<String, Object?> payload,
    String? scopeKey,
    String? ownerId,
  }) async {
    await _ensureReady();
    final database = _database!;
    final currentVersion = await database.currentEntityVersion(
      entityType: entityType,
      entityId: entityId,
    );
    final nextVersion = currentVersion + 1;
    final now = DateTime.now().toUtc();
    final aad = _aad(entityType, entityId, nextVersion);
    final encrypted = await _crypto.encrypt(
      jsonEncode(payload),
      aad: aad,
    );
    final outbox = SyncOutboxItem(
      id: 'OUT-L-${now.microsecondsSinceEpoch}',
      entityType: entityType,
      entityId: entityId,
      mutationType: mutationType,
      payloadJson: '<encrypted-local-payload>',
      mutationVersion: nextVersion,
      createdAt: now,
      state: SyncState.queued,
    );

    await database.writeMutation(
      entity: StoredEntityRecord(
        entityType: entityType,
        entityId: entityId,
        version: nextVersion,
        payload: encrypted,
        updatedAt: now,
        scopeKey: scopeKey,
        ownerId: ownerId,
        deleted: mutationType == SyncMutationType.delete,
      ),
      outbox: outbox,
      outboxPayload: encrypted,
    );
    await _refreshOutbox();
    notifyListeners();
    return DurableMutationReceipt(
      outbox: outbox,
      entityVersion: nextVersion,
      durable: database.isDurable,
    );
  }

  Future<Map<String, Object?>?> readEntity({
    required String entityType,
    required String entityId,
  }) async {
    await _ensureReady();
    final record = await _database!.readEntity(
      entityType: entityType,
      entityId: entityId,
    );
    if (record == null || record.deleted) return null;
    final clear = await _crypto.decrypt(
      record.payload,
      aad: _aad(record.entityType, record.entityId, record.version),
    );
    final decoded = jsonDecode(clear);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Offline entity payload is not a JSON object.');
    }
    return decoded.cast<String, Object?>();
  }

  Future<Map<String, Object?>> payloadForOutbox(String outboxId) async {
    await _ensureReady();
    final stored = _storedOutbox
        .where((entry) => entry.item.id == outboxId)
        .firstOrNull;
    if (stored == null) {
      throw StateError('Unknown outbox mutation $outboxId.');
    }
    final item = stored.item;
    final clear = await _crypto.decrypt(
      stored.payload,
      aad: _aad(item.entityType, item.entityId, item.mutationVersion),
    );
    final decoded = jsonDecode(clear);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Offline mutation payload is not a JSON object.');
    }
    return decoded.cast<String, Object?>();
  }

  Future<void> markSyncing(String outboxId) async {
    final current = _findOutbox(outboxId);
    if (current == null) return;
    final updated = _copyOutbox(
      current,
      state: SyncState.syncing,
      attemptCount: current.attemptCount + 1,
      lastAttemptAt: DateTime.now().toUtc(),
      clearError: true,
    );
    await _saveOutbox(updated);
  }

  Future<void> markFailed(String outboxId, String error) async {
    final current = _findOutbox(outboxId);
    if (current == null) return;
    await _saveOutbox(
      _copyOutbox(
        current,
        state: SyncState.failed,
        lastAttemptAt: DateTime.now().toUtc(),
        lastError: error,
      ),
    );
  }

  Future<void> markConflict(String outboxId, String reason) async {
    final current = _findOutbox(outboxId);
    if (current == null) return;
    await _saveOutbox(
      _copyOutbox(
        current,
        state: SyncState.conflict,
        lastAttemptAt: DateTime.now().toUtc(),
        lastError: reason,
      ),
    );
  }

  Future<void> queueForRetry(String outboxId) async {
    final current = _findOutbox(outboxId);
    if (current == null) return;
    await _saveOutbox(
      _copyOutbox(
        current,
        state: SyncState.queued,
        clearError: true,
      ),
    );
  }

  Future<void> acknowledge({
    required String outboxId,
    required int serverVersion,
    String? serverReference,
  }) async {
    await _ensureReady();
    final current = _findOutbox(outboxId);
    if (current == null) return;
    final acknowledgedAt = DateTime.now().toUtc();
    final synced = _copyOutbox(
      current,
      state: SyncState.synced,
      lastAttemptAt: acknowledgedAt,
      clearError: true,
    );
    await _database!.updateOutbox(synced);
    await _database!.saveReceipt(
      SyncReceipt(
        outboxId: outboxId,
        entityType: current.entityType,
        entityId: current.entityId,
        serverVersion: serverVersion,
        acknowledgedAt: acknowledgedAt,
        serverReference: serverReference,
      ),
    );
    await _refreshOutbox();
    notifyListeners();
  }

  Future<SyncReceipt?> receiptFor(String outboxId) async {
    await _ensureReady();
    return _database!.receiptFor(outboxId);
  }

  Future<void> close() async {
    final initialization = _initializationFuture;
    if (initialization != null) {
      await initialization;
    }
    await _database?.close();
    _database = null;
    _storedOutbox = const [];
    _state = OfflinePersistenceState.idle;
  }

  Future<void> _ensureReady() async {
    await initialize();
    if (!isReady || _database == null) {
      throw StateError(
        _lastError == null
            ? 'Offline persistence is unavailable.'
            : 'Offline persistence is unavailable: $_lastError',
      );
    }
  }

  SyncOutboxItem? _findOutbox(String id) =>
      outbox.where((item) => item.id == id).firstOrNull;

  Future<void> _saveOutbox(SyncOutboxItem item) async {
    await _ensureReady();
    await _database!.updateOutbox(item);
    await _refreshOutbox();
    notifyListeners();
  }

  Future<void> _refreshOutbox() async {
    final database = _database;
    if (database == null) return;
    _storedOutbox = await database.loadOutbox();
  }

  static String _aad(String entityType, String entityId, int version) =>
      '$entityType|$entityId|v$version';

  static SyncOutboxItem _copyOutbox(
    SyncOutboxItem current, {
    SyncState? state,
    int? attemptCount,
    DateTime? lastAttemptAt,
    String? lastError,
    bool clearError = false,
  }) =>
      SyncOutboxItem(
        id: current.id,
        entityType: current.entityType,
        entityId: current.entityId,
        mutationType: current.mutationType,
        payloadJson: '<encrypted-local-payload>',
        mutationVersion: current.mutationVersion,
        createdAt: current.createdAt,
        state: state ?? current.state,
        attemptCount: attemptCount ?? current.attemptCount,
        lastAttemptAt: lastAttemptAt ?? current.lastAttemptAt,
        lastError: clearError ? null : lastError ?? current.lastError,
      );
}

class OfflinePersistence extends InheritedNotifier<OfflinePersistenceController> {
  const OfflinePersistence({
    super.key,
    required OfflinePersistenceController controller,
    required super.child,
  }) : super(notifier: controller);

  static OfflinePersistenceController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<OfflinePersistence>();
      assert(value != null, 'OfflinePersistence is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<OfflinePersistence>();
    final value = element?.widget as OfflinePersistence?;
    assert(value != null, 'OfflinePersistence is missing above this context.');
    return value!.notifier!;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
