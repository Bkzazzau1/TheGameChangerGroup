import 'models.dart';

enum TgcgCapability {
  viewNationalDashboard,
  viewSituationRoom,
  viewGeography,
  manageMembership,
  accreditAgents,
  manageAgentAssignments,
  viewIncidents,
  createIncident,
  acknowledgeIncident,
  assignIncident,
  closeIncident,
  submitFieldReport,
  verifyFieldReport,
  submitElectionResult,
  verifyElectionResult,
  disputeElectionResult,
  viewCollation,
  manageCollation,
  viewCommunications,
  sendOperationalMessage,
  sendBroadcast,
  viewMediaIntelligence,
  viewDiscussionRoom,
  createDiscussionThread,
  postDiscussionReply,
  viewEvidence,
  manageEvidence,
  viewAudit,
  exportReports,
  manageUsers,
  manageSystemSettings,
}

class TgcgPermissionPolicy {
  const TgcgPermissionPolicy._();

  static const Map<TgcgRole, Set<TgcgCapability>> _roleCapabilities = {
    TgcgRole.nationalAdministrator: {
      ...TgcgCapability.values,
    },
    TgcgRole.nationalCollationOfficer: {
      TgcgCapability.viewNationalDashboard,
      TgcgCapability.viewSituationRoom,
      TgcgCapability.viewGeography,
      TgcgCapability.viewIncidents,
      TgcgCapability.verifyFieldReport,
      TgcgCapability.verifyElectionResult,
      TgcgCapability.disputeElectionResult,
      TgcgCapability.viewCollation,
      TgcgCapability.manageCollation,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.viewMediaIntelligence,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.createDiscussionThread,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewEvidence,
      TgcgCapability.viewAudit,
      TgcgCapability.exportReports,
    },
    TgcgRole.situationRoomDirector: {
      TgcgCapability.viewNationalDashboard,
      TgcgCapability.viewSituationRoom,
      TgcgCapability.viewGeography,
      TgcgCapability.viewIncidents,
      TgcgCapability.createIncident,
      TgcgCapability.acknowledgeIncident,
      TgcgCapability.assignIncident,
      TgcgCapability.closeIncident,
      TgcgCapability.verifyFieldReport,
      TgcgCapability.verifyElectionResult,
      TgcgCapability.disputeElectionResult,
      TgcgCapability.viewCollation,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.sendBroadcast,
      TgcgCapability.viewMediaIntelligence,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.createDiscussionThread,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewEvidence,
      TgcgCapability.manageEvidence,
      TgcgCapability.viewAudit,
      TgcgCapability.exportReports,
    },
    TgcgRole.zonalCoordinator: {
      TgcgCapability.viewSituationRoom,
      TgcgCapability.viewGeography,
      TgcgCapability.viewIncidents,
      TgcgCapability.createIncident,
      TgcgCapability.acknowledgeIncident,
      TgcgCapability.assignIncident,
      TgcgCapability.submitFieldReport,
      TgcgCapability.verifyFieldReport,
      TgcgCapability.verifyElectionResult,
      TgcgCapability.viewCollation,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.sendBroadcast,
      TgcgCapability.viewMediaIntelligence,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.createDiscussionThread,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewEvidence,
      TgcgCapability.exportReports,
    },
    TgcgRole.stateCoordinator: {
      TgcgCapability.viewSituationRoom,
      TgcgCapability.viewGeography,
      TgcgCapability.accreditAgents,
      TgcgCapability.manageAgentAssignments,
      TgcgCapability.viewIncidents,
      TgcgCapability.createIncident,
      TgcgCapability.acknowledgeIncident,
      TgcgCapability.assignIncident,
      TgcgCapability.submitFieldReport,
      TgcgCapability.verifyFieldReport,
      TgcgCapability.verifyElectionResult,
      TgcgCapability.disputeElectionResult,
      TgcgCapability.viewCollation,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.sendBroadcast,
      TgcgCapability.viewMediaIntelligence,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.createDiscussionThread,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewEvidence,
      TgcgCapability.exportReports,
    },
    TgcgRole.lgaCoordinator: {
      TgcgCapability.viewSituationRoom,
      TgcgCapability.viewGeography,
      TgcgCapability.manageAgentAssignments,
      TgcgCapability.viewIncidents,
      TgcgCapability.createIncident,
      TgcgCapability.acknowledgeIncident,
      TgcgCapability.assignIncident,
      TgcgCapability.submitFieldReport,
      TgcgCapability.verifyFieldReport,
      TgcgCapability.submitElectionResult,
      TgcgCapability.verifyElectionResult,
      TgcgCapability.viewCollation,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.viewMediaIntelligence,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.createDiscussionThread,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewEvidence,
    },
    TgcgRole.wardCoordinator: {
      TgcgCapability.viewSituationRoom,
      TgcgCapability.viewGeography,
      TgcgCapability.viewIncidents,
      TgcgCapability.createIncident,
      TgcgCapability.acknowledgeIncident,
      TgcgCapability.submitFieldReport,
      TgcgCapability.submitElectionResult,
      TgcgCapability.viewCollation,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.createDiscussionThread,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewEvidence,
    },
    TgcgRole.pollingUnitAgent: {
      TgcgCapability.viewGeography,
      TgcgCapability.createIncident,
      TgcgCapability.submitFieldReport,
      TgcgCapability.submitElectionResult,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewEvidence,
    },
    TgcgRole.observer: {
      TgcgCapability.viewGeography,
      TgcgCapability.createIncident,
      TgcgCapability.submitFieldReport,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewEvidence,
    },
    TgcgRole.legalOfficer: {
      TgcgCapability.viewSituationRoom,
      TgcgCapability.viewGeography,
      TgcgCapability.viewIncidents,
      TgcgCapability.createIncident,
      TgcgCapability.acknowledgeIncident,
      TgcgCapability.disputeElectionResult,
      TgcgCapability.viewCollation,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.viewMediaIntelligence,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.createDiscussionThread,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewEvidence,
      TgcgCapability.manageEvidence,
      TgcgCapability.viewAudit,
      TgcgCapability.exportReports,
    },
    TgcgRole.technicalSupport: {
      TgcgCapability.viewSituationRoom,
      TgcgCapability.viewGeography,
      TgcgCapability.viewIncidents,
      TgcgCapability.viewCommunications,
      TgcgCapability.sendOperationalMessage,
      TgcgCapability.viewMediaIntelligence,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.createDiscussionThread,
      TgcgCapability.postDiscussionReply,
      TgcgCapability.viewAudit,
      TgcgCapability.manageUsers,
      TgcgCapability.manageSystemSettings,
    },
    TgcgRole.readOnlyExecutive: {
      TgcgCapability.viewNationalDashboard,
      TgcgCapability.viewSituationRoom,
      TgcgCapability.viewGeography,
      TgcgCapability.viewIncidents,
      TgcgCapability.viewCollation,
      TgcgCapability.viewMediaIntelligence,
      TgcgCapability.viewDiscussionRoom,
      TgcgCapability.viewEvidence,
      TgcgCapability.viewAudit,
      TgcgCapability.exportReports,
    },
  };

