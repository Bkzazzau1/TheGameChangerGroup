import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/location/gps_service.dart';
import 'package:tgcg_emcop/tgcg/projects/project_mode.dart';
import 'package:tgcg_emcop/tgcg/projects/projects_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

// Names and numbers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _unit = {
  'level': 'pollingUnit',
  'country': 'Nigeria',
  'stateId': 'KD',
  'lgaId': 'KD-ZARIA',
  'wardId': '18-23-01',
  'pollingUnitId': '18-23-01-001',
  'pollingUnitName': 'KWARBAI I',
};
const _zaria = {'level': 'lga', 'country': 'Nigeria', 'stateId': 'KD', 'lgaId': 'KD-ZARIA', 'lgaName': 'Zaria'};

Map<String, dynamic> _project({
  String? participation,
  Duration startsIn = const Duration(hours: -1),
  Duration endsIn = const Duration(hours: 8),
  bool canAssign = false,
}) {
  final now = DateTime.now().toUtc();
  return {
    'id': 'p-1',
    'name': 'Kaduna governorship election',
    'description': 'Be at your polling unit from 7 am.',
    'starts_at': now.add(startsIn).toIso8601String(),
    'ends_at': now.add(endsIn).toIso8601String(),
    'status': now.add(startsIn).isAfter(now) ? 'scheduled' : 'active',
    'areas': [_zaria],
    'election': {'code': '2027-kd-gov', 'name': 'Kaduna governorship'},
    'check_place': true,
    'cancelled_at': null,
    'cancel_reason': '',
    'my_participation': participation == null
        ? null
        : {
            'id': 'w-1',
            'project': 'p-1',
            'project_name': 'Kaduna governorship election',
            'member': 'TGCG-000201',
            'member_name': 'Musa Bello',
            'place': _unit,
            'status': participation,
            'assigned_by': 'WC-1',
            'reason': '',
          },
    'can_manage': false,
    'can_assign': canAssign,
  };
}

class _Server {
  final requests = <String>[];
  http.Response? Function(String key) answer = (_) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add(key);
      await body.toBytes();
      final response = answer(key) ?? _json({'detail': 'Not found.'}, 404);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );
}

class _FakeSharing implements ProjectSharing {
  GpsProblem? gps;
  final notices = <String>[];
  int stops = 0;

  @override
  bool on = false;

  @override
  Future<GpsProblem?> problem() async => gps;

  @override
  Future<void> start(String notice) async {
    notices.add(notice);
    on = true;
  }

  @override
  Future<void> stop() async {
    stops++;
    on = false;
  }
}

