import '../offline/offline_persistence.dart';

enum SyncPushDisposition { acknowledged, conflict, failed, retryLater }

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

  /// The server rejected the mutation; it needs attention before a retry.
  const SyncPushResult.failed({required String message})
      : this._(
          disposition: SyncPushDisposition.failed,
          message: message,
        );

  /// Temporary problem (offline, server busy, session expired): keep the
  /// mutation queued and stop this run so later items keep their order.
  const SyncPushResult.retryLater({required String message})
      : this._(
          disposition: SyncPushDisposition.retryLater,
          message: message,
        );

  final SyncPushDisposition disposition;
  final int? serverVersion;
  final String? serverReference;
  final String? message;
}

abstract interface class SyncTransport {
  /// Whether this transport can deliver mutations of [entityType]. Others
  /// stay queued untouched until a later version supports them.
  bool supports(String entityType);

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
    this.deferred = 0,
    this.stoppedReason,
  });

  final int attempted;
  final int acknowledged;
  final int conflicts;
  final int failed;

  /// Mutations left queued because of a temporary problem.
  final int deferred;

  /// Why the run stopped early (e.g. offline), if it did.
  final String? stoppedReason;
}

/// Queue sequence from an outbox id (`OUT-L-<micros>-<sequence>`).
int _sequence(String id) => int.tryParse(id.substring(id.lastIndexOf('-') + 1)) ?? 0;

class SyncWorker {
  const SyncWorker({
    required this.persistence,
    required this.transport,
  });

  final OfflinePersistenceController persistence;
  final SyncTransport transport;

  /// Pushes queued mutations oldest first. Stops at the first temporary
  /// failure so dependent mutations (duty start before pings) keep order.
  Future<SyncRunSummary> runOnce({int limit = 25}) async {
    await persistence.initialize();
    // Oldest first; ties (same clock tick) fall back to the queue sequence
    // in the id, since the local database may list newest first.
    final queued = persistence.outbox
        .where((item) => item.state == SyncState.queued && transport.supports(item.entityType))
        .toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : _sequence(a.id).compareTo(_sequence(b.id));
      });
    final work = queued.take(limit).toList(growable: false);

    var acknowledged = 0;
    var conflicts = 0;
    var failed = 0;
    var attempted = 0;
    String? stoppedReason;

    for (final item in work) {
      attempted += 1;
      await persistence.markSyncing(item.id);
      SyncPushResult result;
      try {
        final payload = await persistence.payloadForOutbox(item.id);
        result = await transport.push(mutation: item, payload: payload);
      } catch (error) {
        result = SyncPushResult.failed(message: error.toString());
      }
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
            result.message ?? 'Server rejected the local mutation because versions conflict.',
          );
          conflicts += 1;
        case SyncPushDisposition.failed:
          await persistence.markFailed(item.id, result.message ?? 'Server synchronization failed.');
          failed += 1;
        case SyncPushDisposition.retryLater:
          await persistence.queueForRetry(item.id);
          stoppedReason = result.message;
      }
      if (stoppedReason != null) break;
    }

    return SyncRunSummary(
      attempted: attempted,
      acknowledged: acknowledged,
      conflicts: conflicts,
      failed: failed,
      deferred: stoppedReason == null ? 0 : 1,
      stoppedReason: stoppedReason,
    );
  }
}
