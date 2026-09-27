library;

enum GeographyLevel {
  country,
  geopoliticalZone,
  state,
  senatorialDistrict,
  lga,
  ward,
  pollingUnit,
}

enum TgcgRole {
  nationalAdministrator,
  nationalCollationOfficer,
  situationRoomDirector,
  zonalCoordinator,
  stateCoordinator,
  lgaCoordinator,
  wardCoordinator,
  pollingUnitAgent,
  observer,
  legalOfficer,
  technicalSupport,
  readOnlyExecutive,
}

enum RecordStatus {
  draft,
  submitted,
  underReview,
  verified,
  disputed,
  rejected,
  archived,
}

enum RecordOrigin {
  localEntry,
  imported,
  systemDerived,
  sms,
  ussd,
  manualOverride,
}

enum SubmissionSource { app, sms, ussd, manual }

enum IncidentSeverity { info, low, medium, high, critical }

enum IncidentStatus {
  reported,
  acknowledged,
  assigned,
  investigating,
  escalated,
  resolved,
  closed,
}

enum AccreditationStatus {
  pending,
  approved,
  suspended,
  revoked,
}

enum EvidenceType {
  photo,
  video,
  audio,
  document,
  resultForm,
  location,
}

enum VerificationState {
  unverified,
  investigating,
  verifiedTrue,
  verifiedFalse,
  misleading,
  insufficientEvidence,
}

class GeographicScope {
  const GeographicScope({
    required this.level,
    required this.country,
    this.zoneId,
    this.zoneName,
    this.stateId,
    this.stateName,
    this.senatorialDistrictId,
    this.senatorialDistrictName,
    this.lgaId,
    this.lgaName,
    this.wardId,
    this.wardName,
    this.pollingUnitId,
    this.pollingUnitName,
  });

  final GeographyLevel level;
  final String country;
  final String? zoneId;
  final String? zoneName;
  final String? stateId;
  final String? stateName;
  final String? senatorialDistrictId;
  final String? senatorialDistrictName;
  final String? lgaId;
  final String? lgaName;
  final String? wardId;
  final String? wardName;
  final String? pollingUnitId;
  final String? pollingUnitName;

  static const nigeria = GeographicScope(
    level: GeographyLevel.country,
    country: 'Nigeria',
  );

  String get label => switch (level) {
        GeographyLevel.country => country,
        GeographyLevel.geopoliticalZone => '$zoneName, $country',
        GeographyLevel.state => '$stateName State',
        GeographyLevel.senatorialDistrict =>
          '$senatorialDistrictName, $stateName State',
        GeographyLevel.lga => '$lgaName LGA, $stateName State',
        GeographyLevel.ward => '$wardName Ward, $lgaName LGA',
        GeographyLevel.pollingUnit =>
          '$pollingUnitName • $wardName • $lgaName',
      };
}

class TgcgMember {
  const TgcgMember({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    required this.createdAt,
    required this.status,
    this.email,
    this.membershipNumber,
    this.origin = RecordOrigin.localEntry,
  });

  final String id;
  final String fullName;
  final String phoneNumber;
  final String? email;
  final String? membershipNumber;
  final DateTime createdAt;
  final RecordStatus status;
  final RecordOrigin origin;
}

class AccreditedAgent {
  const AccreditedAgent({
    required this.id,
    required this.memberId,
    required this.agentId,
    required this.role,
    required this.scope,
    required this.status,
    required this.createdAt,
    this.registeredPhoneNumber,
    this.deviceId,
    this.simFingerprint,
    this.biometricEnrolled = false,
    this.trainingCompleted = false,
    this.origin = RecordOrigin.localEntry,
  });

  final String id;
  final String memberId;
  final String agentId;
  final TgcgRole role;
  final GeographicScope scope;
  final AccreditationStatus status;
  final DateTime createdAt;
  final String? registeredPhoneNumber;
  final String? deviceId;
  final String? simFingerprint;
  final bool biometricEnrolled;
  final bool trainingCompleted;
  final RecordOrigin origin;
}

class EvidenceAttachment {
  const EvidenceAttachment({
    required this.id,
    required this.type,
    required this.fileName,
    required this.createdAt,
    required this.uploaderId,
    this.contentHash,
    this.mimeType,
    this.caption,
    this.latitude,
    this.longitude,
    this.origin = RecordOrigin.localEntry,
  });

  final String id;
  final EvidenceType type;
  final String fileName;
  final DateTime createdAt;
  final String uploaderId;
  final String? contentHash;
  final String? mimeType;
  final String? caption;
  final double? latitude;
  final double? longitude;
  final RecordOrigin origin;
}

