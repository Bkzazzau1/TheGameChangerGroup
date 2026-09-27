import 'package:flutter/foundation.dart';

import '../domain/models.dart';
import '../sync/sync_models.dart';

enum SystemSettingCategory { security, sync, evidence, communications }

class SystemSettingRecord {
  const SystemSettingRecord({
    required this.id,
    required this.label,
    required this.category,
    required this.value,
    required this.updatedAt,
    required this.updatedBy,
    this.description,
  });

  final String id;
  final String label;
  final SystemSettingCategory category;
  final bool value;
  final DateTime updatedAt;
  final String updatedBy;
  final String? description;
}

class GovernanceOperationsController extends ChangeNotifier {
  GovernanceOperationsController._({
    required List<AuditEvent> auditEvents,
    required List<SyncOutboxItem> outbox,
    required List<SystemSettingRecord> settings,
  })  : _auditEvents = auditEvents,
        _outbox = outbox,
        _settings = settings;

  factory GovernanceOperationsController.prototypeSeed() {
    final now = DateTime.utc(2026, 9, 27, 8, 10);
    return GovernanceOperationsController._(
      auditEvents: [
        AuditEvent(
          id: 'AUD-0001',
          actorId: 'SYSTEM',
          action: 'prototype_seed_loaded',
          entityType: 'system',
          entityId: 'TGCG-EMCOP',
          timestamp: now.subtract(const Duration(minutes: 45)),
          detail: 'Prototype operational stores initialized.',
          scope: GeographicScope.nigeria,
        ),
        AuditEvent(
          id: 'AUD-0002',
          actorId: 'COLLATION-DESK',
          action: 'result_verified',
          entityType: 'election_result',
          entityId: 'RES-0001',
          timestamp: now.subtract(const Duration(minutes: 32)),
          detail: 'Prototype result accepted into verified-only collation.',
          scope: GeographicScope.nigeria,
        ),
      ],
      outbox: [
        SyncOutboxItem(
          id: 'OUT-0001',
          entityType: 'field_report',
          entityId: 'RPT-0003',
          mutationType: SyncMutationType.create,
          payloadJson: '{"entity":"field_report","id":"RPT-0003"}',
          mutationVersion: 1,
          createdAt: now.subtract(const Duration(minutes: 18)),
          state: SyncState.queued,
        ),
        SyncOutboxItem(
          id: 'OUT-0002',
          entityType: 'evidence',
          entityId: 'EVD-0002',
          mutationType: SyncMutationType.create,
          payloadJson: '{"entity":"evidence","id":"EVD-0002"}',
          mutationVersion: 1,
          createdAt: now.subtract(const Duration(minutes: 27)),
          state: SyncState.failed,
          attemptCount: 2,
          lastAttemptAt: now.subtract(const Duration(minutes: 9)),
          lastError: 'Connectivity unavailable; encrypted local record retained.',
        ),
        SyncOutboxItem(
          id: 'OUT-0003',
          entityType: 'agent_assignment',
          entityId: 'AG-KD-001',
          mutationType: SyncMutationType.update,
          payloadJson: '{"entity":"agent_assignment","id":"AG-KD-001"}',
          mutationVersion: 2,
          createdAt: now.subtract(const Duration(minutes: 41)),
          state: SyncState.conflict,
          attemptCount: 1,
          lastAttemptAt: now.subtract(const Duration(minutes: 36)),
          lastError: 'Server version is newer than local mutation version.',
        ),
      ],
      settings: [
        SystemSettingRecord(
          id: 'SET-MFA',
          label: 'Administrator MFA required',
          category: SystemSettingCategory.security,
          value: true,
          updatedAt: now.subtract(const Duration(days: 1)),
          updatedBy: 'SYSTEM',
          description: 'Production backend must enforce MFA for privileged users.',
        ),
        SystemSettingRecord(
          id: 'SET-EVIDENCE-HASH',
          label: 'Evidence hash required',
          category: SystemSettingCategory.evidence,
          value: true,
          updatedAt: now.subtract(const Duration(days: 1)),
          updatedBy: 'SYSTEM',
          description: 'Evidence records require a cryptographic content hash before server acceptance.',
        ),
        SystemSettingRecord(
          id: 'SET-OFFLINE-QUEUE',
          label: 'Offline durable queue enabled',
          category: SystemSettingCategory.sync,
          value: true,
          updatedAt: now.subtract(const Duration(days: 1)),
          updatedBy: 'SYSTEM',
          description: 'Operational writes remain usable locally while awaiting connectivity.',
        ),
      ],
    );
  }

