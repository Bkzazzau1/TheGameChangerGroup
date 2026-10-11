import 'dart:async';

import 'package:flutter/material.dart';

import 'api/access_repository.dart' show AccessGrant;
import 'domain/models.dart';
import 'domain/permissions.dart';

export 'domain/models.dart';

enum TgcgModule {
  overview,
  accreditation,
  membershipNetwork,
  roleAssignment,
  geography,
  unitMapping,
  agentTracking,
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
  bulkCommunications,
  discussionRoom,
  meetingRoom,
  systemMonitoring,
  reports,
  governance,
  memberReview,
}

class TgcgSessionController extends ChangeNotifier {
  TgcgSessionController({this.onSignOut});

  /// Runs on sign-out, e.g. to revoke the server session.
  final Future<void> Function()? onSignOut;

  TgcgRole? _role;
  String _operatorName = '';
  String _accessId = '';
  GeographicScope _scope = GeographicScope.nigeria;
  Set<String> _serverCapabilities = const {};
  List<AccessGrant> _grants = const [];
  String? _membershipNumber;
  bool _serverSession = false;
  bool _operator = false;
  bool _member = false;

  /// The former fixed role, if the account has one. Accounts whose access
  /// comes from appointments have none.
  TgcgRole? get role => _role;
  String get operatorName => _operatorName;
  String get accessId => _accessId;
  GeographicScope get scope => _scope;
  bool get isAuthenticated => _operator || _member;

  /// Signed in to the operations app (a fixed role, or appointments).
  bool get isOperator => _operator;

  /// Signed in to the member app. Members have no operations role.
  bool get isMember => _member;

  /// True when signed in against the TGCG server (not presentation mode).
  bool get isServerSession => _serverSession;

  /// Capabilities granted by the server for this account.
  Set<String> get serverCapabilities => _serverCapabilities;

  /// Where the server says this account's access comes from: each
  /// appointment, delegation or legacy role, with its own areas.
  List<AccessGrant> get grants => _grants;

  /// The member behind this account, when there is one.
  String? get membershipNumber => _membershipNumber;

  /// Who is acting: the server's grants in a server session, the role's
  /// built-in permissions in presentation mode.
  TgcgActor get actor => _serverSession
      ? TgcgServerActor(_serverCapabilities, legacyRole: _role)
      : _role ?? const TgcgServerActor({});

  /// Whether to offer [capability]. The server still checks every request,
  /// area by area; this only decides what the app shows.
  bool can(TgcgCapability capability) => isAuthenticated && actor.can(capability);

  bool canAny(Iterable<TgcgCapability> capabilities) => capabilities.any(can);

  /// The modules this session may open.
  Set<TgcgModule> get modules => _operator ? allowedModulesFor(can) : const {};

  /// The fixed role's name, or the appointments the access comes from.
  String get roleTitle {
    final role = _role;
    if (role != null) return roleLabel(role);
    final names = <String>{
      for (final grant in _grants)
        if (grant.roleName.isNotEmpty) grant.roleName,
    };
    if (names.isEmpty) return 'Member';
    if (names.length == 1) return names.first;
    return '${names.first} and ${names.length - 1} more';
  }

  /// Sign in with the account the server returned. The server decides the
  /// role (if any), the permissions and the operational scope.
  void signInFromServer({
    TgcgRole? role,
    required String fullName,
    required String accessId,
    required GeographicScope scope,
    required Set<String> capabilities,
    List<AccessGrant> grants = const [],
    String? membershipNumber,
  }) {
    _role = role;
    _operatorName = fullName;
    _accessId = accessId;
    _scope = scope;
    _serverCapabilities = Set.unmodifiable(capabilities);
    _grants = List.unmodifiable(grants);
    _membershipNumber = membershipNumber;
    _serverSession = true;
    _operator = true;
    _member = false;
    notifyListeners();
  }

  /// Take in what the server grants now (after an appointment changed).
  void updateAccess({required Set<String> capabilities, required List<AccessGrant> grants}) {
    _serverCapabilities = Set.unmodifiable(capabilities);
    _grants = List.unmodifiable(grants);
    notifyListeners();
  }

  /// Sign a member in to the member app (server accounts only).
  void signInMember({required String fullName, required String membershipNumber}) {
    _member = true;
    _operator = false;
    _role = null;
    _operatorName = fullName;
    _accessId = membershipNumber;
    _membershipNumber = membershipNumber;
    _scope = GeographicScope.nigeria;
    _serverCapabilities = const {};
    _grants = const [];
    _serverSession = true;
    notifyListeners();
  }

