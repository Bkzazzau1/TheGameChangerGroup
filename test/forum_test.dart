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
  String body = 'Posters are up at the market.',
  String assignment = '',
  List<Map<String, dynamic>> attachments = const [],
  int replies = 0,
  int likes = 0,
  bool isMine = false,
  bool editor = false,
  String reviewReason = '',
  String? editedAt,
}) => {
  'id': id,
  'author_name': 'Musa Bello',
  'author_role': 'PU Organising Officer',
  'scope': _unit,
  'body': body,
  'assignment': assignment,
  'status': status,
  'created_at': '2026-10-24T10:00:00Z',
  'published_at': status == 'published' ? '2026-10-24T10:00:00Z' : null,
  'edited_at': editedAt,
  'review_reason': reviewReason,
  'attachments': attachments,
  'replies': replies,
  'likes': likes,
  'liked': false,
  'is_mine': isMine,
  'can_edit': isMine,
  'can_hide': editor && status == 'published',
  'can_restore': editor && status == 'hidden',
  'can_report': !isMine && status == 'published',
};

Map<String, dynamic> _comment(
  String id, {
  required String author,
  required String body,
  String? parent,
  bool isMine = false,
  String? editedAt,
}) => {
  'id': id,
  'parent': parent,
  'author_name': author,
  'author_role': '',
  'body': body,
  'status': 'visible',
  'hide_reason': '',
  'created_at': '2026-10-24T11:00:00Z',
  'edited_at': editedAt,
  'likes': 0,
  'liked': false,
  'is_mine': isMine,
  'can_edit': isMine,
  'can_hide': false,
  'can_restore': false,
  'can_report': !isMine,
};

http.Response _me({bool editor = false}) => _json({'takes_part': true, 'editor': editor});

class _Server {
  final requests = <String>[];
  final bodies = <String, String>{};
  http.Response? Function(String key, Map<String, String> query, String body) answer =
      (_, _, _) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add('$key ${request.url.query}');
      final sent = latin1.decode(await body.toBytes());
      bodies[key] = sent;
      final response =
          answer(key, request.url.queryParameters, sent) ?? _json({'detail': 'Not found.'}, 404);
      return http.StreamedResponse(
        Stream.value(response.bodyBytes),
        response.statusCode,
        headers: response.headers,
      );
    }),
  );
}

/// An ordinary member: no role, no capabilities.
TgcgSessionController _member() =>
    TgcgSessionController()..signInMember(fullName: 'Musa Bello', membershipNumber: 'TGCG-000201');

