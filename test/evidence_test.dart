import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/http_sync_transport.dart';
import 'package:tgcg_emcop/tgcg/evidence/evidence_upload.dart';
import 'package:tgcg_emcop/tgcg/evidence/evidence_viewer.dart';
import 'package:tgcg_emcop/tgcg/field/field_operations_store.dart';
import 'package:tgcg_emcop/tgcg/field/incident_actions.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_database_stub.dart' as memory_db;
import 'package:tgcg_emcop/tgcg/offline/offline_payloads.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_persistence.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_worker.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);
final _jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, ...List.filled(60, 0)]);
const _photoId = '9a1e0000-0000-4000-8000-000000000002';

const _unit = {
  'level': 'pollingUnit',
  'country': 'Nigeria',
  'stateId': 'KD',
  'stateName': 'Kaduna',
  'lgaId': 'KD-ZARIA',
  'lgaName': 'Zaria',
  'wardId': '18-23-01',
  'pollingUnitId': '18-23-01-001',
  'pollingUnitName': 'KWARBAI I',
};

const _unitScope = GeographicScope(
  level: GeographyLevel.pollingUnit,
  country: 'Nigeria',
  stateId: 'KD',
  lgaId: 'KD-ZARIA',
  wardId: '18-23-01',
  pollingUnitId: '18-23-01-001',
  pollingUnitName: 'KWARBAI I',
);

Map<String, dynamic> _evidence() => {
      'id': _photoId,
      'type': 'photo',
      'file_name': 'box.png',
      'mime_type': 'image/png',
      'size': 70,
      'content_hash': 'ab' * 32,
      'caption': '',
      'latitude': null,
      'longitude': null,
      'captured_at': null,
      'uploader': 'AG-1',
      'origin': 'localEntry',
      'client_id': null,
      'download_url': 'https://api.tgcg.test/api/v1/evidence/$_photoId/download/',
      'created_at': '2027-02-20T10:01:00Z',
    };

Map<String, dynamic> _incident(String reference, {String? clientId, List<Object> evidence = const []}) => {
      'id': '7d3c1f9e-0000-4000-8000-000000000001',
      'reference': reference,
      'title': 'Ballot box snatched',
      'category': 'Violence / threat',
      'severity': 'high',
      'status': 'reported',
      'is_open': true,
      'scope': _unit,
      'summary': '',
      'assigned_team': '',
      'latitude': null,
      'longitude': null,
      'location': null,
      'reporter': 'AG-1',
      'reported_at': '2027-02-20T10:00:00Z',
      'origin': 'localEntry',
      'client_id': clientId,
      'evidence': evidence,
    };

/// A fake TGCG server that records every request.
class _Server {
  final requests = <http.Request>[];
  http.Response? Function(http.Request request, String key)? answer;

  BackendServices connect() => BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          requests.add(request);
          final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
          final custom = answer?.call(request, key);
          if (custom != null) return custom;
          return switch (key) {
            'GET incidents/' || 'GET field-reports/' =>
              _json({'count': 0, 'next': null, 'previous': null, 'results': []}),
            _ => _json({'detail': 'Not found.'}, 404),
          };
        }),
      );

  http.Request sent(String key) =>
      requests.lastWhere((r) => '${r.method} ${r.url.path.replaceFirst('/api/v1/', '')}' == key);
}

Future<OfflinePersistenceController> _offline() async {
  FlutterSecureStorage.setMockInitialValues({});
  final offline = OfflinePersistenceController(openDatabase: memory_db.openOfflineDatabaseBackend);
  await offline.initialize();
  return offline;
}

