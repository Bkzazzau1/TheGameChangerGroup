import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/http_sync_transport.dart';
import 'package:tgcg_emcop/tgcg/api/results_repository.dart';
import 'package:tgcg_emcop/tgcg/collation/collation_page.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/membership/membership_store.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_database_stub.dart' as memory_db;
import 'package:tgcg_emcop/tgcg/offline/offline_persistence.dart';
import 'package:tgcg_emcop/tgcg/results/result_capture_page.dart';
import 'package:tgcg_emcop/tgcg/results/result_operations_store.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_worker.dart';

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

const _kadunaJson = {
  'level': 'state',
  'country': 'Nigeria',
  'zoneId': 'NW',
  'zoneName': 'North West',
  'stateId': 'KD',
  'stateName': 'Kaduna',
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
  pollingUnitId: '18-23-01-001',
  pollingUnitName: 'KWARBAI I',
);

Map<String, dynamic> _result(
  String reference, {
  String status = 'submitted',
  String submittedBy = 'AG-1',
  bool addsUp = true,
  List<String> notes = const [],
  String? clientId,
  String submittedAt = '2027-02-25T15:00:00Z',
  String? verifiedBy,
  String reason = '',
}) =>
    {
      'id': '3c1e0000-0000-4000-8000-000000000001',
      'reference': reference,
      'election': '2027-presidential',
      'status': status,
      'scope': _unit,
      'party_votes': {'APC': 120, 'PDP': 98},
      'calculated_party_votes': 218,
      'total_valid_votes': addsUp ? 218 : 230,
      'accredited_voters': 240,
      'rejected_votes': 6,
      'registered_voters': 400,
      'validation': {
        'arithmetic_valid': addsUp,
        'duplicate_suspected': false,
        'polling_unit_matched': true,
        'agent_scope_matched': true,
        'ocr_confidence': null,
        'ocr_matched_manual_entry': null,
        'notes': notes,
        'requires_human_review': !addsUp,
      },
      'source': 'app',
      'source_reference': '',
      'origin': 'localEntry',
      'client_id': clientId,
      'submitted_by': submittedBy,
      'submitted_at': submittedAt,
      'verified_by': verifiedBy,
      'verified_at': verifiedBy == null ? null : '2027-02-25T16:00:00Z',
      'review_reason': reason,
      'result_form': null,
      'gps': {
        'latitude': '11.085500',
        'longitude': '7.719900',
        'accuracy_m': 9.0,
        'captured_at': '2027-02-25T14:59:00Z',
        'is_mocked': false,
        'distance_to_pu_m': 12,
        'status': 'onSite',
      },
      'official': false,
      'created_at': '2027-02-25T15:00:05Z',
    };

const _elections = [
  {
    'code': '2027-presidential',
    'name': '2027 Presidential Election',
    'type': 'presidential',
    'election_date': '2027-02-20',
    'status': 'open',
    'scope': {'level': 'country', 'country': 'Nigeria'},
    'parties': [
      {'acronym': 'APC', 'name': 'All Progressives Congress'},
      {'acronym': 'PDP', 'name': 'Peoples Democratic Party'},
    ],
  },
];

Map<String, dynamic> _area(String level, String code, String name, int verified, int expected) => {
      'level': level,
      'code': code,
      'name': name,
      'expected_polling_units': expected,
      'reported_polling_units': verified,
      'verified_polling_units': verified,
      'completion_percent': expected == 0 ? 0.0 : verified * 100 / expected,
      'party_votes': {'APC': 120 * verified, 'PDP': 98 * verified},
      'leading_party': verified == 0 ? null : 'APC',
    };

