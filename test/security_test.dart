import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/security/incident_security_panel.dart';
import 'package:tgcg_emcop/tgcg/security/security_officer_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

// Names and numbers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _Server {
  final requests = <String>[];
  final bodies = <String, Object?>{};
  http.Response? Function(String key, Object? body) answer = (_, _) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      final query = request.url.query.isEmpty ? '' : '?${request.url.query}';
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}$query';
      requests.add(key);
      final text = utf8.decode(await body.toBytes());
      final decoded = text.isEmpty ? null : jsonDecode(text);
      bodies[key] = decoded;
      final response = answer(key, decoded) ?? _json({'detail': 'Not found.'}, 404);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );
}

Map<String, dynamic> _incident() => {
  'reference': 'INC-000001',
  'title': 'Thugs at the unit',
  'category': 'Violence / threat',
  'severity': 'critical',
  'status': 'escalated',
  'summary': 'Armed group chasing voters.',
  'reported_at': '2026-10-17T09:55:00Z',
  'scope': {'level': 'country', 'country': 'Nigeria'},
  'place': 'Unit 001, Ward 01, Kaduna North, Kaduna',
  'latitude': 10.5235,
  'longitude': 7.4382,
  'gps': true,
  'reporter_name': 'Agent One',
  'reporter_phone': '+2348035550001',
};

Map<String, dynamic> _mine({
  String id = 'd-1',
  String status = 'sent',
  List<String> next = const ['accepted', 'declined'],
  String outcome = '',
}) => {
  'id': id,
  'status': status,
  'next': next,
  'incident': _incident(),
  'sent_by': 'Situation Director',
  'sent_at': '2026-10-17T10:00:00Z',
  'note': 'Police are 20 minutes out.',
  'distance_m': 60,
  'located_by': 'area',
  'accepted_at': status == 'sent' ? null : '2026-10-17T10:01:00Z',
  'on_the_way_at': null,
  'arrived_at': null,
  'finished_at': outcome.isEmpty ? null : '2026-10-17T11:00:00Z',
  'outcome': outcome,
  'cancel_reason': '',
};

Map<String, dynamic> _dispatch({String status = 'sent', String? phone = '+2348036660001'}) => {
  'id': 'd-1',
  'incident': 'INC-000001',
  'status': status,
  'officer': 'TGCG-000002',
  'officer_name': 'Garba Tanko',
  'officer_phone': phone,
  'sent_by': 'Situation Director',
  'sent_at': '2026-10-17T10:00:00Z',
  'note': '',
  'distance_m': 60,
  'located_by': 'area',
  'notified': ['push', 'sms'],
  'accepted_at': null,
  'on_the_way_at': null,
  'arrived_at': null,
  'finished_at': null,
  'outcome': '',
  'cancelled_by': null,
  'cancel_reason': '',
};

