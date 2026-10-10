import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/http_sync_transport.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_database_stub.dart' as memory_db;
import 'package:tgcg_emcop/tgcg/offline/offline_payloads.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_persistence.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_worker.dart';

http.Response _json(Object body, [int status = 201]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

final _gps = GpsFix(
  latitude: 11.0855,
  longitude: 7.7199,
  accuracyMeters: 9,
  capturedAt: DateTime.utc(2027, 2, 20, 9),
);

const _unitScope = GeographicScope(
  level: GeographyLevel.pollingUnit,
  country: 'Nigeria',
  stateId: 'KD',
  lgaId: 'KD-ZARIA',
  wardId: '18-23-01',
  pollingUnitId: '18-23-01-001',
  pollingUnitName: 'KWARBAI I',
);

class _Server {
  final requests = <http.Request>[];
  http.Response Function(http.Request request) respond = (_) => _json({'reference': 'SRV-1'});

  ApiClient client() {
    final tokens = MemoryTokenStore()..write(access: 'A', refresh: 'R');
    return ApiClient(
      baseUrl: 'https://api.tgcg.test',
      tokens: tokens,
      httpClient: MockClient((request) async {
        requests.add(request);
        return respond(request);
      }),
    );
  }

  Map<String, dynamic> body(int index) => jsonDecode(requests[index].body) as Map<String, dynamic>;
  String path(int index) => requests[index].url.path;
}

Future<OfflinePersistenceController> _offline() async {
  FlutterSecureStorage.setMockInitialValues({});
  final offline = OfflinePersistenceController(openDatabase: memory_db.openOfflineDatabaseBackend);
  await offline.initialize();
  return offline;
}

Future<void> _queue(OfflinePersistenceController offline, String type, Map<String, Object?> payload) =>
    offline.persistMutation(
      entityType: type,
      entityId: '$type-${offline.outbox.length}',
      mutationType: SyncMutationType.create,
      payload: payload,
    );

void main() {
  late _Server server;
  late OfflinePersistenceController offline;
  late SyncWorker worker;

  setUp(() async {
    server = _Server();
    offline = await _offline();
    worker = SyncWorker(
      persistence: offline,
      transport: HttpSyncTransport(server.client(), accessId: () => 'AG-1'),
    );
  });

  test('field records are sent to the matching endpoints', () async {
    await _queue(offline, 'field_incident', fieldIncidentToJson(FieldIncident(
      id: 'INC-0001',
      title: 'Ballot snatching',
      category: 'Security',
      severity: IncidentSeverity.critical,
      status: IncidentStatus.reported,
      scope: _unitScope,
      reportedAt: DateTime.utc(2027, 2, 20, 10),
      reporterId: 'AG-1',
      gps: _gps,
    )));
    await _queue(offline, 'field_report', fieldReportToJson(FieldReport(
      id: 'RPT-0001',
      category: 'Agent check-in',
      summary: 'Agent checked in for field duty.',
      scope: _unitScope,
      reporterId: 'AG-1',
      reportedAt: DateTime.utc(2027, 2, 20, 8),
      status: RecordStatus.submitted,
      gps: _gps,
    )));
    await _queue(offline, 'field_report', fieldReportToJson(FieldReport(
      id: 'RPT-0002',
      category: 'Opening status',
      summary: 'Opened 08:10',
      scope: _unitScope,
      reporterId: 'AG-1',
      reportedAt: DateTime.utc(2027, 2, 20, 8, 15),
      status: RecordStatus.submitted,
    )));

    final summary = await worker.runOnce();

    expect(summary.acknowledged, 3);
    expect([for (var i = 0; i < 3; i++) server.path(i)], [
      '/api/v1/incidents/',
      '/api/v1/tracking/check-ins/',
      '/api/v1/field-reports/',
    ]);
    final incident = server.body(0);
    expect(incident['title'], 'Ballot snatching');
    expect(incident['scope'], {
      'level': 'pollingUnit',
      'stateId': 'KD',
      'lgaId': 'KD-ZARIA',
      'wardId': '18-23-01',
      'pollingUnitId': '18-23-01-001',
    });
    expect(incident['gps']['accuracy_m'], 9.0);
    expect(incident['client_id'], startsWith('AG-1:OUT-L-'));
    expect(server.body(1).keys, unorderedEquals(['gps', 'client_id']));
    expect(offline.pendingOutbox, isEmpty);
  });

  test('results need an election and are sent with party votes and GPS', () async {
    final base = ElectionResultSubmission(
      id: 'RES-0001',
      pollingUnitScope: _unitScope,
      submittedBy: 'AG-1',
      submittedAt: DateTime.utc(2027, 2, 20, 16),
      status: RecordStatus.submitted,
      source: SubmissionSource.app,
      partyVotes: const {'APC': 120, 'PDP': 98},
      totalVotesRecorded: 218,
      accreditedVoters: 230,
      rejectedVotes: 7,
      gps: _gps,
    );
    await _queue(offline, 'election_result', resultSubmissionToJson(base));
    final summary = await worker.runOnce();
    expect(summary.failed, 1);
    expect(server.requests, isEmpty);
    expect(offline.outbox.single.lastError, contains('Choose the election'));

    final withElection = ElectionResultSubmission(
      id: 'RES-0002',
      pollingUnitScope: _unitScope,
      submittedBy: 'AG-1',
      submittedAt: DateTime.utc(2027, 2, 20, 16),
      status: RecordStatus.submitted,
      source: SubmissionSource.app,
      partyVotes: const {'APC': 120, 'PDP': 98},
      totalVotesRecorded: 218,
      accreditedVoters: 230,
      rejectedVotes: 7,
      gps: _gps,
      electionCode: '2027-kd-governorship',
    );
    await _queue(offline, 'election_result', resultSubmissionToJson(withElection));
    await worker.runOnce();
    final body = server.body(0);
    expect(server.path(0), '/api/v1/results/');
    expect(body['election'], '2027-kd-governorship');
    expect(body['polling_unit'], '18-23-01-001');
    expect(body['party_votes'], {'APC': 120, 'PDP': 98});
    expect(body['source'], 'app');
    expect(body['gps']['latitude'], 11.0855);
  });

  test('duty changes keep phone time and pings follow in order', () async {
    await _queue(offline, 'duty_start', {'on_duty': true, 'started_at': '2027-02-20T07:00:00.000Z'});
    await _queue(offline, 'location_ping', _gps.toJson());
    await _queue(offline, 'duty_stop', {'on_duty': false, 'ended_at': '2027-02-20T18:00:00.000Z'});
    await worker.runOnce();
    expect(server.body(0), {'on_duty': true, 'at': '2027-02-20T07:00:00.000Z'});
    expect(server.path(1), '/api/v1/tracking/pings/');
    expect(server.body(1)['pings'], hasLength(1));
    expect(server.body(2), {'on_duty': false, 'at': '2027-02-20T18:00:00.000Z'});
  });

  test('offline stops the run and keeps everything queued in order', () async {
    server.respond = (_) => throw http.ClientException('Network is unreachable');
    await _queue(offline, 'duty_start', {'on_duty': true, 'started_at': '2027-02-20T07:00:00Z'});
    await _queue(offline, 'location_ping', _gps.toJson());

    final summary = await worker.runOnce();

    expect(summary.stoppedReason, contains('No connection'));
    expect(server.requests, hasLength(1)); // the ping was not sent ahead of duty start
    expect(offline.pendingOutbox.map((i) => i.state), everyElement(SyncState.queued));

    server.respond = (_) => _json({'on_duty': true});
    final retry = await worker.runOnce();
    expect(retry.acknowledged, 2);
  });

  test('a server refusal is recorded with its message, others continue', () async {
    server.respond = (request) => request.url.path.endsWith('/incidents/')
        ? _json({'category': ['"Gossip" is not a valid choice.']}, 400)
        : _json({'stored': 1});
    await _queue(offline, 'field_incident', {
      'title': 'x',
      'category': 'Gossip',
      'severity': 'low',
      'scope': geographicScopeToJson(_unitScope),
    });
    await _queue(offline, 'location_ping', _gps.toJson());

    final summary = await worker.runOnce();

    expect(summary.failed, 1);
    expect(summary.acknowledged, 1);
    final refused = offline.outbox.firstWhere((item) => item.entityType == 'field_incident');
    expect(refused.state, SyncState.failed);
    expect(refused.lastError, '"Gossip" is not a valid choice.');
  });

  test('record types the server does not handle yet stay queued untouched', () async {
    await _queue(offline, 'communication_message', {'text': 'hello'});
    final summary = await worker.runOnce();
    expect(summary.attempted, 0);
    expect(server.requests, isEmpty);
    expect(offline.outbox.single.state, SyncState.queued);
  });
}
