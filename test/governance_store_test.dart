import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/governance/governance_store.dart';
import 'package:tgcg_emcop/tgcg/sync/sync_models.dart';

void main() {
  group('GovernanceOperationsController', () {
    test('failed outbox item returns to retry queue and records audit event', () {
      final store = GovernanceOperationsController.prototypeSeed();
      final initialAuditCount = store.auditEvents.length;
      final failed = store.outbox.firstWhere((item) => item.state == SyncState.failed);

      store.queueForRetry(failed.id, actorId: 'TECH-001');

      final updated = store.outbox.firstWhere((item) => item.id == failed.id);
      expect(updated.state, SyncState.queued);
      expect(updated.lastError, isNull);
      expect(store.auditEvents.length, initialAuditCount + 1);
      expect(store.auditEvents.first.action, 'sync_retry_queued');
    });

    test('system setting change is persisted in prototype store and audited', () {
      final store = GovernanceOperationsController.prototypeSeed();
      final initialAuditCount = store.auditEvents.length;
      final setting = store.settings.first;

      store.setSetting(
        settingId: setting.id,
        value: !setting.value,
        actorId: 'ADMIN-001',
      );

      final updated = store.settings.firstWhere((item) => item.id == setting.id);
      expect(updated.value, !setting.value);
      expect(updated.updatedBy, 'ADMIN-001');
      expect(store.auditEvents.length, initialAuditCount + 1);
      expect(store.auditEvents.first.action, 'system_setting_changed');
    });
  });
}
