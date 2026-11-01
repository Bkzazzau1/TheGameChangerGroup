import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/election/daily_reminder.dart';
import 'package:tgcg_emcop/tgcg/messaging/inbox_page.dart';
import 'package:tgcg_emcop/tgcg/messaging/popup_post_dialog.dart';
import 'package:tgcg_emcop/tgcg/messaging/popups_page.dart';
import 'package:tgcg_emcop/tgcg/api/popups_repository.dart';
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_theme.dart';

import 'support/redesign_fixtures.dart';
import 'support/review_fixtures.dart';

// Names here are made up.

const _countdown = 'Get your PVC ready';
final _morning = DateTime.utc(2026, 11, 1, 9);

Map<String, dynamic> _post({
  String id = 'p1',
  String title = 'Rally on Saturday',
  String frequency = 'daily',
  bool picture = false,
  String link = '',
  String label = '',
}) => {
  'id': id,
  'title': title,
  'body': 'Meet at the ward secretariat at 4pm.',
  'has_picture': picture,
  'link_url': link,
  'link_label': label,
  'frequency': frequency,
};

class _Clock {
  _Clock(this.now);

  DateTime now;
  DateTime call() => now;
}

http.Response? _nothing(String path) => switch (path) {
  'me/assignments/' || 'me/projects/' || 'me/popups/' => jsonResponse(<Object>[]),
  'me/member/' => jsonResponse(fakeCard()),
  _ => null,
};

TgcgSessionController _member() =>
    TgcgSessionController()..signInMember(fullName: 'Ada Obi', membershipNumber: 'TGCG-000200');

