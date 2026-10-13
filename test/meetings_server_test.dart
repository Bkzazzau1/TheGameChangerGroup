import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/meetings_repository.dart';
import 'package:tgcg_emcop/tgcg/meeting/meeting_room_page.dart';
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

void main() {
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
