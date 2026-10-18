import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/member_admin_repository.dart' show AreaRef;
import 'package:tgcg_emcop/tgcg/domain/models.dart' show GeographyLevel;
import 'package:tgcg_emcop/tgcg/membership/members_exco_page.dart';
import 'package:tgcg_emcop/tgcg/ui/tgcg_design.dart' show TgcgSectionCard;

// Names and numbers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _Server {
  final requests = <String>[];
  FutureOr<http.Response?> Function(String path, Map<String, String> query) answer = (_, _) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient((request) async {
      final path = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add('$path?${request.url.query}');
      return await answer(path, request.url.queryParameters) ??
          _json({'detail': 'Not found.'}, 404);
    }),
  );
}

Map<String, dynamic> _scope(String level, {String? state, String? stateName}) => {
  'level': level,
  'country': 'Nigeria',
  'stateId': state,
  'stateName': stateName,
};

Map<String, dynamic> _analysis({required bool national}) => {
  'scope': national ? _scope('country') : _scope('state', state: 'KD', stateName: 'Kaduna'),
  'members': {
    'total': 1200,
    'new_7_days': 40,
    'new_30_days': 310,
    'previous_7_days': 28,
    'previous_30_days': 250,
    'fully_verified': 90,
    'with_role': 140,
    'with_disability': 12,
    'verification': {'verified': 600, 'pendingReview': 200, 'unverified': 390, 'rejected': 10},
    'verification_sources': {'automatic': 100, 'chapter': 450, 'person': 50},
    'standing': {'active': 1192, 'suspended': 5, 'deactivated': 3},
    'gender': {'female': 480, 'male': 600, '': 120},
    'channel': {'self': 700, 'import': 400, 'referred': 100},
    'age': {
      'under18': 0,
      '18-24': 200,
      '25-34': 400,
      '35-44': 250,
      '45-54': 100,
      '55-64': 50,
      '65+': 20,
      'unknown': 180,
    },
    'profile': {
      'vin': 800,
      'cardPhoto': 300,
      'selfie': 350,
      'gender': 1080,
      'dateOfBirth': 1020,
      'phoneConfirmed': 0,
      'appAccount': 1100,
      'signedIn': 640,
    },
    'accounts': {
      'without_account': 100,
      'never_signed_in': 460,
      'last_sign_in_7_days': 240,
      'last_sign_in_30_days': 400,
      'last_sign_in_older': 240,
    },
    'quality': {
      'missing_name': 7,
      'missing_vin': 400,
      'missing_card_photo': 900,
      'missing_selfie': 850,
      'missing_gender': 120,
      'missing_birth_date': 180,
      'missing_state': 3,
      'missing_lga': 4,
      'missing_ward': 5,
      'missing_polling_unit': 7,
      'polling_unit_from_list': 2,
    },
    'weekly': [
      for (var week = 0; week < 12; week++)
        {
          'week': DateTime.utc(
            2026,
            7,
            27,
          ).add(Duration(days: 7 * week)).toIso8601String().substring(0, 10),
          'count': week * 10,
        },
    ],
  },
  'exco': {
    'people': 140,
    'appointments': 146,
    'here': national ? 0 : 26,
    'suspended': 2,
    'verified': 140,
    'fully_verified': 12,
    'women': 40,
    'profile': {'signedIn': 70},
    'by_level': {'state': 26, 'lga': 60, 'ward': 40, 'pollingUnit': 20},
    'roles': [
      {'role': 'state-secretary', 'name': 'State Secretary', 'count': 3},
      {'role': 'pu-coordinator', 'name': 'PU Coordinator', 'count': 20},
    ],
  },
  'by': national ? 'state' : 'lga',
  'breakdowns': national ? ['state', 'geopoliticalZone'] : ['lga'],
  'parts': national
      ? [
          {
            'code': 'KD',
            'name': 'Kaduna',
            'members': 1100,
            'verified': 550,
            'fully_verified': 80,
            'women': 440,
            'new_30_days': 300,
            'exco': 140,
            'exco_people': 135,
          },
          {
            'code': 'KN',
            'name': 'Kano',
            'members': 93,
            'verified': 50,
            'fully_verified': 10,
            'women': 40,
            'new_30_days': 10,
            'exco': 6,
            'exco_people': 5,
          },
        ]
      : [
          {
            'code': 'KD-ZARIA',
            'name': 'Zaria',
            'members': 500,
            'verified': 250,
            'fully_verified': 30,
            'women': 200,
            'new_30_days': 100,
            'exco': 60,
            'exco_people': 58,
          },
        ],
  'coverage': {'areas': 2, 'with_members': 2, 'with_exco': 2, 'unplaced_members': 7},
};

