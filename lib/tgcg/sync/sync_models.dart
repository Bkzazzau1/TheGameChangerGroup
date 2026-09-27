enum SyncMutationType { create, update, delete }

enum SyncState { queued, syncing, synced, failed, conflict }

class SyncOutboxItem {
  const SyncOutboxItem({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.mutationType,
    required this.payloadJson,
    required this.mutationVersion,
    required this.createdAt,
    required this.state,
    this.attemptCount = 0,
    this.lastAttemptAt,
    this.lastError,
  });

  final String id;
  final String entityType;
  final String entityId;
  final SyncMutationType mutationType;
  final String payloadJson;
  final int mutationVersion;
  final DateTime createdAt;
  final SyncState state;
  final int attemptCount;
  final DateTime? lastAttemptAt;
  final String? lastError;

  bool get isPending =>
      state == SyncState.queued ||
      state == SyncState.failed ||
      state == SyncState.conflict;
}

class SyncReceipt {
  const SyncReceipt({
    required this.outboxId,
    required this.entityType,
    required this.entityId,
    required this.serverVersion,
    required this.acknowledgedAt,
    this.serverReference,
  });

  final String outboxId;
  final String entityType;
  final String entityId;
  final int serverVersion;
  final DateTime acknowledgedAt;
  final String? serverReference;
}

abstract interface class SyncOutboxRepository {
  Future<void> enqueue(SyncOutboxItem item);

  Future<List<SyncOutboxItem>> pending({int limit = 100});

  Future<void> markSyncing({
    required String outboxId,
    required DateTime attemptedAt,
  });

  Future<void> markSynced({
    required String outboxId,
    required SyncReceipt receipt,
  });

  Future<void> markFailed({
    required String outboxId,
    required DateTime attemptedAt,
    required String error,
  });

  Future<void> markConflict({
    required String outboxId,
    required DateTime attemptedAt,
    required String reason,
  });
}

/// Contract for the encrypted local persistence layer used by field clients.
///
/// Concrete implementations are expected to persist operational writes locally
/// before network synchronization so a successful on-device action is not
/// dependent on connectivity.
abstract interface class LocalOperationalStore {
  Future<void> writeEntity({
    required String entityType,
    required String entityId,
    required String encryptedPayload,
    required int version,
  });

  Future<String?> readEntity({
    required String entityType,
    required String entityId,
  });

  Future<void> deleteEntity({
    required String entityType,
    required String entityId,
  });
}
