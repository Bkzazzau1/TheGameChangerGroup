import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/collation/collation_engine.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';

void main() {
  test('canonical PU registry supplies missing parent geography during drill-down', () {
    final engine = CollationEngine.prototypeSeed();
    const state = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
    );
    final district = engine.childScopes(state).single;

    const legacySubmissionScope = GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
      lgaId: 'KD-KADUNA-NORTH',
      lgaName: 'Kaduna North',
      wardId: 'KD-KN-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'KD-KN-W01-PU001',
      pollingUnitName: 'PU 001',
    );

    final submission = ElectionResultSubmission(
      id: 'R-LEGACY',
      pollingUnitScope: legacySubmissionScope,
      submittedBy: 'AGENT-1',
      submittedAt: DateTime.utc(2026, 9, 27),
      status: RecordStatus.verified,
      source: SubmissionSource.app,
      partyVotes: const {'P1': 12, 'P2': 8},
      totalVotesRecorded: 20,
      accreditedVoters: 22,
    );

    final summary = engine.summarize(district, [submission]);

    expect(summary.verifiedPollingUnitCount, 1);
    expect(summary.includedSubmissionIds, ['R-LEGACY']);
    expect(summary.partyVotes, {'P1': 12, 'P2': 8});
  });
}