Map<String, dynamic> _post(
  String role,
  String name, {
  List<String> gaps = const [],
  bool signedIn = false,
}) => {
  'appointment': 'a-$name',
  'role': role,
  'role_name': role,
  'appointment_state': 'active',
  'area': _scope('state', state: 'KD', stateName: 'Kaduna'),
  'area_name': 'Kaduna',
  'member': {
    'membership_number': 'TGCG-00$name',
    'full_name': name,
    'phone_number': '+2348030000001',
    'gender': 'female',
    'verification_status': 'verified',
    'verified_how': 'chapter',
    'membership_state': 'active',
    'scope': _scope('state', state: 'KD', stateName: 'Kaduna'),
    'gaps': gaps,
    'signed_in': signedIn,
    'has_app_account': true,
  },
};

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'count': items.length,
  'next': null,
  'previous': null,
  'results': items,
};

Map<String, dynamic> _member(String number, String name) => {
  'membership_number': number,
  'full_name': name,
  'verification_status': 'unverified',
  'membership_state': 'active',
  'scope': _scope('state', state: 'KD', stateName: 'Kaduna'),
  'roles': <Map<String, dynamic>>[],
  'gaps': ['vin'],
};

Map<String, dynamic> _emptyAnalysis() => {
  'scope': _scope('state', state: 'KD', stateName: 'Kaduna'),
  'members': {
    'total': 0,
    'new_7_days': 0,
    'new_30_days': 0,
    'previous_7_days': 0,
    'previous_30_days': 0,
    'verification': <String, int>{},
    'verification_sources': {'automatic': 0, 'chapter': 0, 'person': 0},
    'standing': {'active': 0, 'suspended': 0, 'deactivated': 0},
    'gender': <String, int>{},
    'channel': <String, int>{},
    'age': <String, int>{},
    'profile': <String, int>{},
    'accounts': {
      'without_account': 0,
      'never_signed_in': 0,
      'last_sign_in_7_days': 0,
      'last_sign_in_30_days': 0,
      'last_sign_in_older': 0,
    },
    'quality': {
      'missing_name': 0,
      'missing_vin': 0,
      'missing_card_photo': 0,
      'missing_selfie': 0,
      'missing_gender': 0,
      'missing_birth_date': 0,
      'missing_state': 0,
      'missing_lga': 0,
      'missing_ward': 0,
      'missing_polling_unit': 0,
      'polling_unit_from_list': 0,
    },
    'weekly': <Map<String, dynamic>>[],
  },
  'exco': {'people': 0, 'appointments': 0, 'by_level': <String, int>{}, 'roles': []},
  'by': 'lga',
  'breakdowns': ['lga'],
  'parts': <Map<String, dynamic>>[],
  'coverage': {'areas': 0, 'with_members': 0, 'with_exco': 0, 'unplaced_members': 0},
};

