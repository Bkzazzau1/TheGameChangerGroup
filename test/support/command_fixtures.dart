import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/domain/permissions.dart';
import 'package:tgcg_emcop/tgcg/geography/nigeria_map.dart';

import 'redesign_fixtures.dart';

// Places are real; every figure and name here is made up.

Map<String, dynamic> _unit(String stateId, String state, String lga, String name) => {
  'level': 'pollingUnit',
  'country': 'Nigeria',
  'stateId': stateId,
  'stateName': state,
  'lgaId': '$stateId-$lga',
  'lgaName': lga,
  'wardName': 'Central',
  'pollingUnitId': '$stateId-001',
  'pollingUnitName': name,
};

Map<String, dynamic> _page(List<Map<String, dynamic>> items, {int? count}) => {
  'count': count ?? items.length,
  'next': null,
  'previous': null,
  'results': items,
};

Map<String, dynamic> _incident(
  String reference,
  String title,
  Map<String, dynamic> scope, {
  String severity = 'high',
  String status = 'reported',
  String team = '',
  String? latitude,
  String? longitude,
  bool live = false,
}) => {
  'id': reference,
  'reference': reference,
  'title': title,
  'category': 'Violence / threat',
  'severity': severity,
  'status': status,
  'is_open': true,
  'scope': scope,
  'summary': 'Reported by the polling unit agent.',
  'assigned_team': team,
  'latitude': latitude,
  'longitude': longitude,
  'reporter': 'AG-1',
  'reported_at': '2026-10-30T09:15:00Z',
  'origin': 'localEntry',
  'client_id': null,
  'evidence': <Object>[],
  if (live) 'live': {'is_live': true},
};

/// Open incidents across the country, east and west, with and without GPS.
final fakeIncidents = [
  _incident(
    'INC-000011',
    'Ballot box snatched',
    _unit('BO', 'Borno', 'Maiduguri', 'Unit 001'),
    severity: 'critical',
    latitude: '11.833300',
    longitude: '13.150000',
  ),
  _incident(
    'INC-000012',
    'Agents turned away from the unit',
    _unit('SO', 'Sokoto', 'Sokoto North', 'Unit 001'),
    latitude: '13.060000',
    longitude: '5.240000',
    team: 'State Situation Desk',
  ),
  _incident(
    'INC-000013',
    'Materials arrived late',
    _unit('LA', 'Lagos', 'Ikeja', 'Unit 001'),
    severity: 'medium',
    status: 'acknowledged',
    team: 'State Situation Desk',
  ),
  _incident(
    'INC-000014',
    'Queue dispute settled',
    _unit('EN', 'Enugu', 'Enugu North', 'Unit 001'),
    severity: 'low',
    status: 'investigating',
    latitude: '6.450000',
    longitude: '7.500000',
    live: true,
  ),
];

Map<String, dynamic> _area(String level, String code, String name, int verified, int expected) => {
  'level': level,
  'code': code,
  'name': name,
  'expected_polling_units': expected,
  'reported_polling_units': verified + 40,
  'verified_polling_units': verified,
  'completion_percent': verified * 100 / expected,
  'party_votes': {'APC': 120 * verified, 'PDP': 98 * verified},
  'leading_party': verified == 0 ? null : 'APC',
};

const _nationalScope = {'level': 'country', 'country': 'Nigeria'};

Map<String, dynamic> fakeCollation({int verified = 4218}) => {
  'election': '2027-presidential',
  'scope': _nationalScope,
  'expected_polling_units': 176846,
  'reported_polling_units': 6120,
  'verified_polling_units': verified,
  'under_review': 212,
  'disputed': 31,
  'missing_polling_units': 176846 - verified,
  'completion_percent': verified * 100 / 176846,
  'accredited_voters': verified == 0 ? 0 : 1283400,
  'total_valid_votes': verified == 0 ? 0 : 1154000,
  'rejected_votes': verified == 0 ? 0 : 18230,
  'party_votes': verified == 0
      ? {'APC': 0, 'PDP': 0, 'LP': 0}
      : {'APC': 620400, 'PDP': 402300, 'LP': 131300},
  'leading_party': verified == 0 ? null : 'APC',
  'children': [
    _area('state', 'KD', 'Kaduna', 912, 8012),
    _area('state', 'KN', 'Kano', 1204, 11222),
    _area('state', 'LA', 'Lagos', 845, 13325),
    _area('state', 'FC', 'Federal Capital Territory', 0, 2822),
  ],
};

Map<String, dynamic> _tally(int agents, int checkedIn) => {
  'agents': agents,
  'checked_in': checkedIn,
  'not_checked_in': agents - checkedIn,
  'on_site': checkedIn == 0 ? 0 : checkedIn - 3,
  'away': checkedIn == 0 ? 0 : 3,
  'unverified': 0,
  'suspect': 0,
  'on_duty_now': checkedIn == 0 ? 0 : checkedIn - 8,
};

