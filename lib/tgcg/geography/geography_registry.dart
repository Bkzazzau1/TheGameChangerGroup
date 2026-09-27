import '../domain/models.dart';
import 'nigeria_lga_catalog.dart';

class CanonicalZone {
  const CanonicalZone({required this.id, required this.name});

  final String id;
  final String name;

  GeographicScope get scope => GeographicScope(
        level: GeographyLevel.geopoliticalZone,
        country: 'Nigeria',
        zoneId: id,
        zoneName: name,
      );
}

class CanonicalState {
  const CanonicalState({
    required this.id,
    required this.name,
    required this.zoneId,
    required this.zoneName,
    this.isFederalCapitalTerritory = false,
  });

  final String id;
  final String name;
  final String zoneId;
  final String zoneName;
  final bool isFederalCapitalTerritory;

  GeographicScope get scope => GeographicScope(
        level: GeographyLevel.state,
        country: 'Nigeria',
        zoneId: zoneId,
        zoneName: zoneName,
        stateId: id,
        stateName: name,
      );
}

class CanonicalLga {
  const CanonicalLga({
    required this.id,
    required this.name,
    required this.stateId,
    required this.stateName,
    required this.zoneId,
    required this.zoneName,
  });

  final String id;
  final String name;
  final String stateId;
  final String stateName;
  final String zoneId;
  final String zoneName;