Future<void> _pump(
  WidgetTester tester,
  _Server server, {
  TgcgSessionController? session,
  PickForumMedia? pick,
}) async {
  final signedIn = session ?? _member();
  tester.view.physicalSize = const Size(360, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(signedIn.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: server.connect(),
      child: TgcgSession(
        controller: signedIn,
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

Finder _inDialog(Finder finder) => find.descendant(of: find.byType(AlertDialog), matching: finder);

void main() {
  testWidgets('a member with no role posts a picture for an assignment and it appears at once', (
    tester,
  ) async {
    final server = _Server()
      ..answer = (key, query, _) => switch (key) {
        'GET forum/me/' => _me(),
        'GET forum/posts/' => _json(_page([])),
        'GET forum/assignments/' => _json([
          {'tag': 'Market rally', 'posts': 2},
        ]),
        'POST forum/posts/' => _json(
          _post('p1', assignment: 'Market rally', isMine: true),
          201,
        ),
        _ => null,
      };
    await _pump(
      tester,
      server,
      pick: (source) async => [
        ForumUpload(
          kind: ForumMediaKind.photo,
          fileName: 'picture.jpg',
          mimeType: 'image/jpeg',
          bytes: _jpeg,
        ),
      ],
    );

    expect(find.text('Social Forum'), findsOneWidget);
    // Not an editor.
    expect(find.text('Reports'), findsNothing);
    expect(find.text('Hidden'), findsNothing);

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

    expect(find.text('Posted.'), findsOneWidget);
    // It is in the feed straight away, with nothing waiting for approval.
    expect(find.text('Assignment: Market rally'), findsOneWidget);
    expect(find.text('WAITING FOR APPROVAL'), findsNothing);
    final sent = server.bodies['POST forum/posts/']!;
    expect(sent, contains('Posters are up.'));
    expect(sent, contains('name="assignment"'));
    expect(sent, contains('Market rally'));
    expect(sent, contains('filename="picture.jpg"'));
    expect(sent, contains('name="client_id"'));
    expect(server.requests.where((request) => request.contains('forum/settings/')), isEmpty);
  });

  testWidgets('a post shows its assignment, pictures, video, likes and comments', (tester) async {
    final server = _Server()
      ..answer = (key, query, _) => switch (key) {
        'GET forum/me/' => _me(),
        'GET forum/posts/' => _json(
          _page([
            _post(
              'p1',
              assignment: 'Market rally',
              replies: 2,
              likes: 3,
              attachments: [
                {'id': 'a1', 'kind': 'photo', 'mime_type': 'image/png', 'size': 70, 'url': ''},
                {'id': 'a2', 'kind': 'video', 'mime_type': 'video/mp4', 'size': 3145728, 'url': ''},
              ],
            ),
          ]),
        ),
        'GET forum/attachments/a1/' => http.Response.bytes(_pixel, 200),
        'POST forum/posts/p1/like/' => _json({'liked': true, 'likes': 4}),
        'DELETE forum/posts/p1/like/' => _json({'liked': false, 'likes': 3}),
        'GET forum/assignments/' => _json([
          {'tag': 'Market rally', 'posts': 1},
        ]),
        _ => null,
      };
    await _pump(tester, server);

    expect(find.text('Musa Bello'), findsOneWidget);
    expect(find.textContaining('PU Organising Officer'), findsOneWidget);
    expect(find.text('Assignment: Market rally'), findsOneWidget);
    expect(find.text('Video • 3.0 MB'), findsOneWidget);
    expect(find.text('2 comments'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(server.requests, contains('GET forum/attachments/a1/ '));

    await tester.tap(find.byTooltip('Like'));
    await tester.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    await tester.tap(find.byTooltip('Unlike'));
    await tester.pumpAndSettle();
    expect(find.text('3'), findsOneWidget);
    expect(server.requests, containsAll(['POST forum/posts/p1/like/ ', 'DELETE forum/posts/p1/like/ ']));

    await tester.tap(find.text('Assignment: Market rally'));
    await tester.pumpAndSettle();
    expect(
      server.requests.where((request) => request.contains('assignment=Market+rally')),
      isNotEmpty,
    );
  });

  testWidgets('comments come with their answers; a member answers, likes, edits and reports', (
    tester,
  ) async {
    final server = _Server()
      ..answer = (key, query, body) => switch (key) {
        'GET forum/me/' => _me(),
        'GET forum/posts/' => _json(_page([_post('p1', replies: 3)])),
        'GET forum/posts/p1/' => _json(_post('p1', replies: 4)),
        'GET forum/assignments/' => _json([]),
        'GET forum/posts/p1/replies/' => _json([
          _comment('c1', author: 'Aisha Sani', body: 'Well done.'),
          _comment('c2', author: 'Musa Bello', body: 'Thank you all.', isMine: true),
          _comment('c3', author: 'Bala Umar', body: 'Agreed.', parent: 'c1'),
        ]),
        'POST forum/posts/p1/replies/' => _json(
          _comment('c4', author: 'Musa Bello', body: 'See you there.', parent: 'c1', isMine: true),
          201,
        ),
        'POST forum/replies/c1/like/' => _json({'liked': true, 'likes': 1}),
        'PATCH forum/replies/c2/' => _json(
          _comment(
            'c2',
            author: 'Musa Bello',
            body: 'Thank you, everyone.',
            isMine: true,
            editedAt: '2026-10-24T12:00:00Z',
          ),
        ),
        'POST forum/replies/c1/report/' => _json({'id': 'r1'}, 201),
        _ => null,
      };
    await _pump(tester, server);

    await tester.tap(find.text('3 comments'));
    await tester.pumpAndSettle();
    expect(find.text('Comments (3)'), findsOneWidget);

    // The answer sits under the comment it answers, indented, before the
    // next comment.
    final comment = tester.getTopLeft(find.text('Well done.'));
    final answer = tester.getTopLeft(find.text('Agreed.'));
    final next = tester.getTopLeft(find.text('Thank you all.'));
    expect(answer.dx, greaterThan(comment.dx));
    expect(answer.dy, lessThan(next.dy));

    // Answering a comment.
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('c1')), matching: find.text('Reply')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Answering Aisha Sani'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Write an answer'), 'See you there.');
    await tester.tap(find.byTooltip('Send'));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST forum/posts/p1/replies/']!), {
      'body': 'See you there.',
      'parent': 'c1',
    });
    expect(find.text('Answering Aisha Sani'), findsNothing);
    expect(find.text('See you there.'), findsOneWidget);

    // Liking a comment.
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('c1')), matching: find.byTooltip('Like')),
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const ValueKey('c1')), matching: find.byTooltip('Unlike')),
      findsOneWidget,
    );

    // Editing one's own comment.
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('c2')), matching: find.byTooltip('More')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsNothing); // not one's own
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(_inDialog(find.byType(TextField)), 'Thank you, everyone.');
    await tester.pump();
    await tester.tap(_inDialog(find.text('Save')));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['PATCH forum/replies/c2/']!), {'body': 'Thank you, everyone.'});
    expect(find.text('Thank you, everyone.'), findsOneWidget);
    expect(
      find.descendant(of: find.byKey(const ValueKey('c2')), matching: find.textContaining('edited')),
      findsOneWidget,
    );

    // Reporting someone else's.
    await tester.tap(
      find.descendant(of: find.byKey(const ValueKey('c1')), matching: find.byTooltip('More')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsNothing);
    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    await tester.enterText(_inDialog(find.byType(TextField)), 'Insults a member.');
    await tester.pump();
    await tester.tap(_inDialog(find.text('Report')));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST forum/replies/c1/report/']!), {'reason': 'Insults a member.'});
    expect(find.text('Reported to the editors.'), findsOneWidget);
  });

  testWidgets('an author edits and deletes their own post', (tester) async {
    final server = _Server()
      ..answer = (key, query, body) => switch (key) {
        'GET forum/me/' => _me(),
        'GET forum/posts/' => _json(_page([_post('p1', isMine: true)])),
        'GET forum/assignments/' => _json([]),
        'PATCH forum/posts/p1/' => _json(
          _post(
            'p1',
            isMine: true,
            body: 'Posters are up at the main market.',
            editedAt: '2026-10-24T12:00:00Z',
          ),
        ),
        'DELETE forum/posts/p1/' => http.Response('', 204),
        _ => null,
      };
    await _pump(tester, server);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    expect(find.text('Report'), findsNothing);
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(_inDialog(find.byType(TextField)).first, 'Posters are up at the main market.');
    await tester.pump();
    await tester.tap(_inDialog(find.text('Save')));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['PATCH forum/posts/p1/']!), {
      'body': 'Posters are up at the main market.',
      'assignment': '',
    });
    expect(find.text('Posters are up at the main market.'), findsOneWidget);
    expect(find.textContaining('edited'), findsOneWidget);

    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(_inDialog(find.text('Delete')));
    await tester.pumpAndSettle();
    expect(server.requests, contains('DELETE forum/posts/p1/ '));
    expect(find.text('No posts yet'), findsOneWidget);
  });

  testWidgets('an editor hides a reported post, dismisses a report and restores a hidden post', (
    tester,
  ) async {
    Map<String, dynamic> report(String id, {String? reply, String post = 'p1'}) => {
      'id': id,
      'target': reply == null ? 'post' : 'reply',
      'post': post,
      'reply': reply,
      'author_name': 'Bala Umar',
      'excerpt': 'Something rude.',
      'target_status': reply == null ? 'published' : 'visible',
      'reason': 'Insults a member.',
      'reporter': 'Aisha Sani',
      'created_at': '2026-10-24T11:00:00Z',
      'status': 'open',
      'outcome': '',
    };
    final server = _Server()
      ..answer = (key, query, body) => switch (key) {
        'GET forum/me/' => _me(editor: true),
        'GET forum/reports/' => _json(
          _page([report('r1'), report('r2', reply: 'c9', post: 'p2'), report('r3')]),
        ),
        'GET forum/posts/' when query['show'] == 'hidden' => _json(
          _page([_post('p3', status: 'hidden', editor: true, reviewReason: 'Off topic.')]),
        ),
        'GET forum/posts/' => _json(_page([])),
        'GET forum/assignments/' => _json([]),
        'POST forum/posts/p1/hide/' => _json(_post('p1', status: 'hidden', editor: true)),
        'POST forum/reports/r2/dismiss/' => _json({...report('r2', reply: 'c9'), 'status': 'closed'}),
        'POST forum/posts/p3/restore/' => _json(_post('p3', editor: true)),
        _ => null,
      };
    await _pump(
      tester,
      server,
      session: TgcgSessionController()
        ..signInFromServer(
          fullName: 'Musa Bello',
          accessId: 'TGCG-000201',
          scope: const GeographicScope(level: GeographyLevel.ward, country: 'Nigeria', wardId: '18-23-05'),
          capabilities: const {'viewDiscussionRoom'},
        ),
    );

    await tester.tap(find.text('Reports (3)'));
    await tester.pumpAndSettle();
    expect(find.text('Reported by Aisha Sani'), findsNWidgets(3));

    // Hiding the post closes both reports about it.
    await tester.tap(find.widgetWithText(FilledButton, 'Hide').first);
    await tester.pumpAndSettle();
    await tester.enterText(_inDialog(find.byType(TextField)), 'Insults.');
    await tester.pump();
    await tester.tap(_inDialog(find.text('Hide')));
    await tester.pumpAndSettle();
    expect(jsonDecode(server.bodies['POST forum/posts/p1/hide/']!), {'reason': 'Insults.'});
    expect(find.text('Reports (1)'), findsOneWidget);
    expect(find.text('COMMENT'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(server.requests, contains('POST forum/reports/r2/dismiss/ '));
    expect(find.text('No reports'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);

    await tester.tap(find.text('Hidden'));
    await tester.pumpAndSettle();
    expect(find.text('HIDDEN'), findsOneWidget);
    expect(find.text('Off topic.'), findsOneWidget);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(server.requests, contains('POST forum/posts/p3/restore/ '));
    expect(find.text('No hidden posts'), findsOneWidget);
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
