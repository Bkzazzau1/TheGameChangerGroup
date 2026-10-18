import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/domain/permissions.dart';
import 'package:tgcg_emcop/tgcg/membership/member_search.dart';
import 'package:tgcg_emcop/tgcg/membership/members_exco_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

// Names and numbers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

class _Server {
  final searches = <Map<String, String>>[];
  final requests = <String>[];
  final detailOverrides = <String, Map<String, dynamic>>{};
  bool denyDetails = false;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient((request) async {
      final path = request.url.path.replaceFirst('/api/v1/', '');
      final query = request.url.queryParameters;
      requests.add('${request.method} $path');
      for (final person in _people) {
        final number = person['membership_number'] as String;
        if (path == 'members/$number/') {
          if (denyDetails) return _json({'detail': 'Access denied.'}, 403);
          return _json({...person, ...?detailOverrides[number]});
        }
      }
      return switch (path) {
        'register/places/states/' => _json([
          {'code': 'KD', 'name': 'Kaduna'},
          {'code': 'KN', 'name': 'Kano'},
        ]),
        'register/places/lgas/' => _json([
          {'code': 'KD-ZARIA', 'name': 'Zaria'},
        ]),
        'members/analysis/' => _json(_analysis()),
        'members/' => () {
          searches.add(query);
          return _json(_page(query['q'] == 'nobody' ? const [] : _people));
        }(),
        _ => _json({'detail': 'Not found.'}, 404),
      };
    }),
  );
}

Map<String, dynamic> _scope({String? lga}) => {
  'level': lga == null ? 'state' : 'lga',
  'country': 'Nigeria',
  'stateId': 'KD',
  'stateName': 'Kaduna',
  'lgaId': lga == null ? null : 'KD-KADUNA-NORTH',
  'lgaName': lga,
};

Map<String, dynamic> _member(
  String number,
  String name, {
  List<Map<String, dynamic>> roles = const [],
  String verification = 'verified',
  String? how,
  List<String> gaps = const [],
  String? lastSignIn,
}) => {
  'membership_number': number,
  'full_name': name,
  'phone_number': '+2348030000${number.substring(number.length - 3)}',
  'verification_status': verification,
  'membership_state': 'active',
  'scope': _scope(lga: 'Kaduna North'),
  'gender': 'female',
  'date_of_birth': '1988-05-02',
  'roles': roles,
  'gaps': gaps,
  'signed_in': lastSignIn != null,
  'last_sign_in': lastSignIn,
  'verified_how': how,
  'registration_channel': 'import',
  'has_pvc': false,
  'sensitive_visible': true,
  'photo_url': null,
  'has_app_account': true,
  'created_at': '2026-10-16T09:00:00Z',
};

final _people = [
  _member(
    'TGCG-000101',
    'Hauwa Musa',
    roles: [
      {
        'role': 'lga-women-leader',
        'role_name': 'LGA Women Leader',
        'state': 'active',
        'area_level': 'lga',
        'area_name': 'Kaduna North',
      },
    ],
    how: 'chapter',
    gaps: ['vin', 'selfie'],
  ),
  _member(
    'TGCG-000102',
    'Sani Umar',
    verification: 'pendingReview',
    gaps: ['cardPhoto'],
    lastSignIn: '2026-10-17T18:30:00Z',
  ),
];

Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
  'count': items.length,
  'next': null,
  'previous': null,
  'results': items,
};

Map<String, dynamic> _analysis() => {
  'scope': {'level': 'country', 'country': 'Nigeria'},
  'members': {'total': 2, 'weekly': [], 'age': {}, 'profile': {}},
  'exco': {
    'people': 1,
    'appointments': 1,
    'by_level': {'lga': 1},
    'roles': [
      {'role': 'lga-women-leader', 'name': 'LGA Women Leader', 'count': 1},
      {'role': 'state-secretary', 'name': 'State Secretary', 'count': 3},
    ],
  },
  'by': 'state',
  'breakdowns': ['state', 'geopoliticalZone'],
  'parts': [
    {'code': 'KD', 'name': 'Kaduna', 'members': 2, 'exco': 1},
  ],
  'coverage': {'areas': 1, 'with_members': 1, 'with_exco': 1},
};

