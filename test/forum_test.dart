import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/forum_repository.dart';
import 'package:tgcg_emcop/tgcg/discussion/discussion_room_page.dart';
import 'package:tgcg_emcop/tgcg/discussion/forum_media.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

// Names here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Map<String, dynamic> _page(List<Object> results) =>
    {'count': results.length, 'next': null, 'previous': null, 'results': results};

// A 1x1 PNG.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);
final _jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, ...List.filled(32, 0)]);

const _unit = {
  'level': 'pollingUnit',
  'country': 'Nigeria',
  'stateId': 'KD',
  'lgaId': 'KD-ZARIA',
  'wardId': '18-23-05',
  'pollingUnitId': '18-23-05-001',
  'pollingUnitName': 'KAURA PRIMARY SCHOOL',
};

Map<String, dynamic> _post(
  String id, {
  String status = 'published',
  String assignment = '',
  List<Map<String, dynamic>> attachments = const [],
  int replies = 0,
  bool canModerate = false,
  bool isMine = false,
}) => {
  'id': id,
  'author_name': 'Musa Bello',
  'author_role': 'PU Organising Officer',
  'scope': _unit,
  'body': 'Posters are up at the market.',
  'assignment': assignment,
  'status': status,
  'created_at': '2026-10-15T10:00:00Z',
  'published_at': status == 'published' ? '2026-10-15T10:05:00Z' : null,
  'review_reason': '',
  'attachments': attachments,
  'replies': replies,
  'is_mine': isMine,
  'can_moderate': canModerate,
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
      bodies[key] = latin1.decode(await body.toBytes());
      final response =
          answer(key, request.url.queryParameters) ?? _json({'detail': 'Not found.'}, 404);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );
}

TgcgSessionController _signedIn(Set<String> capabilities) => TgcgSessionController()
  ..signInFromServer(
    fullName: 'Musa Bello',
    accessId: 'TGCG-000201',
    scope: const GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      pollingUnitId: '18-23-05-001',
    ),
    capabilities: capabilities,
  );

