import '../offline/offline_persistence.dart';
import '../sync/sync_worker.dart';
import 'api_client.dart';

/// Delivers offline-outbox mutations to the TGCG backend.
///
/// Each upload carries a stable `client_id` derived from the outbox entry,
/// so a retry after a dropped connection never creates a duplicate.
class HttpSyncTransport implements SyncTransport {
  HttpSyncTransport(this.client, {required this.accessId});

  final ApiClient client;

  /// The signed-in account; prefixes client ids so devices never collide.
  final String Function() accessId;

  static const _handlers = {
    'field_incident',
    'field_report',
    'election_result',
    'duty_start',
    'duty_stop',
    'location_ping',
  };

  @override
  bool supports(String entityType) => _handlers.contains(entityType);

  @override
  Future<SyncPushResult> push({
    required SyncOutboxItem mutation,
    required Map<String, Object?> payload,
  }) async {
    if (mutation.mutationType != SyncMutationType.create) {
      // Status changes are made online against server records.
      return const SyncPushResult.failed(
        message: 'Only new records sync from this device; make changes while online.',
      );
    }
    final clientId = _clientId(mutation);
    try {
      final body = await switch (mutation.entityType) {
        'field_incident' => client.post('incidents/', body: _incident(payload, clientId)),
        'field_report' when payload['category'] == 'Agent check-in' =>
          client.post('tracking/check-ins/', body: _checkIn(payload, clientId)),
        'field_report' => client.post('field-reports/', body: _report(payload, clientId)),
        'election_result' => client.post('results/', body: _result(payload, clientId)),
        'duty_start' => client.post(
            'tracking/duty/',
            body: {'on_duty': true, 'at': payload['started_at']},
          ),
        'duty_stop' => client.post(
            'tracking/duty/',
            body: {'on_duty': false, 'at': payload['ended_at']},
          ),
        'location_ping' => client.post('tracking/pings/', body: {'pings': [payload]}),
        _ => throw StateError('Unsupported ${mutation.entityType}'),
      };
      return SyncPushResult.acknowledged(
        serverVersion: mutation.mutationVersion,
        serverReference: _reference(body),
      );
    } on _MissingData catch (error) {
      return SyncPushResult.failed(message: error.message);
    } on ApiException catch (error) {
      if (error.isOffline || error.isUnauthorized || error.statusCode >= 500 || error.statusCode == 429) {
        return SyncPushResult.retryLater(message: error.message);
      }
      if (error.statusCode == 409) return SyncPushResult.conflict(message: error.message);
      return SyncPushResult.failed(message: error.message);
    }
  }

  String _clientId(SyncOutboxItem mutation) {
    final id = '${accessId()}:${mutation.id}';
    return id.length <= 64 ? id : id.substring(id.length - 64);
  }

  static String? _reference(Object? body) {
    if (body is! Map) return null;
    return (body['reference'] ?? body['id'] ?? body['agent_id'])?.toString();
  }

  /// Only the scope's level and unit ids are sent; the server derives names
  /// and parent units, and rejects codes it does not know.
  static Map<String, Object?>? _scope(Object? scope) {
    if (scope is! Map) return null;
    return {
      for (final key in const [
        'level',
        'zoneId',
        'stateId',
        'senatorialDistrictId',
        'lgaId',
        'wardId',
        'pollingUnitId',
      ])
        if (scope[key] != null) key: scope[key],
    };
  }

  static Map<String, Object?> _incident(Map<String, Object?> p, String clientId) => {
        'title': p['title'],
        'category': p['category'],
        'severity': p['severity'],
        'summary': p['summary'] ?? '',
        'scope': _scope(p['scope']),
        'reported_at': p['reportedAt'],
        'gps': p['gps'],
        'client_id': clientId,
      }..removeWhere((_, value) => value == null);

  static Map<String, Object?> _report(Map<String, Object?> p, String clientId) => {
        'category': p['category'],
        'summary': p['summary'],
        'scope': _scope(p['scope']),
        'reported_at': p['reportedAt'],
        'client_id': clientId,
      }..removeWhere((_, value) => value == null);

  static Map<String, Object?> _checkIn(Map<String, Object?> p, String clientId) {
    if (p['gps'] == null) {
      throw const _MissingData('This check-in has no GPS reading. Check in again with location on.');
    }
    return {'gps': p['gps'], 'client_id': clientId};
  }

  static Map<String, Object?> _result(Map<String, Object?> p, String clientId) {
    final election = p['electionCode'];
    if (election == null) {
      throw const _MissingData('Choose the election this result belongs to, then submit it again.');
    }
    final scope = p['pollingUnitScope'];
    final pollingUnit = scope is Map ? scope['pollingUnitId'] : null;
    return {
      'election': election,
      'polling_unit': pollingUnit,
      'party_votes': p['partyVotes'],
      'total_valid_votes': p['totalVotesRecorded'],
      'accredited_voters': p['accreditedVoters'],
      'rejected_votes': p['rejectedVotes'],
      'registered_voters': p['registeredVoters'],
      'source': p['source'],
      'source_reference': p['sourceReference'] ?? '',
      'submitted_at': p['submittedAt'],
      'gps': p['gps'],
      'client_id': clientId,
    }..removeWhere((_, value) => value == null);
  }
}

class _MissingData implements Exception {
  const _MissingData(this.message);
  final String message;
}