Future<void> _pumpPage(
  WidgetTester tester,
  _Server server, {
  AreaRef? area,
  Size size = const Size(1300, 5200),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TgcgBackend(
      services: server.connect(),
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: MembersExcoPage(start: area)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder target) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Map<String, String> _lastMemberQuery(_Server server) => Uri.parse(
  server.requests.lastWhere((request) => request.startsWith('GET members/?')).substring(4),
).queryParameters;

List<ShareBar> _barsIn(WidgetTester tester, String title) => tester
    .widgetList<ShareBar>(
      find.descendant(
        of: find.byWidgetPredicate((widget) => widget is TgcgSectionCard && widget.title == title),
        matching: find.byType(ShareBar),
      ),
    )
    .toList();

void main() {
  testWidgets('the administrator goes from Nigeria to a state, its exco and its members', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 5200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final person = {
      'membership_number': 'TGCG-000777',
      'full_name': 'Sani Umar',
      'phone_number': '+2348051234567',
      'sensitive_visible': true,
      'verification_status': 'pendingReview',
      'membership_state': 'active',
      'scope': _scope('state', state: 'KD', stateName: 'Kaduna'),
      'gender': 'male',
      'date_of_birth': '1990-01-15',
      'roles': <Map<String, dynamic>>[],
      'gaps': ['cardPhoto', 'selfie'],
      'signed_in': false,
      'verified_how': null,
      'registration_channel': 'self',
      'created_at': '2026-10-10T09:00:00Z',
    };
    final server = _Server()
      ..answer = (path, query) => switch (path) {
        'GET members/analysis/' => _json(_analysis(national: query['level'] == 'country')),
        'GET members/exco/' => _json(
          _page([
            _post('State Secretary', 'Aisha Bello', signedIn: true),
            _post('State Women Leader', 'Hauwa Musa', gaps: ['selfie', 'cardPhoto']),
          ]),
        ),
        'GET members/' => _json(_page([person])),
        'GET members/TGCG-000777/' => _json(person),
        _ => null,
      };
    await tester.pumpWidget(
      TgcgBackend(
        services: server.connect(),
        child: const MaterialApp(home: Scaffold(body: MembersExcoPage())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1,200'), findsOneWidget); // members
    expect(find.text('+310 in 30 days · +40 in 7'), findsOneWidget);
    expect(find.text('146 posts · 2 of 2 states'), findsOneWidget);
    expect(find.text('Women'), findsWidgets);
    expect(find.text('25-34'), findsOneWidget);
    expect(find.text('400 · 33%'), findsWidgets);
    expect(find.text('12 told us of a disability.'), findsOneWidget);
    expect(find.text("From chapters' lists"), findsOneWidget);
    expect(find.text('Positions held most'), findsOneWidget);

    // Nigeria by zone as well as by state.
    await tester.tap(find.text('Zones'));
    await tester.pumpAndSettle();
    expect(server.requests.last, 'GET members/analysis/?level=country&by=geopoliticalZone');
    expect(find.text('Nigeria, zone by zone.'), findsOneWidget);
    await tester.tap(find.text('States').first);
    await tester.pumpAndSettle();

    // States, most members first; open Kaduna.
    expect(
      find.text('140 exco posts · 50% verified · 40% women · +300 in 30 days'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('area-KD')));
    await tester.pumpAndSettle();
    expect(server.requests, contains('GET members/analysis/?level=state&code=KD'));
    expect(find.text('Kaduna State.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Nigeria'), findsOneWidget);
    expect(find.text('LGAs'), findsOneWidget);

    // The state's own exco, then everyone below it.
    await tester.tap(find.text('Exco').last);
    await tester.pumpAndSettle();
    expect(
      server.requests.last,
      'GET members/exco/?level=state&code=KD&at=state%2CsenatorialDistrict',
    );
    expect(find.text('Kaduna exco'), findsOneWidget);
    expect(find.text('State exco (26)'), findsOneWidget);
    expect(find.text('State Women Leader'), findsOneWidget);
    // One has everything on record; the other was verified on the chapter's word.
    expect(find.text("Verified on the chapter's list"), findsOneWidget);
    expect(find.text('No selfie'), findsWidgets);
    expect(find.text('Never signed in'), findsWidgets);
    await tester.tap(find.text('Not fully verified').first);
    await tester.pumpAndSettle();
    expect(server.requests.last, contains('show=notFullyVerified'));
    // Each level has its own exco: the LGAs', the wards', the units'.
    await tester.tap(find.text('LGA exco (60)'));
    await tester.pumpAndSettle();
    expect(server.requests.last, contains('at=lga'));
    expect(find.text('LGA exco in Kaduna'), findsOneWidget);
    expect(find.text('Ward exco (40)'), findsOneWidget);
    expect(find.text('Polling unit exco (20)'), findsOneWidget);
    await tester.tap(find.text('Everyone (146)'));
    await tester.pumpAndSettle();
    expect(server.requests.last, isNot(contains('at=')));
    expect(find.text('KADUNA STATE'), findsOneWidget);

    // Members registered in Kaduna, narrowed to those not fully verified.
    await tester.tap(find.text('Members').last);
    await tester.pumpAndSettle();
    expect(server.requests.last, contains('state__code=KD'));
    expect(find.text('Sani Umar'), findsOneWidget);
    expect(find.text('Awaiting review'), findsWidgets);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Not fully verified'));
    await tester.pumpAndSettle();
    expect(server.requests.last, contains('show=notFullyVerified'));
    await tester.tap(find.text('Sani Umar'));
    await tester.pumpAndSettle();
    Finder inDialog(String text) =>
        find.descendant(of: find.byType(Dialog), matching: find.text(text));
    expect(inDialog('+2348051234567'), findsOneWidget);
    expect(inDialog('Joined in the app'), findsOneWidget);
    expect(inDialog('Never signed in'), findsWidgets);

    // Back to Nigeria from the trail.
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Nigeria'));
    await tester.pumpAndSettle();
    expect(find.text('Nigeria, state by state.'), findsOneWidget);
  });

  testWidgets('on a phone every part fits the screen', (tester) async {
    tester.view.physicalSize = const Size(400, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _Server()
      ..answer = (path, query) => switch (path) {
        'GET members/analysis/' => _json(_analysis(national: false)),
        'GET members/exco/' => _json(_page([_post('State Secretary', 'Aisha Bello')])),
        _ => null,
      };
    await tester.pumpWidget(
      TgcgBackend(
        services: server.connect(),
        child: const MaterialApp(
          home: Scaffold(
            body: MembersExcoPage(start: AreaRef(GeographyLevel.state, 'KD', 'Kaduna')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Zaria'), findsOneWidget);
    await tester.tap(find.text('Exco').last);
    await tester.pumpAndSettle();
    expect(find.text('Aisha Bello'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quality and standing figures open members in the selected state', (tester) async {
    final server = _Server()
      ..answer = (path, query) => switch (path) {
        'GET members/analysis/' => _json(_analysis(national: query['level'] == 'country')),
        'GET members/' => _json(_page([_member('TGCG-000701', 'Aisha Bello')])),
        _ => null,
      };
    await _pumpPage(tester, server);
    await _tapVisible(tester, find.byKey(const ValueKey('area-KD')));

    await _tapVisible(tester, find.byKey(const ValueKey('member-metric-missingVin')));
    expect(_lastMemberQuery(server)['state__code'], 'KD');
    expect(_lastMemberQuery(server)['show'], 'missingVin');
    expect(_lastMemberQuery(server).containsKey('membership_state'), isFalse);
    expect(find.byKey(const ValueKey('selected-member-filter')), findsOneWidget);

    await _tapVisible(tester, find.byKey(const ValueKey('clear-member-filter')));
    expect(_lastMemberQuery(server)['state__code'], 'KD');
    expect(_lastMemberQuery(server).containsKey('show'), isFalse);
    expect(find.byKey(const ValueKey('selected-member-filter')), findsNothing);

    for (final standing in ['suspended', 'deactivated']) {
      await _tapVisible(tester, find.byKey(ValueKey('member-metric-standing-$standing')));
      expect(_lastMemberQuery(server)['state__code'], 'KD');
      expect(_lastMemberQuery(server)['membership_state'], standing);
      expect(_lastMemberQuery(server).containsKey('show'), isFalse);
      expect(_lastMemberQuery(server).containsKey('verification_status'), isFalse);
    }
  });

  testWidgets('identity and account rows are disjoint while demographics keep their labels', (
    tester,
  ) async {
    final server = _Server()
      ..answer = (path, query) =>
          path == 'GET members/analysis/' ? _json(_analysis(national: false)) : null;
    await _pumpPage(tester, server, area: const AreaRef(GeographyLevel.state, 'KD', 'Kaduna'));

    // Fully verified is part of verified, so the second row must subtract it.
    final identity = _barsIn(tester, 'Identity');
    expect(identity.map((bar) => bar.value), orderedEquals([90, 510, 200, 390, 10]));
    expect(identity.fold(0, (sum, bar) => sum + bar.value), 1200);
    expect(identity.map((bar) => bar.total), everyElement(1200));
    expect(identity[1].label, 'Verified profile incomplete');

    final gender = _barsIn(tester, 'Gender');
    expect(gender.map((bar) => bar.label), orderedEquals(['Women', 'Men', 'Not given']));
    expect(gender.map((bar) => bar.value), orderedEquals([480, 600, 120]));
    expect(
      _barsIn(tester, 'Age').map((bar) => bar.label),
      containsAll(['Under 18', '25-34', 'Not given']),
    );

    // The seven-day activity count is nested in the 30-day count, not another row.
    final accounts = _barsIn(tester, 'App accounts');
    expect(
      accounts.map((bar) => bar.label),
      orderedEquals([
        'No app account',
        'Account never signed in',
        'Signed in within 30 days',
        'Last sign-in over 30 days ago',
      ]),
    );
    expect(accounts.map((bar) => bar.value), orderedEquals([100, 460, 400, 240]));
    expect(accounts.fold(0, (sum, bar) => sum + bar.value), 1200);
    expect(find.text('240 signed in within 7 days'), findsOneWidget);

    final sources = _barsIn(tester, 'Verified by');
    expect(sources.map((bar) => bar.label), orderedEquals(['System', 'Chapter', 'Reviewer']));
    expect(sources.map((bar) => bar.value), orderedEquals([100, 450, 50]));
    expect(sources.map((bar) => bar.total), everyElement(600));
  });

  testWidgets('account activity and verification sources select their own member groups', (
    tester,
  ) async {
    final server = _Server()
      ..answer = (path, query) => switch (path) {
        'GET members/analysis/' => _json(_analysis(national: false)),
        'GET members/' => _json(_page([_member('TGCG-000702', 'Sani Umar')])),
        _ => null,
      };
    await _pumpPage(tester, server, area: const AreaRef(GeographyLevel.state, 'KD', 'Kaduna'));

    for (final show in [
      'noAppAccount',
      'accountNeverSignedIn',
      'signedIn30Days',
      'lastSignInOlder',
      'verifiedAutomatic',
      'verifiedChapter',
      'verifiedPerson',
    ]) {
      await _tapVisible(tester, find.byKey(ValueKey('member-metric-$show')));
      expect(_lastMemberQuery(server)['show'], show, reason: 'Selected $show');
      expect(_lastMemberQuery(server)['state__code'], 'KD');
      expect(_lastMemberQuery(server).containsKey('verification_status'), isFalse);
      expect(_lastMemberQuery(server).containsKey('membership_state'), isFalse);
    }
  });

  testWidgets('large text on a normal phone can reach metrics, results and the member profile', (
    tester,
  ) async {
    const name = 'Aisha Fatima Bello Abdullahi Muhammad';
    final person = _member('TGCG-000703', name);
    final server = _Server()
      ..answer = (path, query) => switch (path) {
        'GET members/analysis/' => _json(_analysis(national: false)),
        'GET members/' => _json(_page([person])),
        'GET members/TGCG-000703/' => _json(person),
        _ => null,
      };
    await _pumpPage(
      tester,
      server,
      area: const AreaRef(GeographyLevel.state, 'KD', 'Kaduna'),
      size: const Size(380, 800),
      textScale: 1.5,
    );
    await _tapVisible(tester, find.byKey(const ValueKey('member-metric-missingVin')));
    expect(_lastMemberQuery(server)['show'], 'missingVin');
    await _tapVisible(tester, find.text(name));
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.descendant(of: find.byType(Dialog), matching: find.text(name)), findsOneWidget);
    await _tapVisible(tester, find.widgetWithText(TextButton, 'Close'));
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty figures remain finite and usable on a phone with large text', (tester) async {
    final server = _Server()
      ..answer = (path, query) => switch (path) {
        'GET members/analysis/' => _json(_emptyAnalysis()),
        'GET members/' => _json(_page([])),
        _ => null,
      };
    await _pumpPage(
      tester,
      server,
      area: const AreaRef(GeographyLevel.state, 'KD', 'Kaduna'),
      size: const Size(360, 740),
      textScale: 1.5,
    );
    await _tapVisible(tester, find.byKey(const ValueKey('member-metric-noAppAccount')));
    expect(_lastMemberQuery(server)['show'], 'noAppAccount');
    await tester.ensureVisible(find.text('No members found.'));
    await tester.pumpAndSettle();
    expect(find.text('No members found.'), findsOneWidget);
    expect(find.textContaining('NaN'), findsNothing);
    expect(find.textContaining('Infinity'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late members response cannot replace the newly selected group', (tester) async {
    final earlier = Completer<http.Response>();
    final server = _Server()
      ..answer = (path, query) {
        if (path == 'GET members/analysis/') return _json(_analysis(national: false));
        if (path == 'GET members/') {
          return query['verification_status'] == 'pendingReview'
              ? _json(_page([_member('TGCG-000705', 'Current member')]))
              : earlier.future;
        }
        return null;
      };
    await _pumpPage(tester, server, area: const AreaRef(GeographyLevel.state, 'KD', 'Kaduna'));
    await tester.ensureVisible(find.text('Members').last);
    await tester.tap(find.text('Members').last);
    await tester.pump(const Duration(milliseconds: 100));
    expect(_lastMemberQuery(server).containsKey('verification_status'), isFalse);

    final pending = find.widgetWithText(ChoiceChip, 'Awaiting review');
    await tester.ensureVisible(pending);
    await tester.tap(pending);
    await tester.pumpAndSettle();
    expect(find.text('Current member'), findsOneWidget);
    earlier.complete(_json(_page([_member('TGCG-000704', 'Stale member')])));
    await tester.pumpAndSettle();
    expect(find.text('Current member'), findsOneWidget);
    expect(find.text('Stale member'), findsNothing);
  });

  testWidgets('a late exco response cannot mix posts from the old level into the new one', (
    tester,
  ) async {
    final earlier = Completer<http.Response>();
    final server = _Server()
      ..answer = (path, query) {
        if (path == 'GET members/analysis/') return _json(_analysis(national: false));
        if (path == 'GET members/exco/') {
          return query['at'] == 'lga'
              ? _json(_page([_post('LGA Secretary', 'Current holder')]))
              : earlier.future;
        }
        return null;
      };
    await _pumpPage(tester, server, area: const AreaRef(GeographyLevel.state, 'KD', 'Kaduna'));
    await tester.ensureVisible(find.text('Exco').last);
    await tester.tap(find.text('Exco').last);
    await tester.pump(const Duration(milliseconds: 100));

    final lga = find.text('LGA exco (60)');
    await tester.ensureVisible(lga);
    await tester.tap(lga);
    await tester.pumpAndSettle();
    expect(find.text('Current holder'), findsOneWidget);
    earlier.complete(_json(_page([_post('State Secretary', 'Stale holder')])));
    await tester.pumpAndSettle();
    expect(find.text('Current holder'), findsOneWidget);
    expect(find.text('Stale holder'), findsNothing);
  });

  testWidgets('unplaced members in the zone breakdown open the exact national group', (
    tester,
  ) async {
    final figures = _analysis(national: true);
    figures['by'] = 'geopoliticalZone';
    figures['parts'] = [
      {'code': 'NW', 'name': 'North West', 'members': 1100, 'exco': 110},
    ];
    figures['coverage'] = {'areas': 1, 'with_members': 1, 'with_exco': 1, 'unplaced_members': 100};
    final server = _Server()
      ..answer = (path, query) => switch (path) {
        'GET members/analysis/' => _json(figures),
        'GET members/' => _json(_page([])),
        _ => null,
      };
    await _pumpPage(tester, server);
    await _tapVisible(tester, find.byKey(const ValueKey('member-metric-unplaced')));
    expect(_lastMemberQuery(server)['show'], 'missingZone');
    expect(_lastMemberQuery(server).containsKey('state__code'), isFalse);
    expect(_lastMemberQuery(server).containsKey('zone__code'), isFalse);
  });

  test('numbers are grouped and shares rounded', () {
    expect(formatCount(160873), '160,873');
    expect(formatCount(999), '999');
    expect(share(1, 3), '33%');
    expect(share(5, 0), '0%');
    expect(share(1, 1000), '<1%');
    expect(share(999, 1000), '>99%');
    expect(share(1000, 1000), '100%');
  });
}
