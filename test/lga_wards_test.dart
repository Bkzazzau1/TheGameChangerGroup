import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/geography/lga_ward_map_dialog.dart';
import 'package:tgcg_emcop/tgcg/geography/lga_wards.dart';
import 'package:tgcg_emcop/tgcg/geography/nigeria_map.dart';

LgaWards _read(String lga) => LgaWards.parse(File(nigeriaWardAsset(lga)).readAsStringSync());

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

void main() {
  test('every LGA has a ward file with polling unit counts', () {
    final files = Directory('assets/geo/ward').listSync().whereType<File>().toList();
    expect(files, hasLength(774));
    var wards = 0;
    var units = 0;
    for (final file in files) {
      final lga = LgaWards.parse(file.readAsStringSync());
      wards += lga.wards.length;
      units += lga.pollingUnits;
    }
    expect(wards, 8809);
    expect(units, 176846);
  });

  test('Zaria has 13 mapped wards and 584 polling units', () {
    final zaria = _read('KD-ZARIA');
    expect(zaria.wards, hasLength(13));
    expect(zaria.pollingUnits, 584);
    expect(zaria.wards.first.code, '18-23-01');
    expect(zaria.wards.first.pollingUnits, 51);
    expect(zaria.shapes, isNotNull);
    expect(zaria.mappedWards, 13);
    // Zaria city sits inside the LGA's wards.
    expect(zaria.shapes!.idAt(11.0855, 7.7199), isNotNull);
  });

  test('states without published boundaries still list wards', () {
    final ikeja = _read('LA-IKEJA');
    expect(ikeja.shapes, isNull);
    expect(ikeja.wards, isNotEmpty);
    expect(ikeja.pollingUnits, greaterThan(0));
  });

  testWidgets('dialog shows ward counts and selects from the list', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.runAsync(() => LgaWards.load('KD-ZARIA'));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: LgaWardMapDialog(lga: _zaria))),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump();

    expect(find.text('Kaduna State • 13 wards • 584 polling units'), findsOneWidget);
    expect(find.text('Kwarbai "a"'), findsOneWidget);
    expect(find.text('51 PUs'), findsOneWidget);

    await tester.tap(find.text('Kwarbai "a"'));
    await tester.pump();
    final tile = tester.widget<ListTile>(find.widgetWithText(ListTile, 'Kwarbai "a"'));
    expect(tile.selected, isTrue);
  });
}
