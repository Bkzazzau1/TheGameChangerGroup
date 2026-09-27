import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/collation/collation_engine.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';

void main() {
  const pu1 = GeographicScope(
    level: GeographyLevel.pollingUnit,
    country: 'Nigeria',
    zoneId: 'NW',
    zoneName: 'North West',
    stateId: 'KD',
    stateName: 'Kaduna',
    senatorialDistrictId: 'KD-SD-01',
    senatorialDistrictName: 'District 01',
    lgaId: 'KD-LGA-01',
    lgaName: 'LGA 01',
    wardId: 'KD-W01',
    wardName: 'Ward 01',
    pollingUnitId: 'PU-001',
    pollingUnitName: 'PU 001',
  );
  const pu2 = GeographicScope(
    level: GeographyLevel.pollingUnit,
    country: 'Nigeria',
    zoneId: 'NW',
    zoneName: 'North West',
    stateId: 'KD',
    stateName: 'Kaduna',
    senatorialDistrictId: 'KD-SD-01',
    senatorialDistrictName: 'District 01',
    lgaId: 'KD-LGA-01',
    lgaName: 'LGA 01',
    wardId: 'KD-W01',
    wardName: 'Ward 01',
    pollingUnitId: 'PU-002',
    pollingUnitName: 'PU 002',
  );

  const engine = CollationEngine(
    expectedPollingUnits: [
      ExpectedPollingUnit(id: 'PU-001', name: 'PU 001', scope: pu1),
      ExpectedPollingUnit(id: 'PU-002', name: 'PU 002', scope: pu2),
    ],
  );

  ElectionResultSubmission result({
    required String id,
    required GeographicScope scope,
    required RecordStatus status,
    Map<String, int> votes = const {'P1': 10, 'P2': 7},
  }) => ElectionResultSubmission(
        id: id,
        pollingUnitScope: scope,
        submittedBy: 'AGENT-1',
        submittedAt: DateTime.utc(2026, 9, 27),
        status: status,
        source: SubmissionSource.app,
        partyVotes: votes,
        totalVotesRecorded: votes.values.fold(0, (a, b) => a + b),
        accreditedVoters: 20,
      );

  test('only verified polling-unit submissions are included', () {
    final summary = engine.summarize(
      GeographicScope.nigeria,
      [
        result(id: 'R1', scope: pu1, status: RecordStatus.verified),
        result(id: 'R2', scope: pu2, status: RecordStatus.submitted),
      ],
    );

    expect(summary.verifiedPollingUnitCount, 1);
    expect(summary.partyVotes, {'P1': 10, 'P2': 7});
    expect(summary.includedSubmissionIds, ['R1']);
    expect(summary.missingPollingUnitIds, ['PU-002']);
    expect(summary.excludedSubmissionIds, ['R2']);
    expect(summary.completionPercent, .5);
  });

  test('two verified records for one polling unit create a conflict and count neither', () {
    final summary = engine.summarize(
      GeographicScope.nigeria,
      [
        result(id: 'R1', scope: pu1, status: RecordStatus.verified),
        result(
          id: 'R2',
          scope: pu1,
          status: RecordStatus.verified,
          votes: const {'P1': 9, 'P2': 8},
        ),
      ],
    );

    expect(summary.verifiedPollingUnitCount, 0);
    expect(summary.partyVotes, isEmpty);
    expect(summary.conflictingPollingUnitIds, ['PU-001']);
    expect(summary.missingPollingUnitIds, ['PU-002']);
    expect(summary.excludedSubmissionIds, ['R1', 'R2']);
  });

  test('disputed result remains excluded from collation', () {
    final summary = engine.summarize(
      GeographicScope.nigeria,
      [result(id: 'R1', scope: pu1, status: RecordStatus.disputed)],
    );

    expect(summary.verifiedPollingUnitCount, 0);
    expect(summary.includedSubmissionIds, isEmpty);
    expect(summary.excludedSubmissionIds, ['R1']);
  });

  test('child hierarchy includes senator district between state and LGA', () {
    const state = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
    );

    final children = engine.childScopes(state);

    expect(children, hasLength(1));
    expect(children.single.level, GeographyLevel.senatorialDistrict);
    expect(children.single.senatorialDistrictId, 'KD-SD-01');
  });
}