  final List<AuditEvent> _auditEvents;
  final List<SyncOutboxItem> _outbox;
  final List<SystemSettingRecord> _settings;

  List<AuditEvent> get auditEvents => List.unmodifiable(_auditEvents);
  List<SyncOutboxItem> get outbox => List.unmodifiable(_outbox);
  List<SystemSettingRecord> get settings => List.unmodifiable(_settings);

  List<AuditEvent> auditForScope(GeographicScope scope) => _auditEvents
      .where((event) => event.scope == null || _overlaps(scope, event.scope!))
      .toList(growable: false)
    ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

  List<SyncOutboxItem> get pendingOutbox =>
      _outbox.where((item) => item.isPending).toList(growable: false);

  void recordAudit({
    required String actorId,
    required String action,
    required String entityType,
    required String entityId,
    String? detail,
    String? deviceId,
    GeographicScope? scope,
  }) {
    _auditEvents.insert(
      0,
      AuditEvent(
        id: 'AUD-${(_auditEvents.length + 1).toString().padLeft(4, '0')}',
        actorId: actorId,
        action: action,
        entityType: entityType,
        entityId: entityId,
        timestamp: DateTime.now().toUtc(),
        detail: detail,
        deviceId: deviceId,
        scope: scope,
      ),
    );
    notifyListeners();
  }

  void queueForRetry(String outboxId, {required String actorId}) {
    final index = _outbox.indexWhere((item) => item.id == outboxId);
    if (index < 0) return;
    final current = _outbox[index];
    _outbox[index] = _copyOutbox(
      current,
      state: SyncState.queued,
      lastError: null,
    );
    recordAudit(
      actorId: actorId,
      action: 'sync_retry_queued',
      entityType: current.entityType,
      entityId: current.entityId,
      detail: 'Outbox ${current.id} returned to the retry queue.',
    );
  }

  void setSetting({
    required String settingId,
    required bool value,
    required String actorId,
  }) {
    final index = _settings.indexWhere((item) => item.id == settingId);
    if (index < 0) return;
    final current = _settings[index];
    _settings[index] = SystemSettingRecord(
      id: current.id,
      label: current.label,
      category: current.category,
      value: value,
      updatedAt: DateTime.now().toUtc(),
      updatedBy: actorId,
      description: current.description,
    );
    recordAudit(
      actorId: actorId,
      action: 'system_setting_changed',
      entityType: 'system_setting',
      entityId: current.id,
      detail: '${current.label} set to $value.',
      scope: GeographicScope.nigeria,
    );
  }

  static SyncOutboxItem _copyOutbox(
    SyncOutboxItem current, {
    SyncState? state,
    String? lastError,
  }) =>
      SyncOutboxItem(
        id: current.id,
        entityType: current.entityType,
        entityId: current.entityId,
        mutationType: current.mutationType,
        payloadJson: current.payloadJson,
        mutationVersion: current.mutationVersion,
        createdAt: current.createdAt,
        state: state ?? current.state,
        attemptCount: current.attemptCount,
        lastAttemptAt: current.lastAttemptAt,
        lastError: lastError,
      );

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

class GovernanceOperations extends InheritedNotifier<GovernanceOperationsController> {
  const GovernanceOperations({
    super.key,
    required GovernanceOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static GovernanceOperationsController of(BuildContext context, {bool listen = true}) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<GovernanceOperations>();
      assert(value != null, 'GovernanceOperations is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<GovernanceOperations>();
    final value = element?.widget as GovernanceOperations?;
    assert(value != null, 'GovernanceOperations is missing above this context.');
    return value!.notifier!;
  }
}
