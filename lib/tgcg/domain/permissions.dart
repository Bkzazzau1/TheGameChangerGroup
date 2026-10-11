import 'models.dart';

/// Who is acting, for the app's own checks of what to offer. The server
/// still decides every request; these checks never authorize anything.
abstract interface class TgcgActor {
  /// Whether the actor may use [capability] somewhere.
  bool can(TgcgCapability capability);

  /// The former fixed role, when the actor has one.
  TgcgRole? get legacyRole;
}

/// A server session: exactly what the server granted, from every appointment,
/// delegation or legacy role the account holds.
class TgcgServerActor implements TgcgActor {
  const TgcgServerActor(this.capabilities, {this.legacyRole});

  /// Server permission codes (the [TgcgCapability] names).
  final Set<String> capabilities;

  @override
  final TgcgRole? legacyRole;

  @override
  bool can(TgcgCapability capability) => capabilities.contains(capability.name);
}

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
  viewMeetingRoom,
  startMeeting,
  joinMeeting,
  viewEvidence,
  manageEvidence,
  viewAudit,
  exportReports,
  manageUsers,
  manageSystemSettings,
  // Members, roles and delegation (the server's codes of the same names).
  registerMembers,
  confirmAgentLocation,
  viewRoles,
  manageRoles,
  assignRoles,
  manageAssignments,
  delegateAuthority,
  viewMemberSensitiveData,
  verifyMemberIdentity,
  suspendMembers,
  reviewPollingUnitChanges,
  appointNationalAdministrator,
  approveAdministratorRemoval,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.joinMeeting,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.startMeeting,
      TgcgCapability.joinMeeting,
      TgcgCapability.viewEvidence,
      TgcgCapability.manageEvidence,
      TgcgCapability.viewAudit,
      TgcgCapability.exportReports,
    },
    TgcgRole.zonalCoordinator: {
      // As on the server: register members, pin units, see members' contacts.
      TgcgCapability.registerMembers,
      TgcgCapability.confirmAgentLocation,
      TgcgCapability.viewMemberSensitiveData,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.startMeeting,
      TgcgCapability.joinMeeting,
      TgcgCapability.viewEvidence,
      TgcgCapability.exportReports,
    },
    TgcgRole.stateCoordinator: {
      // As on the server: register members, pin units, see members' contacts.
      TgcgCapability.registerMembers,
      TgcgCapability.confirmAgentLocation,
      TgcgCapability.viewMemberSensitiveData,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.startMeeting,
      TgcgCapability.joinMeeting,
      TgcgCapability.viewEvidence,
      TgcgCapability.exportReports,
    },
    TgcgRole.lgaCoordinator: {
      // As on the server: register members, pin units, see members' contacts.
      TgcgCapability.registerMembers,
      TgcgCapability.confirmAgentLocation,
      TgcgCapability.viewMemberSensitiveData,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.startMeeting,
      TgcgCapability.joinMeeting,
      TgcgCapability.viewEvidence,
    },
    TgcgRole.wardCoordinator: {
      // As on the server: register members, pin units, see members' contacts.
      TgcgCapability.registerMembers,
      TgcgCapability.confirmAgentLocation,
      TgcgCapability.viewMemberSensitiveData,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.startMeeting,
      TgcgCapability.joinMeeting,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.joinMeeting,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.joinMeeting,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.startMeeting,
      TgcgCapability.joinMeeting,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.startMeeting,
      TgcgCapability.joinMeeting,
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
      TgcgCapability.viewMeetingRoom,
      TgcgCapability.joinMeeting,
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
    TgcgActor actor,
    GeographicScope userScope,
    TgcgCapability capability, {
    GeographicScope? targetScope,
  }) {
    if (!actor.can(capability)) return false;
    if (targetScope == null) return true;
    return scopeAllows(userScope, targetScope);
  }
}
