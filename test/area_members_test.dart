import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/geography/lga_ward_map_dialog.dart';
import 'package:tgcg_emcop/tgcg/geography/lga_wards.dart';
import 'package:tgcg_emcop/tgcg/geography/nigeria_map.dart';
import 'package:tgcg_emcop/tgcg/geography/state_lga_map_dialog.dart';
import 'package:tgcg_emcop/tgcg/geography/ward_polling_units_page.dart';
import 'package:tgcg_emcop/tgcg/session.dart';

// Names and numbers here are made up.
http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

const _zaria = CanonicalLga(
  id: 'KD-ZARIA',
  name: 'Zaria',
  stateId: 'KD',
  stateName: 'Kaduna',
  zoneId: 'NW',
  zoneName: 'North West',
  senatorialDistrictId: 'KD-N',
  senatorialDistrictName: 'Kaduna North',
);

const _units = {
  'count': 2,
  'next': null,
  'previous': null,
  'results': [
    {'code': '18-23-05-001', 'name': 'KAURA PRIMARY SCHOOL', 'ward': '18-23-05', 'registered_voters': 750},
    {'code': '18-23-05-002', 'name': 'KAURA MARKET', 'ward': '18-23-05', 'registered_voters': null},
  ],
};

Map<String, dynamic> _member(String number, String name, {List<String> roles = const []}) => {
  'membership_number': number,
  'full_name': name,
  'verification_status': 'verified',
  'membership_state': 'active',
  'scope': {
    'level': 'pollingUnit',
    'country': 'Nigeria',
    'stateId': 'KD',
    'lgaId': 'KD-ZARIA',
    'wardId': '18-23-05',
    'pollingUnitId': '18-23-05-001',
    'pollingUnitName': 'KAURA PRIMARY SCHOOL',
  },
  'phone_number': '+2348030000001',
  'email': null,
  'vin': null,
  'has_pvc': false,
  'gender': 'male',
  'date_of_birth': '1990-05-01',
  'occupation': 'Trader',
  'registration_channel': 'import',
  'phone_verified': false,
  'has_app_account': true,
  'photo_url': null,
  'sensitive_visible': true,
  'roles': [for (final role in roles) {'role_name': role}],
  'created_at': '2026-10-15T10:00:00Z',
};

class _Server {
  final requests = <String>[];
  http.Response? Function(String key, Map<String, String> query) answer = (_, _) => null;

  BackendServices connect() => BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient((request) async {
      final key = '${request.method} ${request.url.path.replaceFirst('/api/v1/', '')}';
      requests.add('$key ${request.url.query}');
      return answer(key, request.url.queryParameters) ??
          _json({'detail': 'Not found.'}, 404);
    }),
  );
}

TgcgSessionController _signedIn(Set<String> capabilities) => TgcgSessionController()
  ..signInFromServer(
    role: TgcgRole.nationalAdministrator,
    fullName: 'Admin',
    accessId: 'NA-1',
    scope: GeographicScope.nigeria,
    capabilities: capabilities,
  );

Future<void> _pump(
  WidgetTester tester,
  _Server server,
  TgcgSessionController session,
  Widget home,
) async {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(session.dispose);
  await tester.pumpWidget(
    TgcgBackend(
      services: server.connect(),
      child: TgcgSession(
        controller: session,
        child: MaterialApp(home: Scaffold(body: home)),
      ),
    ),
  );
}

