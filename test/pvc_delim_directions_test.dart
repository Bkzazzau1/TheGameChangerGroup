import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/reference_repository.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/location/directions.dart';
import 'package:tgcg_emcop/tgcg/membership/pvc_enrollment_page.dart';
import 'package:tgcg_emcop/tgcg/membership/pvc_recognition_service.dart';

BackendServices _backend(Map<String, dynamic> Function(http.Request) respond) =>
    BackendServices.connect(
      'https://api.tgcg.test',
      tokens: MemoryTokenStore(),
      httpClient: MockClient((request) async => http.Response(
            jsonEncode(respond(request)),
            200,
            headers: {'content-type': 'application/json'},
          )),
    );

Map<String, dynamic> _unit(Object? navigation) => {
      'code': '18-23-01-001',
      'name': 'KWARBAI I/ PRI. SCH. MADARKACI',
      'location': '',
      'ward': '18-23-01',
      'registered_voters': 812,
      'latitude': null,
      'longitude': null,
      'mapping_status': navigation == null ? 'unmapped' : 'pinned',
      'navigation': navigation,
    };

void main() {
  group('PVC DELIM', () {
    test('reads the labelled DELIM line in any separator style', () {
      expect(PvcRecognitionService.extractDelim('DELIM: 18/23/01/001'), '18-23-01-001');
      expect(PvcRecognitionService.extractDelim('DELIM\n18-23-1-1'), '18-23-01-001');
      expect(PvcRecognitionService.extractDelim('DELIM 24 / 8 / 8 / 26'), '24-08-08-026');
    });

    test('prefers the DELIM line and ignores dates of birth', () {
      const card = 'INDEPENDENT NATIONAL ELECTORAL COMMISSION\n'
          'VIN 90F5 B0E8 D029 5847 263\n'
          'DATE OF BIRTH 14/05/1990\n'
          'DELIM 37/06/09/012\n'
          'BELLO MUSA';
      expect(PvcRecognitionService.extractDelim(card), '37-06-09-012');
      expect(PvcRecognitionService.extractDelim('DATE OF BIRTH 14/05/1990'), isNull);
      // INEC numbers states 1-37.
      expect(PvcRecognitionService.extractDelim('DELIM 52/01/01/001'), isNull);
    });

    test('joins a VIN that OCR split into groups', () {
      expect(
        PvcRecognitionService.extractVoterId('VIN 90F5 B0E8 D029 5847 263'),
        '90F5B0E8D0295847263',
      );
      expect(
        PvcRecognitionService.extractVoterId('VIN\n90F5B0E8D0295847263'),
        '90F5B0E8D0295847263',
      );
    });

    test('server state names match registry states', () {
      final states = GeographyRegistry.prototypeSeed().states;
      expect(matchStateByName(states, 'Kaduna')?.id, 'KD');
      expect(matchStateByName(states, 'FCT')?.id, 'FCT');
      expect(matchStateByName(states, 'Federal Capital Territory')?.id, 'FCT');
      expect(matchStateByName(states, 'Atlantis'), isNull);
    });

    test('looks up the polling unit for a DELIM code', () async {
      late Uri asked;
      final backend = _backend((request) {
        asked = request.url;
        return {
          'code': '18-23-01-001',
          'name': 'KWARBAI I/ PRI. SCH. MADARKACI',
          'location': '',
          'ward': 'KWARBAI "A"',
          'ward_code': '18-23-01',
          'lga': 'Zaria',
          'state': 'Kaduna',
          'navigation': null,
        };
      });
      final unit = await backend.reference.pollingUnitForDelim('18/23/01/001');
      expect(asked.path, '/api/v1/register/polling-unit/');
      expect(asked.queryParameters['delim'], '18/23/01/001');
      expect(unit.label, 'KWARBAI I/ PRI. SCH. MADARKACI, KWARBAI "A" ward, Zaria LGA, Kaduna State');
    });
  });

  group('Navigate to polling unit', () {
    Future<List<Uri>> pump(WidgetTester tester, Object? navigation) async {
      final launched = <Uri>[];
      await tester.pumpWidget(
        TgcgBackend(
          services: _backend((_) => _unit(navigation)),
          child: MaterialApp(
            home: Scaffold(
              body: NavigateToUnitButton(
                unitCode: '18-23-01-001',
                launch: (uri) async {
                  launched.add(uri);
                  return true;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return launched;
    }

    testWidgets('opens Google Maps directions to a mapped unit', (tester) async {
      final launched = await pump(tester, {
        'latitude': 11.0855,
        'longitude': 7.7199,
        'confirmed': true,
        'accuracy_m': 12,
      });
      expect(find.textContaining('not yet confirmed'), findsNothing);
      await tester.tap(find.text('Navigate to polling unit'));
      await tester.pump();
      expect(
        launched.single.toString(),
        'https://www.google.com/maps/dir/?api=1&destination=11.0855%2C7.7199',
      );
    });

    testWidgets('warns when only one coordinator has pinned the unit', (tester) async {
      await pump(tester, {
        'latitude': 11.0855,
        'longitude': 7.7199,
        'confirmed': false,
        'accuracy_m': 25,
      });
      expect(find.text('Navigate to polling unit'), findsOneWidget);
      expect(find.textContaining('not yet confirmed'), findsOneWidget);
    });

    testWidgets('says so when the unit is not mapped', (tester) async {
      final launched = await pump(tester, null);
      expect(find.text('Navigate to polling unit'), findsNothing);
      expect(find.textContaining('has not been mapped yet'), findsOneWidget);
      expect(launched, isEmpty);
    });

    testWidgets('explains that offline mode has no directions', (tester) async {
      await tester.pumpWidget(
        const TgcgBackend(
          services: null,
          child: MaterialApp(
            home: Scaffold(body: NavigateToUnitButton(unitCode: '18-23-01-001')),
          ),
        ),
      );
      expect(find.textContaining('need a connection'), findsOneWidget);
    });
  });

  test('directions parse from the server payload', () {
    expect(UnitDirections.fromJson(null), isNull);
    final to = UnitDirections.fromJson({
      'latitude': 11.0855,
      'longitude': 7.7199,
      'confirmed': false,
      'accuracy_m': null,
    })!;
    expect(to.confirmed, isFalse);
    expect(to.accuracyMeters, isNull);
  });
}