Map<String, dynamic> _part(String code, String name, int members, int exco) => {
  'code': code,
  'name': name,
  'members': members,
  'verified': members ~/ 2,
  'fully_verified': members ~/ 10,
  'women': members * 2 ~/ 5,
  'new_30_days': members ~/ 12,
  'exco': exco,
  'exco_people': exco - 2,
};

/// The whole country's figures.
Map<String, dynamic> fakeAnalysis({bool empty = false}) {
  int n(int value) => empty ? 0 : value;
  return {
    'scope': _nationalScope,
    'members': {
      'total': n(248310),
      'new_7_days': n(1840),
      'new_30_days': n(9320),
      'previous_7_days': n(1510),
      'previous_30_days': n(8120),
      'fully_verified': n(21890),
      'with_role': n(6120),
      'with_disability': n(412),
      'verification': {
        'verified': n(120450),
        'pendingReview': n(14300),
        'unverified': n(111200),
        'rejected': n(2360),
      },
      'verification_sources': {'automatic': n(18200), 'chapter': n(96100), 'person': n(6150)},
      'standing': {'active': n(247900), 'suspended': n(300), 'deactivated': n(110)},
      'gender': {'female': n(98300), 'male': n(131000), '': n(19010)},
      'channel': {
        'self': n(101200),
        'import': n(118300),
        'assisted': n(9800),
        'referred': n(19010),
      },
      'age': {
        '18-24': n(41200),
        '25-34': n(88300),
        '35-44': n(61200),
        '45-54': n(28400),
        '55-64': n(11200),
        '65+': n(3100),
        'unknown': n(14910),
      },
      'profile': {
        'vin': n(170300),
        'cardPhoto': n(61200),
        'selfie': n(58300),
        'gender': n(229300),
        'dateOfBirth': n(233400),
        'phoneConfirmed': n(0),
        'signedIn': n(132100),
      },
      'accounts': {
        'without_account': n(92100),
        'never_signed_in': n(24110),
        'last_sign_in_7_days': n(38200),
        'last_sign_in_30_days': n(84300),
        'last_sign_in_older': n(47800),
      },
      'quality': {
        'missing_name': n(120),
        'missing_vin': n(78010),
        'missing_card_photo': n(187110),
        'missing_selfie': n(190010),
        'missing_gender': n(19010),
        'missing_birth_date': n(14910),
        'missing_state': n(412),
        'missing_lga': n(903),
        'missing_ward': n(4120),
        'missing_polling_unit': n(8210),
        'polling_unit_from_list': n(30100),
      },
      'weekly': [
        for (var week = 0; week < 12; week++)
          {
            'week': DateTime.utc(
              2026,
              8,
              10,
            ).add(Duration(days: 7 * week)).toIso8601String().substring(0, 10),
            'count': empty ? 0 : 900 + (week * week * 11) + (week.isEven ? 240 : 0),
          },
      ],
    },
    'exco': {
      'people': n(6120),
      'appointments': n(6410),
      'here': n(38),
      'suspended': n(9),
      'verified': n(5210),
      'fully_verified': n(1840),
      'women': n(1520),
      'profile': {'signedIn': n(3880)},
      'by_level': {'country': n(38), 'state': n(620), 'lga': n(2210), 'ward': n(3542)},
      'roles': empty
          ? <Object>[]
          : [
              {'role': 'state-secretary', 'name': 'State Secretary', 'count': 37},
              {'role': 'lga-coordinator', 'name': 'LGA Coordinator', 'count': 774},
            ],
    },
    'by': 'state',
    'breakdowns': ['state', 'geopoliticalZone'],
    'parts': empty
        ? <Object>[]
        : [
            _part('KD', 'Kaduna', 48210, 812),
            _part('KN', 'Kano', 41230, 730),
            _part('LA', 'Lagos', 32100, 610),
            _part('RI', 'Rivers', 18400, 402),
            _part('BO', 'Borno', 9200, 0),
          ],
    'coverage': {
      'areas': empty ? 0 : 5,
      'with_members': empty ? 0 : 5,
      'with_exco': empty ? 0 : 4,
      'unplaced_members': n(412),
    },
  };
}

/// A fake server for the operations app, honouring the filters it sends.
/// [quiet]: nothing has happened yet. [down]: only signing in works.
BackendServices commandBackend({
  bool quiet = false,
  bool down = false,
  Set<String>? capabilities,
}) => BackendServices.connect(
  'https://api.tgcg.test',
  tokens: MemoryTokenStore(),
  httpClient: MockClient((request) async {
    final path = request.url.path.replaceFirst('/api/v1/', '');
    if (down && path != 'auth/login/') {
      return jsonResponse({'detail': 'The server could not answer.'}, 500);
    }
    // As the real server does for an account without the power.
    if (capabilities != null && const {'incidents/', 'field-reports/', 'results/'}.contains(path)) {
      return jsonResponse({'detail': 'You may not see this.'}, 403);
    }
    return commandServer(
          path,
          request.url.queryParameters,
          quiet: quiet,
          capabilities: capabilities,
        ) ??
        jsonResponse({'detail': 'Not found.'}, 404);
  }),
);

