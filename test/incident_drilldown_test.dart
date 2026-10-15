import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/field/field_operations_store.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/geography/lga_ward_map_dialog.dart';
import 'package:tgcg_emcop/tgcg/geography/lga_wards.dart';
import 'package:tgcg_emcop/tgcg/geography/nigeria_map.dart';
import 'package:tgcg_emcop/tgcg/geography/state_lga_map_dialog.dart';
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

GeographicScope _place({String? ward, String? wardName, String? unit, String? unitName, String lga = 'KD-ZARIA'}) =>
    GeographicScope(
      level: unit != null
          ? GeographyLevel.pollingUnit
          : ward != null
              ? GeographyLevel.ward
              : GeographyLevel.lga,
      country: 'Nigeria',
      stateId: 'KD',
      stateName: 'Kaduna',
      lgaId: lga,
      lgaName: lga == 'KD-ZARIA' ? 'Zaria' : 'Kaduna North',
      wardId: ward,
      wardName: wardName,
      pollingUnitId: unit,
      pollingUnitName: unitName,
    );

FieldIncident _incident(
  String id,
  String title,
  IncidentSeverity severity,
  GeographicScope scope, {
  IncidentStatus status = IncidentStatus.reported,
}) =>
    FieldIncident(
      id: id,
      title: title,
      category: 'Security',
      severity: severity,
      status: status,
      scope: scope,
      reportedAt: DateTime.utc(2027, 2, 25, 9, 30),
      reporterId: 'AG-00001',
      summary: '$title: details from the field.',
    );

final _incidents = [
  _incident(
    'INC-000001',
    'Ballot box snatched',
    IncidentSeverity.critical,
    _place(ward: '18-23-05', wardName: 'KAURA', unit: '18-23-05-001', unitName: 'KAURA PRIMARY SCHOOL'),
  ),
  _incident(
    'INC-000002',
    'Crowd at the ward collation centre',
    IncidentSeverity.medium,
    _place(ward: '18-23-05', wardName: 'KAURA'),
  ),
  _incident('INC-000003', 'Road blocked into Zaria', IncidentSeverity.high, _place()),
  _incident(
    'INC-000004',
    'Late materials',
    IncidentSeverity.low,
    _place(ward: '18-23-01', wardName: 'KWARBAI "A"', unit: '18-23-01-001', unitName: 'KWARBAI I'),
    status: IncidentStatus.resolved,
  ),
  _incident('INC-000005', 'Elsewhere in Kaduna', IncidentSeverity.critical, _place(lga: 'KD-KADUNA-NORTH')),
];

