import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/askme/ask_me_chat.dart';
import 'package:tgcg_emcop/tgcg/askme/ask_me_hub_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

// Names, questions and figures here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _page(List<Object> results) =>
    {'count': results.length, 'next': null, 'previous': null, 'results': results};

Map<String, dynamic> _me({
  bool canAsk = true,
  bool? trainingOk = false,
  bool review = false,
  bool approve = false,
}) => {
  'can_ask': canAsk,
  'enabled': canAsk,
  'training_ok': trainingOk,
  'asked_today': 0,
  'daily_limit': 20,
  'can_review': review || approve,
  'can_approve': approve,
  'ai_ready': true,
};

const _source = {'title': 'Student loans', 'url': 'https://www.statehouse.gov.ng/loans', 'date': null};

Map<String, dynamic> _answer({String status = 'answered', int? rating}) => {
  'id': 'q1',
  'text': 'Me gwamnati ta yi wa dalibai?',
  'language': 'ha',
  'status': status,
  'answer': 'Gwamnati ta ba dalibai lamuni.',
  'sources': status == 'answered' ? [_source] : [],
  'rating': rating,
  'created_at': '2026-10-25T10:00:00Z',
};

class _Server {
  final requests = <String>[];
  final bodies = <String, String>{};
  http.Response? Function(String key, Map<String, String> query) answer = (_, _) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add('$key ${request.url.query}');
      bodies[key] = utf8.decode(await body.toBytes());
      final response = answer(key, request.url.queryParameters) ?? _json({'detail': 'Not found.'}, 404);
      return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode, headers: response.headers);
    }),
  );
}