int _results(String? status) => switch (status) {
  null => 6120,
  'verified' => 4218,
  'underReview' => 212,
  'disputed' => 31,
  'submitted' => 96,
  _ => 0,
};

/// The server as a National Administrator sees it.
http.Response? commandServer(
  String path,
  Map<String, String> query, {
  bool quiet = false,
  Set<String>? capabilities,
}) => switch (path) {
  'auth/login/' => jsonResponse({
    'access': 'A',
    'refresh': 'R',
    'user': commandUser(capabilities: capabilities),
  }),
  'members/' => jsonResponse(_page(const [], count: quiet ? 0 : 248310)),
  'members/analysis/' => jsonResponse(fakeAnalysis(empty: quiet)),
  'members/exco/' => jsonResponse(_page(const [])),
  'tracking/coverage/' => jsonResponse({
    'date': '2026-10-30',
    'scope': _nationalScope,
    ...(quiet ? _tally(0, 0) : _tally(160210, 142318)),
    'children': quiet
        ? <Object>[]
        : [
            {'level': 'state', 'code': 'KD', 'name': 'Kaduna', ..._tally(8012, 7402)},
            {'level': 'state', 'code': 'KN', 'name': 'Kano', ..._tally(11222, 9804)},
            {'level': 'state', 'code': 'LA', 'name': 'Lagos', ..._tally(13325, 8120)},
            {'level': 'state', 'code': 'FC', 'name': 'Federal Capital', ..._tally(2822, 12)},
          ],
  }),
  'results/' => jsonResponse(_page(const [], count: quiet ? 0 : _results(query['status']))),
  'incidents/' => jsonResponse(_page(quiet || query['open'] == 'false' ? const [] : fakeIncidents)),
  'field-reports/' => jsonResponse(_page(const [])),
  'elections/' => jsonResponse([
    {
      'code': '2027-presidential',
      'name': 'Presidential election',
      'type': 'presidential',
      'status': 'open',
      'parties': [
        {'acronym': 'APC', 'name': 'All Progressives Congress'},
        {'acronym': 'PDP', 'name': "People's Democratic Party"},
        {'acronym': 'LP', 'name': 'Labour Party'},
      ],
      'scope': _nationalScope,
    },
  ]),
  'collation/' => jsonResponse(fakeCollation(verified: quiet ? 0 : 4218)),
  _ when path.endsWith('/events/') => jsonResponse(<Object>[]),
  _ when path.endsWith('/security/') => jsonResponse({'can_send': false, 'dispatches': <Object>[]}),
  _ => null,
};

/// A National Administrator, or, with [capabilities], a member appointed to
/// only those powers (a fixed role would bring all of its own).
Map<String, dynamic> commandUser({Set<String>? capabilities}) => {
  'access_id': capabilities == null ? 'NA-0001' : 'TGCG-000123',
  'full_name': 'Hauwa Danladi',
  'role': capabilities == null ? 'nationalAdministrator' : 'member',
  'scope': _nationalScope,
  'capabilities': (capabilities ?? {for (final power in TgcgCapability.values) power.name})
      .toList(),
  if (capabilities != null) 'membership_number': 'TGCG-000123',
  'access': [
    {
      'source': 'assignment',
      'assignment': 'a1',
      'role': 'national-administrator',
      'role_name': capabilities == null ? 'National Administrator' : 'National Media Director',
      'protected': capabilities == null,
      'areas': [_nationalScope],
      'permissions': (capabilities ?? const <String>{}).toList(),
    },
  ],
};

/// Signs in on the real login page, as agents and coordinators do.
Future<void> signInAsCoordinator(WidgetTester tester, double width) async {
  await tester.pumpAndSettle();
  if (width < 980) {
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('Agent or coordinator'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextField).at(0), 'NA-0001');
  await tester.enterText(find.byType(TextField).at(1), 'made-up');
  await tester.tap(find.text('Sign in').last);
  await settleLoads(tester);
}

/// The app caches the map's boundaries for good. Loaded inside a test, the
/// cache belongs to that test's fake clock and the next test waits for ever:
/// call this from setUpAll.
Future<void> loadMapOnce() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await GeoShapeSet.nigeriaStates();
}

/// Lets real asynchronous work (the map's boundaries, server replies) finish:
/// a spinner never settles, so this waits in real time until none is left.
Future<void> settleLoads(WidgetTester tester) async {
  for (var round = 0; round < 40; round++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 100));
    if (round > 2 && find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Opens a page from the sidebar, or the drawer on a phone.
Future<void> openModule(WidgetTester tester, String label, double width) async {
  if (width < 1100) {
    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
  }
  final item = find.widgetWithText(InkWell, label).last;
  await tester.ensureVisible(item);
  await tester.pumpAndSettle();
  await tester.tap(item);
  await settleLoads(tester);
}
