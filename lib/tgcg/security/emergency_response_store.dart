import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../governance/governance_store.dart';

enum EmergencyAgencyType {
  police,
  civilDefence,
  roadSafety,
  fireRescue,
  medical,
  other,
}

enum EmergencyDispatchPriority { routine, urgent, critical }

enum EmergencyDispatchStatus {
  assigned,
  acknowledged,
  responding,
  onScene,
  resolved,
  closed,
}

class EmergencyAgency {
  const EmergencyAgency({
    required this.id,
    required this.name,
    required this.shortName,
    required this.type,
    required this.coverage,
    required this.commandDesk,
    required this.contactPhone,
    this.active = true,
  });

  final String id;
  final String name;
  final String shortName;
  final EmergencyAgencyType type;
  final GeographicScope coverage;
  final String commandDesk;
  final String contactPhone;
  final bool active;
}

class EmergencyDispatch {
  const EmergencyDispatch({
    required this.id,
    required this.incidentId,
    required this.agencyId,
    required this.scope,
    required this.priority,
    required this.status,
    required this.assignedAt,
    required this.assignedBy,
    this.instructions,
    this.acknowledgedAt,
    this.respondingAt,
    this.onSceneAt,
    this.resolvedAt,
    this.closedAt,
    this.lastUpdatedBy,
  });

  final String id;
  final String incidentId;
  final String agencyId;
  final GeographicScope scope;
  final EmergencyDispatchPriority priority;
  final EmergencyDispatchStatus status;
  final DateTime assignedAt;
  final String assignedBy;
  final String? instructions;
  final DateTime? acknowledgedAt;
  final DateTime? respondingAt;
  final DateTime? onSceneAt;
  final DateTime? resolvedAt;
  final DateTime? closedAt;
  final String? lastUpdatedBy;
}

class EmergencyResponseController extends ChangeNotifier {
  EmergencyResponseController._({
    required GovernanceOperationsController governance,
    required List<EmergencyAgency> agencies,
    required List<EmergencyDispatch> dispatches,
  })  : _governance = governance,
        _agencies = agencies,
        _dispatches = dispatches;

  factory EmergencyResponseController.prototypeSeed(
    GovernanceOperationsController governance,
  ) {
    final now = DateTime.utc(2026, 9, 28, 2, 0);
    const nigeria = GeographicScope.nigeria;
    return EmergencyResponseController._(
      governance: governance,
      agencies: const [
        EmergencyAgency(
          id: 'AGENCY-POLICE',
          name: 'Police Response Desk',
          shortName: 'Police',
          type: EmergencyAgencyType.police,
          coverage: nigeria,
          commandDesk: 'National Operations Desk',
          contactPhone: '+234 000 000 0101',
        ),
        EmergencyAgency(
          id: 'AGENCY-NSCDC',
          name: 'Civil Defence Response Desk',
          shortName: 'Civil Defence',
          type: EmergencyAgencyType.civilDefence,
          coverage: nigeria,
          commandDesk: 'National Operations Desk',
          contactPhone: '+234 000 000 0102',
        ),
        EmergencyAgency(
          id: 'AGENCY-FRSC',
          name: 'Road Safety Response Desk',
          shortName: 'Road Safety',
          type: EmergencyAgencyType.roadSafety,
          coverage: nigeria,
          commandDesk: 'National Operations Desk',
          contactPhone: '+234 000 000 0103',
        ),
        EmergencyAgency(
          id: 'AGENCY-FIRE',
          name: 'Fire & Rescue Desk',
          shortName: 'Fire & Rescue',
          type: EmergencyAgencyType.fireRescue,
          coverage: nigeria,
          commandDesk: 'Emergency Coordination Desk',
          contactPhone: '+234 000 000 0104',
        ),
        EmergencyAgency(
          id: 'AGENCY-MEDICAL',
          name: 'Medical Emergency Desk',
          shortName: 'Medical',
          type: EmergencyAgencyType.medical,
          coverage: nigeria,
          commandDesk: 'Emergency Coordination Desk',
          contactPhone: '+234 000 000 0105',
        ),
      ],
      dispatches: [
        EmergencyDispatch(
          id: 'DSP-0001',
          incidentId: 'INC-0001',
          agencyId: 'AGENCY-POLICE',
          scope: GeographicScope(
            level: GeographyLevel.lga,
            country: 'Nigeria',
            zoneId: 'NW',
            zoneName: 'North West',
            stateId: 'KD',
            stateName: 'Kaduna',
            lgaId: 'KD-KADUNA-NORTH',
            lgaName: 'Kaduna North',
          ),
          priority: EmergencyDispatchPriority.urgent,
          status: EmergencyDispatchStatus.acknowledged,
          assignedAt: now.subtract(const Duration(minutes: 14)),
          acknowledgedAt: now.subtract(const Duration(minutes: 10)),
          assignedBy: 'SITUATION-ROOM',
          lastUpdatedBy: 'POLICE-DESK',
          instructions: 'Confirm access conditions and update the Situation Room.',
        ),
      ],
    );
  }

  final GovernanceOperationsController _governance;
  final List<EmergencyAgency> _agencies;
  final List<EmergencyDispatch> _dispatches;

  List<EmergencyAgency> get agencies => List.unmodifiable(_agencies);
  List<EmergencyDispatch> get dispatches => List.unmodifiable(_dispatches);

  List<EmergencyAgency> agenciesForScope(GeographicScope scope) => _agencies
      .where((agency) => agency.active && _overlaps(agency.coverage, scope))
      .toList(growable: false);

