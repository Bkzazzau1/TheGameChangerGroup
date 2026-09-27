import 'package:flutter/widgets.dart';

import '../domain/models.dart';
import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../governance/governance_store.dart';

enum ReportKind {
  incidentSummary,
  fieldActivity,
  accreditationReadiness,
  verifiedCollation,
  evidencePackage,
  auditTrail,
  syncOutbox,
}

enum ExportFormat { pdf, csv, json, zip }

enum ExportJobStatus { queued, generating, completed, failed }

class ReportExportJob {
  const ReportExportJob({
    required this.id,
    required this.kind,
    required this.format,
    required this.scope,
    required this.requestedBy,
    required this.requestedAt,
    required this.status,
    this.recordCount,
    this.completedAt,
    this.fileName,
    this.contentHash,
    this.error,
  });

  final String id;
  final ReportKind kind;
  final ExportFormat format;
  final GeographicScope scope;
  final String requestedBy;
  final DateTime requestedAt;
  final ExportJobStatus status;
  final int? recordCount;
  final DateTime? completedAt;
  final String? fileName;
  final String? contentHash;
  final String? error;
}

class ReportOperationsController extends ChangeNotifier {
  ReportOperationsController._({
    required GovernanceOperationsController governance,
    required List<ReportExportJob> jobs,
  })  : _governance = governance,
        _jobs = jobs;

  factory ReportOperationsController.prototypeSeed(
    GovernanceOperationsController governance,
  ) {
    final now = DateTime.utc(2026, 9, 27, 8, 35);
    return ReportOperationsController._(
      governance: governance,
      jobs: [
        ReportExportJob(
          id: 'EXP-0001',
          kind: ReportKind.incidentSummary,
          format: ExportFormat.pdf,
          scope: GeographicScope.nigeria,
          requestedBy: 'SITUATION-ROOM',
          requestedAt: now.subtract(const Duration(hours: 2)),
          status: ExportJobStatus.completed,
          recordCount: 4,
          completedAt: now.subtract(const Duration(hours: 1, minutes: 58)),
          fileName: 'incident-summary-prototype.pdf',
          contentHash: 'sha256:prototype-export-exp-0001',
        ),
        ReportExportJob(
          id: 'EXP-0002',
          kind: ReportKind.auditTrail,
          format: ExportFormat.csv,
          scope: GeographicScope.nigeria,
          requestedBy: 'SYSTEM-ADMIN',
          requestedAt: now.subtract(const Duration(minutes: 54)),
          status: ExportJobStatus.completed,
          recordCount: governance.auditEvents.length,
          completedAt: now.subtract(const Duration(minutes: 53)),
          fileName: 'audit-trail-prototype.csv',
          contentHash: 'sha256:prototype-export-exp-0002',
        ),
        ReportExportJob(
          id: 'EXP-0003',
          kind: ReportKind.evidencePackage,
          format: ExportFormat.zip,
          scope: GeographicScope.nigeria,
          requestedBy: 'LEGAL-DESK',
          requestedAt: now.subtract(const Duration(minutes: 19)),
          status: ExportJobStatus.queued,
          recordCount: 3,
        ),
      ],
    );
  }

  final GovernanceOperationsController _governance;
  final List<ReportExportJob> _jobs;

  List<ReportExportJob> get jobs => List.unmodifiable(_jobs);

  List<ReportExportJob> jobsForScope(
    GeographicScope scope, {
    TgcgRole? role,
  }) {
    final jobs = _jobs.where((job) {
      if (!GeographyRegistry.scopeContains(scope, job.scope)) return false;
      if (role == null) return true;
      return canExportKind(
        kind: job.kind,
        role: role,
        userScope: scope,
        targetScope: job.scope,
      );
    }).toList(growable: false)
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    return jobs;
  }

  bool canExportKind({
    required ReportKind kind,
    required TgcgRole role,
    required GeographicScope userScope,
    required GeographicScope targetScope,
  }) {
    if (!TgcgPermissionPolicy.may(
      role,
      userScope,
      TgcgCapability.exportReports,
      targetScope: targetScope,
    )) {
      return false;
    }
    if (!GeographyRegistry.scopeContains(userScope, targetScope)) return false;

    bool allows(TgcgCapability capability) =>
        TgcgPermissionPolicy.allows(role, capability);

    return switch (kind) {
      ReportKind.incidentSummary => allows(TgcgCapability.viewIncidents),
      ReportKind.fieldActivity => allows(TgcgCapability.viewIncidents),
      ReportKind.accreditationReadiness =>
        allows(TgcgCapability.manageMembership) ||
            allows(TgcgCapability.accreditAgents) ||
            allows(TgcgCapability.manageAgentAssignments),
      ReportKind.verifiedCollation => allows(TgcgCapability.viewCollation),
      ReportKind.evidencePackage => allows(TgcgCapability.viewEvidence),
      ReportKind.auditTrail => allows(TgcgCapability.viewAudit),
      ReportKind.syncOutbox =>
        targetScope.level == GeographyLevel.country &&
            allows(TgcgCapability.viewAudit),
    };
  }

