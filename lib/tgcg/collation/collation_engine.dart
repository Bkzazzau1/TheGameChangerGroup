import '../domain/models.dart';

class ExpectedPollingUnit {
  const ExpectedPollingUnit({
    required this.id,
    required this.name,
    required this.scope,
  });

  final String id;
  final String name;
  final GeographicScope scope;
}

class CollationSummary {
  const CollationSummary({
    required this.scope,
    required this.expectedPollingUnitCount,
    required this.verifiedPollingUnitCount,
    required this.partyVotes,
    required this.includedSubmissionIds,
    required this.missingPollingUnitIds,
    required this.conflictingPollingUnitIds,
    required this.excludedSubmissionIds,
  });

  final GeographicScope scope;
  final int expectedPollingUnitCount;
  final int verifiedPollingUnitCount;
  final Map<String, int> partyVotes;
  final List<String> includedSubmissionIds;
  final List<String> missingPollingUnitIds;
  final List<String> conflictingPollingUnitIds;
  final List<String> excludedSubmissionIds;

  double get completionPercent => expectedPollingUnitCount == 0
      ? 0
      : verifiedPollingUnitCount / expectedPollingUnitCount;

  bool get complete =>
      expectedPollingUnitCount > 0 &&
      verifiedPollingUnitCount == expectedPollingUnitCount &&
      conflictingPollingUnitIds.isEmpty;
}

class CollationEngine {
  const CollationEngine({required this.expectedPollingUnits});

  final List<ExpectedPollingUnit> expectedPollingUnits;