  GeographicScope get scope => GeographicScope(
        level: GeographyLevel.lga,
        country: 'Nigeria',
        zoneId: zoneId,
        zoneName: zoneName,
        stateId: stateId,
        stateName: stateName,
        lgaId: id,
        lgaName: name,
      );
}

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
  const GeographyRegistry({
    this.zones = const [],
    this.states = const [],
    required this.pollingUnits,
  });

  final List<CanonicalZone> zones;
  final List<CanonicalState> states;
  final List<CanonicalPollingUnit> pollingUnits;

  factory GeographyRegistry.prototypeSeed() => const GeographyRegistry(
        zones: [
          CanonicalZone(id: 'NC', name: 'North Central'),
          CanonicalZone(id: 'NE', name: 'North East'),
          CanonicalZone(id: 'NW', name: 'North West'),
          CanonicalZone(id: 'SE', name: 'South East'),
          CanonicalZone(id: 'SS', name: 'South South'),
          CanonicalZone(id: 'SW', name: 'South West'),
        ],
        states: [
          CanonicalState(id: 'BN', name: 'Benue', zoneId: 'NC', zoneName: 'North Central'),
          CanonicalState(id: 'FCT', name: 'Federal Capital Territory', zoneId: 'NC', zoneName: 'North Central', isFederalCapitalTerritory: true),
          CanonicalState(id: 'KO', name: 'Kogi', zoneId: 'NC', zoneName: 'North Central'),
          CanonicalState(id: 'KW', name: 'Kwara', zoneId: 'NC', zoneName: 'North Central'),
          CanonicalState(id: 'NA', name: 'Nasarawa', zoneId: 'NC', zoneName: 'North Central'),
          CanonicalState(id: 'NI', name: 'Niger', zoneId: 'NC', zoneName: 'North Central'),
          CanonicalState(id: 'PL', name: 'Plateau', zoneId: 'NC', zoneName: 'North Central'),
          CanonicalState(id: 'AD', name: 'Adamawa', zoneId: 'NE', zoneName: 'North East'),
          CanonicalState(id: 'BA', name: 'Bauchi', zoneId: 'NE', zoneName: 'North East'),
          CanonicalState(id: 'BO', name: 'Borno', zoneId: 'NE', zoneName: 'North East'),
          CanonicalState(id: 'GO', name: 'Gombe', zoneId: 'NE', zoneName: 'North East'),
          CanonicalState(id: 'TA', name: 'Taraba', zoneId: 'NE', zoneName: 'North East'),
          CanonicalState(id: 'YO', name: 'Yobe', zoneId: 'NE', zoneName: 'North East'),
          CanonicalState(id: 'JI', name: 'Jigawa', zoneId: 'NW', zoneName: 'North West'),
          CanonicalState(id: 'KD', name: 'Kaduna', zoneId: 'NW', zoneName: 'North West'),
          CanonicalState(id: 'KN', name: 'Kano', zoneId: 'NW', zoneName: 'North West'),
          CanonicalState(id: 'KT', name: 'Katsina', zoneId: 'NW', zoneName: 'North West'),
          CanonicalState(id: 'KE', name: 'Kebbi', zoneId: 'NW', zoneName: 'North West'),
          CanonicalState(id: 'SO', name: 'Sokoto', zoneId: 'NW', zoneName: 'North West'),
          CanonicalState(id: 'ZA', name: 'Zamfara', zoneId: 'NW', zoneName: 'North West'),
          CanonicalState(id: 'AB', name: 'Abia', zoneId: 'SE', zoneName: 'South East'),
          CanonicalState(id: 'AN', name: 'Anambra', zoneId: 'SE', zoneName: 'South East'),
          CanonicalState(id: 'EB', name: 'Ebonyi', zoneId: 'SE', zoneName: 'South East'),
          CanonicalState(id: 'EN', name: 'Enugu', zoneId: 'SE', zoneName: 'South East'),
          CanonicalState(id: 'IM', name: 'Imo', zoneId: 'SE', zoneName: 'South East'),
          CanonicalState(id: 'AK', name: 'Akwa Ibom', zoneId: 'SS', zoneName: 'South South'),
          CanonicalState(id: 'BY', name: 'Bayelsa', zoneId: 'SS', zoneName: 'South South'),
          CanonicalState(id: 'CR', name: 'Cross River', zoneId: 'SS', zoneName: 'South South'),
          CanonicalState(id: 'DE', name: 'Delta', zoneId: 'SS', zoneName: 'South South'),
          CanonicalState(id: 'ED', name: 'Edo', zoneId: 'SS', zoneName: 'South South'),
          CanonicalState(id: 'RI', name: 'Rivers', zoneId: 'SS', zoneName: 'South South'),
          CanonicalState(id: 'EK', name: 'Ekiti', zoneId: 'SW', zoneName: 'South West'),
          CanonicalState(id: 'LA', name: 'Lagos', zoneId: 'SW', zoneName: 'South West'),
          CanonicalState(id: 'OG', name: 'Ogun', zoneId: 'SW', zoneName: 'South West'),
          CanonicalState(id: 'ON', name: 'Ondo', zoneId: 'SW', zoneName: 'South West'),
          CanonicalState(id: 'OS', name: 'Osun', zoneId: 'SW', zoneName: 'South West'),
          CanonicalState(id: 'OY', name: 'Oyo', zoneId: 'SW', zoneName: 'South West'),
        ],
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

  CanonicalZone? zone(String id) {
    for (final item in zones) {
      if (item.id == id) return item;
    }
    return null;
  }

  CanonicalState? state(String id) {
    for (final item in states) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<CanonicalState> statesForZone(String zoneId) => states
      .where((item) => item.zoneId == zoneId)
      .toList(growable: false);

  List<CanonicalLga> get lgas => states
      .expand((item) => lgasForState(item.id))
      .toList(growable: false);

  int get nationalLgaCount => lgas.length;

  List<CanonicalLga> lgasForState(String stateId) {
    final stateItem = state(stateId);
    if (stateItem == null) return const [];
    final slugs = nigeriaLgaSlugsByStateId[stateId] ?? const <String>[];
    return slugs
        .map(
          (slug) => CanonicalLga(
            id: '$stateId-${slug.toUpperCase().replaceAll("'", '')}',
            name: nigeriaLgaDisplayName(slug),
            stateId: stateItem.id,
            stateName: stateItem.name,
            zoneId: stateItem.zoneId,
            zoneName: stateItem.zoneName,
          ),
        )
        .toList(growable: false);
  }

  CanonicalLga? lga(String id) {
    for (final item in lgas) {
      if (item.id == id) return item;
    }
    return null;
  }

  CanonicalPollingUnit? pollingUnit(String id) {
    for (final unit in pollingUnits) {
      if (unit.code == id || unit.scope.pollingUnitId == id) return unit;
    }
    return null;
  }

  List<CanonicalPollingUnit> pollingUnitsWithin(GeographicScope scope) =>
      pollingUnits
          .where((unit) => scopeContains(scope, unit.scope))
          .toList(growable: false);

  List<GeographicScope> childScopes(GeographicScope parent) {
    if (parent.level == GeographyLevel.country && zones.isNotEmpty) {
      return zones.map((item) => item.scope).toList(growable: false);
    }
    if (parent.level == GeographyLevel.geopoliticalZone && states.isNotEmpty) {
      return statesForZone(parent.zoneId ?? '')
          .map((item) => item.scope)
          .toList(growable: false);
    }
    if (parent.level == GeographyLevel.state) {
      final stateLgas = lgasForState(parent.stateId ?? '');
      if (stateLgas.isNotEmpty) {
        return stateLgas.map((item) => item.scope).toList(growable: false);
      }
    }

    final values = <String, GeographicScope>{};
    for (final unit in pollingUnitsWithin(parent)) {
      final child = directChild(parent.level, unit.scope);
      if (child != null) values[_key(child)] = child;
    }
    final result = values.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
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
        parent.senatorialDistrictId != child.senatorialDistrictId) {
      return false;
    }
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
        GeographyLevel.senatorialDistrict =>
          scope.senatorialDistrictId ?? scope.label,
        GeographyLevel.lga => scope.lgaId ?? scope.label,
        GeographyLevel.ward => scope.wardId ?? scope.label,
        GeographyLevel.pollingUnit => scope.pollingUnitId ?? scope.label,
      };
}
