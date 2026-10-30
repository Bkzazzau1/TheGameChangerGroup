import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/field/field_agent_shell.dart';
import 'package:tgcg_emcop/tgcg/field/field_operations_store.dart';
import 'package:tgcg_emcop/tgcg/offline/offline_database_stub.dart' as memory_db;
import 'package:tgcg_emcop/tgcg/offline/offline_persistence.dart';
import 'package:tgcg_emcop/tgcg/results/result_operations_store.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_controller.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_worker.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_theme.dart';

// Names here are made up.

http.Response jsonResponse(Object body, [int status = 200]) => http.Response.bytes(
  utf8.encode(jsonEncode(body)),
  status,
  headers: {'content-type': 'application/json'},
);

const fakeUnit = {
  'code': '18-23-01-014',
  'name': 'UNG. ASKA I/ L.E.A. ANGUWAN KAHU',
  'location': '',
  'ward': 'KWARBAI "A"',
  'ward_code': '18-23-01',
  'lga': 'Zaria',
  'state': 'Kaduna',
  'navigation': {
    'latitude': 11.0539,
    'longitude': 7.712955,
    'source': 'inec',
    'confirmed': false,
    'note': '',
  },
};

Map<String, dynamic> fakeCard({
  String verification = 'verified',
  String name = 'Musa Bello',
  List<String> missing = const [],
}) => {
  'membership_number': 'TGCG-000123',
  'full_name': name,
  'phone_number': '+2348031234567',
  'email': '',
  'vin': '90F5***********7263',
  'has_pvc': true,
  'gender': 'male',
  'date_of_birth': '1990-05-14',
  'occupation': 'Teacher',
  'status': 'submitted',
  'membership_state': 'active',
  'verification_status': verification,
  'polling_unit': fakeUnit,
  'member_since': '2026-10-11T08:00:00Z',
  'photo_url': null,
  'qr_token': 'TGCG-000123:signed-token',
  'card_missing': missing,
};

/// What a member's app asks for, as a server with one announcement answers.
http.Response? memberServer(String path, {Map<String, dynamic>? card}) => switch (path) {
  'me/member/' => jsonResponse(card ?? fakeCard()),
  'me/polling-unit/' => jsonResponse({
    'polling_unit': fakeUnit,
    'members_in_unit': 12,
    'members_in_ward': 140,
  }),
  'me/announcements/' => jsonResponse({
    'count': 1,
    'results': [
      {
        'id': 'a1',
        'title': 'Ward meeting on Saturday',
        'body': 'All Kwarbai A members meet at 4pm at the ward secretariat.',
        'author': 'Ward Coordinator',
        'published_at': '2026-10-10T16:00:00Z',
      },
    ],
  }),
  'me/volunteer/' => jsonResponse(<Object>[]),
  'me/assignments/' => jsonResponse(<Object>[]),
  'me/messages/' => jsonResponse(<Object>[]),
  'me/pvc-scan/' || 'me/member/pvc-scan/' => jsonResponse({'can_scan': true, 'latest': null}),
  'me/referral/' => jsonResponse({
    'code': '1234567',
    'link': 'https://app.tgcg.online/?ref=1234567',
    'joined': 3,
    'credited': 2,
  }),
  _ => null,
};

/// A fake TGCG server: every request is recorded, and [answer] replies by
/// path (404 for anything it does not know).
BackendServices fakeBackend(
  http.Response? Function(String path) answer, {
  List<String>? requests,
  Future<void>? hold,
}) => BackendServices.connect(
  'https://api.tgcg.test',
  tokens: MemoryTokenStore(),
  httpClient: MockClient((request) async {
    final path = request.url.path.replaceFirst('/api/v1/', '');
    requests?.add(path);
    // A slow network: answers wait for this.
    await hold;
    return answer(path) ?? jsonResponse({'detail': 'Not found.'}, 404);
  }),
);

/// The member app, with the app's real theme.
Widget memberApp(BackendServices services, TgcgSessionController session, Widget home) =>
    TgcgBackend(
      services: services,
      child: TgcgSession(
        controller: session,
        child: MaterialApp(theme: tgcgTheme(), home: home),
      ),
    );