class FieldIncident {
  const FieldIncident({
    required this.id,
    required this.title,
    required this.category,
    required this.severity,
    required this.status,
    required this.scope,
    required this.reportedAt,
    required this.reporterId,
    this.summary,
    this.assignedTeam,
    this.latitude,
    this.longitude,
    this.evidence = const [],
    this.origin = RecordOrigin.localEntry,
  });

  final String id;
  final String title;
  final String category;
  final IncidentSeverity severity;
  final IncidentStatus status;
  final GeographicScope scope;
  final DateTime reportedAt;
  final String reporterId;
  final String? summary;
  final String? assignedTeam;
  final double? latitude;
  final double? longitude;
  final List<EvidenceAttachment> evidence;
  final RecordOrigin origin;
}

class FieldReport {
  const FieldReport({
    required this.id,
    required this.category,
    required this.summary,
    required this.scope,
    required this.reporterId,
    required this.reportedAt,
    required this.status,
    this.incidentId,
    this.evidence = const [],
    this.origin = RecordOrigin.localEntry,
  });

  final String id;
  final String category;
  final String summary;
  final GeographicScope scope;
  final String reporterId;
  final DateTime reportedAt;
  final RecordStatus status;
  final String? incidentId;
  final List<EvidenceAttachment> evidence;
  final RecordOrigin origin;
}

class ResultValidationSummary {
  const ResultValidationSummary({
    required this.arithmeticValid,
    required this.duplicateSuspected,
    required this.pollingUnitMatched,
    required this.agentScopeMatched,
    this.ocrConfidence,
    this.ocrMatchedManualEntry,
    this.notes = const [],
  });

  final bool arithmeticValid;
  final bool duplicateSuspected;
  final bool pollingUnitMatched;
  final bool agentScopeMatched;
  final double? ocrConfidence;
  final bool? ocrMatchedManualEntry;
  final List<String> notes;

  bool get requiresHumanReview =>
      !arithmeticValid ||
      duplicateSuspected ||
      !pollingUnitMatched ||
      !agentScopeMatched ||
      ocrMatchedManualEntry == false;
}

class ElectionResultSubmission {
  const ElectionResultSubmission({
    required this.id,
    required this.pollingUnitScope,
    required this.submittedBy,
    required this.submittedAt,
    required this.status,
    required this.source,
    required this.partyVotes,
    required this.totalVotesRecorded,
    required this.accreditedVoters,
    this.rejectedVotes,
    this.registeredVoters,
    this.resultForm,
    this.validation,
    this.verifiedBy,
    this.verifiedAt,
    this.disputeReason,
    this.sourceReference,
    this.origin = RecordOrigin.localEntry,
  });

  final String id;
  final GeographicScope pollingUnitScope;
  final String submittedBy;
  final DateTime submittedAt;
  final RecordStatus status;
  final SubmissionSource source;
  final Map<String, int> partyVotes;
  final int totalVotesRecorded;
  final int accreditedVoters;
  final int? rejectedVotes;
  final int? registeredVoters;
  final EvidenceAttachment? resultForm;
  final ResultValidationSummary? validation;
  final String? verifiedBy;
  final DateTime? verifiedAt;
  final String? disputeReason;
  final String? sourceReference;
  final RecordOrigin origin;

  int get calculatedPartyVotes =>
      partyVotes.values.fold<int>(0, (total, votes) => total + votes);

  bool get arithmeticMatches => calculatedPartyVotes == totalVotesRecorded;

  bool get isOfficial => false;
}

class CollationSnapshot {
  const CollationSnapshot({
    required this.id,
    required this.scope,
    required this.generatedAt,
    required this.verifiedSubmissionCount,
    required this.expectedPollingUnitCount,
    required this.partyVotes,
    this.disputedSubmissionCount = 0,
  });

  final String id;
  final GeographicScope scope;
  final DateTime generatedAt;
  final int verifiedSubmissionCount;
  final int expectedPollingUnitCount;
  final int disputedSubmissionCount;
  final Map<String, int> partyVotes;

  double get completionPercent => expectedPollingUnitCount == 0
      ? 0
      : (verifiedSubmissionCount / expectedPollingUnitCount) * 100;
}

class AuditEvent {
  const AuditEvent({
    required this.id,
    required this.actorId,
    required this.action,
    required this.entityType,
    required this.entityId,
    required this.timestamp,
    this.detail,
    this.deviceId,
    this.scope,
  });

  final String id;
  final String actorId;
  final String action;
  final String entityType;
  final String entityId;
  final DateTime timestamp;
  final String? detail;
  final String? deviceId;
  final GeographicScope? scope;
}
