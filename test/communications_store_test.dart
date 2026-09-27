import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/communications/communications_store.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';
import 'package:tgcg_emcop/tgcg/governance/governance_store.dart';

void main() {
  group('CommunicationsController', () {
    test('authorized message is locally queued and audited', () {
      final governance = GovernanceOperationsController.prototypeSeed();
      final store = CommunicationsController.prototypeSeed(governance);
      final initialAuditCount = governance.auditEvents.length;

      final sent = store.sendMessage(
        roomId: 'ROOM-NATIONAL',
        senderId: 'ADMIN-001',
        body: 'Operational test message',
        role: TgcgRole.nationalAdministrator,
        userScope: GeographicScope.nigeria,
      );

      expect(sent, isTrue);
      expect(store.messages.last.body, 'Operational test message');
      expect(store.messages.last.deliveryState, MessageDeliveryState.localQueued);
      expect(governance.auditEvents.length, initialAuditCount + 1);
      expect(governance.auditEvents.first.action, 'operational_message_created');
    });

    test('read-only executive cannot send operational message', () {
      final governance = GovernanceOperationsController.prototypeSeed();
      final store = CommunicationsController.prototypeSeed(governance);
      final initialCount = store.messages.length;

      final sent = store.sendMessage(
        roomId: 'ROOM-NATIONAL',
        senderId: 'VIEWER-001',
        body: 'Should not be accepted',
        role: TgcgRole.readOnlyExecutive,
        userScope: GeographicScope.nigeria,
      );

      expect(sent, isFalse);
      expect(store.messages.length, initialCount);
    });

    test('broadcast cannot target outside operator geographic scope', () {
      final governance = GovernanceOperationsController.prototypeSeed();
      final store = CommunicationsController.prototypeSeed(governance);
      const kaduna = GeographicScope(
        level: GeographyLevel.state,
        country: 'Nigeria',
        zoneId: 'NW',
        zoneName: 'North West',
        stateId: 'KD',
        stateName: 'Kaduna',
      );

      final sent = store.sendBroadcast(
        title: 'Outside scope',
        body: 'This national broadcast should be rejected for a state-scoped user.',
        targetScope: GeographicScope.nigeria,
        senderId: 'KD-COORD',
        role: TgcgRole.stateCoordinator,
        userScope: kaduna,
      );

      expect(sent, isFalse);
    });
  });
}