  void signIn({
    required TgcgRole role,
    required String operatorName,
    required String accessId,
    GeographicScope scope = GeographicScope.nigeria,
  }) {
    _role = role;
    _operator = true;
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
    if (_serverSession) unawaited(onSignOut?.call());
    _serverSession = false;
    _serverCapabilities = const {};
    _grants = const [];
    _membershipNumber = null;
    _operator = false;
    _member = false;
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

/// The modules a fixed role opens in presentation mode.
Set<TgcgModule> allowedModules(TgcgRole role) => allowedModulesFor(role.can);

/// The modules whoever holds the capabilities [can] allows may open.
Set<TgcgModule> allowedModulesFor(bool Function(TgcgCapability capability) can) {
  bool any(Iterable<TgcgCapability> capabilities) => capabilities.any(can);
  final modules = <TgcgModule>{TgcgModule.overview};

  if (any(const [
    TgcgCapability.manageMembership,
    TgcgCapability.accreditAgents,
    TgcgCapability.manageAgentAssignments,
  ])) {
    modules.add(TgcgModule.accreditation);
  }
  if (can(TgcgCapability.manageMembership)) {
    modules.add(TgcgModule.membershipNetwork);
  }
  if (any(const [
    TgcgCapability.viewRoles,
    TgcgCapability.manageRoles,
    TgcgCapability.assignRoles,
    TgcgCapability.manageAssignments,
    TgcgCapability.delegateAuthority,
  ])) {
    modules.add(TgcgModule.roleAssignment);
  }
  if (any(const [
    TgcgCapability.verifyMemberIdentity,
    TgcgCapability.reviewPollingUnitChanges,
    TgcgCapability.suspendMembers,
  ])) {
    modules.add(TgcgModule.memberReview);
  }
  // Polling-unit mapping: whoever pins units and confirms agents' locations.
  if (can(TgcgCapability.confirmAgentLocation)) {
    modules.add(TgcgModule.unitMapping);
  }
  if (can(TgcgCapability.viewGeography)) {
    modules.add(TgcgModule.geography);
    // Operational views; agents and observers (who see no incidents) go without.
    if (can(TgcgCapability.viewIncidents)) {
      modules.add(TgcgModule.liveOperations);
      modules.add(TgcgModule.aiAnalytics);
      modules.add(TgcgModule.alertCenter);
    }
  }
  if (any(const [
    TgcgCapability.viewIncidents,
    TgcgCapability.createIncident,
    TgcgCapability.submitFieldReport,
  ])) {
    modules.add(TgcgModule.fieldMonitoring);
  }
  if (can(TgcgCapability.viewEvidence)) {
    modules.add(TgcgModule.evidenceCapture);
  }
  if (can(TgcgCapability.viewSituationRoom)) {
    modules.add(TgcgModule.situationRoom);
    // Live agent positions and check-in coverage (server tracking/live and coverage).
    modules.add(TgcgModule.agentTracking);
  }
  if (can(TgcgCapability.viewSituationRoom) && can(TgcgCapability.assignIncident)) {
    modules.add(TgcgModule.securityResponse);
  }
  if (any(const [
    TgcgCapability.submitElectionResult,
    TgcgCapability.verifyElectionResult,
    TgcgCapability.disputeElectionResult,
  ])) {
    modules.add(TgcgModule.resultCapture);
  }
  if (any(const [
    TgcgCapability.verifyElectionResult,
    TgcgCapability.manageMembership,
    TgcgCapability.manageEvidence,
  ])) {
    modules.add(TgcgModule.aiVerification);
  }
  if (can(TgcgCapability.viewCollation)) {
    modules.add(TgcgModule.collation);
  }
  if (can(TgcgCapability.viewMediaIntelligence)) {
    modules.add(TgcgModule.mediaIntelligence);
  }
  if (can(TgcgCapability.viewCommunications)) {
    modules.add(TgcgModule.communications);
  }
  if (can(TgcgCapability.sendBroadcast)) {
    modules.add(TgcgModule.bulkCommunications);
  }
  if (can(TgcgCapability.viewDiscussionRoom)) {
    modules.add(TgcgModule.discussionRoom);
  }
  if (can(TgcgCapability.viewMeetingRoom)) {
    modules.add(TgcgModule.meetingRoom);
  }
  if (any(const [
    TgcgCapability.viewAudit,
    TgcgCapability.manageSystemSettings,
    TgcgCapability.viewSituationRoom,
  ])) {
    modules.add(TgcgModule.systemMonitoring);
  }
  if (can(TgcgCapability.exportReports)) {
    modules.add(TgcgModule.reports);
  }
  if (any(const [
    TgcgCapability.viewAudit,
    TgcgCapability.manageUsers,
    TgcgCapability.manageSystemSettings,
  ])) {
    modules.add(TgcgModule.governance);
  }

  return modules;
}