Future<void> _open(
  WidgetTester tester, {
  required ReminderLog log,
  required _Clock clock,
  List<Map<String, dynamic>> posts = const [],
  http.Response? Function(String path)? answer,
  TgcgSessionController? session,
  Key? key,
}) async {
  await tester.pumpWidget(
    TgcgBackend(
      key: key,
      services: fakeBackend(
        (path) =>
            answer?.call(path) ??
            switch (path) {
              'me/popups/' => jsonResponse(posts),
              'popups/p1/picture/' => http.Response.bytes(tinyPicture, 200),
              _ => _nothing(path),
            },
      ),
      child: TgcgSession(
        controller: session ?? _member(),
        child: MaterialApp(
          theme: tgcgTheme(),
          home: DailyReminder(
            log: log,
            clock: clock.call,
            child: const Scaffold(body: Text('Home')),
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

/// Pictures decode outside the test's own clock.
Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.text('Close'));
  await _settle(tester);
}

Future<void> _comeBack(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await _settle(tester);
}

/// Opens the app afresh: a page load, or a phone starting it again.
Future<void> _reopen(
  WidgetTester tester,
  int time, {
  required ReminderLog log,
  required _Clock clock,
  List<Map<String, dynamic>> posts = const [],
}) => _open(tester, log: log, clock: clock, posts: posts, key: ValueKey(time));

void main() {
  group('a posted message', () {
    testWidgets('takes the place of the countdown', (tester) async {
      await _open(
        tester,
        log: MemoryReminderLog(),
        clock: _Clock(_morning),
        posts: [
          _post(picture: true, link: 'https://tgcg.online/rally', label: 'Read more'),
        ],
      );
      expect(find.text('Rally on Saturday'), findsOneWidget);
      expect(find.text('Meet at the ward secretariat at 4pm.'), findsOneWidget);
      expect(find.text('Read more'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.text(_countdown), findsNothing);
    });

    testWidgets('with nothing posted, the countdown remains', (tester) async {
      await _open(tester, log: MemoryReminderLog(), clock: _Clock(_morning));
      expect(find.text(_countdown), findsOneWidget);
    });

    testWidgets('a server without pop-ups leaves the countdown too', (tester) async {
      await _open(
        tester,
        log: MemoryReminderLog(),
        clock: _Clock(_morning),
        answer: (path) =>
            path == 'me/popups/' ? jsonResponse({'detail': 'Not found.'}, 404) : null,
      );
      expect(find.text(_countdown), findsOneWidget);
    });

    testWidgets('its assignments still come with it', (tester) async {
      await _open(
        tester,
        log: MemoryReminderLog(),
        clock: _Clock(_morning),
        posts: [_post()],
        answer: (path) =>
            path == 'me/member/' ? jsonResponse(fakeCard(missing: ['pvc_photo'])) : null,
      );
      expect(find.text('Rally on Saturday'), findsOneWidget);
      expect(find.text('Complete your membership card'), findsOneWidget);
    });

    testWidgets('the words still show when the picture cannot be fetched', (tester) async {
      await _open(
        tester,
        log: MemoryReminderLog(),
        clock: _Clock(_morning),
        posts: [_post(picture: true)],
        answer: (path) => path == 'popups/p1/picture/'
            ? jsonResponse({'detail': 'The server could not answer.'}, 500)
            : null,
      );
      expect(find.text('Rally on Saturday'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('its button opens the link', (tester) async {
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PopupPostDialog(
            post: PopupPost.fromJson(
              _post(link: 'https://tgcg.online/rally', label: 'Read more'),
            ),
            openLink: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      );
      await tester.tap(find.text('Read more'));
      expect(opened.single.toString(), 'https://tgcg.online/rally');
    });

    testWidgets('closing it brings no second pop-up', (tester) async {
      await _open(
        tester,
        log: MemoryReminderLog(),
        clock: _Clock(_morning),
        posts: [_post(frequency: 'once')],
      );
      await _close(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('several show one after the other, the newest first', (tester) async {
      await _open(
        tester,
        log: MemoryReminderLog(),
        clock: _Clock(_morning),
        posts: [
          _post(id: 'p2', title: 'Newest', frequency: 'once'),
          _post(id: 'p3', title: 'Older', frequency: 'once'),
        ],
      );
      expect(find.text('Newest'), findsOneWidget);
      await _close(tester);
      expect(find.text('Older'), findsOneWidget);
      await _close(tester);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('a new message is found when coming back to the app', (tester) async {
      var posts = <Map<String, dynamic>>[];
      final clock = _Clock(_morning);
      await _open(
        tester,
        log: MemoryReminderLog(),
        clock: clock,
        answer: (path) => path == 'me/popups/' ? jsonResponse(posts) : null,
      );
      await _close(tester); // the countdown

      posts = [_post()];
      clock.now = _morning.add(const Duration(minutes: 1));
      await _comeBack(tester);
      expect(find.text('Rally on Saturday'), findsNothing); // read a minute ago

      clock.now = _morning.add(const Duration(minutes: 6));
      await _comeBack(tester);
      expect(find.text('Rally on Saturday'), findsOneWidget);
    });
  });

  group('how often it shows', () {
    testWidgets('once only: then the countdown comes back', (tester) async {
      final log = MemoryReminderLog();
      final clock = _Clock(_morning);
      final posts = [_post(frequency: 'once')];
      await _reopen(tester, 1, log: log, clock: clock, posts: posts);
      expect(find.text('Rally on Saturday'), findsOneWidget);
      await _close(tester);

      await _reopen(tester, 2, log: log, clock: clock, posts: posts);
      expect(find.byType(Dialog), findsNothing);

      clock.now = _morning.add(const Duration(hours: 24));
      await _reopen(tester, 3, log: log, clock: clock, posts: posts);
      expect(find.text('Rally on Saturday'), findsNothing);
      expect(find.text(_countdown), findsOneWidget);
    });

    testWidgets('once a day', (tester) async {
      final log = MemoryReminderLog();
      final clock = _Clock(_morning);
      final posts = [_post()];
      await _reopen(tester, 1, log: log, clock: clock, posts: posts);
      await _close(tester);

      clock.now = _morning.add(const Duration(hours: 23));
      await _reopen(tester, 2, log: log, clock: clock, posts: posts);
      expect(find.byType(Dialog), findsNothing);

      clock.now = _morning.add(const Duration(hours: 24));
      await _reopen(tester, 3, log: log, clock: clock, posts: posts);
      expect(find.text('Rally on Saturday'), findsOneWidget);
      expect(find.text(_countdown), findsNothing);
    });

    testWidgets('once a week, with the countdown on the days between', (tester) async {
      final log = MemoryReminderLog();
      final clock = _Clock(_morning);
      final posts = [_post(frequency: 'weekly')];
      await _reopen(tester, 1, log: log, clock: clock, posts: posts);
      await _close(tester);

      clock.now = _morning.add(const Duration(days: 6));
      await _reopen(tester, 2, log: log, clock: clock, posts: posts);
      expect(find.text('Rally on Saturday'), findsNothing);
      expect(find.text(_countdown), findsOneWidget);
      await _close(tester);

      clock.now = _morning.add(const Duration(days: 7));
      await _reopen(tester, 3, log: log, clock: clock, posts: posts);
      expect(find.text('Rally on Saturday'), findsOneWidget);
    });

    testWidgets('every sign-in, but not on every glance away', (tester) async {
      final log = MemoryReminderLog();
      final clock = _Clock(_morning);
      final posts = [_post(frequency: 'everyOpen')];
      await _reopen(tester, 1, log: log, clock: clock, posts: posts);
      await _close(tester);

      await _reopen(tester, 2, log: log, clock: clock, posts: posts);
      expect(find.text('Rally on Saturday'), findsOneWidget);
      await _close(tester);

      // Away for a moment, as when taking a photo.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.now = _morning.add(const Duration(minutes: 10));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _comeBack(tester);
      expect(find.text('Rally on Saturday'), findsNothing);

      // Away long enough to count as opening it again.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock.now = _morning.add(const Duration(minutes: 50));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await _comeBack(tester);
      expect(find.text('Rally on Saturday'), findsOneWidget);
    });

    testWidgets('each account keeps its own count', (tester) async {
      final log = MemoryReminderLog();
      final clock = _Clock(_morning);
      final posts = [_post(frequency: 'once')];
      await _open(tester, log: log, clock: clock, posts: posts, key: const ValueKey(1));
      await _close(tester);
      await _open(
        tester,
        log: log,
        clock: clock,
        posts: posts,
        session: TgcgSessionController()
          ..signInMember(fullName: 'Sani Garba', membershipNumber: 'TGCG-000999'),
        key: const ValueKey(2),
      );
      expect(find.text('Rally on Saturday'), findsOneWidget);
    });
  });

  group('posting', () {
    List<http.Request> requests() => [];

    Future<BackendServices> pumpPage(
      WidgetTester tester, {
      required List<Map<String, dynamic>> posts,
      required List<http.Request> sent,
      http.Response Function()? refuse,
      PickPopupImage? pickImage,
    }) async {
      tester.view.physicalSize = const Size(900, 1300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          final path = request.url.path.replaceFirst('/api/v1/', '');
          if (request.method == 'POST') sent.add(request);
          if (path == 'popups/' && request.method == 'GET') {
            return jsonResponse({'count': posts.length, 'next': null, 'results': posts});
          }
          if (path == 'popups/' && request.method == 'POST') {
            return refuse?.call() ?? jsonResponse(_post(), 201);
          }
          if (path.endsWith('/stop/')) return jsonResponse(_post());
          return jsonResponse({'detail': 'Not found.'}, 404);
        }),
      );
      await tester.pumpWidget(
        TgcgBackend(
          services: services,
          child: MaterialApp(
            theme: tgcgTheme(),
            home: Scaffold(body: PopupsPage(pickImage: pickImage ?? () async => null)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return services;
    }

    Map<String, dynamic> posted({String state = 'showing', String frequency = 'once'}) => {
      ..._post(frequency: frequency),
      'starts_at': '2026-11-01T09:00:00Z',
      'state': state,
      'author': 'Aisha Bello',
    };

    testWidgets('someone with the power finds the page in the menu', (tester) async {
      final session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Aisha Bello',
          accessId: 'TGCG-000300',
          scope: GeographicScope.nigeria,
          capabilities: {'postPopups'},
        );
      expect(session.modules, contains(TgcgModule.popups));
      session.signInFromServer(
        fullName: 'Sani Garba',
        accessId: 'TGCG-000301',
        scope: GeographicScope.nigeria,
        capabilities: {'viewGeography'},
      );
      expect(session.modules, isNot(contains(TgcgModule.popups)));
    });

    testWidgets('a message goes out with its picture, frequency and button', (tester) async {
      final sent = requests();
      await pumpPage(
        tester,
        posts: const [],
        sent: sent,
        pickImage: () async => (bytes: tinyPicture, name: 'rally.png'),
      );
      expect(find.text('No messages yet'), findsOneWidget);

      await tester.tap(find.text('New message'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Post to everyone')).onPressed,
        isNull,
      );

      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Rally on Saturday');
      await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Meet at 4pm.');
      await tester.enterText(find.widgetWithText(TextField, 'Words on a button (optional)'), 'Read');
      await tester.enterText(
        find.widgetWithText(TextField, 'Link the button opens'),
        'https://tgcg.online/rally',
      );
      await tester.tap(find.text('Add a picture'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('popup-frequency')));
      await tester.tap(find.byKey(const ValueKey('popup-frequency')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Once a week').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Post to everyone'));
      await tester.pumpAndSettle();

      final body = utf8.decode(sent.single.bodyBytes, allowMalformed: true);
      for (final words in [
        'name="title"',
        'Rally on Saturday',
        'Meet at 4pm.',
        'name="frequency"',
        'weekly',
        'https://tgcg.online/rally',
        'name="picture"; filename="rally.png"',
      ]) {
        expect(body, contains(words));
      }
      expect(find.text('New pop-up message'), findsNothing);
    });

    testWidgets('what the server refuses is said beside the field', (tester) async {
      await pumpPage(
        tester,
        posts: const [],
        sent: requests(),
        refuse: () => jsonResponse({
          'link_url': ['Use a link that starts with https://.'],
        }, 400),
      );
      await tester.tap(find.text('New message'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Rally');
      await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Meet at 4pm.');
      await tester.pump();
      await tester.tap(find.text('Post to everyone'));
      await tester.pumpAndSettle();
      expect(find.text('Use a link that starts with https://.'), findsOneWidget);
      expect(find.text('New pop-up message'), findsOneWidget); // nothing written is lost
    });

    testWidgets('the preview shows it as people will see it', (tester) async {
      await pumpPage(tester, posts: const [], sent: requests());
      await tester.tap(find.text('New message'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Title'), 'Rally on Saturday');
      await tester.enterText(find.widgetWithText(TextField, 'Message'), 'Meet at 4pm.');
      await tester.pump();
      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.byType(PopupPostDialog), findsOneWidget);
    });

    testWidgets('each message shows how it stands, and one showing can be stopped', (
      tester,
    ) async {
      final sent = requests();
      await pumpPage(
        tester,
        sent: sent,
        posts: [
          posted(),
          {...posted(state: 'ended'), 'id': 'p2', 'title': 'Last month'},
        ],
      );
      expect(find.text('Showing'), findsOneWidget);
      expect(find.text('Ended'), findsOneWidget);
      expect(find.textContaining('Once only · From'), findsNWidgets(2));
      expect(find.widgetWithText(TextButton, 'Stop'), findsOneWidget); // only on the live one

      await tester.tap(find.widgetWithText(TextButton, 'Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);

      await tester.tap(find.widgetWithText(TextButton, 'Stop'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop it'));
      await tester.pumpAndSettle();
      expect(sent.single.url.path, endsWith('popups/p1/stop/'));
    });
  });

  group('the in-app notifications', () {
    testWidgets('a pop-up there keeps its picture', (tester) async {
      await tester.pumpWidget(
        TgcgBackend(
          services: fakeBackend(
            (path) => switch (path) {
              'me/messages/' => jsonResponse([
                {
                  'id': 'p1',
                  'title': 'Rally on Saturday',
                  'body': 'Meet at 4pm.',
                  'created_at': '2026-11-01T09:00:00Z',
                  'popup': 'p1',
                },
                {
                  'id': 'n1',
                  'title': 'You have been given a position',
                  'body': 'You are appointed Ward Secretary for Kaduna.',
                  'created_at': '2026-10-31T09:00:00Z',
                },
              ]),
              'popups/p1/picture/' => http.Response.bytes(tinyPicture, 200),
              _ => null,
            },
          ),
          child: const MaterialApp(home: InboxPage()),
        ),
      );
      await _settle(tester);
      expect(find.text('Rally on Saturday'), findsOneWidget);
      expect(find.text('You have been given a position'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
