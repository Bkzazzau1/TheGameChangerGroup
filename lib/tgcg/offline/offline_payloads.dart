import '../domain/models.dart';

String scopeStorageKey(GeographicScope scope) => [
      scope.country,
      scope.zoneId,
      scope.stateId,
      scope.senatorialDistrictId,
      scope.lgaId,
      scope.wardId,
      scope.pollingUnitId,
    ].whereType<String>().join('/');

Map<String, Object?> geographicScopeToJson(GeographicScope scope) => {
      'level': scope.level.name,
      'country': scope.country,
      'zoneId': scope.zoneId,
      'zoneName': scope.zoneName,
      'stateId': scope.stateId,
      'stateName': scope.stateName,
      'senatorialDistrictId': scope.senatorialDistrictId,
      'senatorialDistrictName': scope.senatorialDistrictName,
      'lgaId': scope.lgaId,
      'lgaName': scope.lgaName,
      'wardId': scope.wardId,
      'wardName': scope.wardName,
      'pollingUnitId': scope.pollingUnitId,
      'pollingUnitName': scope.pollingUnitName,
    };

Map<String, Object?> evidenceToJson(EvidenceAttachment evidence) => {
      'id': evidence.id,
      'type': evidence.type.name,
      'fileName': evidence.fileName,
      'createdAt': evidence.createdAt.toUtc().toIso8601String(),
      'uploaderId': evidence.uploaderId,
      'contentHash': evidence.contentHash,
      'mimeType': evidence.mimeType,
      'caption': evidence.caption,
      'latitude': evidence.latitude,
      'longitude': evidence.longitude,
      'origin': evidence.origin.name,
    };

Map<String, Object?> fieldIncidentToJson(FieldIncident incident) => {
      'id': incident.id,
      'title': incident.title,
      'category': incident.category,
      'severity': incident.severity.name,
      'status': incident.status.name,
      'scope': geographicScopeToJson(incident.scope),
      'reportedAt': incident.reportedAt.toUtc().toIso8601String(),
      'reporterId': incident.reporterId,
      'summary': incident.summary,
      'assignedTeam': incident.assignedTeam,
      'latitude': incident.latitude,
      'longitude': incident.longitude,
      'gps': incident.gps?.toJson(),
      'evidence': incident.evidence.map(evidenceToJson).toList(growable: false),
      'origin': incident.origin.name,
    };

Map<String, Object?> fieldReportToJson(FieldReport report) => {
      'id': report.id,
      'category': report.category,
      'summary': report.summary,
      'scope': geographicScopeToJson(report.scope),
      'reporterId': report.reporterId,
      'reportedAt': report.reportedAt.toUtc().toIso8601String(),
      'status': report.status.name,
      'incidentId': report.incidentId,
      'gps': report.gps?.toJson(),
      'evidence': report.evidence.map(evidenceToJson).toList(growable: false),
      'origin': report.origin.name,
    };

Map<String, Object?> resultSubmissionToJson(
  ElectionResultSubmission submission,
) => {
      'id': submission.id,
      'pollingUnitScope': geographicScopeToJson(submission.pollingUnitScope),
      'submittedBy': submission.submittedBy,
      'submittedAt': submission.submittedAt.toUtc().toIso8601String(),
      'status': submission.status.name,
      'source': submission.source.name,
      'partyVotes': submission.partyVotes,
      'totalVotesRecorded': submission.totalVotesRecorded,
      'accreditedVoters': submission.accreditedVoters,
      'rejectedVotes': submission.rejectedVotes,
      'registeredVoters': submission.registeredVoters,
      'gps': submission.gps?.toJson(),
      'electionCode': submission.electionCode,
      'resultForm': submission.resultForm == null
          ? null
          : evidenceToJson(submission.resultForm!),
      'validation': submission.validation == null
          ? null
          : {
              'arithmeticValid': submission.validation!.arithmeticValid,
              'duplicateSuspected': submission.validation!.duplicateSuspected,
              'pollingUnitMatched': submission.validation!.pollingUnitMatched,
              'agentScopeMatched': submission.validation!.agentScopeMatched,
              'ocrConfidence': submission.validation!.ocrConfidence,
              'ocrMatchedManualEntry':
                  submission.validation!.ocrMatchedManualEntry,
              'notes': submission.validation!.notes,
              'requiresHumanReview':
                  submission.validation!.requiresHumanReview,
            },
      'verifiedBy': submission.verifiedBy,
      'verifiedAt': submission.verifiedAt?.toUtc().toIso8601String(),
      'disputeReason': submission.disputeReason,
      'sourceReference': submission.sourceReference,
      'origin': submission.origin.name,
      'isOfficial': false,
    };