Future<void> _pump(WidgetTester tester, Widget home, {Size size = const Size(1400, 1000)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final session = TgcgSessionController()
    ..signInFromServer(
      role: TgcgRole.nationalAdministrator,
      fullName: 'Admin',
      accessId: 'NA-1',
      scope: GeographicScope.nigeria,
      capabilities: {'viewSituationRoom', 'viewIncidents'},
    );
  final field = FieldOperationsController.prototypeSeed();
  addTearDown(() {
    field.dispose();
    session.dispose();
  });
  await tester.pumpWidget(
    TgcgBackend(
      services: BackendServices.connect(
        'https://api.tgcg.test',
        tokens: MemoryTokenStore(),
        httpClient: MockClient((request) async {
          final path = request.url.path.replaceFirst('/api/v1/', '');
          return path == 'geography/polling-units/'
              ? _json(_units)
              : _json({'detail': 'Not found.'}, 404);
        }),
      ),
      child: TgcgSession(
        controller: session,
        child: FieldOperations(
          controller: field,
          child: MaterialApp(home: Scaffold(body: home)),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('open incidents go on from an LGA to its wards, polling units and reports', (
    tester,
  ) async {
    await tester.runAsync(() => LgaWards.load('KD-ZARIA'));
    await _pump(tester, LgaWardMapDialog(lga: _zaria, incidents: _incidents));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    // Zaria's three open incidents: two in Kaura ward, one for the whole LGA.
    expect(find.text('3 OPEN'), findsOneWidget);
    expect(find.text('1 open incident for the whole LGA'), findsOneWidget);
    final kaura = find.widgetWithText(ListTile, 'Kaura');
    expect(find.descendant(of: kaura, matching: find.text('2 OPEN')), findsOneWidget);
    // The ward with incidents comes first in the list.
    expect(
      tester.getTopLeft(kaura).dy,
      lessThan(tester.getTopLeft(find.widgetWithText(ListTile, 'Kwarbai "a"')).dy),
    );

    // The polling unit view is one switch away.
    await tester.tap(find.text('Polling units'));
    await tester.pump();
    expect(find.text('2 OPEN'), findsNothing);
    expect(find.text('51 PUs'), findsOneWidget);
    await tester.tap(find.text('Incidents'));
    await tester.pump();

    // A ward opens its polling units with the reports at each.
    await tester.tap(find.text('Kaura'));
    await tester.pumpAndSettle();
    expect(find.text('Kaura ward'), findsOneWidget);
    expect(find.text('OPEN INCIDENTS (2)'), findsOneWidget);
    expect(find.text('Whole ward'), findsOneWidget);
    expect(find.text('Crowd at the ward collation centre'), findsOneWidget);
    expect(find.text('Kaura Primary School • 18-23-05-001'), findsOneWidget);
    expect(find.text('Ballot box snatched'), findsOneWidget);
    expect(find.text('Road blocked into Zaria'), findsNothing);
    expect(find.text('Late materials'), findsNothing);
    final school = find.widgetWithText(ListTile, 'Kaura Primary School');
    expect(find.descendant(of: school, matching: find.text('1 OPEN')), findsOneWidget);
    final market = find.widgetWithText(ListTile, 'Kaura Market');
    expect(find.descendant(of: market, matching: find.textContaining('OPEN')), findsNothing);

    // Each report opens in full.
    await tester.tap(find.text('Ballot box snatched'));
    await tester.pumpAndSettle();
    expect(find.text('Incident report'), findsOneWidget);
    expect(find.text('INC-000001'), findsOneWidget);
    expect(find.text('Ballot box snatched: details from the field.'), findsOneWidget);
    expect(find.text('KAURA PRIMARY SCHOOL • KAURA • Zaria'), findsOneWidget);
  });

  testWidgets('on a phone the ward map and polling units fit with their incidents', (tester) async {
    await tester.runAsync(() => LgaWards.load('KD-ZARIA'));
    await _pump(
      tester,
      LgaWardMapDialog(lga: _zaria, incidents: _incidents),
      size: const Size(360, 780),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    // An overflow anywhere fails the test.
    expect(find.text('Zaria LGA: wards'), findsOneWidget);
    expect(find.text('3 OPEN'), findsOneWidget);
    await tester.tap(find.text('Kaura'));
    await tester.pumpAndSettle();
    expect(find.text('Ballot box snatched'), findsOneWidget);
  });

  testWidgets('without incidents the ward map stays a polling unit map', (tester) async {
    await tester.runAsync(() => LgaWards.load('KD-ZARIA'));
    await _pump(tester, const LgaWardMapDialog(lga: _zaria));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    expect(find.text('51 PUs'), findsOneWidget);
    expect(find.text('Incidents'), findsNothing);
    expect(find.textContaining('OPEN'), findsNothing);
  });

  testWidgets('from the state map, an LGA lists its reports and opens its wards on them', (
    tester,
  ) async {
    final registry = GeographyRegistry.prototypeSeed();
    await tester.runAsync(() => GeoShapeSet.lgasOf('KD'));
    await tester.runAsync(() => LgaWards.load('KD-ZARIA'));
    await _pump(
      tester,
      StateLgaMapDialog(
        state: registry.state('KD')!,
        lgas: registry.lgasForState('KD'),
        incidents: [
          for (final incident in _incidents)
            if (incident.scope.lgaId == 'KD-ZARIA') incident,
        ],
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    await tester.tap(find.widgetWithText(ListTile, 'Zaria'));
    await tester.pump();
    expect(find.text('OPEN INCIDENTS (3)'), findsOneWidget);
    expect(find.text('KAURA PRIMARY SCHOOL • KAURA • Zaria'), findsOneWidget);

    await tester.tap(find.text('Wards & polling units'));
    // The ward dialog is built first; its ward data then arrives.
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(find.text('Zaria LGA: wards'), findsOneWidget);
    final wards = find.byType(LgaWardMapDialog);
    expect(find.descendant(of: wards, matching: find.text('3 OPEN')), findsOneWidget);
    expect(find.descendant(of: wards, matching: find.text('2 OPEN')), findsOneWidget);

    // A report in the LGA's list opens in full too.
    await tester.tap(find.byTooltip('Close').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road blocked into Zaria'));
    await tester.pumpAndSettle();
    expect(find.text('Road blocked into Zaria: details from the field.'), findsOneWidget);
  });
}
