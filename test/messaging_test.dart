import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/messaging/inbox_page.dart';
import 'package:tgcg_emcop/tgcg/messaging/messages_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

// Names and numbers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _Server {
  final requests = <String>[];
  final bodies = <String, Object?>{};
  http.Response? Function(String key) answer = (_) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add(key);
      final text = utf8.decode(await body.toBytes());
      bodies[key] = text.isEmpty ? null : jsonDecode(text);
      final response = answer(key) ?? _json({'detail': 'Not found.'}, 404);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );
}

Future<void> _pump(WidgetTester tester, _Server server, Widget page, {Set<String> can = const {}}) async {
  tester.view.physicalSize = const Size(420, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TgcgSessionController()
    ..signInFromServer(
      fullName: 'Kaduna Messenger',
      accessId: 'TGCG-000301',
      scope: GeographicScope.nigeria,
      capabilities: can,
    );
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

Map<String, dynamic> _sent({String status = 'sending'}) => {
  'id': 'b-1',
  'sender': 'TGCG-000301',
  'sender_name': 'Kaduna Messenger',
  'title': '',
  'body': 'Meeting at the ward office, 4 pm.',
  'channels': ['sms'],
  'audience': <String, Object>{},
  'people': 3,
  'unreachable': {'sms': 0},
  'status': status,
  'created_at': '2026-10-17T10:00:00Z',
  'finished_at': null,
  'delivered': {
    'sms': {'sent': 2, 'failed': 1},
  },
};

void main() {
  test('SMS pages are counted as the server counts them', () {
    expect(smsPages('Hello'), 1);
    expect(smsPages('a' * 160), 1);
    expect(smsPages('a' * 161), 2);
    expect(smsPages('a' * 306), 2);
    expect(smsPages('a' * 307), 3);
    expect(smsPages('₦${'a' * 69}'), 1);
    expect(smsPages('₦${'a' * 70}'), 2);
  });

  testWidgets('a sender checks who a message reaches, then sends it', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET broadcasts/roles/' => _json({
        'roles': [
          {'code': 'pollingUnitAgent', 'name': 'Polling Unit Agent'},
        ],
        'channels': ['sms', 'push'],
      }),
      'POST broadcasts/preview/' => _json({
        'people': 3,
        'channels': {
          'sms': {'reachable': 3, 'unreachable': 0},
        },
        'sms_pages': 1,
      }),
      'POST broadcasts/' => _json(_sent(), 201),
      _ => null,
    };
    await _pump(tester, server, const MessagesPage(), can: {'sendSms', 'sendPushNotifications'});

    // Only the channels this account may send on.
    expect(find.widgetWithText(FilterChip, 'SMS'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'App notification'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'WhatsApp'), findsNothing);

    await tester.tap(find.widgetWithText(FilterChip, 'SMS'));
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Meeting at the ward office, 4 pm.');
    await tester.pump();
    expect(find.text('1 SMS page(s)'), findsOneWidget);
    await tester.tap(find.widgetWithText(ActionChip, 'People'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();
    expect(find.text('Everyone in all your area'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Who it reaches'));
    await tester.pumpAndSettle();
    expect(find.text('Reaches 3 people'), findsOneWidget);
    expect(server.bodies['POST broadcasts/preview/'], {
      'channels': ['sms'],
      'title': '',
      'body': 'Meeting at the ward office, 4 pm.',
      'groups': [
        {'type': 'filter', 'areas': <Object>[], 'people': 'everyone', 'gender': '', 'verified_only': false},
      ],
    });

    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(find.text('Send to 3 people?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Send').last);
    await tester.pumpAndSettle();
    expect(server.requests, contains('POST broadcasts/'));
    expect(find.text('Sending to 3 people.'), findsOneWidget);
  });

  testWidgets('one message goes to a project team and a saved list together', (tester) async {
    final server = _Server();
    final now = DateTime.now().toUtc();
    server.answer = (key) => switch (key) {
      'GET broadcasts/roles/' => _json({'roles': <Object>[], 'channels': ['whatsapp']}),
      'GET projects/' => _json([
        {
          'id': 'p-1',
          'name': 'Kaduna governorship election',
          'starts_at': now.toIso8601String(),
          'ends_at': now.add(const Duration(hours: 8)).toIso8601String(),
          'status': 'active',
          'areas': <Object>[],
          'election': null,
          'my_participation': null,
        },
      ]),
      'GET message-lists/' => _json([
        {'id': 'l-1', 'name': 'Ward secretaries', 'people': 12},
      ]),
      'POST broadcasts/preview/' => _json({
        'people': 40,
        'channels': {
          'whatsapp': {'reachable': 38, 'unreachable': 2},
        },
        'sms_pages': 1,
      }),
      _ => null,
    };
    await _pump(tester, server, const MessagesPage(), can: {'sendWhatsApp'});

    await tester.tap(find.widgetWithText(FilterChip, 'WhatsApp'));
    await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Collation starts at 6 pm.');
    await tester.tap(find.widgetWithText(ActionChip, 'Project team'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kaduna governorship election'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ActionChip, 'Saved list'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ward secretaries (12)'));
    await tester.pumpAndSettle();
    expect(find.text('Team: Kaduna governorship election'), findsOneWidget);
    expect(find.text('List: Ward secretaries'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Who it reaches'));
    await tester.pumpAndSettle();
    expect(
      (server.bodies['POST broadcasts/preview/']! as Map<String, dynamic>)['groups'],
      [
        {'type': 'project', 'project': 'p-1'},
        {'type': 'list', 'list': 'l-1'},
      ],
    );
    expect(find.text('Reaches 40 people'), findsOneWidget);
    expect(find.text('WhatsApp: 38 (2 with no number)'), findsOneWidget);
  });

  testWidgets('with no channel set up on the server there is nothing to send on', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET broadcasts/roles/' => _json({'roles': <Object>[], 'channels': <Object>[]}),
      _ => null,
    };
    await _pump(tester, server, const MessagesPage(), can: {'sendSms', 'sendWhatsApp'});
    expect(find.text('No way to send yet'), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Who it reaches'), findsNothing);
  });

  testWidgets('saved lists that cannot be loaded say why', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET broadcasts/roles/' => _json({'roles': <Object>[], 'channels': ['sms']}),
      'GET message-lists/' => _json({'detail': 'You do not have permission to perform this action.'}, 403),
      _ => null,
    };
    await _pump(tester, server, const MessagesPage(), can: {'sendSms'});
    await tester.tap(find.widgetWithText(ActionChip, 'Saved list'));
    await tester.pumpAndSettle();
    expect(find.text('You do not have permission to perform this action.'), findsOneWidget);
    expect(find.byType(SimpleDialog), findsNothing);
  });

  testWidgets('the sender sees how far each message got', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET broadcasts/roles/' => _json({'roles': <Object>[], 'channels': ['sms']}),
      'GET broadcasts/' => _json({'count': 1, 'next': null, 'previous': null, 'results': [_sent(status: 'done')]}),
      _ => null,
    };
    await _pump(tester, server, const MessagesPage(), can: {'sendSms'});
    await tester.tap(find.text('Sent'));
    await tester.pumpAndSettle();
    expect(find.text('SMS: 2 sent, 1 not sent'), findsOneWidget);
    expect(find.textContaining('3 people'), findsOneWidget);
  });

  testWidgets('members read their messages in the inbox', (tester) async {
    final server = _Server();
    server.answer = (key) => switch (key) {
      'GET me/messages/' => _json([
        {'id': 'b-1', 'title': 'Election day', 'body': 'Polls open at 8 am.', 'created_at': '2026-10-17T06:00:00Z'},
      ]),
      _ => null,
    };
    await _pump(tester, server, const InboxPage());
    expect(find.text('Election day'), findsOneWidget);
    expect(find.text('Polls open at 8 am.'), findsOneWidget);
  });

  test('sending powers open the Messages page', () {
    for (final can in ['sendSms', 'sendWhatsApp', 'sendPushNotifications']) {
      final session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Messenger',
          accessId: 'TGCG-000301',
          scope: GeographicScope.nigeria,
          capabilities: {can},
        );
      addTearDown(session.dispose);
      expect(session.modules, contains(TgcgModule.messages), reason: can);
    }
    final coordinator = TgcgSessionController()
      ..signInFromServer(
        fullName: 'Coordinator',
        accessId: 'WC-1',
        scope: GeographicScope.nigeria,
        capabilities: {'viewLiveOperations'},
      );
    addTearDown(coordinator.dispose);
    expect(coordinator.modules, isNot(contains(TgcgModule.messages)));
  });
}
