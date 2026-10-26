import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/askme/ask_me_chat.dart';
import 'package:tgcg_emcop/tgcg/askme/ask_me_hub_page.dart';
import 'package:tgcg_emcop/tgcg/askme/ask_me_voice.dart';
import 'package:tgcg_emcop/tgcg/evidence/evidence_upload.dart';
import 'package:tgcg_emcop/tgcg/evidence/voice_note.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

// Questions and answers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _page(List<Object> results) =>
    {'count': results.length, 'next': null, 'previous': null, 'results': results};

final _wav = Uint8List.fromList([...'RIFF'.codeUnits, ...List.filled(40, 0)]);
final _mp3 = Uint8List.fromList([...'ID3'.codeUnits, ...List.filled(40, 0)]);

Map<String, dynamic> _me({bool voiceReady = true, bool? voiceOk, bool review = false, bool approve = false}) => {
  'can_ask': true,
  'enabled': true,
  'training_ok': false,
  'asked_today': 0,
  'daily_limit': 20,
  'can_review': review || approve,
  'can_approve': approve,
  'ai_ready': true,
  'voice_ready': voiceReady,
  'voice_ok': voiceOk,
};

Map<String, dynamic> _answer({String channel = 'voice'}) => {
  'id': 'q1',
  'text': 'Me gwamnati ta yi wa dalibai?',
  'language': 'ha',
  'channel': channel,
  'status': 'answered',
  'answer': 'Gwamnati ta ba dalibai lamuni.',
  'sources': [],
  'rating': null,
  'created_at': '2026-10-26T10:00:00Z',
};

class _Recorder implements VoiceRecorder {
  _Recorder({this.allowed = true});

  final bool allowed;
  var started = false;

  @override
  Future<bool> start() async => started = allowed;

  @override
  Future<PendingEvidence?> stop() async =>
      evidenceFromBytes(type: EvidenceType.audio, name: 'voice-note.wav', bytes: _wav, mimeType: 'audio/wav');

  @override
  Future<void> cancel() async {}

  @override
  Future<void> dispose() async {}
}

class _Speaker implements AskMeSpeaker {
  final played = <(int, String)>[];
  var stops = 0;

  @override
  Future<void> play(Uint8List audio, {required String id}) async => played.add((audio.length, id));

  @override
  Future<void> stop() async => stops++;
}

class _Server {
  final requests = <String>[];
  final bodies = <String, String>{};
  http.Response? Function(String key) answer = (_) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add(key);
      bodies[key] = latin1.decode(await body.toBytes());
      final response = answer(key) ?? _json({'detail': 'Not found.'}, 404);
      return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode, headers: response.headers);
    }),
  );
}