TgcgSessionController memberSession({String name = 'Musa Bello', String? waitingRole}) =>
    TgcgSessionController()
      ..signInMember(fullName: name, membershipNumber: 'TGCG-000123', waitingRole: waitingRole);

const fakeAgentScope = GeographicScope(
  level: GeographyLevel.pollingUnit,
  country: 'Nigeria',
  stateId: 'KD',
  stateName: 'Kaduna',
  lgaId: 'KD-ZARIA',
  lgaName: 'Zaria',
  wardId: '18-23-01',
  wardName: 'KWARBAI "A"',
  pollingUnitId: '18-23-01-001',
  pollingUnitName: 'KWARBAI I',
);

const agentCapabilities = {
  'createIncident',
  'submitFieldReport',
  'submitElectionResult',
  'viewMeetingRoom',
  'joinMeeting',
  'viewDiscussionRoom',
  'createDiscussionThread',
  'postDiscussionReply',
};

/// Sends nothing unless a test says what the server answers.
class StubTransport implements SyncTransport {
  StubTransport(this.answer);

  SyncPushResult Function() answer;

  @override
  bool supports(String entityType) => true;

  @override
  Future<SyncPushResult> push({
    required SyncOutboxItem mutation,
    required Map<String, Object?> payload,
  }) async => answer();
}

/// An agent's phone, signed in to a fake server, with the app's real stores.
class AgentPhone {
  AgentPhone._(this.services, this.session, this.offline, this.field, this.results, this.sync);

  final BackendServices services;
  final TgcgSessionController session;
  final OfflinePersistenceController offline;
  final FieldOperationsController field;
  final ResultOperationsController results;
  final SyncController sync;

  static Future<AgentPhone> start({
    Set<String> capabilities = agentCapabilities,
    String? membershipNumber = 'TGCG-000001',
    http.Response? Function(String path)? answer,
    SyncPushResult Function()? upload,
  }) async {
    FlutterSecureStorage.setMockInitialValues({});
    final services = fakeBackend(
      (path) =>
          answer?.call(path) ??
          switch (path) {
            'incidents/' || 'field-reports/' || 'results/' => jsonResponse({
              'count': 0,
              'next': null,
              'previous': null,
              'results': <Object>[],
            }),
            'tracking/check-ins/' => jsonResponse({'count': 0, 'results': <Object>[]}),
            _ => null,
          },
    );
    final session = TgcgSessionController()
      ..signInFromServer(
        role: TgcgRole.pollingUnitAgent,
        fullName: 'Musa Bello',
        accessId: 'AG-00001',
        membershipNumber: membershipNumber,
        scope: fakeAgentScope,
        capabilities: capabilities,
      );
    final offline = OfflinePersistenceController(
      openDatabase: memory_db.openOfflineDatabaseBackend,
    );
    await offline.initialize();
    final field = FieldOperationsController.prototypeSeed(persistence: offline);
    final results = ResultOperationsController.prototypeSeed(persistence: offline);
    field.connect(services.field, account: session.accessId);
    results.connect(services.results, account: session.accessId);
    await field.refreshIfOlderThan(const Duration(hours: 1));
    await results.refreshIfOlderThan(const Duration(hours: 1));
    final sync = SyncController(
      persistence: offline,
      transport: StubTransport(
        upload ?? () => const SyncPushResult.retryLater(message: 'No connection.'),
      ),
      interval: const Duration(hours: 6),
      debounce: const Duration(hours: 6),
    );
    return AgentPhone._(services, session, offline, field, results, sync);
  }

  /// Stops the phone's timers: call before a test ends.
  void stop() => sync.setEnabled(false);

  Widget app({Widget home = const FieldAgentShell()}) => TgcgBackend(
    services: services,
    child: TgcgSync(
      controller: sync,
      child: TgcgSession(
        controller: session,
        child: OfflinePersistence(
          controller: offline,
          child: FieldOperations(
            controller: field,
            child: ResultOperations(
              controller: results,
              child: MaterialApp(theme: tgcgTheme(), home: home),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Sets the screen for a test, and puts it back afterwards.
void useScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The phone widths the design must hold at, and a wide screen.
const screenWidths = [320.0, 360.0, 390.0, 428.0, 1200.0];
