import 'package:flutter/material.dart';

import 'domain/models.dart';
import 'domain/permissions.dart';

export 'domain/models.dart';

enum TgcgModule {
  overview,
  accreditation,
  membershipNetwork,
  roleAssignment,
  geography,
  liveOperations,
  aiVerification,
  aiAnalytics,
  alertCenter,
  fieldMonitoring,
  evidenceCapture,
  situationRoom,
  securityResponse,
  resultCapture,
  collation,
  mediaIntelligence,
  communications,
  discussionRoom,
  meetingRoom,
  systemMonitoring,
  reports,
  governance,
}

class TgcgSessionController extends ChangeNotifier {
  TgcgRole? _role;
  String _operatorName = '';
  String _accessId = '';
  GeographicScope _scope = GeographicScope.nigeria;

  TgcgRole? get role => _role;
  String get operatorName => _operatorName;
  String get accessId => _accessId;
  GeographicScope get scope => _scope;
  bool get isAuthenticated => _role != null;

  void signIn({
    required TgcgRole role,
    required String operatorName,
    required String accessId,
    GeographicScope scope = GeographicScope.nigeria,
  }) {
    _role = role;
    _operatorName =
        operatorName.trim().isEmpty ? roleLabel(role) : operatorName.trim();
    _accessId = accessId.trim();
    _scope = scope;
    notifyListeners();
  }

  void updateScope(GeographicScope scope) {
    final unchanged = _scope.level == scope.level &&
        _scope.country == scope.country &&
        _scope.zoneId == scope.zoneId &&
        _scope.stateId == scope.stateId &&
        _scope.senatorialDistrictId == scope.senatorialDistrictId &&
        _scope.lgaId == scope.lgaId &&
        _scope.wardId == scope.wardId &&
        _scope.pollingUnitId == scope.pollingUnitId;
    if (unchanged) return;
    _scope = scope;
    notifyListeners();
  }

  void signOut() {
    _role = null;
    _operatorName = '';
    _accessId = '';
    _scope = GeographicScope.nigeria;
    notifyListeners();
  }
}

class TgcgSession extends InheritedNotifier<TgcgSessionController> {
  const TgcgSession({
    super.key,
    required TgcgSessionController controller,
    required super.child,
  }) : super(notifier: controller);

  static TgcgSessionController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value =
          context.dependOnInheritedWidgetOfExactType<TgcgSession>();
      assert(value != null, 'TgcgSession is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<TgcgSession>();
    final value = element?.widget as TgcgSession?;
    assert(value != null, 'TgcgSession is missing above this context.');
    return value!.notifier!;
  }
}

String roleLabel(TgcgRole role) => switch (role) {
      TgcgRole.nationalAdministrator => 'National Administrator',
      TgcgRole.nationalCollationOfficer => 'National Collation Officer',
      TgcgRole.situationRoomDirector => 'Situation Room Director',
      TgcgRole.zonalCoordinator => 'Zonal Coordinator',
      TgcgRole.stateCoordinator => 'State Coordinator',
      TgcgRole.lgaCoordinator => 'LGA Coordinator',
      TgcgRole.wardCoordinator => 'Ward Coordinator',
      TgcgRole.pollingUnitAgent => 'Polling Unit Agent',
      TgcgRole.observer => 'Observer',
      TgcgRole.legalOfficer => 'Legal Officer',
      TgcgRole.technicalSupport => 'Technical Support',
      TgcgRole.readOnlyExecutive => 'Executive Viewer',
    };