Map<String, dynamic> _collation(Map<String, dynamic> scope, List<Map<String, dynamic>> children) => {
      'election': '2027-presidential',
      'official': false,
      'scope': scope,
      'expected_polling_units': 8012,
      'reported_polling_units': 2,
      'verified_polling_units': 1,
      'under_review': 1,
      'disputed': 0,
      'missing_polling_units': 8011,
      'completion_percent': 0.01,
      'accredited_voters': 240,
      'total_valid_votes': 218,
      'rejected_votes': 6,
      'party_votes': {'APC': 120, 'PDP': 98},
      'leading_party': 'APC',
      'children': children,
    };

Map<String, dynamic> _page(List<Map<String, dynamic>> results) =>
    {'count': results.length, 'next': null, 'previous': null, 'results': results};

/// A fake TGCG server holding results.
class _ResultsServer {
  var results = <Map<String, dynamic>>[];

  /// Answers before the defaults (null: use them).
  http.Response? Function(String key, Map<String, String> query, Map<String, dynamic>? body)? answer;

  final requests = <Uri>[];
  final bodies = <String, Map<String, dynamic>>{};

  BackendServices connect() => BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          requests.add(request.url);
          final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
          final query = request.url.queryParameters;
          final body = request.method == 'POST'
              ? jsonDecode(request.body) as Map<String, dynamic>
              : null;
          if (body != null) bodies[key] = body;
          final custom = answer?.call(key, query, body);
          if (custom != null) return custom;
          return switch (key) {
            'GET results/' when query['status'] != null =>
              _json(_page([for (final item in results) if (item['status'] == query['status']) item])),
            'GET results/' => _json(_page(results)),
            'GET elections/' => _json(_elections),
            _ => _json({'detail': 'Not found.'}, 404),
          };
        }),
      );
}

Future<OfflinePersistenceController> _offline() async {
  FlutterSecureStorage.setMockInitialValues({});
  final offline = OfflinePersistenceController(openDatabase: memory_db.openOfflineDatabaseBackend);
  await offline.initialize();
  return offline;
}

Future<void> _connect(ResultOperationsController store, BackendServices backend) async {
  store.connect(backend.results, account: 'SC-KD');
  await store.refreshIfOlderThan(const Duration(hours: 1));
}