  factory CollationEngine.prototypeSeed() => CollationEngine(
        expectedPollingUnits: const [
          ExpectedPollingUnit(
            id: 'KD-KN-W01-PU001',
            name: 'PU 001',
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
          ExpectedPollingUnit(
            id: 'KD-KN-W01-PU002',
            name: 'PU 002',
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
          ExpectedPollingUnit(
            id: 'BN-MK-W01-PU004',
            name: 'PU 004',
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
          ExpectedPollingUnit(
            id: 'BN-MK-W01-PU005',
            name: 'PU 005',
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
          ExpectedPollingUnit(
            id: 'LA-IK-W03-PU012',
            name: 'PU 012',
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
          ExpectedPollingUnit(
            id: 'LA-IK-W03-PU013',
            name: 'PU 013',
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

  CollationSummary summarize(
    GeographicScope scope,
    List<ElectionResultSubmission> submissions,
  ) {
    final expected = expectedPollingUnits
        .where((unit) => _within(scope, unit.scope))
        .toList(growable: false);
    final expectedIds = expected.map((unit) => unit.id).toSet();

    final inScope = submissions
        .where((submission) => _submissionWithin(scope, submission))
        .toList(growable: false);
    final verified = inScope
        .where((submission) => submission.status == RecordStatus.verified)
        .toList(growable: false);

    final verifiedByPollingUnit = <String, List<ElectionResultSubmission>>{};
    for (final submission in verified) {
      final puId = submission.pollingUnitScope.pollingUnitId;
      if (puId == null) continue;
      verifiedByPollingUnit.putIfAbsent(puId, () => []).add(submission);
    }

    final conflicts = verifiedByPollingUnit.entries
        .where((entry) => entry.value.length > 1)
        .map((entry) => entry.key)
        .toList(growable: false)
      ..sort();

    final included = <ElectionResultSubmission>[];
    for (final entry in verifiedByPollingUnit.entries) {
      if (!expectedIds.contains(entry.key)) continue;
      if (entry.value.length != 1) continue;
      included.add(entry.value.single);
    }

    final totals = <String, int>{};
    for (final submission in included) {
      for (final entry in submission.partyVotes.entries) {
        totals.update(entry.key, (value) => value + entry.value,
            ifAbsent: () => entry.value);
      }
    }

    final includedPuIds = included
        .map((submission) => submission.pollingUnitScope.pollingUnitId)
        .whereType<String>()
        .toSet();
    final missing = expectedIds
        .where((id) => !includedPuIds.contains(id) && !conflicts.contains(id))
        .toList(growable: false)
      ..sort();

    final includedIds = included.map((submission) => submission.id).toList()
      ..sort();
    final excludedIds = inScope
        .where((submission) => !includedIds.contains(submission.id))
        .map((submission) => submission.id)
        .toList(growable: false)
      ..sort();

    return CollationSummary(
      scope: scope,
      expectedPollingUnitCount: expected.length,
      verifiedPollingUnitCount: included.length,
      partyVotes: Map.unmodifiable(totals),
      includedSubmissionIds: List.unmodifiable(includedIds),
      missingPollingUnitIds: List.unmodifiable(missing),
      conflictingPollingUnitIds: List.unmodifiable(conflicts),
      excludedSubmissionIds: List.unmodifiable(excludedIds),
    );
  }

  List<GeographicScope> childScopes(GeographicScope scope) {
    final children = <String, GeographicScope>{};
    for (final unit in expectedPollingUnits.where((u) => _within(scope, u.scope))) {
      final child = _directChild(scope.level, unit.scope);
      if (child == null) continue;
      children[_scopeKey(child)] = child;
    }
    final result = children.values.toList()
      ..sort((a, b) => a.label.compareTo(b.label));
    return result;
  }

  ExpectedPollingUnit? expectedPollingUnit(String id) {
    for (final unit in expectedPollingUnits) {
      if (unit.id == id) return unit;
    }
    return null;
  }

  bool _submissionWithin(
    GeographicScope parent,
    ElectionResultSubmission submission,
  ) {
    final pollingUnitId = submission.pollingUnitScope.pollingUnitId;
    if (pollingUnitId != null) {
      final canonical = expectedPollingUnit(pollingUnitId);
      if (canonical != null) return _within(parent, canonical.scope);
    }
    return _within(parent, submission.pollingUnitScope);
  }

  GeographicScope? _directChild(
    GeographyLevel parentLevel,
    GeographicScope pollingUnit,
  ) => switch (parentLevel) {
        GeographyLevel.country => GeographicScope(
            level: GeographyLevel.geopoliticalZone,
            country: pollingUnit.country,
            zoneId: pollingUnit.zoneId,
            zoneName: pollingUnit.zoneName,
          ),
        GeographyLevel.geopoliticalZone => GeographicScope(
            level: GeographyLevel.state,
            country: pollingUnit.country,
            zoneId: pollingUnit.zoneId,
            zoneName: pollingUnit.zoneName,
            stateId: pollingUnit.stateId,
            stateName: pollingUnit.stateName,
          ),
        GeographyLevel.state => GeographicScope(
            level: GeographyLevel.senatorialDistrict,
            country: pollingUnit.country,
            zoneId: pollingUnit.zoneId,
            zoneName: pollingUnit.zoneName,
            stateId: pollingUnit.stateId,
            stateName: pollingUnit.stateName,
            senatorialDistrictId: pollingUnit.senatorialDistrictId,
            senatorialDistrictName: pollingUnit.senatorialDistrictName,
          ),
        GeographyLevel.senatorialDistrict => GeographicScope(
            level: GeographyLevel.lga,
            country: pollingUnit.country,
            zoneId: pollingUnit.zoneId,
            zoneName: pollingUnit.zoneName,
            stateId: pollingUnit.stateId,
            stateName: pollingUnit.stateName,
            senatorialDistrictId: pollingUnit.senatorialDistrictId,
            senatorialDistrictName: pollingUnit.senatorialDistrictName,
            lgaId: pollingUnit.lgaId,
            lgaName: pollingUnit.lgaName,
          ),
        GeographyLevel.lga => GeographicScope(
            level: GeographyLevel.ward,
            country: pollingUnit.country,
            zoneId: pollingUnit.zoneId,
            zoneName: pollingUnit.zoneName,
            stateId: pollingUnit.stateId,
            stateName: pollingUnit.stateName,
            senatorialDistrictId: pollingUnit.senatorialDistrictId,
            senatorialDistrictName: pollingUnit.senatorialDistrictName,
            lgaId: pollingUnit.lgaId,
            lgaName: pollingUnit.lgaName,
            wardId: pollingUnit.wardId,
            wardName: pollingUnit.wardName,
          ),
        GeographyLevel.ward => pollingUnit,
        GeographyLevel.pollingUnit => null,
      };

  static String _scopeKey(GeographicScope scope) => switch (scope.level) {
        GeographyLevel.country => scope.country,
        GeographyLevel.geopoliticalZone => scope.zoneId ?? scope.label,
        GeographyLevel.state => scope.stateId ?? scope.label,
        GeographyLevel.senatorialDistrict =>
          scope.senatorialDistrictId ?? scope.label,
        GeographyLevel.lga => scope.lgaId ?? scope.label,
        GeographyLevel.ward => scope.wardId ?? scope.label,
        GeographyLevel.pollingUnit => scope.pollingUnitId ?? scope.label,
      };

  static bool _within(GeographicScope parent, GeographicScope child) {
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
}
