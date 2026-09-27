import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';
import 'package:tgcg_emcop/tgcg/geography/geography_registry.dart';
import 'package:tgcg_emcop/tgcg/membership/membership_store.dart';

void main() {
  group('MembershipOperationsController', () {
    late GeographyRegistry geography;
    late MembershipOperationsController store;

    setUp(() {
      geography = GeographyRegistry.prototypeSeed();
      store = MembershipOperationsController.prototypeSeed(geography);
    });

    tearDown(() => store.dispose());

    test('creates a member in submitted state', () {
      final before = store.members.length;
      final member = store.createMember(
        fullName: 'Test Member',
        phoneNumber: '+2348000000099',
      );

      expect(store.members.length, before + 1);
      expect(member.status, RecordStatus.submitted);
      expect(member.membershipNumber, isNotNull);
    });

    test('creates a pending accreditation against canonical polling unit', () {
      final member = store.members.first;
      final pu = geography.pollingUnit('KD-KN-W01-PU002')!.scope;

      final agent = store.accredit(
        memberId: member.id,
        role: TgcgRole.pollingUnitAgent,
        scope: pu,
        phoneNumber: member.phoneNumber,
      );

      expect(agent.status, AccreditationStatus.pending);
      expect(agent.scope.pollingUnitId, 'KD-KN-W01-PU002');
    });

    test('approved polling-unit agents contribute to assignment coverage', () {
      final kaduna = geography.pollingUnit('KD-KN-W01-PU001')!.scope;
      final state = GeographicScope(
        level: GeographyLevel.state,
        country: 'Nigeria',
        zoneId: kaduna.zoneId,
        zoneName: kaduna.zoneName,
        stateId: kaduna.stateId,
        stateName: kaduna.stateName,
      );

      expect(store.assignedPollingUnitsWithin(state), 1);
    });

    test('status changes update accreditation record', () {
      final pending = store.agents.firstWhere(
        (agent) => agent.status == AccreditationStatus.pending,
      );

      store.updateAccreditationStatus(
        pending.id,
        AccreditationStatus.approved,
      );

      final updated = store.agents.firstWhere((agent) => agent.id == pending.id);
      expect(updated.status, AccreditationStatus.approved);
    });

    test('readiness update preserves identity while changing readiness', () {
      final agent = store.agents.first;

      store.updateReadiness(
        agent.id,
        trainingCompleted: false,
        biometricEnrolled: false,
        deviceId: 'DEV-UPDATED',
      );

      final updated = store.agents.firstWhere((item) => item.id == agent.id);
      expect(updated.agentId, agent.agentId);
      expect(updated.trainingCompleted, isFalse);
      expect(updated.biometricEnrolled, isFalse);
      expect(updated.deviceId, 'DEV-UPDATED');
    });
  });
}