Future<void> _pump(
  WidgetTester tester,
  _Server server,
  TgcgSessionController session, {
  PickForumMedia? pick,
}) async {
  tester.view.physicalSize = const Size(360, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: server.connect(),
      child: TgcgSession(
        controller: session,
        child: MaterialApp(
          home: Scaffold(
            body: pick == null ? const DiscussionRoomPage() : DiscussionRoomPage(pickMedia: pick),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _poster = {'viewDiscussionRoom', 'createDiscussionThread', 'postDiscussionReply'};

void main() {
  testWidgets('a polling unit executive posts a picture for an assignment and waits for approval', (
    tester,
  ) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET forum/posts/' when query['show'] == 'mine' => _json(
          _page([_post('p1', status: 'pending', assignment: 'Market rally', isMine: true)]),
        ),
        'GET forum/posts/' => _json(_page([])),
        'GET forum/settings/' => _json({'approval_required': true, 'can_change': false}),
        'GET forum/assignments/' => _json([
          {'tag': 'Market rally', 'posts': 2},
        ]),
        'POST forum/posts/' => _json(
          _post('p1', status: 'pending', assignment: 'Market rally', isMine: true),
          201,
        ),
        _ => null,
      };
    await _pump(
      tester,
      server,
      _signedIn(_poster),
      pick: (source) async => [
        ForumUpload(
          kind: ForumMediaKind.photo,
          fileName: 'picture.jpg',
          mimeType: 'image/jpeg',
          bytes: _jpeg,
        ),
      ],
    );

    // Not a moderator, not the administrator.
    expect(find.text('To approve'), findsNothing);
    expect(find.byTooltip('Forum settings'), findsNothing);

    await tester.enterText(find.widgetWithText(TextField, 'Share an update'), 'Posters are up.');
    // Assignments already in use are offered while typing.
    await tester.enterText(find.widgetWithText(TextField, 'Assignment (optional)'), 'market');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Market rally'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Take a picture'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Remove'), findsOneWidget);
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    expect(find.text('Sent to your ward coordinator for approval.'), findsOneWidget);
    final sent = server.bodies['POST forum/posts/']!;
    expect(sent, contains('Posters are up.'));
    expect(sent, contains('name="assignment"'));
    expect(sent, contains('Market rally'));
    expect(sent, contains('filename="picture.jpg"'));
    expect(sent, contains('name="client_id"'));

    // Their own posts show it waiting.
    await tester.tap(find.text('My posts'));
    await tester.pumpAndSettle();
    expect(find.text('WAITING FOR APPROVAL'), findsOneWidget);
    expect(find.text('Assignment: Market rally'), findsOneWidget);
  });

  testWidgets('the ward coordinator approves a waiting post', (tester) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET forum/posts/' when query['show'] == 'review' => _json(
          _page([_post('p1', status: 'pending', canModerate: true)]),
        ),
        'GET forum/posts/' => _json(_page([])),
        'GET forum/settings/' => _json({'approval_required': true, 'can_change': false}),
        'GET forum/assignments/' => _json([]),
        'POST forum/posts/p1/approve/' => _json(_post('p1', canModerate: true)),
        _ => null,
      };
    await _pump(tester, server, _signedIn({..._poster, 'moderateDiscussion'}));

    await tester.tap(find.text('To approve (1)'));
    await tester.pumpAndSettle();
    expect(find.text('WAITING FOR APPROVAL'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(server.requests, contains('POST forum/posts/p1/approve/ '));
    expect(find.text('WAITING FOR APPROVAL'), findsNothing);
    expect(find.text('To approve'), findsOneWidget);
  });

  testWidgets('the National Administrator switches approval off', (tester) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET forum/posts/' => _json(_page([])),
        'GET forum/settings/' => _json({'approval_required': true, 'can_change': true}),
        'PATCH forum/settings/' => _json({'approval_required': false, 'can_change': true}),
        'GET forum/assignments/' => _json([]),
        _ => null,
      };
    await _pump(tester, server, _signedIn({..._poster, 'moderateDiscussion'}));

    await tester.tap(find.byTooltip('Forum settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(jsonDecode(server.bodies['PATCH forum/settings/']!), {'approval_required': false});
    expect(find.text('Forum settings'), findsNothing); // the dialog closed
  });

  testWidgets('a post shows its assignment, pictures, video and replies, and filters by assignment', (
    tester,
  ) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET forum/posts/' => _json(
          _page([
            _post(
              'p1',
              assignment: 'Market rally',
              replies: 2,
              attachments: [
                {'id': 'a1', 'kind': 'photo', 'mime_type': 'image/png', 'size': 70, 'url': ''},
                {'id': 'a2', 'kind': 'video', 'mime_type': 'video/mp4', 'size': 3145728, 'url': ''},
              ],
            ),
          ]),
        ),
        'GET forum/attachments/a1/' => http.Response.bytes(_pixel, 200),
        'GET forum/settings/' => _json({'approval_required': true, 'can_change': false}),
        'GET forum/assignments/' => _json([
          {'tag': 'Market rally', 'posts': 1},
        ]),
        _ => null,
      };
    await _pump(tester, server, _signedIn({'viewDiscussionRoom'}));

    // Only reading: no composer.
    expect(find.text('Share an update'), findsNothing);
    expect(find.text('Musa Bello'), findsOneWidget);
    expect(find.text('PU Organising Officer • Kaura Primary School'), findsNothing);
    expect(find.textContaining('PU Organising Officer'), findsOneWidget);
    expect(find.text('Assignment: Market rally'), findsOneWidget);
    expect(find.text('Video • 3.0 MB'), findsOneWidget);
    expect(find.text('2 replies'), findsOneWidget);
    expect(server.requests, contains('GET forum/attachments/a1/ '));

    await tester.tap(find.text('Assignment: Market rally'));
    await tester.pumpAndSettle();
    expect(
      server.requests.where((request) => request.contains('assignment=Market+rally')),
      isNotEmpty,
    );
  });

  test('pictures and videos are named for what they really are', () {
    final photo = forumUploadFrom('IMG_1.png', _jpeg)!;
    expect(photo.kind, ForumMediaKind.photo);
    expect(photo.fileName, 'IMG_1.jpg');
    final mp4 = Uint8List.fromList([0, 0, 0, 24, ...ascii.encode('ftypmp42'), ...List.filled(8, 0)]);
    expect(forumUploadFrom('clip', mp4)!.fileName, 'clip.mp4');
    final mov = Uint8List.fromList([0, 0, 0, 24, ...ascii.encode('ftypqt  '), ...List.filled(8, 0)]);
    expect(forumUploadFrom('clip.mp4', mov)!.mimeType, 'video/quicktime');
    expect(forumUploadFrom('notes.pdf', Uint8List.fromList(ascii.encode('%PDF-1.4'))), isNull);
  });
}
