import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';

void main() {
  group('GeographyRegistry', () {
    final registry = GeographyRegistry.prototypeSeed();

    test('resolves a canonical polling unit by code', () {
      final unit = registry.pollingUnit('KD-KN-W01-PU001');

      expect(unit, isNotNull);
      expect(unit!.scope.level, GeographyLevel.pollingUnit);
      expect(unit.scope.stateName, 'Kaduna');
      expect(unit.scope.senatorialDistrictName, 'Kaduna Central');
      expect(unit.scope.lgaName, 'Kaduna North');
    });

    test('country children are all geopolitical zones', () {
      final children = registry.childScopes(GeographicScope.nigeria);

      expect(children.length, 6);
      expect(
        children.every(
          (scope) => scope.level == GeographyLevel.geopoliticalZone,
        ),
        isTrue,
      );
      expect(
        children.map((scope) => scope.zoneId).toSet(),
        containsAll({'NC', 'NE', 'NW', 'SE', 'SS', 'SW'}),
      );
    });

    test('nationwide geography contains 109 districts and 774 LGAs', () {
      expect(registry.nationalSenatorialDistrictCount, 109);
      expect(registry.nationalLgaCount, 774);
    });

    test('state drill-down follows district then LGA hierarchy', () {
      final northWest = registry
          .childScopes(GeographicScope.nigeria)
          .firstWhere((scope) => scope.zoneId == 'NW');
      final kaduna = registry
          .childScopes(northWest)
          .firstWhere((scope) => scope.stateId == 'KD');
      final kadunaDistricts = registry.childScopes(kaduna);
      final kadunaCentral = kadunaDistricts.firstWhere(
        (scope) => scope.senatorialDistrictId == 'SD/053/KD',
      );
      final centralLgas = registry.childScopes(kadunaCentral);
      final kadunaNorth = centralLgas.firstWhere(
        (scope) => scope.lgaId == 'KD-KADUNA-NORTH',
      );
      final wards = registry.childScopes(kadunaNorth);
      final ward = wards.single;
      final pollingUnits = registry.childScopes(ward);

      expect(kaduna.level, GeographyLevel.state);
      expect(kadunaDistricts.length, 3);
      expect(
        kadunaDistricts.every(
          (scope) => scope.level == GeographyLevel.senatorialDistrict,
        ),
        isTrue,
      );
      expect(kadunaCentral.senatorialDistrictName, 'Kaduna Central');
      expect(centralLgas.length, 7);
      expect(
        centralLgas.every((scope) => scope.level == GeographyLevel.lga),
        isTrue,
      );
      expect(kadunaNorth.lgaName, 'Kaduna North');
      expect(ward.level, GeographyLevel.ward);
      expect(pollingUnits.length, 2);
      expect(
        pollingUnits.every(
          (scope) => scope.level == GeographyLevel.pollingUnit,
        ),
        isTrue,
      );
    });

    test('FCT has one senatorial district covering six area councils', () {
      final northCentral = registry
          .childScopes(GeographicScope.nigeria)
          .firstWhere((scope) => scope.zoneId == 'NC');
      final fct = registry
          .childScopes(northCentral)
          .firstWhere((scope) => scope.stateId == 'FCT');
      final districts = registry.childScopes(fct);
      final areaCouncils = registry.childScopes(districts.single);

      expect(districts.length, 1);
      expect(districts.single.senatorialDistrictId, 'SD/109/FCT');
      expect(areaCouncils.length, 6);
      expect(
        areaCouncils.every((scope) => scope.level == GeographyLevel.lga),
        isTrue,
      );
    });

    test('scope containment rejects another state', () {
      final kd = registry.pollingUnit('KD-KN-W01-PU001')!.scope;
      final la = registry.pollingUnit('LA-IK-W03-PU012')!.scope;
      final kadunaState = GeographicScope(
        level: GeographyLevel.state,
        country: 'Nigeria',
        zoneId: kd.zoneId,
        zoneName: kd.zoneName,
        stateId: kd.stateId,
        stateName: kd.stateName,
      );

      expect(GeographyRegistry.scopeContains(kadunaState, kd), isTrue);
      expect(GeographyRegistry.scopeContains(kadunaState, la), isFalse);
    });
  });
}