void main() {
  test('evidence is named for what it is and fingerprinted', () async {
    final unnamed = await evidenceFromBytes(type: EvidenceType.photo, name: 'blob-42', bytes: _jpeg);
    expect(unnamed.fileName, 'blob-42.jpg');
    expect(unnamed.mimeType, 'image/jpeg');
    final named = await evidenceFromBytes(type: EvidenceType.photo, name: 'IMG_1.JPEG', bytes: _jpeg);
    expect(named.fileName, 'IMG_1.JPEG');
    final png = await evidenceFromBytes(type: EvidenceType.resultForm, name: 'sheet', bytes: _png);
    expect((png.fileName, png.mimeType), ('sheet.png', 'image/png'));
    final abc = await evidenceFromBytes(
      type: EvidenceType.document,
      name: 'notes.txt',
      bytes: Uint8List.fromList(utf8.encode('abc')),
    );
    expect(abc.sha256, 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
  });

  test('a photo uploads after its incident, to the server reference', () async {
    final server = _Server();
    final backend = server.connect();
    final offline = await _offline();
    server.answer = (request, key) => switch (key) {
          'POST incidents/' => _json(
              _incident(
                'INC-000009',
                clientId: (jsonDecode(request.body) as Map<String, dynamic>)['client_id'] as String,
              ),
              201,
            ),
          'POST incidents/INC-000009/evidence/' => _json(_evidence(), 201),
          _ => null,
        };
    final store = FieldOperationsController.prototypeSeed(persistence: offline);
    store.connect(backend.field, account: 'AG-1');
    await store.refreshIfOlderThan(const Duration(hours: 1));

    final photo = await evidenceFromBytes(type: EvidenceType.photo, name: 'box', bytes: _png);
    final incident = await store.createIncident(
      title: 'Ballot box snatched',
      category: 'Violence / threat',
      severity: IncidentSeverity.high,
      scope: _unitScope,
      reporterId: 'AG-1',
      photos: [photo],
    );
    expect(incident.evidence.single.fileName, 'box.png');
    expect(
      offline.pendingOutbox.map((item) => item.entityType),
      unorderedEquals(['field_incident', 'evidence_upload']),
    );

    final worker = SyncWorker(
      persistence: offline,
      transport: HttpSyncTransport(backend.client, accessId: () => 'AG-1', outbox: offline),
    );
    expect((await worker.runOnce()).acknowledged, 2);
    final upload = server.sent('POST incidents/INC-000009/evidence/');
    expect(upload.headers['content-type'], startsWith('multipart/form-data'));
    final body = utf8.decode(upload.bodyBytes, allowMalformed: true);
    expect(body, contains('name="type"\r\n\r\nphoto'));
    expect(body, contains('name="content_hash"\r\n\r\n${photo.sha256}'));
    expect(body, contains('name="client_id"\r\n\r\nAG-1:OUT-L-'));
    expect(body, contains('filename="box.png"'));
  });

  test('a photo whose incident was refused is refused too, without holding others up', () async {
    final server = _Server();
    final backend = server.connect();
    final offline = await _offline();
    server.answer = (request, key) => switch (key) {
          'POST incidents/' => _json({'scope': ['Unknown polling unit.']}, 400),
          'POST field-reports/' => _json({'reference': 'RPT-000001'}, 201),
          _ => null,
        };
    final made = await offline.persistMutation(
      entityType: 'field_incident',
      entityId: 'NEW-1',
      mutationType: SyncMutationType.create,
      payload: fieldIncidentToJson(FieldIncident(
        id: 'NEW-1',
        title: 'Ballot box snatched',
        category: 'Violence / threat',
        severity: IncidentSeverity.high,
        status: IncidentStatus.reported,
        scope: _unitScope,
        reportedAt: DateTime.utc(2027, 2, 20, 10),
        reporterId: 'AG-1',
      )),
    );
    await queueEvidence(
      offline,
      parent: EvidenceParent.incident,
      recordOutboxId: made.outbox.id,
      evidence: await evidenceFromBytes(type: EvidenceType.photo, name: 'box', bytes: _png),
      ownerId: 'AG-1',
    );
    await offline.persistMutation(
      entityType: 'field_report',
      entityId: 'NEW-2',
      mutationType: SyncMutationType.create,
      payload: fieldReportToJson(FieldReport(
        id: 'NEW-2',
        category: 'Opening status',
        summary: 'Opened late.',
        scope: _unitScope,
        reporterId: 'AG-1',
        reportedAt: DateTime.utc(2027, 2, 20, 11),
        status: RecordStatus.submitted,
      )),
    );

    final summary = await SyncWorker(
      persistence: offline,
      transport: HttpSyncTransport(backend.client, accessId: () => 'AG-1', outbox: offline),
    ).runOnce();

    expect((summary.failed, summary.acknowledged), (2, 1));
    final photo = offline.outbox.singleWhere((item) => item.entityType == 'evidence_upload');
    expect(photo.state, SyncState.failed);
    expect(photo.lastError, 'The server refused its record, so this file was not sent.');
  });

  test('a photo for a record already on the server goes straight to it', () async {
    final server = _Server()
      ..answer = (request, key) =>
          key == 'POST results/RES-000001/evidence/' ? _json(_evidence(), 201) : null;
    final backend = server.connect();
    final offline = await _offline();
    await queueEvidence(
      offline,
      parent: EvidenceParent.result,
      reference: 'RES-000001',
      evidence: await evidenceFromBytes(type: EvidenceType.resultForm, name: 'ec8a', bytes: _jpeg),
      ownerId: 'AG-1',
    );
    final summary = await SyncWorker(
      persistence: offline,
      transport: HttpSyncTransport(backend.client, accessId: () => 'AG-1', outbox: offline),
    ).runOnce();
    expect(summary.acknowledged, 1);
    final body = utf8.decode(server.sent('POST results/RES-000001/evidence/').bodyBytes, allowMalformed: true);
    expect(body, contains('name="type"\r\n\r\nresultForm'));
    expect(body, contains('filename="ec8a.jpg"'));
  });

  group('screens', () {
    late _Server server;
    late BackendServices backend;
    late FieldOperationsController store;
    late TgcgSessionController session;

    setUp(() async {
      server = _Server()
        ..answer = (request, key) => switch (key) {
              'GET incidents/' when request.url.queryParameters['open'] == 'true' => _json({
                  'count': 1,
                  'next': null,
                  'previous': null,
                  'results': [
                    _incident('INC-000001', evidence: [_evidence()]),
                  ],
                }),
              'GET evidence/$_photoId/download/' =>
                http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'}),
              _ => null,
            };
      backend = server.connect();
      store = FieldOperationsController.prototypeSeed();
      store.connect(backend.field, account: 'SC-KD');
      await store.refreshIfOlderThan(const Duration(hours: 1));
      session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Kaduna Coordinator',
          accessId: 'SC-KD',
          scope: const GeographicScope(level: GeographyLevel.state, country: 'Nigeria', stateId: 'KD'),
          capabilities: {'viewIncidents', 'viewEvidence', 'manageEvidence'},
        );
    });

    tearDown(() {
      session.dispose();
      store.dispose();
    });

    Future<void> pump(WidgetTester tester, Widget body, {FieldOperationsController? field}) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TgcgBackend(
          services: backend,
          child: TgcgSession(
            controller: session,
            child: FieldOperations(
              controller: field ?? store,
              child: MaterialApp(home: Scaffold(body: body)),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('evidence on the server opens when tapped', (tester) async {
      final incident = store.incidents.single;
      await pump(
        tester,
        Column(children: [EvidenceRow(evidence: incident.evidence.single, icon: Icons.image_outlined)]),
      );
      expect(find.text('View'), findsOneWidget);
      await tester.tap(find.text('box.png'));
      await tester.pumpAndSettle();
      expect(server.requests.last.url.path, '/api/v1/evidence/$_photoId/download/');
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Pinch or scroll to zoom.'), findsOneWidget);
    });

    testWidgets('photos are added to an incident on the server', (tester) async {
      final offline = await tester.runAsync(_offline);
      final local = FieldOperationsController.prototypeSeed(persistence: offline);
      local.connect(backend.field, account: 'SC-KD');
      await tester.runAsync(() => local.refreshIfOlderThan(const Duration(hours: 1)));
      addTearDown(local.dispose);
      final photo = await tester.runAsync(
        () => evidenceFromBytes(type: EvidenceType.photo, name: 'scene', bytes: _png),
      );
      await pump(
        tester,
        IncidentPhotoButton(
          incident: local.incidents.single,
          pick: ({required type, required camera}) async => photo,
        ),
        field: local,
      );
      await tester.tap(find.text('Take photo'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pumpAndSettle();
      final queued = offline!.outbox.singleWhere((item) => item.entityType == 'evidence_upload');
      expect(queued.state, SyncState.queued);
      expect(find.textContaining('Photo saved'), findsOneWidget);
    });

    testWidgets('the photo picker adds and removes photos', (tester) async {
      final photo = await tester.runAsync(
        () => evidenceFromBytes(type: EvidenceType.photo, name: 'scene', bytes: _png),
      );
      var photos = <PendingEvidence>[];
      await pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) => EvidencePhotoPicker(
            photos: photos,
            max: 1,
            pick: ({required type, required camera}) async => photo,
            onChanged: (value) => setState(() => photos = value),
          ),
        ),
      );
      await tester.tap(find.text('Take photo'));
      await tester.pumpAndSettle();
      expect(photos.single.fileName, 'scene.png');
      expect(find.text('Take photo'), findsNothing); // one is the most
      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      expect(photos, isEmpty);
    });
  });
}
