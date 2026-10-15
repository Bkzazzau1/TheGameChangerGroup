import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/field_repository.dart';
import 'package:tgcg_emcop/tgcg/api/http_sync_transport.dart';
import 'package:tgcg_emcop/tgcg/evidence/evidence_upload.dart';
import 'package:tgcg_emcop/tgcg/evidence/evidence_viewer.dart';
import 'package:tgcg_emcop/tgcg/evidence/voice_note.dart';
import 'package:tgcg_emcop/tgcg/field/incident_actions.dart';
import 'package:tgcg_emcop/tgcg/field/field_monitoring_page.dart';
import 'package:tgcg_emcop/tgcg/field/field_operations_store.dart';
import 'package:tgcg_emcop/tgcg/field/situation_room_page.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/location/gps_service.dart';
import 'package:tgcg_emcop/tgcg/membership/membership_store.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_database_stub.dart' as memory_db;
import 'package:tgcg_emcop/tgcg/offline/offline_payloads.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_persistence.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_worker.dart';

/// Location off until a [fix] is set.
class _FakeGps extends GpsService {
  GpsFix? fix;

  @override
  Future<GpsFix> currentFix({Duration timeout = const Duration(seconds: 20)}) async {
    final reading = fix;
    if (reading == null) throw const GpsUnavailable(GpsProblem.serviceOff);
    return reading;
  }
}

class _FakeRecorder implements VoiceRecorder {
  @override
  Future<bool> start() async => true;

  @override
  Future<PendingEvidence?> stop() async => PendingEvidence(
        type: EvidenceType.audio,
        fileName: 'voice-note.m4a',
        mimeType: 'audio/mp4',
        bytes: Uint8List.fromList([0, 0, 0, 24, 102, 116, 121, 112]),
        sha256: 'ab' * 32,
        takenAt: DateTime.utc(2027, 2, 20, 10),
      );

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _unit = {
  'level': 'pollingUnit',
  'country': 'Nigeria',
  'zoneId': 'NW',
  'zoneName': 'North West',
  'stateId': 'KD',
  'stateName': 'Kaduna',
  'lgaId': 'KD-ZARIA',
  'lgaName': 'Zaria',
  'wardId': '18-23-01',
  'wardName': 'KWARBAI "A"',
  'pollingUnitId': '18-23-01-001',
  'pollingUnitName': 'KWARBAI I',
};

const _kaduna = GeographicScope(
  level: GeographyLevel.state,
  country: 'Nigeria',
  zoneId: 'NW',
  zoneName: 'North West',
  stateId: 'KD',
  stateName: 'Kaduna',
);

const _unitScope = GeographicScope(
  level: GeographyLevel.pollingUnit,
  country: 'Nigeria',
  zoneId: 'NW',
  stateId: 'KD',
  stateName: 'Kaduna',
  lgaId: 'KD-ZARIA',
  lgaName: 'Zaria',
  wardId: '18-23-01',
  wardName: 'KWARBAI "A"',
  pollingUnitId: '18-23-01-001',
  pollingUnitName: 'KWARBAI I',
);

final _gps = GpsFix(
  latitude: 11.0855,
  longitude: 7.7199,
  accuracyMeters: 9,
  capturedAt: DateTime.utc(2027, 2, 20, 9),
);

Map<String, dynamic> _incident(
  String reference, {
  String status = 'reported',
  String severity = 'high',
  String team = '',
  String? clientId,
}) =>
    {
      'id': '7d3c1f9e-0000-4000-8000-000000000001',
      'reference': reference,
      'title': 'Ballot box snatched',
      'category': 'Violence / threat',
      'severity': severity,
      'status': status,
      'is_open': status != 'resolved' && status != 'closed',
      'scope': _unit,
      'summary': 'Thugs took the box at 11:20.',
      'assigned_team': team,
      'latitude': '11.085500',
      'longitude': '7.719900',
      'location': {
        'latitude': '11.085500',
        'longitude': '7.719900',
        'accuracy_m': 9.0,
        'captured_at': '2027-02-20T10:00:00Z',
        'is_mocked': false,
        'distance_to_pu_m': 12,
        'status': 'onSite',
      },
      'reporter': 'AG-1',
      'reported_at': '2027-02-20T10:00:00Z',
      'acknowledged_at': null,
      'resolved_at': null,
      'closed_at': null,
      'origin': 'localEntry',
      'client_id': clientId,
      'evidence': [
        {
          'id': '9a1e0000-0000-4000-8000-000000000002',
          'type': 'photo',
          'file_name': 'box.jpg',
          'mime_type': 'image/jpeg',
          'size': 2048,
          'content_hash': 'ab' * 32,
          'caption': '',
          'latitude': null,
          'longitude': null,
          'captured_at': null,
          'uploader': 'AG-1',
          'origin': 'localEntry',
          'client_id': null,
          'download_url': 'https://api.tgcg.test/api/v1/evidence/9a1e/download/',
          'created_at': '2027-02-20T10:01:00Z',
        },
      ],
      'created_at': '2027-02-20T10:00:05Z',
      'updated_at': '2027-02-20T10:00:05Z',
    };

Map<String, dynamic> _report(
  String reference, {
  String status = 'submitted',
  String reporter = 'AG-1',
  String? clientId,
}) =>
    {
      'id': '5b2d0000-0000-4000-8000-000000000003',
      'reference': reference,
      'category': 'Opening status',
      'summary': 'Opened 08:10 with all materials.',
      'status': status,
      'scope': _unit,
      'incident': null,
      'reporter': reporter,
      'reported_at': '2027-02-20T08:15:00Z',
      'reviewed_by': null,
      'reviewed_at': null,
      'review_reason': '',
      'origin': 'localEntry',
      'client_id': clientId,
      'evidence': [],
      'created_at': '2027-02-20T08:15:05Z',
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> results, [int? count]) =>
    {'count': count ?? results.length, 'next': null, 'previous': null, 'results': results};

/// A fake TGCG server holding incidents and reports.
class _FieldServer {
  var open = <Map<String, dynamic>>[];
  var closed = <Map<String, dynamic>>[];
  var reports = <Map<String, dynamic>>[];
  int? openCount;

