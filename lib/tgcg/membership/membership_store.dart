import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../geography/geography_registry.dart';

class MembershipOperationsController extends ChangeNotifier {
  MembershipOperationsController._({
    required GeographyRegistry geography,
    required List<TgcgMember> members,
    required List<AccreditedAgent> agents,
  })  : _geography = geography,
        _members = members,
        _agents = agents;

  factory MembershipOperationsController.prototypeSeed(
    GeographyRegistry geography,
  ) {
    final now = DateTime.utc(2026, 9, 27, 7, 30);
    final kd = geography.pollingUnit('KD-KN-W01-PU001')!.scope;
    final bn = geography.pollingUnit('BN-MK-W01-PU004')!.scope;
    final la = geography.pollingUnit('LA-IK-W03-PU012')!.scope;

    return MembershipOperationsController._(
      geography: geography,
      members: [
        TgcgMember(
          id: 'MEM-0001',
          fullName: 'Amina Yusuf',
          phoneNumber: '+2348000000001',
          membershipNumber: 'TGCG-000001',
          createdAt: now.subtract(const Duration(days: 45)),
          status: RecordStatus.verified,
          origin: RecordOrigin.systemDerived,
        ),
        TgcgMember(
          id: 'MEM-0002',
          fullName: 'Samuel Terna',
          phoneNumber: '+2348000000002',
          membershipNumber: 'TGCG-000002',
          createdAt: now.subtract(const Duration(days: 38)),
          status: RecordStatus.verified,
          origin: RecordOrigin.systemDerived,
        ),
        TgcgMember(
          id: 'MEM-0003',
          fullName: 'Chinedu Okafor',
          phoneNumber: '+2348000000003',
          membershipNumber: 'TGCG-000003',
          createdAt: now.subtract(const Duration(days: 30)),
          status: RecordStatus.submitted,
          origin: RecordOrigin.systemDerived,
        ),
        TgcgMember(
          id: 'MEM-0004',
          fullName: 'Bisi Adeyemi',
          phoneNumber: '+2348000000004',
          membershipNumber: 'TGCG-000004',
          createdAt: now.subtract(const Duration(days: 21)),
          status: RecordStatus.verified,
          origin: RecordOrigin.systemDerived,
        ),
      ],
      agents: [
        AccreditedAgent(
          id: 'ACC-0001',
          memberId: 'MEM-0001',
          agentId: 'AG-KD-001',
          role: TgcgRole.pollingUnitAgent,
          scope: kd,
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 20)),
          registeredPhoneNumber: '+2348000000001',
          deviceId: 'DEV-KD-001',
          simFingerprint: 'SIM-KD-001',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0002',
          memberId: 'MEM-0002',
          agentId: 'AG-BN-014',
          role: TgcgRole.pollingUnitAgent,
          scope: bn,
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 18)),
          registeredPhoneNumber: '+2348000000002',
          deviceId: 'DEV-BN-014',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0003',
          memberId: 'MEM-0004',
          agentId: 'AG-LA-032',
          role: TgcgRole.pollingUnitAgent,
          scope: la,
          status: AccreditationStatus.pending,
          createdAt: now.subtract(const Duration(days: 9)),
          registeredPhoneNumber: '+2348000000004',
          biometricEnrolled: false,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
      ],
    );
  }

  final GeographyRegistry _geography;
  final List<TgcgMember> _members;
  final List<AccreditedAgent> _agents;

  GeographyRegistry get geography => _geography;
  List<TgcgMember> get members => List.unmodifiable(_members);
  List<AccreditedAgent> get agents => List.unmodifiable(_agents);

  TgcgMember? memberById(String id) {
    for (final member in _members) {
      if (member.id == id) return member;
    }
    return null;
  }

  List<AccreditedAgent> agentsForScope(GeographicScope scope) =>
      _agents.where((agent) => GeographyRegistry.scopeContains(scope, agent.scope)).toList(growable: false);

  int assignedPollingUnitsWithin(GeographicScope scope) => agentsForScope(scope)
      .where((agent) =>
          agent.status == AccreditationStatus.approved &&
          agent.role == TgcgRole.pollingUnitAgent &&
          agent.scope.pollingUnitId != null)
      .map((agent) => agent.scope.pollingUnitId!)
      .toSet()
      .length;

  TgcgMember createMember({
    required String fullName,
    required String phoneNumber,
    String? email,
  }) {
    final member = TgcgMember(
      id: 'MEM-${(_members.length + 1).toString().padLeft(4, '0')}',
      fullName: fullName.trim(),
      phoneNumber: phoneNumber.trim(),
      email: email?.trim().isEmpty == true ? null : email?.trim(),
      membershipNumber: 'TGCG-${(_members.length + 1).toString().padLeft(6, '0')}',
      createdAt: DateTime.now().toUtc(),
      status: RecordStatus.submitted,
      origin: RecordOrigin.localEntry,
    );
    _members.insert(0, member);
    notifyListeners();
    return member;
  }

  AccreditedAgent accredit({
    required String memberId,
    required TgcgRole role,
    required GeographicScope scope,
    String? phoneNumber,
    String? deviceId,
    String? simFingerprint,
  }) {
    if (scope.level == GeographyLevel.pollingUnit &&
        _geography.pollingUnit(scope.pollingUnitId ?? '') == null) {
      throw ArgumentError('Polling-unit assignment must use canonical geography.');
    }

    final agent = AccreditedAgent(
      id: 'ACC-${(_agents.length + 1).toString().padLeft(4, '0')}',
      memberId: memberId,
      agentId: 'AG-${(_agents.length + 1).toString().padLeft(5, '0')}',
      role: role,
      scope: scope,
      status: AccreditationStatus.pending,
      createdAt: DateTime.now().toUtc(),
      registeredPhoneNumber: phoneNumber?.trim(),
      deviceId: deviceId?.trim().isEmpty == true ? null : deviceId?.trim(),
      simFingerprint:
          simFingerprint?.trim().isEmpty == true ? null : simFingerprint?.trim(),
      origin: RecordOrigin.localEntry,
    );
    _agents.insert(0, agent);
    notifyListeners();
    return agent;
  }

  void updateAccreditationStatus(String id, AccreditationStatus status) {
    final index = _agents.indexWhere((agent) => agent.id == id);
    if (index < 0) return;
    _agents[index] = _copyAgent(_agents[index], status: status);
    notifyListeners();
  }

  void updateReadiness(
    String id, {
    bool? trainingCompleted,
    bool? biometricEnrolled,
    String? deviceId,
    String? simFingerprint,
  }) {
    final index = _agents.indexWhere((agent) => agent.id == id);
    if (index < 0) return;
    final current = _agents[index];
    _agents[index] = AccreditedAgent(
      id: current.id,
      memberId: current.memberId,
      agentId: current.agentId,
      role: current.role,
      scope: current.scope,
      status: current.status,
      createdAt: current.createdAt,
      registeredPhoneNumber: current.registeredPhoneNumber,
      deviceId: deviceId ?? current.deviceId,
      simFingerprint: simFingerprint ?? current.simFingerprint,
      biometricEnrolled: biometricEnrolled ?? current.biometricEnrolled,
      trainingCompleted: trainingCompleted ?? current.trainingCompleted,
      origin: current.origin,
    );
    notifyListeners();
  }

  static AccreditedAgent _copyAgent(
    AccreditedAgent current, {
    AccreditationStatus? status,
  }) => AccreditedAgent(
        id: current.id,
        memberId: current.memberId,
        agentId: current.agentId,
        role: current.role,
        scope: current.scope,
        status: status ?? current.status,
        createdAt: current.createdAt,
        registeredPhoneNumber: current.registeredPhoneNumber,
        deviceId: current.deviceId,
        simFingerprint: current.simFingerprint,
        biometricEnrolled: current.biometricEnrolled,
        trainingCompleted: current.trainingCompleted,
        origin: current.origin,
      );
}

class MembershipOperations extends InheritedNotifier<MembershipOperationsController> {
  const MembershipOperations({
    super.key,
    required MembershipOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static MembershipOperationsController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<MembershipOperations>();
      assert(value != null, 'MembershipOperations is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<MembershipOperations>();
    final value = element?.widget as MembershipOperations?;
    assert(value != null, 'MembershipOperations is missing above this context.');
    return value!.notifier!;
  }
}