  ReportExportJob? requestExport({
    required ReportKind kind,
    required ExportFormat format,
    required GeographicScope targetScope,
    required String actorId,
    required TgcgRole role,
    required GeographicScope userScope,
    int? recordCount,
  }) {
    if (!canExportKind(
      kind: kind,
      role: role,
      userScope: userScope,
      targetScope: targetScope,
    )) {
      return null;
    }

    final job = ReportExportJob(
      id: 'EXP-${(_jobs.length + 1).toString().padLeft(4, '0')}',
      kind: kind,
      format: format,
      scope: targetScope,
      requestedBy: actorId,
      requestedAt: DateTime.now().toUtc(),
      status: ExportJobStatus.queued,
      recordCount: recordCount,
    );
    _jobs.insert(0, job);
    _governance.recordAudit(
      actorId: actorId,
      action: 'report_export_requested',
      entityType: 'report_export',
      entityId: job.id,
      detail:
          '${kind.name} requested as ${format.name.toUpperCase()} for ${targetScope.label}.',
      scope: targetScope,
    );
    notifyListeners();
    return job;
  }

  void markGenerating(String id, {required String actorId}) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    _jobs[index] = _copyJob(
      _jobs[index],
      status: ExportJobStatus.generating,
      clearError: true,
    );
    _governance.recordAudit(
      actorId: actorId,
      action: 'report_export_generating',
      entityType: 'report_export',
      entityId: id,
      detail: 'Export worker accepted the queued report job.',
      scope: _jobs[index].scope,
    );
    notifyListeners();
  }

  void markCompleted(
    String id, {
    required String actorId,
    required String fileName,
    required String contentHash,
  }) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    _jobs[index] = _copyJob(
      _jobs[index],
      status: ExportJobStatus.completed,
      completedAt: DateTime.now().toUtc(),
      fileName: fileName,
      contentHash: contentHash,
      clearError: true,
    );
    _governance.recordAudit(
      actorId: actorId,
      action: 'report_export_completed',
      entityType: 'report_export',
      entityId: id,
      detail: 'Export artifact completed with content hash $contentHash.',
      scope: _jobs[index].scope,
    );
    notifyListeners();
  }

  void markFailed(
    String id, {
    required String actorId,
    required String error,
  }) {
    final index = _jobs.indexWhere((job) => job.id == id);
    if (index < 0) return;
    _jobs[index] = _copyJob(
      _jobs[index],
      status: ExportJobStatus.failed,
      error: error,
    );
    _governance.recordAudit(
      actorId: actorId,
      action: 'report_export_failed',
      entityType: 'report_export',
      entityId: id,
      detail: error,
      scope: _jobs[index].scope,
    );
    notifyListeners();
  }

  static ReportExportJob _copyJob(
    ReportExportJob current, {
    ExportJobStatus? status,
    DateTime? completedAt,
    String? fileName,
    String? contentHash,
    String? error,
    bool clearError = false,
  }) =>
      ReportExportJob(
        id: current.id,
        kind: current.kind,
        format: current.format,
        scope: current.scope,
        requestedBy: current.requestedBy,
        requestedAt: current.requestedAt,
        status: status ?? current.status,
        recordCount: current.recordCount,
        completedAt: completedAt ?? current.completedAt,
        fileName: fileName ?? current.fileName,
        contentHash: contentHash ?? current.contentHash,
        error: clearError ? null : error ?? current.error,
      );
}

class ReportOperations extends InheritedNotifier<ReportOperationsController> {
  const ReportOperations({
    super.key,
    required ReportOperationsController controller,
    required super.child,
  }) : super(notifier: controller);

  static ReportOperationsController of(
    BuildContext context, {
    bool listen = true,
  }) {
    if (listen) {
      final value = context.dependOnInheritedWidgetOfExactType<ReportOperations>();
      assert(value != null, 'ReportOperations is missing above this context.');
      return value!.notifier!;
    }
    final element = context.getElementForInheritedWidgetOfExactType<ReportOperations>();
    final value = element?.widget as ReportOperations?;
    assert(value != null, 'ReportOperations is missing above this context.');
    return value!.notifier!;
  }
}