Future<void> _pump(WidgetTester tester, _Server server, Widget page) async {
  tester.view.physicalSize = const Size(400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TgcgSessionController()..signInMember(fullName: 'Ada Obi', membershipNumber: 'TGCG-000201');
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: server.connect(),
      child: TgcgSession(controller: session, child: MaterialApp(home: Scaffold(body: page))),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a member asks in Hausa, opens the source and marks an answer unhelpful', (tester) async {
    final opened = <Uri>[];
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET askme/me/' => _json(_me()),
        'GET askme/questions/' => _json(_page([])),
        'POST askme/ask/' => _json(_answer(), 201),
        'POST askme/questions/q1/rate/' => _json(_answer(rating: -1)),
        _ => null,
      };
    await _pump(
      tester,
      server,
      AskMeChat(
        openSource: (uri) async {
          opened.add(uri);
          return true;
        },
      ),
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Hausa'));
    await tester.enterText(find.byType(TextField), 'Me gwamnati ta yi wa dalibai?');
    await tester.tap(find.byTooltip('Ask'));
    await tester.pumpAndSettle();

    expect(jsonDecode(server.bodies['POST askme/ask/']!), {
      'text': 'Me gwamnati ta yi wa dalibai?',
      'language': 'ha',
    });
    expect(find.text('Gwamnati ta ba dalibai lamuni.'), findsOneWidget);
    expect(find.text('TGCG Ask Me · AI'), findsOneWidget);
    await tester.tap(find.text('Source: statehouse.gov.ng'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://www.statehouse.gov.ng/loans');

    await tester.tap(find.byTooltip('Not helpful'));
    await tester.pumpAndSettle();
    await tester.enterText(find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)), 'Too short');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST askme/questions/q1/rate/']!), {'rating': -1, 'reason': 'Too short'});
    expect(find.byIcon(Icons.thumb_down_alt_rounded), findsOneWidget);
  });

  testWidgets('the first time, a member is asked about training, once', (tester) async {
    var consent = <String, dynamic>{..._me(trainingOk: null)};
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET askme/me/' => _json(consent),
        'PATCH askme/me/' => _json(consent = {..._me(trainingOk: true)}),
        'GET askme/questions/' => _json(_page([_answer(status: 'not_yet')])),
        _ => null,
      };
    await _pump(tester, server, const AskMeChat());

    // Earlier questions show, oldest first.
    expect(find.text('Me gwamnati ta yi wa dalibai?'), findsOneWidget);
    expect(find.textContaining('May TGCG use your questions'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['PATCH askme/me/']!), {'training_ok': true});
    expect(find.textContaining('May TGCG use your questions'), findsNothing);
  });

  testWidgets('until it opens, members are told so', (tester) async {
    final server = _Server()
      ..answer = (key, query) => key == 'GET askme/me/' ? _json(_me(canAsk: false)) : null;
    await _pump(tester, server, const AskMeChat());
    expect(find.text('Ask Me is not open yet'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('a reviewer corrects an answer, and the administrator approves an item and opens Ask Me', (
    tester,
  ) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET askme/me/' => _json(_me(approve: true)),
        'GET askme/questions/' => _json(_page([])),
        'GET askme/review/' => _json(
          _page([
            {
              'id': 'r1',
              'text': 'How do I collect my PVC?',
              'language': 'en',
              'status': 'not_yet',
              'route': 'none',
              'answer': '',
              'corrected_answer': '',
              'sources': [],
              'check_failed': 'No AI key on the server: a reviewer answers it.',
              'rating': null,
              'flag_reason': '',
              'review': 'unreviewed',
              'training_ok': true,
              'created_at': '2026-10-25T09:00:00Z',
            },
          ]),
        ),
        'POST askme/review/r1/decide/' => _json({
          'id': 'r1',
          'text': 'How do I collect my PVC?',
          'status': 'not_yet',
          'review': 'corrected',
        }),
        'GET askme/items/' => _json(
          _page([
            {
              'id': 'i1',
              'topic': 'voting',
              'title': 'Collecting your PVC',
              'fact': 'Collect your PVC at your INEC local government office.',
              'status': 'draft',
              'review_note': '',
            },
          ]),
        ),
        'POST askme/items/i1/approve/' => _json({'id': 'i1', 'title': 'Collecting your PVC', 'fact': '', 'status': 'approved'}),
        'GET askme/settings/' => _json({
          'enabled': false,
          'tone': 'calm',
          'daily_limit': 20,
          'monthly_ai_limit': 5000,
          'silence_starts_at': null,
          'silence_ends_at': null,
          'not_yet_messages': {},
          'in_silence': false,
          'ai_answers_this_month': 12,
        }),
        'PATCH askme/settings/' => _json({'enabled': true, 'tone': 'passionate', 'daily_limit': 20, 'monthly_ai_limit': 5000}),
        _ => null,
      };
    await _pump(tester, server, const AskMeHubPage());

    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('How do I collect my PVC?'), findsOneWidget);
    expect(find.textContaining('Held back: No AI key'), findsOneWidget);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Write the answer'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'Go to your INEC local government office.',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save answer'));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST askme/review/r1/decide/']!), {
      'decision': 'correct',
      'corrected_answer': 'Go to your INEC local government office.',
    });
    expect(find.text('How do I collect my PVC?'), findsNothing);

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(server.requests, contains('GET askme/items/ status=draft'));
    await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
    await tester.pumpAndSettle();
    expect(server.requests, contains('POST askme/items/i1/approve/ '));
    // Clear the "Saved" and "Approved" messages from the bottom of the screen.
    tester.state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger)).clearSnackBars();
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('AI answers this month: 12 of 5000'), findsOneWidget);
    await tester.tap(find.text('Open to members'));
    await tester.tap(find.text('Passionate advocate'));
    await tester.pump();
    await tester.ensureVisible(find.text('Save settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    final saved = jsonDecode(server.bodies['PATCH askme/settings/']!) as Map<String, dynamic>;
    expect(saved['enabled'], isTrue);
    expect(saved['tone'], 'passionate');
  });

  testWidgets('a member without a review power gets only the questions', (tester) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET askme/me/' => _json(_me()),
        'GET askme/questions/' => _json(_page([])),
        _ => null,
      };
    await _pump(tester, server, const AskMeHubPage());
    expect(find.text('Review'), findsNothing);
    expect(find.text('Ask me anything'), findsOneWidget);
  });
}
