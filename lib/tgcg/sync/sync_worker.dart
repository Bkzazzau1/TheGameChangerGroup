import '../offline/offline_persistence.dart';

enum SyncPushDisposition { acknowledged, conflict, failed }

class SyncPushResult {
  const SyncPushResult._({
    required this.disposition,
    this.serverVersion,
    this.serverReference,
    this.message,
  });

  const SyncPushResult.acknowledged({
    required int serverVersion,
    String? serverReference,
  }) : this._(
          disposition: SyncPushDisposition.acknowledged,
          serverVersion: serverVersion,
          serverReference: serverReference,
        );

  const SyncPushResult.conflict({
    required String message,
    int? serverVersion,
  }) : this._(
          disposition: SyncPushDisposition.conflict,
          message: message,
          serverVersion: serverVersion,
        );

  const SyncPushResult.failed({required String message})
      : this._(
          disposition: SyncPushDisposition.failed,
          message: message,
        );

  final SyncPushDisposition disposition;
  final int? serverVersion;
  final String? serverReference;
  final String? message;
}

abstract interface class SyncTransport {
  Future<SyncPushResult> push({
    required SyncOutboxItem mutation,
    required Map<String, Object?> payload,
  });
}

class SyncRunSummary {
  const SyncRunSummary({
    required this.attempted,
    required this.acknowledged,
    required this.conflicts,
    required this.failed,
  });

  final int attempted;
  final int acknowledged;
  final int conflicts;
  final int failed;
}

class SyncWorker {
  const SyncWorker({
    required this.persistence,
    required this.transport,
  });

  final OfflinePersistenceController persistence;
  final SyncTransport transport;

  Future<SyncRunSummary> runOnce({int limit = 25}) async {
    await persistence.initialize();
    final batch = persistence.outbox
        .where((item) => item.state == SyncState.queued)
        .take(limit)
        .toList(growable: false);

    var acknowledged = 0;
    var conflicts = 0;
    var failed = 0;

    for (final item in batch) {
      await persistence.markSyncing(item.id);
      try {
        final payload = await persistence.payloadForOutbox(item.id);
        final result = await transport.push(
          mutation: item,
          payload: payload,
        );
        switch (result.disposition) {
          case SyncPushDisposition.acknowledged:
            await persistence.acknowledge(
              outboxId: item.id,
              serverVersion: result.serverVersion ?? item.mutationVersion,
              serverReference: result.serverReference,
            );
            acknowledged += 1;
          case SyncPushDisposition.conflict:
            await persistence.markConflict(
              item.id,
              result.message ??
                  'Server rejected the local mutation because versions conflict.',
            );
            conflicts += 1;
          case SyncPushDisposition.failed:
            await persistence.markFailed(
              item.id,
              result.message ?? 'Server synchronization failed.',
            );
            failed += 1;
        }
      } catch (error) {
        await persistence.markFailed(item.id, error.toString());
        failed += 1;
      }
    }

    return SyncRunSummary(
      attempted: batch.length,
      acknowledged: acknowledged,
      conflicts: conflicts,
      failed: failed,
    );
  }
}
