import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tgcg_emcop/tgcg/api/api_client.dart';
import 'package:tgcg_emcop/tgcg/api/backend.dart';
import 'package:tgcg_emcop/tgcg/api/mapping_repository.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';
import 'package:tgcg_emcop/tgcg/location/directions.dart';
import 'package:tgcg_emcop/tgcg/location/gps_service.dart';
import 'package:tgcg_emcop/tgcg/mapping/pin_guide_page.dart';

class _FakeGps extends GpsService {
  _FakeGps(this.readings);
  final StreamController<GpsFix> readings;

  @override
  Future<void> ensureAccess() async {}

  @override
  Stream<GpsFix> watch() => readings.stream;
}

GpsFix _fix(double accuracy, {bool mocked = false}) => GpsFix(
      latitude: 11.0855,
      longitude: 7.7199,
      accuracyMeters: accuracy,
      capturedAt: DateTime.utc(2026, 10, 11, 9),
      isMocked: mocked,
    );

// A valid 1x1 PNG, so the photo preview decodes.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

const _unit = MappingUnit(
  code: '18-23-01-001',
  name: 'KWARBAI I/ PRI. SCH. MADARKACI',
  location: '',
  wardCode: '18-23-01',
  wardName: 'KWARBAI "A"',
  status: MappingStatus.unmapped,
  pins: 0,
);

Future<List<http.BaseRequest>> _pump(
  WidgetTester tester,
  _FakeGps gps,
  http.Response Function(http.Request) respond, {
  MappingUnit unit = _unit,
  LaunchDirections? launch,
}) async {
  final requests = <http.BaseRequest>[];
  final backend = BackendServices.connect(
    'https://api.tgcg.test',
    tokens: MemoryTokenStore(),
    httpClient: MockClient.streaming((request, body) async {
      requests.add(request);
      final bytes = await body.toBytes();
      final plain = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = bytes;
      final response = respond(plain);
      return http.StreamedResponse(Stream.value(response.bodyBytes), response.statusCode,
          headers: response.headers);
    }),
  );
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    TgcgBackend(
      services: backend,
      child: MaterialApp(
        home: PinGuidePage(
          unit: unit,
          gps: gps,
          pickPhoto: () async => (_pixel, 'sign.png'),
          launch: launch ?? (_) async => true,
        ),
      ),
    ),
  );
  return requests;
}