  /// Answers before the defaults (null: use them).
  http.Response? Function(String key, Map<String, dynamic>? body)? answer;

  /// While set, answers (decided when asked) wait for it.
  Future<void>? hold;

  final requests = <Uri>[];
  final bodies = <String, Map<String, dynamic>>{};

  BackendServices connect() => BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          requests.add(request.url);
          final wait = hold;
          final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
          final body = request.method == 'POST'
              ? jsonDecode(request.body) as Map<String, dynamic>
              : null;
          if (body != null) bodies[key] = body;
          final query = request.url.queryParameters;
          final response = answer?.call(key, body) ??
              switch (key) {
                'GET incidents/' when query['open'] == 'true' => _json(_page(open, openCount)),
                'GET incidents/' => _json(_page(closed)),
                'GET field-reports/' => _json(_page(reports)),
                _ => _json({'detail': 'Not found.'}, 404),
              };
          if (wait != null) await wait;
          return response;
        }),
      );
}

Future<OfflinePersistenceController> _offline() async {
  FlutterSecureStorage.setMockInitialValues({});
  final offline = OfflinePersistenceController(openDatabase: memory_db.openOfflineDatabaseBackend);
  await offline.initialize();
  return offline;
}

/// Connects [store] and waits for the first load.
Future<void> _connect(FieldOperationsController store, BackendServices backend) async {
  store.connect(backend.field, account: 'SC-KD');
  await store.refreshIfOlderThan(const Duration(hours: 1));
}

