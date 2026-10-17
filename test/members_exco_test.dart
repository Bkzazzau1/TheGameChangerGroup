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

// Names and numbers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _Server {
  final requests = <String>[];
  http.Response? Function(String path, Map<String, String> query) answer = (_, _) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient((request) async {
      final path = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add('$path?${request.url.query}');
      return answer(path, request.url.queryParameters) ?? _json({'detail': 'Not found.'}, 404);
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
    'fully_verified': 90,
    'with_role': 140,
    'with_disability': 12,
    'verification': {'verified': 600, 'pendingReview': 200, 'unverified': 390, 'rejected': 10},
    'standing': {'active': 1195, 'suspended': 5},
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
    'weekly': [
      for (var week = 0; week < 12; week++)
        {
          'week': DateTime.utc(2026, 7, 27).add(Duration(days: 7 * week)).toIso8601String().substring(0, 10),
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
            'members': 100,
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
  'coverage': {'areas': 2, 'with_members': 2, 'with_exco': 2},
};

Map<String, dynamic> _post(String role, String name, {List<String> gaps = const [], bool signedIn = false}) => {
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

Map<String, dynamic> _page(List<Map<String, dynamic>> items) =>
    {'count': items.length, 'next': null, 'previous': null, 'results': items};

void main() {
  testWidgets('the administrator goes from Nigeria to a state, its exco and its members', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1300, 5200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = _Server()
      ..answer = (path, query) => switch (path) {
        'GET members/analysis/' => _json(_analysis(national: query['level'] == 'country')),
        'GET members/exco/' => _json(
          _page([
            _post('State Secretary', 'Aisha Bello', signedIn: true),
            _post('State Women Leader', 'Hauwa Musa', gaps: ['selfie', 'cardPhoto']),
          ]),
        ),
        'GET members/' => _json(
          _page([
            {
              'membership_number': 'TGCG-000777',
              'full_name': 'Sani Umar',
              'phone_number': '+2348051234567',
              'verification_status': 'pendingReview',
              'membership_state': 'active',
              'scope': _scope('state', state: 'KD', stateName: 'Kaduna'),
              'gender': 'male',
              'date_of_birth': '1990-01-15',
              'roles': [],
              'gaps': ['cardPhoto', 'selfie'],
              'signed_in': false,
              'verified_how': null,
              'registration_channel': 'self',
              'created_at': '2026-10-10T09:00:00Z',
            },
          ]),
        ),
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

    // States, most members first; open Kaduna.
    expect(find.text('States'), findsOneWidget);
    expect(find.text('140 exco posts · 50% verified · 40% women · +300 in 30 days'), findsOneWidget);
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
    expect(find.text('State Women Leader'), findsOneWidget);
    // One has everything on record; the other was verified on the chapter's word.
    expect(find.text("Verified on the chapter's list"), findsOneWidget);
    expect(find.text('No selfie'), findsOneWidget);
    expect(find.text('Never signed in'), findsWidgets);
    await tester.tap(find.text('Not fully verified').first);
    await tester.pumpAndSettle();
    expect(server.requests.last, contains('show=notFullyVerified'));
    await tester.tap(find.text('Everyone below'));
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
        find.descendant(of: find.byType(AlertDialog), matching: find.text(text));
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

  test('numbers are grouped and shares rounded', () {
    expect(formatCount(160873), '160,873');
    expect(formatCount(999), '999');
    expect(share(1, 3), '33%');
    expect(share(5, 0), '0%');
  });
}