void main() {
  test('results, history and collation read from the server', () {
    final result = resultFromJson(_result('RES-000001', addsUp: false, notes: ['Sum off']));
    expect(result.id, 'RES-000001');
    expect(result.status, RecordStatus.submitted);
    expect(result.partyVotes, {'APC': 120, 'PDP': 98});
    expect(result.totalVotesRecorded, 230);
    expect(result.validation!.arithmeticValid, isFalse);
    expect(result.validation!.notes, ['Sum off']);
    expect(result.gps!.accuracyMeters, 9);
    expect(result.electionCode, '2027-presidential');
    expect(result.disputeReason, isNull);

    final step = ResultHistoryEntry.fromJson({
      'from_status': '',
      'to_status': 'submitted',
      'note': 'Submitted',
      'actor': 'AG-1',
      'created_at': '2027-02-25T15:00:05Z',
    });
    expect(step.fromStatus, isNull);
    expect(step.toStatus, RecordStatus.submitted);

    final collation = ServerCollation.fromJson(
      _collation(_kadunaJson, [_area('senatorialDistrict', 'KD-N', 'Kaduna North', 1, 2500)]),
    );
    expect(collation.scope.stateId, 'KD');
    expect(collation.verifiedPollingUnits, 1);
    expect(collation.leadingParty, 'APC');
    expect(collation.children.single.level, GeographyLevel.senatorialDistrict);
  });

  test('a server session shows the server results, awaiting ones by status', () async {
    final server = _ResultsServer()
      ..results = [
        _result('RES-000001'),
        _result('RES-000002', status: 'underReview', addsUp: false),
        _result('RES-000003', status: 'verified', verifiedBy: 'SC-X'),
      ];
    final store = ResultOperationsController.prototypeSeed();
    await _connect(store, server.connect());

    expect(store.isLive, isTrue);
    expect([for (final item in store.submissions) item.id], ['RES-000002', 'RES-000001', 'RES-000003']);
    expect(store.awaitingOnServer, 2);
    final statuses = [for (final url in server.requests) url.queryParameters['status']];
    expect(statuses, containsAll(['underReview', 'disputed', 'submitted', null]));
    // Flagged first, then the oldest.
    expect(
      [for (final item in store.awaitingDecisionForScope(_kaduna)) item.id],
      ['RES-000002', 'RES-000001'],
    );

    store.disconnect();
    expect(store.isLive, isFalse);
    expect(store.submissions, hasLength(4));
  });

  test('decisions are made on the server and its answer replaces the result', () async {
    final server = _ResultsServer()..results = [_result('RES-000001')];
    server.answer = (key, query, body) => switch (key) {
          'POST results/RES-000001/verify/' when body!['note'] == 'refuse' =>
            _json({'status': ['Results that fail arithmetic checks cannot be verified; resubmit.']}, 400),
          'POST results/RES-000001/verify/' =>
            _json(_result('RES-000001', status: 'verified', verifiedBy: 'SC-KD')),
          'POST results/RES-000001/dispute/' =>
            _json(_result('RES-000001', status: 'disputed', reason: body!['reason'] as String)),
          'POST results/RES-000001/reject/' =>
            _json(_result('RES-000001', status: 'rejected', reason: body!['reason'] as String)),
          _ => null,
        };
    final store = ResultOperationsController.prototypeSeed();
    await _connect(store, server.connect());
    final session = TgcgSessionController()
      ..signInFromServer(
        fullName: 'Kaduna Verifier',
        accessId: 'SC-KD',
        scope: _kaduna,
        capabilities: {'verifyElectionResult', 'disputeElectionResult'},
      );
    addTearDown(session.dispose);
    Future<bool> verify(String note) => store.verify(
          submissionId: 'RES-000001',
          verifierId: 'SC-KD',
          role: session.actor,
          userScope: _kaduna,
          note: note,
        );

    await expectLater(
      verify('refuse'),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('arithmetic'))),
    );
    expect(store.submissions.single.status, RecordStatus.submitted);

    expect(await verify('Matches the EC8A'), isTrue);
    expect(server.bodies['POST results/RES-000001/verify/'], {'note': 'Matches the EC8A'});
    expect(store.submissions.single.status, RecordStatus.verified);
    expect(store.submissions.single.verifiedBy, 'SC-KD');

    await store.dispute(
      submissionId: 'RES-000001',
      reviewerId: 'SC-KD',
      reason: 'Agent says the sheet was altered',
      role: session.actor,
      userScope: _kaduna,
    );
    expect(server.bodies['POST results/RES-000001/dispute/'], {
      'reason': 'Agent says the sheet was altered',
    });
    expect(store.submissions.single.disputeReason, 'Agent says the sheet was altered');

    await store.reject(
      submissionId: 'RES-000001',
      reviewerId: 'SC-KD',
      reason: 'Wrong unit',
      role: session.actor,
      userScope: _kaduna,
    );
    expect(server.bodies['POST results/RES-000001/reject/'], {'reason': 'Wrong unit'});
    expect(store.submissions.single.status, RecordStatus.rejected);
  });

  test('a result sent from this device stays until the server copy replaces it', () async {
    final server = _ResultsServer();
    final backend = server.connect();
    final offline = await _offline();
    server.answer = (key, query, body) {
      if (key != 'POST results/') return null;
      final made = _result('RES-000009', submittedBy: 'SC-KD', clientId: body!['client_id'] as String);
      server.results = [made];
      return _json(made, 201);
    };
    final store = ResultOperationsController.prototypeSeed(persistence: offline);
    await _connect(store, backend);

    final saved = await store.submit(
      pollingUnitScope: _unitScope,
      submittedBy: 'SC-KD',
      source: SubmissionSource.app,
      partyVotes: const {'APC': 120, 'PDP': 98},
      totalVotesRecorded: 218,
      accreditedVoters: 240,
      rejectedVotes: 6,
      gps: GpsFix(
        latitude: 11.0855,
        longitude: 7.7199,
        accuracyMeters: 9,
        capturedAt: DateTime.utc(2027, 2, 25, 14, 59),
      ),
      electionCode: '2027-presidential',
    );
    expect(saved.id, startsWith('NEW-'));
    expect(store.isOnDevice(saved.id), isTrue);

    final worker = SyncWorker(
      persistence: offline,
      transport: HttpSyncTransport(backend.client, accessId: () => 'SC-KD'),
    );
    expect((await worker.runOnce()).acknowledged, 1);
    await store.refreshIfOlderThan(const Duration(hours: 1));

    expect(server.bodies['POST results/']!['polling_unit'], '18-23-01-001');
    expect(store.isOnDevice(saved.id), isFalse);
    expect([for (final item in store.submissions) item.id], ['RES-000009']);
  });

  test('presentation mode can reject a result locally', () async {
    final store = ResultOperationsController.prototypeSeed();
    final rejected = await store.reject(
      submissionId: 'RES-0003',
      reviewerId: 'NCO-1',
      reason: 'Wrong unit',
      role: TgcgRole.nationalCollationOfficer,
      userScope: GeographicScope.nigeria,
    );
    expect(rejected, isTrue);
    final item = store.submissions.firstWhere((result) => result.id == 'RES-0003');
    expect(item.status, RecordStatus.rejected);
    expect(item.disputeReason, 'Wrong unit');
    expect(await store.resultHistory('RES-0003'), isEmpty);
  });

  group('pages', () {
    late _ResultsServer server;
    late BackendServices backend;
    late ResultOperationsController store;
    late TgcgSessionController session;

    setUp(() async {
      server = _ResultsServer()
        ..results = [
          _result('RES-000001', submittedAt: '2027-02-25T15:00:00Z'),
          _result(
            'RES-000002',
            status: 'underReview',
            submittedBy: 'AG-2',
            addsUp: false,
            notes: ['Party vote sum (218) does not match the recorded total (230).'],
            submittedAt: '2027-02-25T15:10:00Z',
          ),
          _result('RES-000003', submittedBy: 'SC-KD', submittedAt: '2027-02-25T15:20:00Z'),
          _result('RES-000004', status: 'verified', verifiedBy: 'SC-OTHER'),
        ];
      server.answer = (key, query, body) => switch (key) {
            'POST results/RES-000001/verify/' =>
              _json(_result('RES-000001', status: 'verified', verifiedBy: 'SC-KD')),
            'POST results/RES-000002/reject/' =>
              _json(_result('RES-000002', status: 'rejected', addsUp: false, reason: body!['reason'] as String)),
            'GET collation/' when query['code'] == 'KD-N' => _json(
                _collation(
                  {
                    'level': 'senatorialDistrict',
                    'country': 'Nigeria',
                    'stateId': 'KD',
                    'stateName': 'Kaduna',
                    'senatorialDistrictId': 'KD-N',
                    'senatorialDistrictName': 'Kaduna North',
                  },
                  [_area('lga', 'KD-ZARIA', 'Zaria', 1, 400)],
                ),
              ),
            'GET collation/' => _json(
                _collation(_kadunaJson, [
                  _area('senatorialDistrict', 'KD-C', 'Kaduna Central', 0, 3000),
                  _area('senatorialDistrict', 'KD-N', 'Kaduna North', 1, 2500),
                ]),
              ),
            _ => null,
          };
      backend = server.connect();
      store = ResultOperationsController.prototypeSeed();
      await _connect(store, backend);
      session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Kaduna Verifier',
          accessId: 'SC-KD',
          scope: _kaduna,
          capabilities: {'verifyElectionResult', 'disputeElectionResult', 'viewCollation'},
        );
    });

    tearDown(() {
      session.dispose();
      store.dispose();
    });

    Future<void> pump(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(1300, 5200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TgcgBackend(
          services: backend,
          child: TgcgSession(
            controller: session,
            child: OfflinePersistence(
              controller: OfflinePersistenceController(),
              child: MembershipOperations(
                controller: MembershipOperationsController.prototypeSeed(
                  GeographyRegistry.prototypeSeed(),
                ),
                child: ResultOperations(
                  controller: store,
                  child: MaterialApp(home: Scaffold(body: page)),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder inDialog(Finder finder) => find.descendant(of: find.byType(AlertDialog), matching: finder);

    testWidgets('Result Capture verifies and rejects on the server', (tester) async {
      await pump(tester, const ResultCapturePage());

      expect(find.text('LIVE FROM SERVER'), findsOneWidget);
      expect(find.textContaining('Demo data'), findsNothing);
      expect(find.text('Verification queue'), findsOneWidget);
      expect(find.text('3 AWAITING'), findsOneWidget);
      // Only the clean result someone else sent can be verified.
      expect(find.widgetWithText(FilledButton, 'Verify'), findsOneWidget);
      expect(find.textContaining('The figures do not add up'), findsOneWidget);
      expect(find.textContaining('You sent this result'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
      await tester.pumpAndSettle();
      expect(find.text('Verify RES-000001'), findsOneWidget);
      await tester.tap(inDialog(find.widgetWithText(FilledButton, 'Verify')));
      await tester.pumpAndSettle();
      expect(server.bodies['POST results/RES-000001/verify/'], {'note': ''});
      expect(find.text('RES-000001 verified.'), findsOneWidget);
      expect(find.text('2 AWAITING'), findsOneWidget);
      expect(find.text('Verified by SC-KD'), findsOneWidget);

      // The flagged result comes first; rejecting it needs a reason.
      await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').first);
      await tester.pumpAndSettle();
      expect(find.text('Reject RES-000002'), findsOneWidget);
      final confirm = inDialog(find.widgetWithText(FilledButton, 'Reject'));
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(inDialog(find.byType(TextField)), 'Figures do not add up');
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(server.bodies['POST results/RES-000002/reject/'], {'reason': 'Figures do not add up'});
      expect(find.text('1 AWAITING'), findsOneWidget);
      expect(find.text('Rejected: Figures do not add up'), findsOneWidget);

      // Verified results can still be disputed from the ledger.
      expect(find.widgetWithText(OutlinedButton, 'Dispute'), findsWidgets);
    });

    testWidgets('a role that only reads results has no decisions to take', (tester) async {
      session.updateAccess(capabilities: {'viewCollation'}, grants: const []);
      await pump(tester, const ResultCapturePage());
      for (final action in ['Verify', 'Reject', 'Dispute']) {
        expect(find.text(action), findsNothing, reason: action);
      }
    });

    testWidgets('Collation shows the server totals and opens areas below', (tester) async {
      await pump(tester, const CollationPage());

      expect(find.text('UNOFFICIAL: NOT INEC'), findsOneWidget);
      expect(find.text('1 of 8,012'), findsOneWidget);
      expect(find.text('AHEAD: APC'), findsOneWidget);
      expect(find.text('APC · All Progressives Congress'), findsOneWidget);
      expect(find.text('Senatorial district breakdown'), findsOneWidget);

      await tester.tap(find.text('Kaduna North'));
      await tester.pumpAndSettle();
      final opened = server.requests.lastWhere((url) => url.path.endsWith('/collation/'));
      expect(opened.queryParameters, {
        'election': '2027-presidential',
        'level': 'senatorialDistrict',
        'code': 'KD-N',
      });
      expect(find.text('LGA breakdown'), findsOneWidget);
      expect(find.text('Zaria'), findsOneWidget);

      await tester.tap(find.text('Kaduna State'));
      await tester.pumpAndSettle();
      expect(find.text('Senatorial district breakdown'), findsOneWidget);
    });
  });
}
