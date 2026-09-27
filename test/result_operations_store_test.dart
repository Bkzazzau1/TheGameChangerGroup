import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';
import 'package:tgcg_emcop/tgcg/results/result_operations_store.dart';

void main() {
  test('prototype review queue contains flagged submissions only', () {
    final store = ResultOperationsController.prototypeSeed();

    final review = store.reviewQueueForScope(GeographicScope.nigeria);

    expect(review.map((item) => item.id), containsAll(<String>['RES-0002', 'RES-0004']));
    expect(review.any((item) => item.id == 'RES-0001'), isFalse);
  });

  test('human verification removes a flagged record from review queue', () async {
    final store = ResultOperationsController.prototypeSeed();

    final verified = await store.verify(
      submissionId: 'RES-0002',
      verifierId: 'NATIONAL-REVIEWER',
      role: TgcgRole.nationalCollationOfficer,
      userScope: GeographicScope.nigeria,
    );

    expect(verified, isTrue);
    expect(
      store.reviewQueueForScope(GeographicScope.nigeria).any((item) => item.id == 'RES-0002'),
      isFalse,
    );
  });

  test('clean new polling-unit submission is not routed to human review', () async {
    final store = ResultOperationsController.prototypeSeed();
    const scope = GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'NE',
      zoneName: 'North East',
      stateId: 'BA',
      stateName: 'Bauchi',
      lgaId: 'BA-DEMO',
      lgaName: 'Demo LGA',
      wardId: 'BA-DEMO-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'BA-DEMO-W01-PU001',
      pollingUnitName: 'PU 001',
    );

    final submission = await store.submit(
      pollingUnitScope: scope,
      submittedBy: 'AG-BA-001',
      source: SubmissionSource.app,
      partyVotes: const {'P1': 100, 'P2': 80, 'P3': 20},
      totalVotesRecorded: 200,
      accreditedVoters: 210,
      rejectedVotes: 10,
      registeredVoters: 500,
      ocrPartyVotes: const {'P1': 100, 'P2': 80, 'P3': 20},
      ocrConfidence: .96,
    );

    expect(submission.validation?.requiresHumanReview, isFalse);
    expect(submission.status, RecordStatus.submitted);
  });

  test('second active submission for same polling unit is flagged duplicate', () async {
    final store = ResultOperationsController.prototypeSeed();
    const scope = GeographicScope(
      level: GeographyLevel.pollingUnit,
      country: 'Nigeria',
      zoneId: 'SE',
      zoneName: 'South East',
      stateId: 'EN',
      stateName: 'Enugu',
      lgaId: 'EN-DEMO',
      lgaName: 'Demo LGA',
      wardId: 'EN-DEMO-W01',
      wardName: 'Ward 01',
      pollingUnitId: 'EN-DEMO-W01-PU001',
      pollingUnitName: 'PU 001',
    );

    await store.submit(
      pollingUnitScope: scope,
      submittedBy: 'AG-EN-001',
      source: SubmissionSource.sms,
      partyVotes: const {'P1': 70, 'P2': 60},
      totalVotesRecorded: 130,
      accreditedVoters: 135,
      rejectedVotes: 5,
    );
    final duplicate = await store.submit(
      pollingUnitScope: scope,
      submittedBy: 'AG-EN-002',
      source: SubmissionSource.ussd,
      partyVotes: const {'P1': 70, 'P2': 60},
      totalVotesRecorded: 130,
      accreditedVoters: 135,
      rejectedVotes: 5,
    );

    expect(duplicate.validation?.duplicateSuspected, isTrue);
    expect(duplicate.status, RecordStatus.underReview);
  });
}
