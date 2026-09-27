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
      expect(unit.scope.lgaName, 'Kaduna North');
    });

    test('country children are geopolitical zones', () {
      final children = registry.childScopes(GeographicScope.nigeria);

      expect(children, isNotEmpty);
      expect(children.every((scope) => scope.level == GeographyLevel.geopoliticalZone), isTrue);
      expect(children.map((scope) => scope.zoneId).toSet(), containsAll({'NW', 'NC', 'SW'}));
    });

    test('drill-down preserves canonical hierarchy', () {
      final northWest = registry
          .childScopes(GeographicScope.nigeria)
          .firstWhere((scope) => scope.zoneId == 'NW');
      final kaduna = registry.childScopes(northWest).single;
      final district = registry.childScopes(kaduna).single;
      final lga = registry.childScopes(district).single;
      final ward = registry.childScopes(lga).single;
      final pollingUnits = registry.childScopes(ward);

      expect(kaduna.level, GeographyLevel.state);
      expect(district.level, GeographyLevel.senatorialDistrict);
      expect(lga.level, GeographyLevel.lga);
      expect(ward.level, GeographyLevel.ward);
      expect(pollingUnits.length, 2);
      expect(pollingUnits.every((scope) => scope.level == GeographyLevel.pollingUnit), isTrue);
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