Future<void> _pump(
  WidgetTester tester,
  _Server server,
  Widget page, {
  Size size = const Size(1200, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TgcgBackend(
      services: server.connect(),
      child: MaterialApp(home: Scaffold(body: page)),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pick(WidgetTester tester, Key chip, String item) async {
  await tester.tap(find.byKey(chip));
  await tester.pumpAndSettle();
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one search finds members anywhere, with their posts and standing', (tester) async {
    final server = _Server();
    await _pump(tester, server, const MemberSearchPage());

    // Everyone at first, A to Z.
    expect(find.text('2 members'), findsOneWidget);
    expect(server.searches.last['ordering'], 'full_name');
    expect(find.text('LGA Women Leader · Kaduna North LGA'), findsOneWidget);
    expect(find.text("Verified on the chapter's list"), findsOneWidget);
    expect(find.text('No selfie'), findsOneWidget);
    expect(find.text('Awaiting review'), findsWidgets);
    expect(find.text('TGCG-000101 · +2348030000101'), findsOneWidget);

    // Words for a position and a place; the filters narrow it further.
    await tester.enterText(find.byKey(const ValueKey('member-search-field')), 'women leader zaria');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(server.searches.last['q'], 'women leader zaria');

    await _pick(tester, const ValueKey('filter-state'), 'Kaduna');
    expect(server.searches.last['state__code'], 'KD');
    await _pick(tester, const ValueKey('filter-lga'), 'Zaria');
    expect(server.searches.last['lga__code'], 'KD-ZARIA');
    expect(server.searches.last.containsKey('state__code'), isFalse);
    await _pick(tester, const ValueKey('filter-position'), 'State Secretary (3)');
    expect(server.searches.last['role'], 'state-secretary');
    await _pick(tester, const ValueKey('filter-status'), 'Not fully verified');
    expect(server.searches.last['show'], 'notFullyVerified');
    await _pick(tester, const ValueKey('filter-status'), 'Awaiting review');
    expect(server.searches.last['verification_status'], 'pendingReview');
    expect(server.searches.last.containsKey('show'), isFalse);

    await tester.tap(find.text('Newest'));
    await tester.pumpAndSettle();
    expect(server.searches.last['ordering'], '-created_at');

    // A member's profile: posts, contact, registration and the app.
    await tester.tap(find.byKey(const ValueKey('member-TGCG-000101')));
    await tester.pumpAndSettle();
    Finder inProfile(String text) =>
        find.descendant(of: find.byType(Dialog), matching: find.text(text));
    expect(inProfile('POSITIONS'), findsOneWidget);
    expect(inProfile('LGA Women Leader'), findsOneWidget);
    expect(inProfile('Kaduna North LGA'), findsOneWidget);
    expect(inProfile("From a chapter's list"), findsOneWidget);
    expect(inProfile('Never'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('+2348030000101')),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('member-TGCG-000102')));
    await tester.pumpAndSettle();
    expect(inProfile('None'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.textContaining('Last on')),
      findsOneWidget,
    );
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    // Clearing everything shows everyone again.
    await tester.tap(find.text('Clear all').first);
    await tester.pumpAndSettle();
    expect(server.searches.last.containsKey('role'), isFalse);
    expect(server.searches.last.containsKey('q'), isFalse);
  });

  testWidgets('no match says so and offers to clear the filters', (tester) async {
    final server = _Server();
    await _pump(tester, server, const MemberSearchPage(query: 'nobody'));
    expect(find.text('No members match'), findsOneWidget);
    await _pick(tester, const ValueKey('filter-status'), 'Exco');
    expect(find.widgetWithText(OutlinedButton, 'Clear all'), findsOneWidget);
  });

  testWidgets('member details refresh the record and show its registered location', (tester) async {
    final server = _Server();
    server.detailOverrides['TGCG-000101'] = {
      'full_name': 'Updated Member',
      'whatsapp_number': '+2348031111222',
      'verified_at': '2026-10-18T08:00:00Z',
      'updated_at': '2026-10-18T09:00:00Z',
      'polling_unit_from_list': true,
      'disabilities': ['hearing'],
      'scope': {
        ..._scope(lga: 'Kaduna North'),
        'level': 'pollingUnit',
        'wardId': '18-01-01',
        'wardName': 'Ward One',
        'pollingUnitId': '18-01-01-001',
        'pollingUnitName': 'School Gate',
      },
    };
    await _pump(tester, server, const MemberSearchPage(), size: const Size(380, 2400));
    await tester.tap(find.byKey(const ValueKey('member-TGCG-000101')));
    await tester.pumpAndSettle();
    Finder inProfile(String text) =>
        find.descendant(of: find.byType(Dialog), matching: find.text(text));
    expect(server.requests, contains('GET members/TGCG-000101/'));
    expect(inProfile('Updated Member'), findsOneWidget);
    expect(inProfile('Hauwa Musa'), findsNothing);
    expect(inProfile('+2348031111222'), findsOneWidget);
    expect(inProfile('School Gate · 18-01-01-001'), findsOneWidget);
    expect(inProfile('Chosen from the list'), findsOneWidget);
    expect(inProfile('Verified on'), findsOneWidget);
    expect(inProfile('Last updated'), findsOneWidget);
    expect(inProfile('ACCESSIBILITY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('member detail honors private visibility even if a payload includes old values', (
    tester,
  ) async {
    final server = _Server();
    server.detailOverrides['TGCG-000101'] = {
      'sensitive_visible': false,
      'phone_number': '+2348031111999',
      'whatsapp_number': '+2348031111888',
      'email': 'private@example.test',
      'disabilities': ['hearing'],
    };
    await _pump(tester, server, const MemberSearchPage());
    await tester.tap(find.byKey(const ValueKey('member-TGCG-000101')));
    await tester.pumpAndSettle();
    Finder inProfile(String text) =>
        find.descendant(of: find.byType(Dialog), matching: find.text(text));
    expect(inProfile('Hidden for your role'), findsOneWidget);
    for (final privateValue in ['+2348031111999', '+2348031111888', 'private@example.test']) {
      expect(inProfile(privateValue), findsNothing);
    }
    expect(inProfile('ACCESSIBILITY'), findsNothing);
    expect(inProfile('Born'), findsNothing);
  });

  testWidgets('member detail cannot fall back to a cached row after access is denied', (
    tester,
  ) async {
    final server = _Server()..denyDetails = true;
    await _pump(tester, server, const MemberSearchPage());
    await tester.tap(find.byKey(const ValueKey('member-TGCG-000101')));
    await tester.pumpAndSettle();
    expect(server.requests, contains('GET members/TGCG-000101/'));
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('Hauwa Musa')),
      findsNothing,
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.textContaining('Access denied')),
      findsOneWidget,
    );
  });

  testWidgets('on Members & Exco, searching replaces the figures until it is cleared', (
    tester,
  ) async {
    final server = _Server();
    await _pump(tester, server, const MembersExcoPage());
    expect(find.byKey(const ValueKey('area-KD')), findsOneWidget);
    expect(find.byKey(const ValueKey('member-TGCG-000101')), findsNothing);

    await tester.enterText(find.byKey(const ValueKey('member-search-field')), 'hauwa');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('member-TGCG-000101')), findsOneWidget);
    expect(find.byKey(const ValueKey('area-KD')), findsNothing);

    await tester.tap(find.byTooltip('Clear the search'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('area-KD')), findsOneWidget);
  });

  testWidgets('on a phone the search and its results fit the screen', (tester) async {
    final server = _Server();
    await _pump(tester, server, const MemberSearchPage(), size: const Size(380, 2400));
    expect(find.text('Hauwa Musa'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the top bar offers member search only with Members & Exco', (tester) async {
    Future<void> show(Set<String> capabilities) async {
      final session = TgcgSessionController()
        ..signInFromServer(
          fullName: 'Admin',
          accessId: 'NA-1',
          scope: GeographicScope.nigeria,
          capabilities: capabilities,
        );
      addTearDown(session.dispose);
      await tester.pumpWidget(
        TgcgSession(
          controller: session,
          child: const MaterialApp(home: Scaffold(body: MemberSearchButton())),
        ),
      );
    }

    await show({TgcgCapability.manageMembership.name});
    expect(find.byTooltip('Find members'), findsOneWidget);
    await show({TgcgCapability.viewIncidents.name});
    expect(find.byTooltip('Find members'), findsNothing);
  });
}
