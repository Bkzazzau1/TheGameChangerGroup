import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/meetings_repository.dart';
import 'package:tgcg_emcop/tgcg/meeting/meeting_room_page.dart';
import 'package:tgcg_emcop/tgcg/meeting/meeting_call_page.dart';
import 'package:tgcg_emcop/tgcg/meeting/server_meetings_view.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _kaduna = {
  'level': 'state',
  'country': 'Nigeria',
  'zoneId': 'NW',
  'zoneName': 'North West',
  'stateId': 'KD',
  'stateName': 'Kaduna',
};

Map<String, dynamic> _meeting(
  String reference, {
  String title = 'Ward situation call',
  String status = 'live',
  String kind = 'audio',
  String audience = 'area',
  bool canJoin = true,
  bool canManage = true,
  bool calls = true,
  List<String> invitees = const [],
}) =>
    {
      'id': '6f2c0000-0000-4000-8000-000000000001',
      'reference': reference,
      'title': title,
      'agenda': 'Turnout and security',
      'kind': kind,
      'audience': audience,
      'scope': _kaduna,
      'starts_at': '2027-02-25T09:00:00Z',
      'duration_minutes': 60,
      'ends_at': '2027-02-25T10:00:00Z',
      'status': status,
      'host': 'SC-KD',
      'host_name': 'Kaduna Coordinator',
      'invitees': invitees,
      'admitted': 2,
      'ended_at': null,
      'cancelled_at': null,
      'cancel_reason': '',
      'can_join': canJoin,
      'can_manage': canManage,
      'calls_available': calls,
      'created_at': '2027-02-25T08:30:00Z',
    };

/// A fake TGCG server holding meetings.
class _MeetingsServer {
  var meetings = <Map<String, dynamic>>[];
  final bodies = <String, Map<String, dynamic>>{};

  BackendServices connect() => BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
          if (request.method == 'POST') {
            bodies[key] = request.body.isEmpty
                ? const {}
                : jsonDecode(request.body) as Map<String, dynamic>;
          }
          return switch (key) {
            'GET meetings/' => _json({
                'count': meetings.length,
                'next': null,
                'previous': null,
                'results': meetings,
              }),
            'POST meetings/' => _json(
                _meeting('MTG-000003', title: bodies[key]!['title'] as String),
                201,
              ),
            'POST meetings/MTG-000001/join/' => _json({
                'url': 'wss://tgcg.livekit.cloud',
                'token': 'pass-token',
                'room': 'tgcg-room-1',
                'expires_at': '2027-02-25T09:30:00Z',
              }),
            'POST meetings/MTG-000002/cancel/' => _json(
                _meeting('MTG-000002', status: 'cancelled', canJoin: false),
              ),
            _ => _json({'detail': 'Not found.'}, 404),
          };
        }),
      );
}