void main() {
  testWidgets('guides a coordinator from arrival to a confirmed pin', (tester) async {
    final readings = StreamController<GpsFix>();
    final requests = await _pump(tester, _FakeGps(readings), (_) => http.Response(
          jsonEncode({'status': 'pinned', 'gps': {'distance_to_pu_m': null}}),
          201,
          headers: {'content-type': 'application/json'},
        ));

    // Step 1: must confirm standing at the entrance.
    final next = find.widgetWithText(FilledButton, 'Next').first;
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Next').first);
    await tester.pumpAndSettle();

    // Step 2: signboard matches.
    await tester.tap(find.text('Yes, it matches'));
    // The GPS step refreshes every second, so advance time instead of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    // Step 3: a vague fix is not enough; a precise one unlocks the button.
    readings.add(_fix(80));
    await tester.pump();
    expect(find.text('±80 m'), findsOneWidget);
    expect(find.text('Waiting for a precise fix'), findsOneWidget);
    readings.add(_fix(12));
    await tester.pump();
    expect(find.text('±12 m'), findsOneWidget);
    await tester.tap(find.text('Use this location (±12 m)'));
    await tester.pumpAndSettle();

    // Step 4: photo.
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Next').last);
    await tester.pumpAndSettle();

    // Step 5: submit.
    await tester.tap(find.text('Pin this unit'));
    await tester.pumpAndSettle();
    expect(find.text('Location set'), findsOneWidget);

    expect(requests.single.url.path, '/api/v1/mapping/units/18-23-01-001/pin/');
    expect(requests.single, isA<http.MultipartRequest>());
    final multipart = requests.single as http.MultipartRequest;
    expect(multipart.fields['at_entrance'], 'true');
    expect(jsonDecode(multipart.fields['gps']!)['accuracy_m'], 12.0);
    expect(multipart.files.single.field, 'photo');
    // Not awaited: done is never delivered once the page stops listening.
    unawaited(readings.close());
  });

  testWidgets('a fake-location app blocks the pin', (tester) async {
    final readings = StreamController<GpsFix>();
    await _pump(tester, _FakeGps(readings), (_) => http.Response('{}', 500));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Next').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, it matches'));
    // The GPS step refreshes every second, so advance time instead of settling.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    readings.add(_fix(5, mocked: true));
    await tester.pump();
    expect(find.textContaining('fake-location app is active'), findsOneWidget);
    expect(find.text('Waiting for a precise fix'), findsOneWidget);
    // Not awaited: done is never delivered once the page stops listening.
    unawaited(readings.close());
  });

  testWidgets("guides the coordinator to INEC's location for checking", (tester) async {
    const inecUnit = MappingUnit(
      code: '18-23-01-014',
      name: 'UNG. ASKA I/ L.E.A. ANGUWAN KAHU',
      location: '',
      wardCode: '18-23-01',
      wardName: 'KWARBAI "A"',
      status: MappingStatus.pinned,
      pins: 0,
      latitude: 11.0539,
      longitude: 7.712954605,
      locationSource: 'inec',
    );
    final launched = <Uri>[];
    final requests = await _pump(
      tester,
      _FakeGps(StreamController<GpsFix>()),
      (_) => http.Response('{}', 500),
      unit: inecUnit,
      launch: (uri) async {
        launched.add(uri);
        return true;
      },
    );
    expect(find.text('INEC LOCATION'), findsOneWidget);
    expect(find.textContaining("INEC's polling unit locator places this unit"), findsOneWidget);

    await tester.tap(find.text("Directions to INEC's location"));
    await tester.pump();
    expect(launched.single.queryParameters['destination'], '11.0539,7.712954605');
    expect(requests, isEmpty);
  });

  test('progress and units read INEC locations', () {
    final progress = MappingProgress.fromJson({
      'total': 51,
      'unmapped': 10,
      'pinned': 40,
      'confirmed': 1,
      'conflict': 0,
      'problem': 0,
      'from_inec': 38,
      'mapped_percent': 80.4,
    });
    expect(progress.fromInec, 38);
    expect(progress.mapped, 41);
    final unit = MappingUnit.fromJson({
      'code': '18-23-01-014',
      'name': 'UNG. ASKA I/ L.E.A. ANGUWAN KAHU',
      'location': '',
      'ward': '18-23-01',
      'ward_name': 'KWARBAI "A"',
      'mapping_status': 'pinned',
      'latitude': '11.053900',
      'longitude': '7.712955',
      'location_source': 'inec',
      'pins': 0,
    });
    expect(unit.locatedByInec, isTrue);
    expect(unit.hasLocation, isTrue);
  });

  testWidgets('a mismatched signboard reports a problem instead of pinning', (tester) async {
    final requests = await _pump(tester, _FakeGps(StreamController<GpsFix>()), (_) => http.Response(
          jsonEncode({'status': 'problem'}),
          201,
          headers: {'content-type': 'application/json'},
        ));
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Next').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('No / cannot find it'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report problem'));
    await tester.pump();
    expect(find.textContaining('Describe what you found'), findsOneWidget);
    expect(requests, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'What did you find?'),
      'Moved to the new school by the market.',
    );
    await tester.ensureVisible(find.text('Report problem'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report problem'));
    await tester.pumpAndSettle();
    expect(requests.single.url.path, '/api/v1/mapping/units/18-23-01-001/problem/');
  });
}