void main() {
  test('incidents, reports and history read from the server', () {
    final incident = fieldIncidentFromJson(_incident('INC-000001', clientId: 'AG-1:OUT-L-1'));
    expect(incident.id, 'INC-000001');
    expect(incident.severity, IncidentSeverity.high);
    expect(incident.status, IncidentStatus.reported);
    expect(incident.scope.pollingUnitId, '18-23-01-001');
    expect(incident.assignedTeam, isNull);
    expect(incident.latitude, 11.0855);
    expect(incident.gps!.accuracyMeters, 9);
    expect(incident.evidence.single.fileName, 'box.jpg');
    expect(incident.clientId, 'AG-1:OUT-L-1');

    final report = fieldReportFromJson(_report('RPT-000001'));
    expect(report.status, RecordStatus.submitted);
    expect(report.incidentId, isNull);

    final step = IncidentHistoryEntry.fromJson({
      'action': 'statusChanged',
      'from_status': 'reported',
      'to_status': 'acknowledged',
      'note': '',
      'actor': 'SC-KD',
      'created_at': '2027-02-20T10:05:00Z',
    });
    expect(step.fromStatus, IncidentStatus.reported);
    expect(step.toStatus, IncidentStatus.acknowledged);
    expect(step.actor, 'SC-KD');
  });

  test('a server session shows the server records instead of the samples', () async {
    final server = _FieldServer()
      ..open = [_incident('INC-000002', severity: 'critical')]
      ..closed = [_incident('INC-000001', status: 'closed')]
      ..reports = [_report('RPT-000001')]
      ..openCount = 600;
    final store = FieldOperationsController.prototypeSeed();
    expect(store.incidents, hasLength(4));

    await _connect(store, server.connect());

    expect(store.isLive, isTrue);
    expect(store.loadError, isNull);
    expect([for (final item in store.incidents) item.id], ['INC-000002', 'INC-000001']);
    expect([for (final item in store.reports) item.id], ['RPT-000001']);
    expect(store.openOnServer, 600);
    final urgent = server.requests.firstWhere((url) => url.queryParameters['open'] == 'true');
    expect(urgent.queryParameters['ordering'], '-severity_rank,-reported_at');
    expect(urgent.queryParameters['limit'], '500');

    store.disconnect();
    expect(store.isLive, isFalse);
    expect(store.incidents, hasLength(4));
  });

  test('a load that ends after the session changed is dropped', () async {
    final slow = Completer<void>();
    final server = _FieldServer()
      ..open = [_incident('INC-000001')]
      ..hold = slow.future;
    final backend = server.connect();
    final store = FieldOperationsController.prototypeSeed();
    store.connect(backend.field, account: 'SC-KD'); // its answers wait

    store.disconnect();
    server
      ..hold = null
      ..open = [_incident('INC-000002')];
    store.connect(backend.field, account: 'LC-ZARIA');
    await store.refreshIfOlderThan(const Duration(hours: 1));
    slow.complete();
    await pumpEventQueue();

    expect([for (final item in store.incidents) item.id], ['INC-000002']);
    expect(store.loading, isFalse);
  });

  test('a failed load says why and keeps the page usable', () async {
    final server = _FieldServer()
      ..answer = (key, _) => _json({'detail': 'The server had a problem.'}, 500);
    final store = FieldOperationsController.prototypeSeed();
    await _connect(store, server.connect());
    expect(store.loadError, 'The server had a problem.');
    expect(store.incidents, isEmpty);
    expect(store.loading, isFalse);
  });

  test('changes are made on the server and its answer replaces the record', () async {
    final server = _FieldServer()
      ..open = [_incident('INC-000001')]
      ..reports = [_report('RPT-000001')];
    server.answer = (key, body) => switch (key) {
          'POST incidents/INC-000001/status/' when body!['note'] == '' =>
            _json({'note': ['A note is required for this change.']}, 400),
          'POST incidents/INC-000001/status/' =>
            _json(_incident('INC-000001', status: body!['status'] as String)),
          'POST incidents/INC-000001/assign/' =>
            _json(_incident('INC-000001', status: 'assigned', team: body!['team'] as String)),
          'POST field-reports/RPT-000001/review/' => _json(_report('RPT-000001', status: 'verified')),
          'GET incidents/INC-000001/events/' => _json([
              {
                'action': 'reported',
                'from_status': '',
                'to_status': 'reported',
                'note': '',
                'actor': 'AG-1',
                'created_at': '2027-02-20T10:00:00Z',
              },
            ]),
          _ => null,
        };
    final store = FieldOperationsController.prototypeSeed();
    await _connect(store, server.connect());

    await expectLater(
      store.changeIncidentStatus('INC-000001', IncidentStatus.escalated),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('note'))),
    );
    expect(store.incidents.single.status, IncidentStatus.reported);

    await store.changeIncidentStatus('INC-000001', IncidentStatus.escalated, note: 'Police called');
    expect(server.bodies['POST incidents/INC-000001/status/'], {
      'status': 'escalated',
      'note': 'Police called',
    });
    expect(store.incidents.single.status, IncidentStatus.escalated);

    await store.assignIncident('INC-000001', 'Zaria Response Desk');
    expect(server.bodies['POST incidents/INC-000001/assign/'], {
      'team': 'Zaria Response Desk',
      'note': '',
    });
    expect(store.incidents.single.assignedTeam, 'Zaria Response Desk');

    await store.reviewReport('RPT-000001', accepted: true);
    expect(server.bodies['POST field-reports/RPT-000001/review/'], {'accepted': true, 'reason': ''});
    expect(store.reports.single.status, RecordStatus.verified);

    final history = await store.incidentHistory('INC-000001');
    expect(history.single.action, 'reported');
  });

  test('presentation mode changes stay on the device', () async {
    final store = FieldOperationsController.prototypeSeed();
    await store.assignIncident('INC-0004', 'Kano Desk');
    final incident = store.incidents.firstWhere((item) => item.id == 'INC-0004');
    expect(incident.status, IncidentStatus.assigned);
    expect(incident.assignedTeam, 'Kano Desk');
    await store.reviewReport('RPT-0003', accepted: false, reason: 'Wrong unit');
    expect(store.reports.firstWhere((item) => item.id == 'RPT-0003').status, RecordStatus.rejected);
    expect(await store.incidentHistory('INC-0004'), isEmpty);
  });

  test('a record made here stays on the device until the server copy replaces it', () async {
    final server = _FieldServer();
    final backend = server.connect();
    final offline = await _offline();
    server.answer = (key, body) {
      if (key == 'POST incidents/') {
        final made = _incident('INC-000009', clientId: body!['client_id'] as String);
        server.open = [made];
        return _json(made, 201);
      }
      if (key == 'POST tracking/check-ins/') return _json({'id': 'c1'}, 201);
      return null;
    };
    final store = FieldOperationsController.prototypeSeed(persistence: offline);
    await _connect(store, backend);

    final incident = await store.createIncident(
      title: 'Ballot box snatched',
      category: 'Violence / threat',
      severity: IncidentSeverity.critical,
      scope: _unitScope,
      reporterId: 'SC-KD',
      gps: _gps,
    );
    final checkIn = await store.submitFieldReport(
      category: 'Agent check-in',
      summary: 'Checked in.',
      scope: _unitScope,
      reporterId: 'SC-KD',
      gps: _gps,
    );
    expect(store.isOnDevice(incident.id), isTrue);
    expect(store.uploadStatus(incident.id), startsWith('Saved on this device'));

    final worker = SyncWorker(
      persistence: offline,
      transport: HttpSyncTransport(backend.client, accessId: () => 'SC-KD'),
    );
    expect((await worker.runOnce()).acknowledged, 2);
    // The upload prompts a load; wait for it.
    await store.refreshIfOlderThan(const Duration(hours: 1));

    expect(store.isOnDevice(incident.id), isFalse);
    expect([for (final item in store.incidents) item.id], ['INC-000009']);
    // Check-ins never come back as field reports, so the one made here stays
    // (the agent's screen reads it to know they checked in).
    expect(store.reports.single.id, checkIn.id);
    expect(store.uploadStatus(checkIn.id), 'Uploaded to the server.');
  });

  test('reports link only to incidents the server holds', () async {
    final server = _FieldServer()..answer = (key, body) => _json({'reference': 'RPT-000001'}, 201);
    final backend = server.connect();
    final offline = await _offline();
    final worker = SyncWorker(
      persistence: offline,
      transport: HttpSyncTransport(backend.client, accessId: () => 'SC-KD'),
    );
    for (final (id, linked) in [('RPT-1', 'INC-000012'), ('RPT-2', 'INC-0002'), ('RPT-3', 'NEW-K2J9')]) {
      await offline.persistMutation(
        entityType: 'field_report',
        entityId: id,
        mutationType: SyncMutationType.create,
        payload: fieldReportToJson(FieldReport(
          id: id,
          category: 'Operational update',
          summary: 'Police arrived.',
          scope: _unitScope,
          reporterId: 'SC-KD',
          reportedAt: DateTime.utc(2027, 2, 20, 11),
          status: RecordStatus.submitted,
          incidentId: linked,
        )),
      );
      await worker.runOnce();
      final sent = server.bodies['POST field-reports/']!;
      expect(sent['incident'], linked == 'INC-000012' ? 'INC-000012' : isNull, reason: linked);
      expect(sent['client_id'], startsWith('SC-KD:OUT-L-'));
    }
    expect(syncClientId('SC-KD', 'OUT-L-1'), 'SC-KD:OUT-L-1');
    expect(syncClientId('A' * 60, 'OUT-L-1'), hasLength(64));
  });

  group('pages', () {
    late _FieldServer server;
    late BackendServices backend;
    late FieldOperationsController store;
    late TgcgSessionController session;

    setUp(() async {
      server = _FieldServer()
        ..open = [_incident('INC-000001')]
        ..reports = [_report('RPT-000001')];
      server.answer = (key, body) => switch (key) {
            'POST incidents/INC-000001/status/' =>
              _json(_incident('INC-000001', status: body!['status'] as String)),
            'POST field-reports/RPT-000001/review/' =>
              _json(_report('RPT-000001', status: body!['accepted'] == true ? 'verified' : 'rejected')),
            'GET incidents/INC-000001/events/' => _json([
                {
                  'action': 'reported',
                  'from_status': '',
                  'to_status': 'reported',
                  'note': '',
                  'actor': 'AG-1',
                  'created_at': '2027-02-20T10:00:00Z',
                },
              ]),
            _ => null,
          };
      backend = server.connect();
      store = FieldOperationsController.prototypeSeed();
      await _connect(store, backend);
      session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Kaduna Coordinator',
          accessId: 'SC-KD',
          scope: _kaduna,
          capabilities: {
            'viewIncidents',
            'createIncident',
            'acknowledgeIncident',
            'assignIncident',
            'closeIncident',
            'submitFieldReport',
            'verifyFieldReport',
            'viewSituationRoom',
          },
        );
    });

    tearDown(() {
      session.dispose();
      store.dispose();
    });

    Future<void> pump(
      WidgetTester tester,
      Widget page, {
      bool settle = true,
      Size size = const Size(1300, 4200),
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TgcgBackend(
          services: backend,
          child: TgcgSession(
            controller: session,
            child: MembershipOperations(
              controller: MembershipOperationsController.prototypeSeed(
                GeographyRegistry.prototypeSeed(),
              ),
              child: FieldOperations(
                controller: store,
                child: MaterialApp(home: Scaffold(body: page)),
              ),
            ),
          ),
        ),
      );
      if (settle) {
        await tester.pumpAndSettle();
      } else {
        // The map's state shapes load from an asset, which a widget test
        // does not finish; give the server calls a few frames instead.
        for (var frame = 0; frame < 5; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }
    }

    testWidgets('Field Monitoring acts on server incidents and reviews reports', (tester) async {
      await pump(tester, const FieldMonitoringPage());

      expect(find.text('LIVE FROM SERVER'), findsOneWidget);
      expect(find.text('Ballot box snatched'), findsWidgets);
      expect(find.textContaining('Demo data'), findsNothing);
      // How far from its polling unit it was reported, as the server judged.
      expect(find.text('At the polling unit (12 m away)'), findsOneWidget);
      // A reported incident can be acknowledged, escalated or closed, or given a team.
      for (final action in ['Acknowledge', 'Escalate', 'Close', 'Assign team']) {
        expect(find.text(action), findsOneWidget, reason: action);
      }
      expect(find.text('Resolve'), findsNothing);
      // The history comes from the server.
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Reported'), findsWidgets);

      await tester.tap(find.text('Escalate'));
      await tester.pumpAndSettle();
      expect(find.text('Escalate INC-000001'), findsOneWidget);
      final confirm = find.widgetWithText(FilledButton, 'Escalate');
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull); // a note is needed
      await tester.enterText(find.byType(TextField).last, 'Police called to the unit');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(server.bodies['POST incidents/INC-000001/status/'], {
        'status': 'escalated',
        'note': 'Police called to the unit',
      });
      expect(find.text('INC-000001 escalated.'), findsOneWidget);
      expect(store.incidents.single.status, IncidentStatus.escalated);

      expect(find.text('Reports to review'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
      await tester.pumpAndSettle();
      expect(server.bodies['POST field-reports/RPT-000001/review/'], {
        'accepted': true,
        'reason': '',
      });
      expect(find.text('Nothing to review'), findsOneWidget);
    });

    testWidgets('on a phone, the incident and field report forms fit their words', (tester) async {
      await pump(tester, const FieldMonitoringPage(), size: const Size(360, 3000));
      Finder inDialog(Finder finder) =>
          find.descendant(of: find.byType(AlertDialog), matching: finder);

      await tester.tap(find.text('Report incident'));
      await tester.pumpAndSettle();
      expect(find.text('Report field incident'), findsOneWidget);
      // Side by side neither has room for its words, so Severity goes below.
      expect(
        tester.getTopLeft(inDialog(find.text('Severity'))).dy,
        greaterThan(tester.getTopLeft(inDialog(find.text('Category'))).dy),
      );
      // The longest category fits once chosen (an overflow fails the test).
      await tester.tap(inDialog(find.byType(DropdownButtonFormField<String>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Materials / logistics').last);
      await tester.pumpAndSettle();
      await tester.tap(inDialog(find.byType(DropdownButtonFormField<IncidentSeverity>)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Critical').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Field report'));
      await tester.pumpAndSettle();
      expect(find.text('Submit field report'), findsOneWidget);
      await tester.tap(inDialog(find.byType(DropdownButtonFormField<String>)).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Queue / turnout observation').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('from a polling unit an incident needs GPS and may carry a voice note', (
      tester,
    ) async {
      session.dispose();
      session = TgcgSessionController()
        ..signInFromServer(
          role: TgcgRole.pollingUnitAgent,
          fullName: 'Polling Agent',
          accessId: 'AG-1',
          scope: _unitScope,
          capabilities: {'createIncident', 'submitFieldReport', 'viewIncidents'},
        );
      final gps = _FakeGps();
      await pump(
        tester,
        FieldMonitoringPage(gps: gps, newVoiceRecorder: _FakeRecorder.new),
        size: const Size(420, 3000),
      );
      // Their own incident on the server can go live.
      expect(find.text('Go live'), findsOneWidget);
      await tester.tap(find.text('Report incident'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Incident title'), 'Box snatched');

      // A voice note to explain it.
      await tester.tap(find.text('Record a voice note'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Stop'));
      await tester.pumpAndSettle();
      expect(find.text('Voice note · 0:00'), findsOneWidget);

      // With location off it cannot be sent from the polling unit.
      await tester.tap(find.text('Save incident'));
      await tester.pumpAndSettle();
      expect(find.text('Location needed to report this incident'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel').last);
      await tester.pumpAndSettle();
      expect(find.text('Report field incident'), findsOneWidget);

      gps.fix = _gps;
      await tester.tap(find.text('Save incident'));
      await tester.pumpAndSettle();
      expect(find.text('Report field incident'), findsNothing);
      final saved = store.incidents.firstWhere((item) => item.title == 'Box snatched');
      expect(saved.gps?.latitude, _gps.latitude);
      expect(saved.evidence.single.type, EvidenceType.audio);
      expect(find.textContaining('with a voice note'), findsOneWidget);
    });

    testWidgets('a live incident offers its video to those who can see it', (tester) async {
      server.open = [
        {
          ..._incident('INC-000001'),
          'live': {
            'id': 'l1',
            'is_live': true,
            'started_by': 'AG-1',
            'started_at': '2027-02-20T10:00:00Z',
            'ended_at': null,
            'recording': 'recording',
          },
        },
      ];
      await tester.runAsync(() => store.refresh());
      await pump(tester, const FieldMonitoringPage());
      expect(find.text('LIVE'), findsWidgets);
      expect(find.text('Watch live'), findsOneWidget);
      expect(find.text('Go live'), findsNothing); // only its reporter broadcasts
    });

    testWidgets('the Situation Room shows the server incidents', (tester) async {
      await pump(tester, const SituationRoomPage(), settle: false);
      expect(find.text('LIVE FROM SERVER'), findsOneWidget);
      expect(find.text('DEMO FEED'), findsNothing);
      expect(find.text('Ballot box snatched'), findsWidgets);
      expect(find.text('Acknowledge'), findsOneWidget);
    });

    testWidgets('a role without incident powers sees no command actions', (tester) async {
      session.updateAccess(capabilities: {'viewIncidents', 'viewSituationRoom'}, grants: const []);
      await pump(tester, const FieldMonitoringPage());
      expect(find.text('Ballot box snatched'), findsWidgets);
      for (final action in ['Acknowledge', 'Escalate', 'Close', 'Assign team', 'Reports to review']) {
        expect(find.text(action), findsNothing, reason: action);
      }
    });
  });

  test('an incident says where it was reported, against its polling unit', () {
    FieldIncident at(String? status, [int? meters]) => FieldIncident(
          id: 'INC-1',
          title: 'Box',
          category: 'Security',
          severity: IncidentSeverity.high,
          status: IncidentStatus.reported,
          scope: _unitScope,
          reportedAt: DateTime.utc(2027, 2, 20),
          reporterId: 'AG-1',
          locationStatus: status,
          distanceToUnitMeters: meters,
        );
    expect(incidentLocationText(at('onSite', 40)), 'At the polling unit (40 m away)');
    expect(incidentLocationText(at('away', 1850)), '1.9 km from the polling unit');
    expect(incidentLocationText(at('unverified')), 'The polling unit is not mapped yet');
    expect(incidentLocationText(at('unverified', 90)), 'About 90 m from the polling unit (weak GPS)');
    expect(incidentLocationText(at('suspect')), 'The location may be faked');
    expect(incidentLocationText(at('noGps')), 'No GPS');
    expect(incidentLocationText(at(null)), isNull);
  });

  test('voice notes and videos on the server can be played', () {
    EvidenceAttachment evidence(String id, EvidenceType type) => EvidenceAttachment(
          id: id,
          type: type,
          fileName: 'note.m4a',
          createdAt: DateTime.utc(2027, 2, 20),
          uploaderId: 'AG-1',
        );
    const server = '9a1e0000-0000-4000-8000-000000000002';
    expect(canPlayEvidence(evidence(server, EvidenceType.audio)), isTrue);
    expect(canPlayEvidence(evidence(server, EvidenceType.video)), isTrue);
    expect(canPlayEvidence(evidence(server, EvidenceType.photo)), isFalse);
    expect(canPlayEvidence(evidence('INC-L-1-PHOTO-1', EvidenceType.audio)), isFalse);
  });
}
