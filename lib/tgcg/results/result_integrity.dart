import '../domain/models.dart';

class ResultIntegrityPolicy {
  const ResultIntegrityPolicy._();

  static ResultValidationSummary validate(
    ElectionResultSubmission submission, {
    bool pollingUnitMatched = true,
    bool agentScopeMatched = true,
    bool duplicateSuspected = false,
    Map<String, int>? ocrPartyVotes,
    double? ocrConfidence,
  }) {
    final notes = <String>[];

    var arithmeticValid = submission.arithmeticMatches;
    if (!submission.arithmeticMatches) {
      notes.add(
        'Party vote sum (${submission.calculatedPartyVotes}) does not match '
        'the recorded total (${submission.totalVotesRecorded}).',
      );
    }

    final rejectedVotes = submission.rejectedVotes ?? 0;
    final ballotsAccountedFor = submission.totalVotesRecorded + rejectedVotes;
    if (ballotsAccountedFor > submission.accreditedVoters) {
      arithmeticValid = false;
      notes.add(
        'Valid plus rejected votes ($ballotsAccountedFor) exceed accredited '
        'voters (${submission.accreditedVoters}).',
      );
    }

    final registeredVoters = submission.registeredVoters;
    if (registeredVoters != null &&
        submission.accreditedVoters > registeredVoters) {
      arithmeticValid = false;
      notes.add(
        'Accredited voters (${submission.accreditedVoters}) exceed registered '
        'voters ($registeredVoters).',
      );
    }

    if (!pollingUnitMatched) {
      notes.add('Submitted polling-unit identity did not match master data.');
    }
    if (!agentScopeMatched) {
      notes.add('Submitting agent is not assigned to the polling-unit scope.');
    }
    if (duplicateSuspected) {
      notes.add('A possible duplicate or conflicting submission was detected.');
    }

    bool? ocrMatchedManualEntry;
    if (ocrPartyVotes != null) {
      ocrMatchedManualEntry = _mapsMatch(
        submission.partyVotes,
        ocrPartyVotes,
      );
      if (!ocrMatchedManualEntry) {
        notes.add(
          'OCR-extracted party figures differ from the submitted figures; '
          'human verification is required.',
        );
      }
    }

    return ResultValidationSummary(
      arithmeticValid: arithmeticValid,
      duplicateSuspected: duplicateSuspected,
      pollingUnitMatched: pollingUnitMatched,
      agentScopeMatched: agentScopeMatched,
      ocrConfidence: ocrConfidence,
      ocrMatchedManualEntry: ocrMatchedManualEntry,
      notes: List.unmodifiable(notes),
    );
  }

  static bool _mapsMatch(Map<String, int> left, Map<String, int> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}