  static bool allows(TgcgRole role, TgcgCapability capability) =>
      _roleCapabilities[role]?.contains(capability) ?? false;

  static Set<TgcgCapability> capabilitiesFor(TgcgRole role) =>
      Set.unmodifiable(_roleCapabilities[role] ?? const {});

  static bool scopeAllows(GeographicScope user, GeographicScope target) {
    if (user.country != target.country) return false;
    if (user.level == GeographyLevel.country) return true;

    if (user.zoneId != null && user.zoneId != target.zoneId) return false;
    if (user.level == GeographyLevel.geopoliticalZone) return true;

    if (user.stateId != null && user.stateId != target.stateId) return false;
    if (user.level == GeographyLevel.state) return true;

    if (user.senatorialDistrictId != null &&
        user.senatorialDistrictId != target.senatorialDistrictId) {
      return false;
    }
    if (user.level == GeographyLevel.senatorialDistrict) return true;

    if (user.lgaId != null && user.lgaId != target.lgaId) return false;
    if (user.level == GeographyLevel.lga) return true;

    if (user.wardId != null && user.wardId != target.wardId) return false;
    if (user.level == GeographyLevel.ward) return true;

    return user.pollingUnitId == target.pollingUnitId;
  }

  static bool may(
    TgcgRole role,
    GeographicScope userScope,
    TgcgCapability capability, {
    GeographicScope? targetScope,
  }) {
    if (!allows(role, capability)) return false;
    if (targetScope == null) return true;
    return scopeAllows(userScope, targetScope);
  }
}