String roleDescription(TgcgRole role) => switch (role) {
      TgcgRole.nationalAdministrator =>
        'National system administration, access control and operational oversight.',
      TgcgRole.nationalCollationOfficer =>
        'National result verification, collation, reconciliation and reporting.',
      TgcgRole.situationRoomDirector =>
        'Live incidents, field reporting, verification and response coordination.',
      TgcgRole.zonalCoordinator =>
        'Cross-state coordination and operational monitoring within an assigned zone.',
      TgcgRole.stateCoordinator =>
        'State-level field network, accreditation, incidents and result verification.',
      TgcgRole.lgaCoordinator =>
        'LGA field coordination, reporting, agent assignments and election-day operations.',
      TgcgRole.wardCoordinator =>
        'Ward-level field monitoring, reporting and result submission support.',
      TgcgRole.pollingUnitAgent =>
        'Polling-unit check-in, incident reporting, evidence and result submission.',
      TgcgRole.observer =>
        'Observation, structured field reporting and evidence submission.',
      TgcgRole.legalOfficer =>
        'Evidence review, disputes, incidents, audit and legal documentation.',
      TgcgRole.technicalSupport =>
        'Technical operations, user support, system monitoring and troubleshooting.',
      TgcgRole.readOnlyExecutive =>
        'Read-only national command, incident, collation and audit visibility.',
    };

IconData roleIcon(TgcgRole role) => switch (role) {
      TgcgRole.nationalAdministrator => Icons.admin_panel_settings_rounded,
      TgcgRole.nationalCollationOfficer => Icons.account_tree_rounded,
      TgcgRole.situationRoomDirector => Icons.radar_rounded,
      TgcgRole.zonalCoordinator => Icons.public_rounded,
      TgcgRole.stateCoordinator => Icons.map_rounded,
      TgcgRole.lgaCoordinator => Icons.location_city_rounded,
      TgcgRole.wardCoordinator => Icons.grid_view_rounded,
      TgcgRole.pollingUnitAgent => Icons.how_to_vote_rounded,
      TgcgRole.observer => Icons.visibility_rounded,
      TgcgRole.legalOfficer => Icons.gavel_rounded,
      TgcgRole.technicalSupport => Icons.support_agent_rounded,
      TgcgRole.readOnlyExecutive => Icons.dashboard_customize_rounded,
    };

Set<TgcgModule> allowedModules(TgcgRole role) {
  final modules = <TgcgModule>{TgcgModule.overview};

  if (TgcgPermissionPolicy.allows(role, TgcgCapability.manageMembership) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.accreditAgents) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.manageAgentAssignments)) {
    modules.add(TgcgModule.accreditation);
  }
  if (role == TgcgRole.nationalAdministrator) {
    modules.add(TgcgModule.membershipNetwork);
    modules.add(TgcgModule.roleAssignment);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewGeography)) {
    modules.add(TgcgModule.geography);
    if (role != TgcgRole.pollingUnitAgent && role != TgcgRole.observer) {
      modules.add(TgcgModule.liveOperations);
      modules.add(TgcgModule.aiAnalytics);
      modules.add(TgcgModule.alertCenter);
    }
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewIncidents) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.createIncident) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.submitFieldReport)) {
    modules.add(TgcgModule.fieldMonitoring);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewEvidence)) {
    modules.add(TgcgModule.evidenceCapture);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewSituationRoom)) {
    modules.add(TgcgModule.situationRoom);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewSituationRoom) &&
      TgcgPermissionPolicy.allows(role, TgcgCapability.assignIncident)) {
    modules.add(TgcgModule.securityResponse);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.submitElectionResult) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.verifyElectionResult) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.disputeElectionResult)) {
    modules.add(TgcgModule.resultCapture);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.verifyElectionResult) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.manageMembership) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.manageEvidence)) {
    modules.add(TgcgModule.aiVerification);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewCollation)) {
    modules.add(TgcgModule.collation);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewMediaIntelligence)) {
    modules.add(TgcgModule.mediaIntelligence);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewCommunications)) {
    modules.add(TgcgModule.communications);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewDiscussionRoom)) {
    modules.add(TgcgModule.discussionRoom);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewMeetingRoom)) {
    modules.add(TgcgModule.meetingRoom);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewAudit) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.manageSystemSettings) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.viewSituationRoom)) {
    modules.add(TgcgModule.systemMonitoring);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.exportReports)) {
    modules.add(TgcgModule.reports);
  }
  if (TgcgPermissionPolicy.allows(role, TgcgCapability.viewAudit) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.manageUsers) ||
      TgcgPermissionPolicy.allows(role, TgcgCapability.manageSystemSettings)) {
    modules.add(TgcgModule.governance);
  }

  return modules;
}