/// No microphone, camera or network: only the room events used by the call UI.
class _CallRoom extends ChangeNotifier
    with lk.EventsEmittable<lk.RoomEvent>
    implements lk.Room {
  final participant = _CallParticipant();

  @override
  _CallParticipant get localParticipant => participant;

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
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<bool> dispose() async {
    super.dispose();
    await events.dispose();
    await participant.dispose();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CallParticipant extends ChangeNotifier implements lk.LocalParticipant {
  @override
  String get name => 'Meeting host';
  @override
  String get identity => 'SC-KD';
  @override
  bool get isSpeaking => false;
  @override
  bool get isMuted => false;
  @override
  List<lk.LocalTrackPublication<lk.LocalVideoTrack>>
  get videoTrackPublications => const [];
  @override
  bool isMicrophoneEnabled() => true;
  @override
  Future<lk.LocalTrackPublication?> setMicrophoneEnabled(
    bool enabled, {
    lk.AudioCaptureOptions? audioCaptureOptions,
  }) async => null;

  @override
  Future<bool> dispose() async {
    super.dispose();
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NavigationObserver extends NavigatorObserver {
  final popped = <String?>[];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route.settings.name);
  }
}

void main() {
  group('ending a call', () {
    late _CallRoom room;
    late Completer<http.Response> ended;
    late GlobalKey<NavigatorState> navigator;
    late _NavigationObserver navigation;

    Future<void> openCall(WidgetTester tester) async {
      room = _CallRoom();
      ended = Completer<http.Response>();
      navigator = GlobalKey<NavigatorState>();
      navigation = _NavigationObserver();
      final backend = BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) => ended.future),
      );
      await tester.pumpWidget(
        TgcgBackend(
          services: backend,
          child: MaterialApp(
            navigatorKey: navigator,
            navigatorObservers: [navigation],
            home: const Scaffold(body: Text('Home page')),
          ),
        ),
      );
      unawaited(
        navigator.currentState!.push<void>(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'meetings'),
            builder: (_) => const Scaffold(body: Text('Meeting list')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(
        navigator.currentState!.push<String>(
          MaterialPageRoute(
            settings: const RouteSettings(name: 'call'),
            builder: (_) => MeetingCallPage(
              meeting: ServerMeeting.fromJson(_meeting('MTG-000001')),
              pass: JoinPass(
                url: 'wss://tgcg.test',
                token: 'test-pass',
                room: 'test-room',
                expiresAt: DateTime.utc(2027),
              ),
              createRoom: () => room,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final disconnectFirst in [true, false]) {
      testWidgets(
        '${disconnectFirst ? 'disconnect before end response' : 'end response before disconnect'} closes only the call',
        (tester) async {
          await openCall(tester);
          await tester.tap(find.text('End for everyone'));
          await tester.pumpAndSettle();
          await tester.tap(
            find.descendant(
              of: find.byType(AlertDialog),
              matching: find.widgetWithText(FilledButton, 'End for everyone'),
            ),
          );
          await tester.pumpAndSettle();

          void disconnected() => room.events.streamCtrl.add(
            lk.RoomDisconnectedEvent(reason: lk.DisconnectReason.roomDeleted),
          );
          void response() =>
              ended.complete(_json(_meeting('MTG-000001', status: 'ended')));
          if (disconnectFirst) {
            disconnected();
            await tester
                .pump(); // Keep the call mounted during its exit animation.
            response();
          } else {
            response();
            await tester.pump();
            disconnected();
          }
          await tester.pumpAndSettle();
          expect(
            navigation.popped.where((name) => name == 'call'),
            hasLength(1),
          );
          expect(navigation.popped, isNot(contains('meetings')));
          expect(find.text('Meeting list'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('Back followed by a disconnect keeps the meeting list open', (
      tester,
    ) async {
      await openCall(tester);
      await tester.pageBack();
      await tester.pump();
      room.events.streamCtrl.add(
        lk.RoomDisconnectedEvent(reason: lk.DisconnectReason.roomDeleted),
      );
      await tester.pumpAndSettle();
      expect(navigation.popped.where((name) => name == 'call'), hasLength(1));
      expect(navigation.popped, isNot(contains('meetings')));
      expect(find.text('Meeting list'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
    testWidgets('disconnect during end confirmation closes the dialog and call', (tester) async {
      await openCall(tester);
      await tester.tap(find.text('End for everyone'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      room.events.streamCtrl.add(
        lk.RoomDisconnectedEvent(reason: lk.DisconnectReason.roomDeleted),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Meeting list'), findsOneWidget);
      expect(navigation.popped.where((name) => name == 'call'), hasLength(1));
      expect(navigation.popped, isNot(contains('meetings')));
      expect(tester.takeException(), isNull);
    });
  });

  test('meetings and join passes read from the server', () {
    final meeting = ServerMeeting.fromJson(
      _meeting('MTG-000001', kind: 'video', audience: 'invited', invitees: ['NCO-1']),
    );
    expect(meeting.kind, MeetingKind.video);
    expect(meeting.audience, MeetingAudience.invited);
    expect(meeting.status, MeetingStatus.live);
    expect(meeting.scope.stateId, 'KD');
    expect(meeting.invitees, ['NCO-1']);
    expect(meeting.durationMinutes, 60);

    final pass = JoinPass.fromJson({
      'url': 'wss://tgcg.livekit.cloud',
      'token': 't',
      'room': 'tgcg-room-1',
      'expires_at': '2027-02-25T09:30:00Z',
    });
    expect(pass.room, 'tgcg-room-1');

    expect(scopeInput(GeographicScope.nigeria), {'level': 'country'});
    expect(
      scopeInput(const GeographicScope(level: GeographyLevel.lga, country: 'Nigeria', lgaId: 'KD-ZARIA')),
      {'level': 'lga', 'lgaId': 'KD-ZARIA'},
    );
  });

  group('the meeting list', () {
    late _MeetingsServer server;
    late BackendServices backend;
    late TgcgSessionController session;

    setUp(() {
      server = _MeetingsServer()
        ..meetings = [
          _meeting('MTG-000001'),
          _meeting('MTG-000002', title: 'Collation briefing', status: 'scheduled'),
        ];
      backend = server.connect();
      session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Kaduna Coordinator',
          accessId: 'SC-KD',
          scope: const GeographicScope(
            level: GeographyLevel.state,
            country: 'Nigeria',
            stateId: 'KD',
            stateName: 'Kaduna',
          ),
          capabilities: {'viewMeetingRoom', 'startMeeting', 'joinMeeting'},
        );
    });

    tearDown(() => session.dispose());

    Future<void> pump(WidgetTester tester, Widget page) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        TgcgBackend(
          services: backend,
          child: TgcgSession(
            controller: session,
            child: MaterialApp(home: Scaffold(body: page)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('the Meeting Room shows the server meetings', (tester) async {
      await pump(tester, const MeetingRoomPage());
      expect(find.text('Open now'), findsOneWidget);
      expect(find.text('Ward situation call'), findsOneWidget);
      expect(find.text('Collation briefing'), findsOneWidget);
      expect(find.textContaining('Demo data'), findsNothing);
    });

    testWidgets('joining opens the call with the server pass', (tester) async {
      JoinPass? opened;
      await pump(
        tester,
        ServerMeetingsView(
          openCall: (context, meeting, pass) async {
            opened = pass;
            return 'The meeting has ended.';
          },
        ),
      );
      expect(find.text('Coming up'), findsOneWidget);
      // Only the open meeting can be joined.
      expect(find.widgetWithText(FilledButton, 'Join'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Join'));
      await tester.pumpAndSettle();
      expect(server.bodies.containsKey('POST meetings/MTG-000001/join/'), isTrue);
      expect(opened!.token, 'pass-token');
      expect(find.text('The meeting has ended.'), findsOneWidget);
    });

    testWidgets('a new meeting is sent to the server', (tester) async {
      await pump(tester, const ServerMeetingsView());
      await tester.tap(find.text('New meeting'));
      await tester.pumpAndSettle();
      final start = find.widgetWithText(FilledButton, 'Start meeting');
      expect(tester.widget<FilledButton>(start).onPressed, isNull);
      await tester.enterText(find.byType(TextField).first, 'Turnout check');
      await tester.pump();
      await tester.tap(start);
      await tester.pumpAndSettle();
      expect(server.bodies['POST meetings/'], {
        'title': 'Turnout check',
        'agenda': '',
        'kind': 'audio',
        'audience': 'area',
        'duration_minutes': 60,
        'invitees': <String>[],
      });
      expect(find.text('Turnout check is set up (MTG-000003).'), findsOneWidget);
    });

    testWidgets('cancelling a meeting needs a reason', (tester) async {
      await pump(tester, const ServerMeetingsView());
      await tester.tap(find.text('Cancel meeting').last);
      await tester.pumpAndSettle();
      final confirm = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Cancel meeting'),
      );
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
      await tester.enterText(
        find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField)),
        'Clashes with the INEC briefing',
      );
      await tester.pump();
      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(server.bodies['POST meetings/MTG-000002/cancel/'], {
        'reason': 'Clashes with the INEC briefing',
      });
    });

    testWidgets('without calls set up, meetings show but cannot be joined', (tester) async {
      server.meetings = [_meeting('MTG-000001', calls: false)];
      session.updateAccess(capabilities: {'viewMeetingRoom', 'joinMeeting'}, grants: const []);
      await pump(tester, const ServerMeetingsView());
      expect(find.textContaining('Calls are not set up on the server yet'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Join')).onPressed, isNull);
      expect(find.text('New meeting'), findsNothing);
    });
  });
}
