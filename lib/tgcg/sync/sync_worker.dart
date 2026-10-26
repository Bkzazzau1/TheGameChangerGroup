import '../offline/offline_persistence.dart';

enum SyncPushDisposition { acknowledged, conflict, failed, retryLater }

class SyncPushResult {
  const SyncPushResult._({
    required this.disposition,
    this.serverVersion,
    this.serverReference,
    this.message,
    this.retryAfter,
    this.serverTrouble = false,
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
  /// [serverTrouble]: the server could not be reached or was busy, so the
  /// phone waits longer before trying again; false when only another record
  /// must go first. [retryAfter]: how long the server asked it to wait.
  const SyncPushResult.retryLater({required String message, Duration? retryAfter, bool serverTrouble = true})
      : this._(
          disposition: SyncPushDisposition.retryLater,
          message: message,
          retryAfter: retryAfter,
          serverTrouble: serverTrouble,
        );

  final SyncPushDisposition disposition;
  final int? serverVersion;
  final String? serverReference;
  final String? message;
  final Duration? retryAfter;
  final bool serverTrouble;
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
    this.serverTrouble = false,
    this.retryAfter,
  });

  final int attempted;
  final int acknowledged;
  final int conflicts;
  final int failed;

  /// Mutations left queued because of a temporary problem.
  final int deferred;

  /// Why the run stopped early (e.g. offline), if it did.
  final String? stoppedReason;

  /// It stopped because the server could not be reached or was busy.
  final bool serverTrouble;

  /// How long the server asked to be left alone, if it said.
  final Duration? retryAfter;
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
    var serverTrouble = false;
    Duration? retryAfter;

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
          serverTrouble = result.serverTrouble;
          retryAfter = result.retryAfter;
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
      serverTrouble: serverTrouble,
      retryAfter: retryAfter,
    );
  }
}
