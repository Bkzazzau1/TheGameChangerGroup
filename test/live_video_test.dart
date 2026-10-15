import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/field_repository.dart';
import 'package:tgcg_emcop/tgcg/field/live_video_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _unit = {
  'level': 'pollingUnit',
  'country': 'Nigeria',
  'zoneId': 'NW',
  'stateId': 'KD',
  'lgaId': 'KD-ZARIA',
  'wardId': '18-23-05',
  'pollingUnitId': '18-23-05-001',
};

Map<String, dynamic> _incident({bool live = false}) => {
  'reference': 'INC-000007',
  'title': 'Ballot box snatched',
  'category': 'Violence / threat',
  'severity': 'high',
  'status': 'reported',
  'scope': _unit,
  'reporter': 'AG-1',
  'reported_at': '2027-02-20T10:00:00Z',
  'evidence': <Object>[],
  'live': {'id': 'l1', 'is_live': live, 'started_by': 'AG-1', 'recording': 'recording'},
};

Map<String, dynamic> _pass(String room) => {
  'stream': {'id': 'l1', 'is_live': true, 'started_by': 'AG-1', 'recording': 'recording'},
  'url': 'wss://tgcg.livekit.cloud',
  'token': 'pass-for-$room',
  'room': room,
  'expires_at': '2027-02-20T10:30:00Z',
};

class _Room extends ChangeNotifier with lk.EventsEmittable<lk.RoomEvent> implements lk.Room {
  final participant = _Me();
  final connected = <String>[];
  var disconnected = false;

  @override
  _Me get localParticipant => participant;

  @override
  UnmodifiableMapView<String, lk.RemoteParticipant> get remoteParticipants =>
      UnmodifiableMapView(const {});

  @override
  Future<void> connect(
    String url,
    String token, {
    lk.ConnectOptions? connectOptions,
    lk.RoomOptions? roomOptions,
    lk.FastConnectOptions? fastConnectOptions,
  }) async => connected.add('$url $token');

  @override
  Future<void> disconnect() async => disconnected = true;

  @override
  Future<bool> dispose() async {
    super.dispose();
    await events.dispose();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Me extends ChangeNotifier implements lk.LocalParticipant {
  bool? camera;
  lk.CameraPosition? cameraPosition;
  var microphone = false;

  @override
  List<lk.LocalTrackPublication<lk.LocalVideoTrack>> get videoTrackPublications => const [];

  @override
  bool isMicrophoneEnabled() => microphone;

  @override
  Future<lk.LocalTrackPublication?> setCameraEnabled(
    bool enabled, {
    lk.CameraCaptureOptions? cameraCaptureOptions,
  }) async {
    camera = enabled;
    cameraPosition = cameraCaptureOptions?.cameraPosition;
    return null;
  }

  @override
  Future<lk.LocalTrackPublication?> setMicrophoneEnabled(
    bool enabled, {
    lk.AudioCaptureOptions? audioCaptureOptions,
  }) async {
    microphone = enabled;
    return null;
  }

  @override
  Future<bool> dispose() async {
    super.dispose();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<String> requests;
  late _Room room;

  Future<void> open(WidgetTester tester, Widget Function() page) async {
    requests = [];
    room = _Room();
    final backend = BackendServices.connect(
      'https://api.tgcg.test',
      tokens: MemoryTokenStore(),
      httpClient: MockClient((request) async {
        final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
        requests.add(key);
        return switch (key) {
          'POST incidents/INC-000007/live/start/' => _json(_pass('tgcg-live-1')),
          'POST incidents/INC-000007/live/watch/' => _json(_pass('tgcg-live-1')),
          'POST incidents/INC-000007/live/end/' => _json(_incident()),
          _ => _json({'detail': 'Not found.'}, 404),
        };
      }),
    );
    final session = TgcgSessionController()
      ..signInFromServer(
        role: TgcgRole.pollingUnitAgent,
        fullName: 'Agent One',
        accessId: 'AG-1',
        scope: GeographicScope.nigeria,
        capabilities: {'createIncident', 'viewIncidents'},
      );
    addTearDown(session.dispose);
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      TgcgBackend(
        services: backend,
        child: TgcgSession(
          controller: session,
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(
                      context,
                    ).push(MaterialPageRoute<void>(builder: (_) => page())),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('the reporter broadcasts from the back camera, then ends the live video', (
    tester,
  ) async {
    final incident = fieldIncidentFromJson(_incident(live: true));
    await open(tester, () => LiveBroadcastPage(incident: incident, createRoom: () => room));

    expect(requests, ['POST incidents/INC-000007/live/start/']);
    expect(room.connected, ['wss://tgcg.livekit.cloud pass-for-tgcg-live-1']);
    expect(room.participant.camera, isTrue);
    expect(room.participant.cameraPosition, lk.CameraPosition.back);
    expect(room.participant.microphone, isTrue);
    expect(find.text('LIVE'), findsOneWidget);

    await tester.tap(find.text('End live video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(requests.last, 'POST incidents/INC-000007/live/end/');
    expect(room.disconnected, isTrue);
    expect(find.text('Open'), findsOneWidget); // back where it was opened
  });

  testWidgets('a coordinator watches until the live video ends', (tester) async {
    final incident = fieldIncidentFromJson(_incident(live: true));
    await open(tester, () => LiveWatchPage(incident: incident, createRoom: () => room));

    expect(requests, ['POST incidents/INC-000007/live/watch/']);
    expect(room.connected, ['wss://tgcg.livekit.cloud pass-for-tgcg-live-1']);
    expect(room.participant.camera, isNull); // watchers never broadcast
    expect(find.text('Waiting for the video…'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);

    room.events.streamCtrl.add(lk.RoomDisconnectedEvent(reason: lk.DisconnectReason.roomDeleted));
    await tester.pump();
    expect(find.text('The live video has ended.'), findsOneWidget);
  });

  test('an incident says when it is live', () {
    expect(fieldIncidentFromJson(_incident(live: true)).isLive, isTrue);
    expect(fieldIncidentFromJson(_incident()).isLive, isFalse);
    expect(fieldIncidentFromJson(_incident()).liveRecording, 'recording');
  });
}
