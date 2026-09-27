import '../domain/models.dart';

class CanonicalPollingUnit {
  const CanonicalPollingUnit({
    required this.code,
    required this.scope,
    this.registeredVoters,
  });

  final String code;
  final GeographicScope scope;
  final int? registeredVoters;
}

class GeographyRegistry {
  const GeographyRegistry({required this.pollingUnits});

  final List<CanonicalPollingUnit> pollingUnits;

  factory GeographyRegistry.prototypeSeed() => const GeographyRegistry(
        pollingUnits: [
          CanonicalPollingUnit(
            code: 'KD-KN-W01-PU001',
            registeredVoters: 481,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NW',
              zoneName: 'North West',
              stateId: 'KD',
              stateName: 'Kaduna',
              senatorialDistrictId: 'KD-SD-01',
              senatorialDistrictName: 'Kaduna District 01',
              lgaId: 'KD-KADUNA-NORTH',
              lgaName: 'Kaduna North',
              wardId: 'KD-KN-W01',
              wardName: 'Ward 01',
              pollingUnitId: 'KD-KN-W01-PU001',
              pollingUnitName: 'PU 001',
            ),
          ),
          CanonicalPollingUnit(
            code: 'KD-KN-W01-PU002',
            registeredVoters: 436,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NW',
              zoneName: 'North West',
              stateId: 'KD',
              stateName: 'Kaduna',
              senatorialDistrictId: 'KD-SD-01',
              senatorialDistrictName: 'Kaduna District 01',
              lgaId: 'KD-KADUNA-NORTH',
              lgaName: 'Kaduna North',
              wardId: 'KD-KN-W01',
              wardName: 'Ward 01',
              pollingUnitId: 'KD-KN-W01-PU002',
              pollingUnitName: 'PU 002',
            ),
          ),
          CanonicalPollingUnit(
            code: 'BN-MK-W01-PU004',
            registeredVoters: 502,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NC',
              zoneName: 'North Central',
              stateId: 'BN',
              stateName: 'Benue',
              senatorialDistrictId: 'BN-SD-01',
              senatorialDistrictName: 'Benue District 01',
              lgaId: 'BN-MAKURDI',
              lgaName: 'Makurdi',
              wardId: 'BN-MK-W01',
              wardName: 'Ward 01',
              pollingUnitId: 'BN-MK-W01-PU004',
              pollingUnitName: 'PU 004',
            ),
          ),
          CanonicalPollingUnit(
            code: 'BN-MK-W01-PU005',
            registeredVoters: 391,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'NC',
              zoneName: 'North Central',
              stateId: 'BN',
              stateName: 'Benue',
              senatorialDistrictId: 'BN-SD-01',
              senatorialDistrictName: 'Benue District 01',
              lgaId: 'BN-MAKURDI',
              lgaName: 'Makurdi',
              wardId: 'BN-MK-W01',
              wardName: 'Ward 01',
              pollingUnitId: 'BN-MK-W01-PU005',
              pollingUnitName: 'PU 005',
            ),
          ),
          CanonicalPollingUnit(
            code: 'LA-IK-W03-PU012',
            registeredVoters: 612,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'SW',
              zoneName: 'South West',
              stateId: 'LA',
              stateName: 'Lagos',
              senatorialDistrictId: 'LA-SD-01',
              senatorialDistrictName: 'Lagos District 01',
              lgaId: 'LA-IKEJA',
              lgaName: 'Ikeja',
              wardId: 'LA-IK-W03',
              wardName: 'Ward 03',
              pollingUnitId: 'LA-IK-W03-PU012',
              pollingUnitName: 'PU 012',
            ),
          ),
          CanonicalPollingUnit(
            code: 'LA-IK-W03-PU013',
            registeredVoters: 577,
            scope: GeographicScope(
              level: GeographyLevel.pollingUnit,
              country: 'Nigeria',
              zoneId: 'SW',
              zoneName: 'South West',
              stateId: 'LA',
              stateName: 'Lagos',
              senatorialDistrictId: 'LA-SD-01',
              senatorialDistrictName: 'Lagos District 01',
              lgaId: 'LA-IKEJA',
              lgaName: 'Ikeja',
              wardId: 'LA-IK-W03',
              wardName: 'Ward 03',
              pollingUnitId: 'LA-IK-W03-PU013',
              pollingUnitName: 'PU 013',
            ),
          ),
        ],
      );

  CanonicalPollingUnit? pollingUnit(String id) {
    for (final unit in pollingUnits) {
      if (unit.code == id || unit.scope.pollingUnitId == id) return unit;
    }
    return null;
  }

  List<CanonicalPollingUnit> pollingUnitsWithin(GeographicScope scope) =>
      pollingUnits.where((unit) => scopeContains(scope, unit.scope)).toList(growable: false);

  List<GeographicScope> childScopes(GeographicScope parent) {
    final values = <String, GeographicScope>{};
    for (final unit in pollingUnitsWithin(parent)) {
      final child = directChild(parent.level, unit.scope);
      if (child != null) values[_key(child)] = child;
    }
    final result = values.values.toList()..sort((a, b) => a.label.compareTo(b.label));
    return result;
  }

  GeographicScope? directChild(
    GeographyLevel parentLevel,
    GeographicScope unit,
  ) => switch (parentLevel) {
        GeographyLevel.country => GeographicScope(
            level: GeographyLevel.geopoliticalZone,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
          ),
        GeographyLevel.geopoliticalZone => GeographicScope(
            level: GeographyLevel.state,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
            stateId: unit.stateId,
            stateName: unit.stateName,
          ),
        GeographyLevel.state => GeographicScope(
            level: GeographyLevel.senatorialDistrict,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
            stateId: unit.stateId,
            stateName: unit.stateName,
            senatorialDistrictId: unit.senatorialDistrictId,
            senatorialDistrictName: unit.senatorialDistrictName,
          ),
        GeographyLevel.senatorialDistrict => GeographicScope(
            level: GeographyLevel.lga,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
            stateId: unit.stateId,
            stateName: unit.stateName,
            senatorialDistrictId: unit.senatorialDistrictId,
            senatorialDistrictName: unit.senatorialDistrictName,
            lgaId: unit.lgaId,
            lgaName: unit.lgaName,
          ),
        GeographyLevel.lga => GeographicScope(
            level: GeographyLevel.ward,
            country: unit.country,
            zoneId: unit.zoneId,
            zoneName: unit.zoneName,
            stateId: unit.stateId,
            stateName: unit.stateName,
            senatorialDistrictId: unit.senatorialDistrictId,
            senatorialDistrictName: unit.senatorialDistrictName,
            lgaId: unit.lgaId,
            lgaName: unit.lgaName,
            wardId: unit.wardId,
            wardName: unit.wardName,
          ),
        GeographyLevel.ward => unit,
        GeographyLevel.pollingUnit => null,
      };

  static bool scopeContains(GeographicScope parent, GeographicScope child) {
    if (parent.country != child.country) return false;
    if (parent.level == GeographyLevel.country) return true;
    if (parent.zoneId != null && parent.zoneId != child.zoneId) return false;
    if (parent.level == GeographyLevel.geopoliticalZone) return true;
    if (parent.stateId != null && parent.stateId != child.stateId) return false;
    if (parent.level == GeographyLevel.state) return true;
    if (parent.senatorialDistrictId != null &&
        parent.senatorialDistrictId != child.senatorialDistrictId) return false;
    if (parent.level == GeographyLevel.senatorialDistrict) return true;
    if (parent.lgaId != null && parent.lgaId != child.lgaId) return false;
    if (parent.level == GeographyLevel.lga) return true;
    if (parent.wardId != null && parent.wardId != child.wardId) return false;
    if (parent.level == GeographyLevel.ward) return true;
    return parent.pollingUnitId == child.pollingUnitId;
  }

  static String _key(GeographicScope scope) => switch (scope.level) {
        GeographyLevel.country => scope.country,
        GeographyLevel.geopoliticalZone => scope.zoneId ?? scope.label,
        GeographyLevel.state => scope.stateId ?? scope.label,
        GeographyLevel.senatorialDistrict => scope.senatorialDistrictId ?? scope.label,
        GeographyLevel.lga => scope.lgaId ?? scope.label,
        GeographyLevel.ward => scope.wardId ?? scope.label,
        GeographyLevel.pollingUnit => scope.pollingUnitId ?? scope.label,
      };
}
