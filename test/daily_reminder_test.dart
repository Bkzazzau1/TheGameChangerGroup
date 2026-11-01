import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/app.dart';
import 'package:tgcg_emcop/tgcg/election/daily_reminder.dart';
import 'package:tgcg_emcop/tgcg/member/member_shell.dart' show MyRolesPage;
import 'package:tgcg_emcop/tgcg/session.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_theme.dart';

import 'support/command_fixtures.dart';
import 'support/redesign_fixtures.dart';

// Names here are made up.

const _area = {
  'level': 'lga',
  'country': 'Nigeria',
  'stateId': 'KD',
  'lgaId': 'KD-ZARIA',
  'lgaName': 'Zaria',
};

/// 76 days before the presidential election.
final _morning = DateTime.utc(2026, 11, 1, 9);

Map<String, dynamic> _appointment({String? acceptedAt, String state = 'active'}) => {
  'id': 'a1',
  'member': 'TGCG-000200',
  'member_name': 'Ada Obi',
  'role': 'ward-secretary',
  'role_name': 'Ward Secretary',
  'supervising_role': null,
  'areas': [_area],
  'restricted_permissions': null,
  'permissions': <String>[],
  'starts_at': '2026-10-11T08:00:00Z',
  'ends_at': null,
  'state': state,
  'status_reason': '',
  'status_changed_at': null,
  'accepted_at': acceptedAt,
  'granted_by': 'NA-1',
  'authority': 'nationalAdministrator',
};

Map<String, dynamic> _project({
  required String answer,
  String name = 'Ward mobilisation',
  Duration startsIn = const Duration(days: 2),
  Duration endsIn = const Duration(days: 3),
}) => {
  'id': 'p-$name',
  'name': name,
  'description': '',
  'starts_at': _morning.add(startsIn).toIso8601String(),
  'ends_at': _morning.add(endsIn).toIso8601String(),
  'status': 'scheduled',
  'areas': [_area],
  'election': null,
  'check_place': false,
  'cancel_reason': '',
  'my_participation': {
    'id': 'w-$name',
    'project': 'p-$name',
    'project_name': name,
    'member': 'TGCG-000200',
    'member_name': 'Ada Obi',
    'place': _area,
    'status': answer,
    'assigned_by': 'WC-1',
    'reason': '',
  },
  'can_manage': false,
  'can_assign': false,
};

Map<String, dynamic> _dispatch({String status = 'sent'}) => {
  'id': 'd1',
  'status': status,
  'next': ['accepted'],
  'incident': {
    'reference': 'INC-1',
    'title': 'Crowd at the collation centre',
    'category': 'security',
    'severity': 'high',
    'status': 'open',
    'reported_at': '2026-11-01T08:00:00Z',
    'scope': _area,
    'place': 'Zaria',
  },
  'sent_by': 'Situation Room',
  'sent_at': '2026-11-01T08:10:00Z',
};

class _Clock {
  _Clock(this.now);

  DateTime now;
  DateTime call() => now;
}

class _BrokenLog implements ReminderLog {
  @override
  Future<DateTime?> lastShown(String account) => Future.error(StateError('no storage'));

  @override
  Future<void> shown(String account, DateTime at) => Future.error(StateError('no storage'));
}

TgcgSessionController _member({String number = 'TGCG-000200', String? waitingRole}) =>
    TgcgSessionController()
      ..signInMember(fullName: 'Ada Obi', membershipNumber: number, waitingRole: waitingRole);

TgcgSessionController _staff(Set<String> capabilities) => TgcgSessionController()
  ..signInFromServer(
    fullName: 'Sani Garba',
    accessId: 'WC-1',
    scope: GeographicScope.nigeria,
    capabilities: capabilities,
  );