Future<void> _pump(WidgetTester tester, _Server server, Widget page, {TgcgRole? role}) async {
  tester.view.physicalSize = const Size(420, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TgcgSessionController();
  if (role != null) session.signIn(role: role, operatorName: 'Operator', accessId: 'OP-1');
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: server.connect(),
      child: TgcgSession(
        controller: session,
        child: MaterialApp(home: Scaffold(body: page)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  testWidgets('a security officer sees where to go, whom to call, and answers each step', (
    tester,
  ) async {
    final server = _Server();
    var current = _mine();
    server.answer = (key, body) => switch (key) {
      'GET me/security/' => _json([
        current,
        _mine(id: 'd-0', status: 'resolved', next: const [], outcome: 'Crowd dispersed.'),
      ]),
      'POST me/security/d-1/respond/' => _json(
        current = switch ((body as Map)['step']) {
          'accepted' => _mine(status: 'accepted', next: const ['onTheWay', 'arrived', 'resolved']),
          _ => _mine(status: 'resolved', next: const [], outcome: '${body['note']}'),
        },
      ),
      _ => null,
    };
    final launched = <Uri>[];
    await _pump(
      tester,
      server,
      SecurityOfficerPage(
        refreshEvery: const Duration(hours: 1),
        launch: (uri) async {
          launched.add(uri);
          return true;
        },
      ),
    );

    expect(find.text('1 with you now'), findsOneWidget);
    expect(find.text('INC-000001 · Thugs at the unit'), findsNWidgets(2));
    expect(find.text('Situation Room: Police are 20 minutes out.'), findsNWidgets(2));
    expect(find.text('Reported by Agent One, +2348035550001'), findsNWidgets(2));
    expect(find.text('Earlier this week'), findsOneWidget);
    expect(find.text('Crowd dispersed.'), findsOneWidget);

    await tester.tap(find.text('Directions'));
    await tester.tap(find.text('Call reporter'));
    await tester.pumpAndSettle();
    expect(launched.first.queryParameters['destination'], '10.5235,7.4382');
    expect(launched.last, Uri(scheme: 'tel', path: '+2348035550001'));

    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(server.bodies['POST me/security/d-1/respond/'], {'step': 'accepted', 'note': ''});
    expect(find.text('On the way'), findsOneWidget);
    expect(find.text('Arrived'), findsOneWidget);

    // Resolving asks what was done.
    await tester.tap(find.text('Resolved').first); // the button, before the earlier card's status
    await tester.pumpAndSettle();
    expect(find.text('Resolve INC-000001'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Crowd dispersed; voting resumed.');
    await tester.pump();
    await tester.tap(_inDialog('Resolved'));
    await tester.pumpAndSettle();
    expect(server.bodies['POST me/security/d-1/respond/'], {
      'step': 'resolved',
      'note': 'Crowd dispersed; voting resumed.',
    });
    expect(find.text('Nothing with you now'), findsOneWidget);
  });

  testWidgets('an officer with nothing sent to them sees an empty page', (tester) async {
    final server = _Server()..answer = (key, _) => key == 'GET me/security/' ? _json([]) : null;
    await _pump(tester, server, const SecurityOfficerPage(refreshEvery: Duration(hours: 1)));
    expect(find.text('No incidents sent to you'), findsOneWidget);
  });

  testWidgets('the Situation Room sends an incident to one of the nearest officers', (tester) async {
    final server = _Server();
    var dispatches = <Map<String, dynamic>>[];
    server.answer = (key, body) {
      if (key == 'GET incidents/INC-000001/security/') {
        return _json({'can_send': true, 'dispatches': dispatches});
      }
      if (key.startsWith('GET incidents/INC-000001/security/nearest/')) {
        final searching = key.contains('search=ladi');
        return _json({
          'located': true,
          'officers': [
            if (!searching)
              {
                'access_id': 'TGCG-000002',
                'name': 'Garba Tanko',
                'roles': ['Security Officer'],
                'distance_m': 60,
                'located_by': 'area',
                'area': 'Unit 001',
                'seen_at': null,
                'busy': false,
              },
            {
              'access_id': 'TGCG-000003',
              'name': 'Ladi Yusuf',
              'roles': ['Security Officer'],
              'distance_m': 2150,
              'located_by': 'live',
              'area': null,
              'seen_at': '2026-10-17T10:00:00Z',
              'busy': true,
            },
          ],
        });
      }
      if (key == 'POST incidents/INC-000001/security/') {
        dispatches = [_dispatch()];
        return _json(dispatches.first, 201);
      }
      if (key == 'POST security/dispatches/d-1/cancel/') {
        dispatches = [_dispatch(status: 'cancelled')];
        return _json(dispatches.first);
      }
      return null;
    };
    final incident = FieldIncident(
      id: 'INC-000001',
      title: 'Thugs at the unit',
      category: 'Violence / threat',
      severity: IncidentSeverity.critical,
      status: IncidentStatus.reported,
      scope: GeographicScope.nigeria,
      reportedAt: DateTime.utc(2026, 10, 17, 9, 55),
      reporterId: 'AG-1',
    );
    await _pump(
      tester,
      server,
      IncidentSecurityPanel(incident: incident, refreshEvery: const Duration(hours: 1)),
      role: TgcgRole.situationRoomDirector,
    );

    await tester.tap(find.text('Send to security'));
    await tester.pumpAndSettle();
    expect(find.text('Send INC-000001 to security'), findsOneWidget);
    expect(find.text('60 m · Unit 001 · Security Officer'), findsOneWidget);
    expect(find.text('2.1 km · live location · Security Officer'), findsOneWidget);
    expect(find.text('BUSY'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send')).onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextField, 'Name or ID'), 'ladi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Garba Tanko'), findsNothing);
    await tester.enterText(find.widgetWithText(TextField, 'Name or ID'), '');
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Garba Tanko'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Note to the officer (optional)'),
      'Police are 20 minutes out.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(server.bodies['POST incidents/INC-000001/security/'], {
      'officer': 'TGCG-000002',
      'note': 'Police are 20 minutes out.',
    });
    expect(find.text('INC-000001 sent to Garba Tanko.'), findsOneWidget);
    expect(find.text('Garba Tanko'), findsOneWidget);
    expect(find.textContaining('Told by app and SMS'), findsOneWidget);
    expect(find.text('Send to security'), findsNothing);
    expect(find.byTooltip('Call Garba Tanko'), findsOneWidget);

    // Taking it back needs a reason.
    await tester.tap(find.text('Take back'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Police arrived first.');
    await tester.pump();
    await tester.tap(_inDialog('Take back'));
    await tester.pumpAndSettle();
    expect(server.bodies['POST security/dispatches/d-1/cancel/'], {'reason': 'Police arrived first.'});
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Send to security'), findsOneWidget);
  });

  testWidgets('those who may not follow an incident see nothing of its security', (tester) async {
    final server = _Server()
      ..answer = (key, _) => key == 'GET incidents/INC-000001/security/'
          ? _json({'detail': 'Your role does not include following incidents.'}, 403)
          : null;
    final incident = FieldIncident(
      id: 'INC-000001',
      title: 'Thugs at the unit',
      category: 'Violence / threat',
      severity: IncidentSeverity.critical,
      status: IncidentStatus.reported,
      scope: GeographicScope.nigeria,
      reportedAt: DateTime.utc(2026, 10, 17, 9, 55),
      reporterId: 'AG-1',
    );
    await _pump(
      tester,
      server,
      IncidentSecurityPanel(incident: incident, refreshEvery: const Duration(hours: 1)),
      role: TgcgRole.lgaCoordinator,
    );
    expect(find.text('Security officer'), findsNothing);
    expect(find.textContaining('could not be loaded'), findsNothing);
  });
}