Future<void> _pump(
  WidgetTester tester,
  _Server server,
  Widget child, {
  _FakeSharing? sharing,
  Set<String> can = const {},
}) async {
  tester.view.physicalSize = const Size(400, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TgcgSessionController()
    ..signInFromServer(
      fullName: 'Musa Bello',
      accessId: 'TGCG-000201',
      scope: GeographicScope.nigeria,
      capabilities: can,
    );
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: server.connect(),
      child: TgcgSession(
        controller: session,
        child: MaterialApp(
          home: ProjectMode(
            sharing: sharing ?? _FakeSharing(),
            child: Scaffold(
              body: Column(
                children: [
                  const ProjectStrip(),
                  Expanded(child: ProjectGpsGate(child: child)),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('sharing runs only while a project the person accepted is on', () async {
    final server = _Server();
    var project = _project(participation: 'accepted');
    server.answer = (key) => switch (key) {
      'GET projects/' => _json([project]),
      'GET me/projects/' => _json([project]),
      _ => null,
    };
    final sharing = _FakeSharing()..gps = GpsProblem.serviceOff;
    final mode = ProjectModeController(repository: server.connect().projects, sharing: sharing);
    addTearDown(mode.dispose);

    await mode.refresh();
    expect(mode.myWork?.name, 'Kaduna governorship election');
    expect(mode.gpsProblem, GpsProblem.serviceOff); // the app waits for location
    expect(sharing.notices, isEmpty);

    sharing.gps = null;
    await mode.retryGps();
    expect(mode.gpsProblem, isNull);
    expect(sharing.notices.single, startsWith('Sharing your location for Kaduna governorship election'));

    project = _project(participation: 'accepted', startsIn: const Duration(hours: -9), endsIn: const Duration(minutes: -1));
    await mode.refresh();
    expect(mode.myWork, isNull);
    expect(sharing.on, isFalse);
    expect(sharing.stops, 1);
  });

  test('an invitation shares nothing until it is accepted', () async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET projects/' => _json([_project(participation: 'invited')]),
      _ => null,
    };
    final sharing = _FakeSharing();
    final mode = ProjectModeController(repository: server.connect().projects, sharing: sharing);
    addTearDown(mode.dispose);
    await mode.refresh();
    expect(mode.myWork, isNull);
    expect(mode.invitations.single.id, 'p-1');
    expect(sharing.notices, isEmpty);
  });

  testWidgets('the person agrees to share their location when accepting', (tester) async {
    final server = _Server();
    var status = 'invited';
    server.answer = (key) => switch (key) {
      'GET projects/' => _json([_project(participation: status)]),
      'GET me/projects/' => _json([_project(participation: status)]),
      'POST me/projects/w-1/accept/' => () {
        status = 'accepted';
        return _json(_project(participation: 'accepted')['my_participation'] as Object);
      }(),
      _ => null,
    };
    final sharing = _FakeSharing();
    await _pump(tester, server, const Text('The app'), sharing: sharing);

    await tester.tap(find.text('You are asked to take part in Kaduna governorship election'));
    await tester.pumpAndSettle();
    expect(find.text('While it runs, your location is shared with your coordinators.'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.pumpAndSettle();

    expect(server.requests, contains('POST me/projects/w-1/accept/'));
    expect(find.textContaining('sharing your location'), findsOneWidget);
    expect(sharing.notices, hasLength(1));
  });

  testWidgets('while location is off, the app waits for it', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET projects/' || 'GET me/projects/' => _json([_project(participation: 'accepted')]),
      _ => null,
    };
    final sharing = _FakeSharing()..gps = GpsProblem.serviceOff;
    await _pump(tester, server, const Text('The app'), sharing: sharing);

    expect(find.text('Turn on your location'), findsOneWidget);
    expect(find.text('The app'), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Turn on location'), findsOneWidget);

    sharing.gps = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Try again'));
    await tester.pumpAndSettle();
    expect(find.text('The app'), findsOneWidget);
  });

  testWidgets('a coordinator sees who is where in a project', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET projects/' || 'GET me/projects/' => _json(<Object>[]),
      'GET projects/p-1/' => _json(_project(canAssign: true)),
      'GET projects/p-1/monitor/' => _json({
        'status': 'active',
        'counts': {'atPlace': 1, 'away': 1},
        'people': [
          {
            'participation': 'w-1',
            'member': 'TGCG-000201',
            'name': 'Musa Bello',
            'place': _unit,
            'status': 'accepted',
            'state': 'away',
            'position': {
              'latitude': '11.13',
              'longitude': '7.72',
              'accuracy_m': 12,
              'captured_at': DateTime.now().toUtc().toIso8601String(),
              'is_mocked': false,
              'distance_to_pu_m': 5500,
              'status': 'away',
            },
            'sharing_since': DateTime.now().toUtc().toIso8601String(),
          },
        ],
        'work': {'incidents': 2, 'reports': 0, 'results': 1},
      }),
      _ => null,
    };
    await _pump(
      tester,
      server,
      const ProjectDetailPage(projectId: 'p-1'),
      can: {'assignProjectParticipants', 'viewLiveOperations'},
    );

    expect(find.text('Kaduna governorship election'), findsOneWidget);
    expect(find.text('Away from their place'), findsWidgets);
    expect(find.textContaining('5500 m from their place'), findsOneWidget);
    expect(find.text('Incidents 2 · Reports 0 · Results 1'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Assign'), findsOneWidget);
  });

  test('assigning and watching projects opens the Projects page', () {
    for (final can in ['assignProjectParticipants', 'manageProjects', 'viewLiveOperations']) {
      final session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Coordinator',
          accessId: 'WC-1',
          scope: GeographicScope.nigeria,
          capabilities: {can},
        );
      addTearDown(session.dispose);
      expect(session.modules, contains(TgcgModule.projects), reason: can);
    }
  });
}