  List<EmergencyDispatch> dispatchesForScope(GeographicScope scope) =>
      _dispatches.where((item) => _overlaps(scope, item.scope)).toList(growable: false)
        ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

  List<EmergencyDispatch> dispatchesForIncident(String incidentId) => _dispatches
      .where((item) => item.incidentId == incidentId)
      .toList(growable: false)
    ..sort((a, b) => b.assignedAt.compareTo(a.assignedAt));

  EmergencyAgency? agencyById(String id) {
    for (final agency in _agencies) {
      if (agency.id == id) return agency;
    }
    return null;
  }

  int get activeDispatchCount => _dispatches
      .where((item) =>
          item.status != EmergencyDispatchStatus.resolved &&
          item.status != EmergencyDispatchStatus.closed)
      .length;

  int get awaitingAcknowledgementCount => _dispatches
      .where((item) => item.status == EmergencyDispatchStatus.assigned)
      .length;

  EmergencyDispatch assign({
    required String incidentId,
    required String agencyId,
    required GeographicScope scope,
    required EmergencyDispatchPriority priority,
    required String actorId,
    String? instructions,
  }) {
    final agency = agencyById(agencyId);
    if (agency == null || !agency.active) {
      throw ArgumentError('Selected response agency is unavailable.');
    }
    if (!_overlaps(agency.coverage, scope)) {
      throw ArgumentError('Selected agency does not cover this incident scope.');
    }

    final dispatch = EmergencyDispatch(
      id: 'DSP-${(_dispatches.length + 1).toString().padLeft(4, '0')}',
      incidentId: incidentId,
      agencyId: agencyId,
      scope: scope,
      priority: priority,
      status: EmergencyDispatchStatus.assigned,
      assignedAt: DateTime.now().toUtc(),
      assignedBy: actorId,
      instructions: instructions?.trim().isEmpty == true ? null : instructions?.trim(),
      lastUpdatedBy: actorId,
    );
    _dispatches.insert(0, dispatch);
    _governance.recordAudit(
      actorId: actorId,
      action: 'emergency_dispatch_assigned',
      entityType: 'emergency_dispatch',
      entityId: dispatch.id,
      detail: '${agency.shortName} assigned to $incidentId with ${priority.name} priority.',
      scope: scope,
    );
    notifyListeners();
    return dispatch;
  }

  void updateStatus({
    required String dispatchId,
    required EmergencyDispatchStatus status,
    required String actorId,
  }) {
    final index = _dispatches.indexWhere((item) => item.id == dispatchId);
    if (index < 0) return;
    final current = _dispatches[index];
    final now = DateTime.now().toUtc();
    _dispatches[index] = EmergencyDispatch(
      id: current.id,
      incidentId: current.incidentId,
      agencyId: current.agencyId,
      scope: current.scope,
      priority: current.priority,
      status: status,
      assignedAt: current.assignedAt,
      assignedBy: current.assignedBy,
      instructions: current.instructions,
      acknowledgedAt: status == EmergencyDispatchStatus.acknowledged && current.acknowledgedAt == null
          ? now
          : current.acknowledgedAt,
      respondingAt: status == EmergencyDispatchStatus.responding && current.respondingAt == null
          ? now
          : current.respondingAt,
      onSceneAt: status == EmergencyDispatchStatus.onScene && current.onSceneAt == null
          ? now
          : current.onSceneAt,
      resolvedAt: status == EmergencyDispatchStatus.resolved && current.resolvedAt == null
          ? now
          : current.resolvedAt,
      closedAt: status == EmergencyDispatchStatus.closed && current.closedAt == null
          ? now
          : current.closedAt,
      lastUpdatedBy: actorId,
    );
    _governance.recordAudit(
      actorId: actorId,
      action: 'emergency_dispatch_${status.name}',
      entityType: 'emergency_dispatch',
      entityId: current.id,
      detail: 'Response status changed to ${status.name}.',
      scope: current.scope,
    );
    notifyListeners();
  }

  static bool _overlaps(GeographicScope a, GeographicScope b) =>
      _within(a, b) || _within(b, a);

  static bool _within(GeographicScope parent, GeographicScope child) {
    if (parent.country != child.country) return false;
    if (parent.level == GeographyLevel.country) return true;
    if (parent.zoneId != null && parent.zoneId != child.zoneId) return false;
    if (parent.level == GeographyLevel.geopoliticalZone) return true;
    if (parent.stateId != null && parent.stateId != child.stateId) return false;
    if (parent.level == GeographyLevel.state) return true;
    if (parent.senatorialDistrictId != null &&
        parent.senatorialDistrictId != child.senatorialDistrictId) return false;
    if (parent.level == GeographyLevel.senatorialDistrict) return true;
    if (parent.lgaId != null && parent.lgaId != child.lgaId) return false;
    if (parent.level == GeographyLevel.lga) return true;
    if (parent.wardId != null && parent.wardId != child.wardId) return false;
    if (parent.level == GeographyLevel.ward) return true;
    return parent.pollingUnitId == child.pollingUnitId;
  }
}

class EmergencyResponse extends InheritedNotifier<EmergencyResponseController> {
  const EmergencyResponse({
    super.key,
    required EmergencyResponseController controller,
    required super.child,
  }) : super(notifier: controller);

  static EmergencyResponseController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<EmergencyResponse>();
      assert(value != null, 'EmergencyResponse is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<EmergencyResponse>();
    final value = element?.widget as EmergencyResponse?;
    assert(value != null, 'EmergencyResponse is missing above this context.');
    return value!.notifier!;
  }
}