Future<void> _pump(WidgetTester tester, _Server server, Widget page) async {
  tester.view.physicalSize = const Size(420, 1100);
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
  testWidgets('a member speaks in Hausa and hears the answer', (tester) async {
    final recorder = _Recorder();
    final speaker = _Speaker();
    var me = _me();
    final server = _Server()
      ..answer = (key) => switch (key) {
        'GET askme/me/' => _json(me),
        'PATCH askme/me/' => _json(me = _me(voiceOk: true)),
        'GET askme/questions/' => _json(_page([])),
        'POST askme/ask/voice/' => _json(_answer(), 201),
        'GET askme/questions/q1/audio/' => http.Response.bytes(_mp3, 200, headers: {'content-type': 'audio/mpeg'}),
        _ => null,
      };
    await _pump(tester, server, AskMeChat(newRecorder: () => recorder, newSpeaker: () => speaker));

    await tester.tap(find.byTooltip('Speak'));
    await tester.pumpAndSettle();
    // "Any language" was chosen, so it asks which one will be spoken.
    await tester.tap(find.text('Hausa').last);
    await tester.pumpAndSettle();
    // And, once, whether the recordings may be kept.
    expect(find.text('Keep your recordings?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Yes'));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['PATCH askme/me/']!), {'voice_ok': true});
    expect(recorder.started, isTrue);
    expect(find.textContaining('Listening (Hausa)'), findsOneWidget);

    await tester.tap(find.byTooltip('Send recording'));
    await tester.pumpAndSettle();
    final sent = server.bodies['POST askme/ask/voice/']!;
    expect(sent, contains('name="language"'));
    expect(sent, contains('ha'));
    expect(sent, contains('filename="voice-note.wav"'));
    expect(find.text('Me gwamnati ta yi wa dalibai?'), findsOneWidget);
    expect(find.text('Gwamnati ta ba dalibai lamuni.'), findsOneWidget);
    // The answer plays at once.
    expect(server.requests, contains('GET askme/questions/q1/audio/'));
    expect(speaker.played, [(_mp3.length, 'q1')]);
    expect(find.text('Stop'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(speaker.stops, greaterThan(0));
    expect(find.text('Listen'), findsOneWidget);
  });

  testWidgets('typed answers can be heard too, and there is no microphone without voice', (tester) async {
    final speaker = _Speaker();
    final server = _Server()
      ..answer = (key) => switch (key) {
        'GET askme/me/' => _json(_me()),
        'GET askme/questions/' => _json(_page([_answer(channel: 'text')])),
        'GET askme/questions/q1/audio/' => http.Response.bytes(_mp3, 200),
        _ => null,
      };
    await _pump(tester, server, AskMeChat(newSpeaker: () => speaker));
    await tester.tap(find.text('Listen'));
    await tester.pumpAndSettle();
    expect(speaker.played.single.$2, 'q1');

    final quiet = _Server()
      ..answer = (key) => switch (key) {
        'GET askme/me/' => _json(_me(voiceReady: false)),
        'GET askme/questions/' => _json(_page([_answer(channel: 'text')])),
        _ => null,
      };
    await _pump(tester, quiet, const AskMeChat(key: ValueKey('quiet')));
    expect(find.byTooltip('Speak'), findsNothing);
    expect(find.text('Listen'), findsNothing);
  });

  testWidgets('a refused microphone says so', (tester) async {
    final server = _Server()
      ..answer = (key) => switch (key) {
        'GET askme/me/' => _json(_me(voiceOk: false)),
        'GET askme/questions/' => _json(_page([])),
        _ => null,
      };
    await _pump(tester, server, AskMeChat(newRecorder: () => _Recorder(allowed: false)));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Igbo'));
    await tester.pump();
    await tester.tap(find.byTooltip('Speak'));
    await tester.pumpAndSettle();
    expect(find.text('Allow the microphone to speak your question.'), findsOneWidget);
    expect(server.requests.where((request) => request.startsWith('POST')), isEmpty);
  });

  testWidgets('reviewers play a kept recording and write what was really said', (tester) async {
    final speaker = _Speaker();
    final queued = {
      'id': 'r1',
      'text': 'Me gwamnati ta yi wa dalibai?',
      'language': 'ha',
      'channel': 'voice',
      'corrected_text': '',
      'has_recording': true,
      'status': 'answered',
      'route': 'ai',
      'answer': 'Gwamnati ta ba dalibai lamuni.',
      'corrected_answer': '',
      'sources': [],
      'check_failed': '',
      'rating': null,
      'flag_reason': '',
      'review': 'unreviewed',
      'training_ok': true,
      'created_at': '2026-10-26T09:00:00Z',
    };
    final server = _Server()
      ..answer = (key) => switch (key) {
        'GET askme/me/' => _json(_me(review: true)),
        'GET askme/questions/' => _json(_page([])),
        'GET askme/review/' => _json(_page([queued])),
        'GET askme/review/r1/recording/' => http.Response.bytes(_wav, 200),
        'POST askme/review/r1/heard/' => _json({...queued, 'corrected_text': 'Me gwamnati ta yi wa ɗalibai?'}),
        _ => null,
      };
    await _pump(tester, server, AskMeHubPage(newSpeaker: () => speaker));
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(find.text('Spoken'), findsOneWidget);

    await tester.tap(find.text('Play recording'));
    await tester.pumpAndSettle();
    expect(speaker.played.single, (_wav.length, 'r1'));

    await tester.tap(find.text('Fix what was heard'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
      'Me gwamnati ta yi wa ɗalibai?',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(utf8.decode(latin1.encode(server.bodies['POST askme/review/r1/heard/']!)), contains('ɗalibai'));
    expect(find.text('Really said: Me gwamnati ta yi wa ɗalibai?'), findsOneWidget);
  });

  testWidgets('the administrator chooses a voice for each language', (tester) async {
    final server = _Server()
      ..answer = (key) => switch (key) {
        'GET askme/me/' => _json(_me(approve: true)),
        'GET askme/questions/' => _json(_page([])),
        'GET askme/settings/' => _json({
          'enabled': true,
          'tone': 'calm',
          'daily_limit': 20,
          'monthly_ai_limit': 5000,
          'silence_starts_at': null,
          'silence_ends_at': null,
          'not_yet_messages': {},
          'voice_enabled': true,
          'voices': {},
          'voice_ready': true,
          'voice_options': {
            'ha': {
              'voices': ['hasan', 'amina', 'zainab', 'aliyu'],
              'chosen': 'aliyu',
            },
          },
          'in_silence': false,
          'ai_answers_this_month': 0,
        }),
        'PATCH askme/settings/' => _json({'enabled': true, 'voice_enabled': false}),
        _ => null,
      };
    await _pump(tester, server, const AskMeHubPage());
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Aliyu'), findsOneWidget);
    await tester.tap(find.text('Aliyu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amina').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Members may speak and listen'));
    await tester.pump();
    // The list builds its end only once scrolled to.
    await tester.scrollUntilVisible(find.text('Save settings'), 300, scrollable: find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save settings'));
    await tester.pumpAndSettle();
    final saved = jsonDecode(server.bodies['PATCH askme/settings/']!) as Map<String, dynamic>;
    expect(saved['voice_enabled'], isFalse);
    expect(saved['voices'], {'ha': 'amina'});
  });
}
