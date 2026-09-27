import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../geography/geography_registry.dart';

class MembershipOperationsController extends ChangeNotifier {
  MembershipOperationsController._({
    required GeographyRegistry geography,
    required List<TgcgMember> members,
    required List<AccreditedAgent> agents,
    required Map<String, GeographicScope> memberScopes,
  })  : _geography = geography,
        _members = members,
        _agents = agents,
        _memberScopes = memberScopes;

  factory MembershipOperationsController.prototypeSeed(
    GeographyRegistry geography,
  ) {
    final now = DateTime.utc(2026, 9, 27, 7, 30);
    final kdPu = geography.pollingUnit('KD-KN-W01-PU001')!.scope;
    final bnPu = geography.pollingUnit('BN-MK-W01-PU004')!.scope;
    final laPu = geography.pollingUnit('LA-IK-W03-PU012')!.scope;

    GeographicScope stateScope(String name) => geography.states
        .firstWhere((item) => item.name == name)
        .scope;

    final members = <TgcgMember>[
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
      TgcgMember(
        id: 'MEM-0005',
        fullName: 'Hauwa Bello',
        phoneNumber: '+2348000000005',
        membershipNumber: 'TGCG-000005',
        createdAt: now.subtract(const Duration(days: 18)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0006',
        fullName: 'Ibrahim Musa',
        phoneNumber: '+2348000000006',
        membershipNumber: 'TGCG-000006',
        createdAt: now.subtract(const Duration(days: 17)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0007',
        fullName: 'Ifeanyi Nwosu',
        phoneNumber: '+2348000000007',
        membershipNumber: 'TGCG-000007',
        createdAt: now.subtract(const Duration(days: 14)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0008',
        fullName: 'Ebiye George',
        phoneNumber: '+2348000000008',
        membershipNumber: 'TGCG-000008',
        createdAt: now.subtract(const Duration(days: 13)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0009',
        fullName: 'Tunde Adebayo',
        phoneNumber: '+2348000000009',
        membershipNumber: 'TGCG-000009',
        createdAt: now.subtract(const Duration(days: 11)),
        status: RecordStatus.submitted,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0010',
        fullName: 'Grace Yakubu',
        phoneNumber: '+2348000000010',
        membershipNumber: 'TGCG-000010',
        createdAt: now.subtract(const Duration(days: 9)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0011',
        fullName: 'Fatima Adamu',
        phoneNumber: '+2348000000011',
        membershipNumber: 'TGCG-000011',
        createdAt: now.subtract(const Duration(days: 7)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
      TgcgMember(
        id: 'MEM-0012',
        fullName: 'Ini Etim',
        phoneNumber: '+2348000000012',
        membershipNumber: 'TGCG-000012',
        createdAt: now.subtract(const Duration(days: 5)),
        status: RecordStatus.verified,
        origin: RecordOrigin.systemDerived,
      ),
    ];

    return MembershipOperationsController._(
      geography: geography,
      members: members,
      memberScopes: {
        'MEM-0001': stateScope('Kaduna'),
        'MEM-0002': stateScope('Benue'),
        'MEM-0003': stateScope('Enugu'),
        'MEM-0004': stateScope('Lagos'),
        'MEM-0005': stateScope('Adamawa'),
        'MEM-0006': stateScope('Kano'),
        'MEM-0007': stateScope('Anambra'),
        'MEM-0008': stateScope('Rivers'),
        'MEM-0009': stateScope('Oyo'),
        'MEM-0010': stateScope('Federal Capital Territory'),
        'MEM-0011': stateScope('Bauchi'),
        'MEM-0012': stateScope('Akwa Ibom'),
      },
      agents: [
        AccreditedAgent(
          id: 'ACC-0001',
          memberId: 'MEM-0001',
          agentId: 'AG-KD-001',
          role: TgcgRole.pollingUnitAgent,
          scope: kdPu,
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
          scope: bnPu,
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
          scope: laPu,
          status: AccreditationStatus.pending,
          createdAt: now.subtract(const Duration(days: 9)),
          registeredPhoneNumber: '+2348000000004',
          biometricEnrolled: false,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0004',
          memberId: 'MEM-0005',
          agentId: 'AG-AD-021',
          role: TgcgRole.stateCoordinator,
          scope: stateScope('Adamawa'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 8)),
          registeredPhoneNumber: '+2348000000005',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0005',
          memberId: 'MEM-0006',
          agentId: 'AG-KN-015',
          role: TgcgRole.stateCoordinator,
          scope: stateScope('Kano'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 8)),
          registeredPhoneNumber: '+2348000000006',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0006',
          memberId: 'MEM-0007',
          agentId: 'AG-AN-018',
          role: TgcgRole.stateCoordinator,
          scope: stateScope('Anambra'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 7)),
          registeredPhoneNumber: '+2348000000007',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0007',
          memberId: 'MEM-0008',
          agentId: 'AG-RI-011',
          role: TgcgRole.stateCoordinator,
          scope: stateScope('Rivers'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 6)),
          registeredPhoneNumber: '+2348000000008',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0008',
          memberId: 'MEM-0009',
          agentId: 'AG-OY-008',
          role: TgcgRole.stateCoordinator,
          scope: stateScope('Oyo'),
          status: AccreditationStatus.pending,
          createdAt: now.subtract(const Duration(days: 5)),
          registeredPhoneNumber: '+2348000000009',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
        AccreditedAgent(
          id: 'ACC-0009',
          memberId: 'MEM-0010',
          agentId: 'AG-FCT-006',
          role: TgcgRole.stateCoordinator,
          scope: stateScope('Federal Capital Territory'),
          status: AccreditationStatus.approved,
          createdAt: now.subtract(const Duration(days: 4)),
          registeredPhoneNumber: '+2348000000010',
          biometricEnrolled: true,
          trainingCompleted: true,
          origin: RecordOrigin.systemDerived,
        ),
      ],
    );
  }

  final GeographyRegistry _geography;
  final List<TgcgMember> _members;
  final List<AccreditedAgent> _agents;
  final Map<String, GeographicScope> _memberScopes;

  GeographyRegistry get geography => _geography;
  List<TgcgMember> get members => List.unmodifiable(_members);
  List<AccreditedAgent> get agents => List.unmodifiable(_agents);

  TgcgMember? memberById(String id) {
    for (final member in _members) {
      if (member.id == id) return member;
    }
    return null;
  }

  GeographicScope? registrationScopeForMember(String memberId) =>
      _memberScopes[memberId];

  List<TgcgMember> membersForScope(GeographicScope scope) => _members
      .where((member) {
        final memberScope = _memberScopes[member.id];
        return memberScope != null &&
            GeographyRegistry.scopeContains(scope, memberScope);
      })
      .toList(growable: false);

  int memberCountForScope(GeographicScope scope) =>
      membersForScope(scope).length;

  List<AccreditedAgent> agentsForScope(GeographicScope scope) =>
      _agents
          .where((agent) => GeographyRegistry.scopeContains(scope, agent.scope))
          .toList(growable: false);

  int agentCountForScope(GeographicScope scope) =>
      agentsForScope(scope).length;

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
    GeographicScope registrationScope = GeographicScope.nigeria,
  }) {
    final member = TgcgMember(
      id: 'MEM-${(_members.length + 1).toString().padLeft(4, '0')}',
      fullName: fullName.trim(),
      phoneNumber: phoneNumber.trim(),
      email: email?.trim().isEmpty == true ? null : email?.trim(),
      membershipNumber:
          'TGCG-${(_members.length + 1).toString().padLeft(6, '0')}',
      createdAt: DateTime.now().toUtc(),
      status: RecordStatus.submitted,
      origin: RecordOrigin.localEntry,
    );
    _members.insert(0, member);
    _memberScopes[member.id] = registrationScope;
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
      throw ArgumentError(
        'Polling-unit assignment must use canonical geography.',
      );
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
      final value =
          context.dependOnInheritedWidgetOfExactType<MembershipOperations>();
      assert(value != null, 'MembershipOperations is missing above this context.');
      return value!.notifier!;
    }
    final element =
        context.getElementForInheritedWidgetOfExactType<MembershipOperations>();
    final value = element?.widget as MembershipOperations?;
    assert(value != null, 'MembershipOperations is missing above this context.');
    return value!.notifier!;
  }
}