/// The server of someone with nothing waiting.
http.Response? _nothing(String path) => switch (path) {
  'me/assignments/' || 'me/projects/' || 'me/security/' => jsonResponse(<Object>[]),
  'me/member/' => jsonResponse(fakeCard()),
  'members/' ||
  'pvc-updates/' ||
  'polling-unit-changes/' => jsonResponse({'count': 0, 'results': <Object>[]}),
  _ => null,
};

Future<void> _open(
  WidgetTester tester, {
  required TgcgSessionController session,
  required ReminderLog log,
  required _Clock clock,
  http.Response? Function(String path) answer = _nothing,
  Key? key,
}) async {
  await tester.pumpWidget(
    TgcgBackend(
      key: key,
      services: fakeBackend((path) => answer(path) ?? _nothing(path)),
      child: TgcgSession(
        controller: session,
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
  await tester.pumpAndSettle();
}

Future<void> _close(WidgetTester tester) async {
  await tester.tap(find.text('Close'));
  await tester.pumpAndSettle();
}

Future<void> _comeBack(WidgetTester tester) async {
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it shows the days left, the PVC reminder and what is waiting', (tester) async {
    await _open(
      tester,
      session: _member(),
      log: MemoryReminderLog(),
      clock: _Clock(_morning),
      answer: (path) => switch (path) {
        'me/assignments/' => jsonResponse([_appointment()]),
        'me/projects/' => jsonResponse([
          _project(answer: 'invited'),
          _project(answer: 'accepted', name: 'Polling unit drive'),
          _project(answer: 'declined', name: 'Declined work'),
        ]),
        'me/member/' => jsonResponse(fakeCard(missing: ['pvc_photo', 'gender'])),
        _ => null,
      },
    );

    expect(find.text('76'), findsOneWidget);
    expect(find.text('days to go'), findsOneWidget);
    expect(find.text('Saturday, 16 January 2027'), findsOneWidget);
    expect(find.text('Get your PVC ready'), findsOneWidget);
    expect(find.text('TO FOLLOW UP'), findsOneWidget);
    expect(find.text('You are asked to take part in Ward mobilisation'), findsOneWidget);
    expect(find.text('Polling unit drive'), findsOneWidget);
    expect(find.text('Declined work'), findsNothing);
    expect(find.text('You are appointed Ward Secretary'), findsOneWidget);
    expect(find.text('Accept or decline it in Roles and access'), findsOneWidget);
    expect(find.text('Complete your membership card'), findsOneWidget);
    expect(find.text('Add a photo of your PVC, your gender'), findsOneWidget);
  });

  testWidgets('it comes once in 24 hours, and again when the app is opened after that', (
    tester,
  ) async {
    final log = MemoryReminderLog();
    final clock = _Clock(_morning);
    await _open(tester, session: _member(), log: log, clock: clock, key: const ValueKey(1));
    await _close(tester);

    // Signing in again, or opening the app, within the 24 hours.
    clock.now = _morning.add(const Duration(hours: 23, minutes: 59));
    await _open(tester, session: _member(), log: log, clock: clock, key: const ValueKey(2));
    expect(find.text('Get your PVC ready'), findsNothing);
    await _comeBack(tester);
    expect(find.text('Get your PVC ready'), findsNothing);

    clock.now = _morning.add(const Duration(hours: 24));
    await _open(tester, session: _member(), log: log, clock: clock, key: const ValueKey(3));
    expect(find.text('Get your PVC ready'), findsOneWidget);
    await _close(tester);

    // Coming back to an app that stayed open.
    clock.now = _morning.add(const Duration(hours: 48));
    await _comeBack(tester);
    expect(find.text('Get your PVC ready'), findsOneWidget);
  });

  testWidgets('each account has its own 24 hours on a shared phone', (tester) async {
    final log = MemoryReminderLog();
    final clock = _Clock(_morning);
    await _open(tester, session: _member(), log: log, clock: clock, key: const ValueKey(1));
    await _close(tester);
    await _open(
      tester,
      session: _member(number: 'TGCG-000999'),
      log: log,
      clock: clock,
      key: const ValueKey(2),
    );
    expect(find.text('Get your PVC ready'), findsOneWidget);
  });

  testWidgets('a clock that was once set ahead does not silence it', (tester) async {
    final log = MemoryReminderLog();
    await log.shown('TGCG-000200', _morning.add(const Duration(days: 300)));
    await _open(tester, session: _member(), log: log, clock: _Clock(_morning));
    expect(find.text('Get your PVC ready'), findsOneWidget);
  });

  testWidgets('a follow-up opens its page, and the reminder is gone on the way back', (
    tester,
  ) async {
    await _open(
      tester,
      session: _member(),
      log: MemoryReminderLog(),
      clock: _Clock(_morning),
      answer: (path) => path == 'me/assignments/' ? jsonResponse([_appointment()]) : null,
    );
    await tester.tap(find.text('You are appointed Ward Secretary'));
    await tester.pumpAndSettle();
    expect(find.byType(MyRolesPage), findsOneWidget);
    expect(find.text('Get your PVC ready'), findsNothing);

    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Get your PVC ready'), findsNothing);
  });

  testWidgets('reviewers see their reviews, security officers the incidents with them', (
    tester,
  ) async {
    await _open(
      tester,
      session: _staff({'verifyMemberIdentity', 'reviewPollingUnitChanges', 'respondToSecurity'}),
      log: MemoryReminderLog(),
      clock: _Clock(_morning),
      answer: (path) => switch (path) {
        'me/security/' => jsonResponse([_dispatch(), _dispatch(status: 'resolved')]),
        'members/' => jsonResponse({'count': 1200, 'results': <Object>[]}),
        'pvc-updates/' => jsonResponse({'count': 1, 'results': <Object>[]}),
        _ => null,
      },
    );
    expect(find.text('An incident was sent to you'), findsOneWidget);
    expect(find.text('Crowd at the collation centre'), findsOneWidget);
    expect(find.text('1,201 reviews are waiting'), findsOneWidget);
    expect(find.text('1,200 identities · 1 PVC update'), findsOneWidget);
  });

  testWidgets('only powers the account holds are asked about', (tester) async {
    final asked = <String>[];
    await tester.pumpWidget(
      TgcgBackend(
        services: fakeBackend(_nothing, requests: asked),
        child: TgcgSession(
          controller: _staff(const {}),
          child: MaterialApp(
            home: DailyReminder(
              log: MemoryReminderLog(),
              clock: _Clock(_morning).call,
              child: const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(asked, ['me/assignments/']);
  });

  testWidgets('a member waiting for their identity check is told so', (tester) async {
    await _open(
      tester,
      session: _member(waitingRole: 'polling unit agent'),
      log: MemoryReminderLog(),
      clock: _Clock(_morning),
    );
    expect(find.text('You are listed as a polling unit agent'), findsOneWidget);
  });

  testWidgets('with nothing waiting it makes no claim about it', (tester) async {
    await _open(tester, session: _member(), log: MemoryReminderLog(), clock: _Clock(_morning));
    expect(find.text('Get your PVC ready'), findsOneWidget);
    expect(find.text('TO FOLLOW UP'), findsNothing);
    expect(find.textContaining('could not be checked'), findsNothing);
  });

  testWidgets('it says so when the assignments could not be checked', (tester) async {
    await _open(
      tester,
      session: _member(),
      log: MemoryReminderLog(),
      clock: _Clock(_morning),
      answer: (_) => jsonResponse({'detail': 'The server could not answer.'}, 500),
    );
    expect(find.text('Get your PVC ready'), findsOneWidget);
    expect(find.text('Your assignments could not be checked just now.'), findsOneWidget);
  });

  testWidgets('what did arrive still shows when one part fails', (tester) async {
    await _open(
      tester,
      session: _member(),
      log: MemoryReminderLog(),
      clock: _Clock(_morning),
      answer: (path) => switch (path) {
        'me/assignments/' => jsonResponse([_appointment()]),
        'me/projects/' => jsonResponse({'detail': 'The server could not answer.'}, 500),
        _ => null,
      },
    );
    expect(find.text('You are appointed Ward Secretary'), findsOneWidget);
    expect(find.text('Your assignments could not be checked just now.'), findsOneWidget);
  });

  testWidgets('on election day it says to take the card along', (tester) async {
    await _open(
      tester,
      session: _member(),
      log: MemoryReminderLog(),
      clock: _Clock(DateTime.utc(2027, 1, 16, 7)),
    );
    expect(find.text('Election Day'), findsOneWidget);
    expect(find.text('Take your PVC with you'), findsOneWidget);
    expect(find.text('Get your PVC ready'), findsNothing);
  });

  testWidgets('after the election only assignments bring it up', (tester) async {
    final after = _Clock(DateTime.utc(2027, 1, 18, 9));
    await _open(tester, session: _member(), log: MemoryReminderLog(), clock: after);
    expect(find.byType(Dialog), findsNothing);

    await _open(
      tester,
      session: _member(),
      log: MemoryReminderLog(),
      clock: after,
      answer: (path) => path == 'me/assignments/' ? jsonResponse([_appointment()]) : null,
      key: const ValueKey('with work'),
    );
    expect(find.text('You are appointed Ward Secretary'), findsOneWidget);
    expect(find.textContaining('PVC'), findsNothing);
  });

  testWidgets('it waits for an open page to close', (tester) async {
    final log = MemoryReminderLog();
    final clock = _Clock(_morning);
    await log.shown('TGCG-000200', _morning.subtract(const Duration(hours: 23)));
    await _open(tester, session: _member(), log: log, clock: clock);
    expect(find.text('Get your PVC ready'), findsNothing);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    final page = navigator.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('A form'))),
    );
    await tester.pumpAndSettle();
    clock.now = _morning.add(const Duration(hours: 2));
    await _comeBack(tester);
    expect(find.text('Get your PVC ready'), findsNothing);

    navigator.pop();
    await page;
    await tester.pumpAndSettle();
    expect(find.text('Get your PVC ready'), findsOneWidget);
  });

  testWidgets('signing out takes it away', (tester) async {
    final session = _member();
    await _open(tester, session: session, log: MemoryReminderLog(), clock: _Clock(_morning));
    expect(find.text('Get your PVC ready'), findsOneWidget);
    session.signOut();
    await tester.pumpAndSettle();
    expect(find.text('Get your PVC ready'), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('a device that cannot remember stays quiet', (tester) async {
    await _open(tester, session: _member(), log: _BrokenLog(), clock: _Clock(_morning));
    expect(find.byType(Dialog), findsNothing);
  });

  test('the device keeps the time for each account', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final log = DeviceReminderLog();
    expect(await log.lastShown('TGCG-000200'), isNull);
    await log.shown('TGCG-000200', _morning);
    expect(await log.lastShown('TGCG-000200'), _morning);
    expect(await log.lastShown('TGCG-000999'), isNull);
  });

  group('in the app', () {
    setUpAll(loadMapOnce);

    testWidgets('it follows signing in, whatever page the app opens on', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final services = BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          final path = request.url.path.replaceFirst('/api/v1/', '');
          if (path == 'me/assignments/') return jsonResponse([_appointment()]);
          return commandServer(path, request.url.queryParameters) ??
              jsonResponse({'detail': 'Not found.'}, 404);
        }),
      );
      await tester.pumpWidget(TgcgApp(backend: services, reminderLog: MemoryReminderLog()));
      await signInAsCoordinator(tester, 1400);
      expect(find.text('You are appointed Ward Secretary'), findsOneWidget);
    });

    testWidgets('a test that brings its own server sees none', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(TgcgApp(backend: commandBackend()));
      await signInAsCoordinator(tester, 1400);
      expect(find.byType(Dialog), findsNothing);
    });
  });
}
