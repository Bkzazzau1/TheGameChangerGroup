import 'models.dart';

abstract interface class MembershipRepository {
  Future<List<TgcgMember>> listMembers({
    RecordStatus? status,
    String? search,
  });

  Future<TgcgMember> createMember({
    required String fullName,
    required String phoneNumber,
    String? email,
  });

  Future<AccreditedAgent> accreditAgent({
    required String memberId,
    required String agentId,
    required TgcgRole role,
    required GeographicScope scope,
    String? registeredPhoneNumber,
    String? deviceId,
    String? simFingerprint,
  });

  Future<List<AccreditedAgent>> listAgents({
    GeographicScope? scope,
    TgcgRole? role,
    AccreditationStatus? status,
  });
}

abstract interface class IncidentRepository {
  Future<List<FieldIncident>> listIncidents({
    GeographicScope? scope,
    IncidentStatus? status,
    IncidentSeverity? minimumSeverity,
  });

  Future<FieldIncident> createIncident({
    required String title,
    required String category,
    required IncidentSeverity severity,
    required GeographicScope scope,
    required String reporterId,
    String? summary,
    double? latitude,
    double? longitude,
    List<EvidenceAttachment> evidence = const [],
  });

  Future<FieldIncident> acknowledge({
    required String incidentId,
    required String actorId,
  });

  Future<FieldIncident> assign({
    required String incidentId,
    required String team,
    required String actorId,
  });

  Future<FieldIncident> changeStatus({
    required String incidentId,
    required IncidentStatus status,
    required String actorId,
    String? reason,
  });
}

abstract interface class FieldReportRepository {
  Future<List<FieldReport>> listReports({
    GeographicScope? scope,
    RecordStatus? status,
  });

  Future<FieldReport> submitReport({
    required String category,
    required String summary,
    required GeographicScope scope,
    required String reporterId,
    String? incidentId,
    List<EvidenceAttachment> evidence = const [],
  });

  Future<FieldReport> reviewReport({
    required String reportId,
    required String reviewerId,
    required bool accepted,
    required String reason,
  });
}

abstract interface class ElectionResultRepository {
  Future<List<ElectionResultSubmission>> listSubmissions({
    GeographicScope? scope,
    RecordStatus? status,
    SubmissionSource? source,
  });

  Future<ElectionResultSubmission> submitResult({
    required GeographicScope pollingUnitScope,
    required String submittedBy,
    required SubmissionSource source,
    required Map<String, int> partyVotes,
    required int totalVotesRecorded,
    required int accreditedVoters,
    int? rejectedVotes,
    int? registeredVoters,
    EvidenceAttachment? resultForm,
    String? sourceReference,
  });

  Future<ElectionResultSubmission> attachValidation({
    required String submissionId,
    required ResultValidationSummary validation,
  });

  Future<ElectionResultSubmission> verifyResult({
    required String submissionId,
    required String verifierId,
  });

  Future<ElectionResultSubmission> disputeResult({
    required String submissionId,
    required String reviewerId,
    required String reason,
  });
}

abstract interface class CollationRepository {
  Future<CollationSnapshot> getSnapshot({
    required GeographicScope scope,
  });

  Future<List<CollationSnapshot>> listChildren({
    required GeographicScope parentScope,
  });

  Future<CollationSnapshot> rebuildVerifiedSnapshot({
    required GeographicScope scope,
    required String actorId,
  });
}

abstract interface class AuditRepository {
  Future<List<AuditEvent>> listEvents({
    String? actorId,
    String? entityType,
    String? entityId,
    GeographicScope? scope,
  });

  Future<void> record({
    required String actorId,
    required String action,
    required String entityType,
    required String entityId,
    String? detail,
    String? deviceId,
    GeographicScope? scope,
  });
}