void main() {
  testWidgets('an administrator follows a ward to its polling units and their people', (
    tester,
  ) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET members/counts/' when query['level'] == 'lga' => _json({
          'total': 7,
          'counts': {'18-23-05': 5, '18-23-01': 2},
        }),
        'GET members/counts/' when query['code'] == '18-23-05' => _json({
          'total': 5,
          'counts': {'18-23-05-001': 2},
        }),
        'GET geography/polling-units/' when query['ward__code'] == '18-23-05' => _json(_units),
        'GET members/' when query['polling_unit__code'] == '18-23-05-001' => _json({
          'count': 2,
          'next': null,
          'previous': null,
          'results': [
            _member('TGCG-000201', 'Musa Bello', roles: ['PU Organising Officer']),
            _member('TGCG-000202', 'Ada Sani'),
          ],
        }),
        _ => null,
      };
    await tester.runAsync(() => LgaWards.load('KD-ZARIA'));
    await _pump(
      tester,
      server,
      _signedIn({'manageMembership', 'viewMemberSensitiveData'}),
      const LgaWardMapDialog(lga: _zaria),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    // Each ward shows its members beside its polling units.
    expect(find.text('2 members'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Kaura'),
      60,
      scrollable: find.ancestor(of: find.text('Kwarbai "a"'), matching: find.byType(Scrollable)).first,
    );
    expect(find.text('5 members'), findsOneWidget);

    // A ward opens its polling units, with the members registered at each.
    await tester.tap(find.text('Kaura'));
    await tester.pumpAndSettle();
    expect(find.text('Kaura ward'), findsOneWidget);
    expect(find.text('18-23-05 • 2 polling units • 5 members'), findsOneWidget);
    expect(find.text('Kaura Primary School'), findsOneWidget);
    expect(find.text('18-23-05-001 • 750 voters'), findsOneWidget);
    expect(find.text('2 members'), findsOneWidget);
    expect(find.text('0 members'), findsOneWidget);

    // A polling unit opens its people, executives with their role.
    await tester.tap(find.text('Kaura Primary School'));
    await tester.pumpAndSettle();
    expect(find.text('18-23-05-001 • 2 members'), findsOneWidget);
    expect(find.text('TGCG-000201 • Verified • PU Organising Officer'), findsOneWidget);

    // And each person's details.
    await tester.tap(find.text('Musa Bello'));
    await tester.pumpAndSettle();
    for (final (label, value) in [
      ('Roles', 'PU Organising Officer'),
      ('Phone', '+2348030000001 (not confirmed)'),
      ('Gender', 'Male'),
      ('Date of birth', '1 May 1990'),
      ('Occupation', 'Trader'),
      ('Joined through', "A chapter's list"),
      ('PVC', 'Not added'),
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
      expect(find.text(value), findsOneWidget, reason: value);
    }
  });

  testWidgets('without member access a ward lists its polling units only', (tester) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET geography/polling-units/' => _json(_units),
        _ => null,
      };
    await _pump(
      tester,
      server,
      _signedIn({'viewSituationRoom', 'viewIncidents'}),
      const WardPollingUnitsPage(code: '18-23-05', name: 'KAURA'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kaura Primary School'), findsOneWidget);
    expect(find.text('18-23-05 • 2 polling units'), findsOneWidget);
    expect(find.textContaining('member'), findsNothing);
    expect(server.requests.where((r) => r.contains('members/')), isEmpty);
    // Nothing behind a polling unit to open.
    await tester.tap(find.text('Kaura Primary School'));
    await tester.pumpAndSettle();
    expect(find.text('Kaura ward'), findsOneWidget);
  });

  testWidgets('a ward beyond the account\'s area shows no member numbers', (tester) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET geography/polling-units/' => _json(_units),
        'GET members/counts/' => _json({'detail': 'This area is outside your access.'}, 403),
        _ => null,
      };
    await _pump(
      tester,
      server,
      _signedIn({'verifyMemberIdentity'}),
      const WardPollingUnitsPage(code: '18-23-05', name: 'KAURA'),
    );
    await tester.pumpAndSettle();

    expect(find.text('Kaura Primary School'), findsOneWidget);
    expect(find.textContaining('member'), findsNothing);
  });

  testWidgets('on a phone the state map shows its title, members and incidents', (tester) async {
    final server = _Server()
      ..answer = (key, query) => switch (key) {
        'GET members/counts/' when query['level'] == 'state' && query['by'] == 'lga' => _json({
          'total': 12,
          'counts': {'KD-ZARIA': 10, 'KD-KADUNA-NORTH': 2},
        }),
        _ => null,
      };
    final registry = GeographyRegistry.prototypeSeed();
    await tester.runAsync(() => GeoShapeSet.lgasOf('KD'));
    await _pump(
      tester,
      server,
      _signedIn({'manageMembership'}),
      StateLgaMapDialog(
        state: registry.state('KD')!,
        lgas: registry.lgasForState('KD'),
        incidents: const [],
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    // An overflow anywhere fails the test.
    expect(find.text('Kaduna State'), findsOneWidget);
    expect(find.text('12 MEMBERS'), findsOneWidget);
    expect(find.text('0 OPEN'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
  });
}
