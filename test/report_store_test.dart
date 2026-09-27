import 'package:flutter_test/flutter_test.dart';
import 'package:tgcg_emcop/tgcg/domain/models.dart';
import 'package:tgcg_emcop/tgcg/governance/governance_store.dart';
import 'package:tgcg_emcop/tgcg/reports/report_store.dart';

void main() {
  test('authorized export is queued and audited', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    final beforeAudit = governance.auditEvents.length;

    final job = reports.requestExport(
      kind: ReportKind.incidentSummary,
      format: ExportFormat.pdf,
      targetScope: GeographicScope.nigeria,
      actorId: 'ADMIN-001',
      role: TgcgRole.nationalAdministrator,
      userScope: GeographicScope.nigeria,
      recordCount: 4,
    );

    expect(job, isNotNull);
    expect(job!.status, ExportJobStatus.queued);
    expect(job.recordCount, 4);
    expect(governance.auditEvents.length, beforeAudit + 1);
    expect(governance.auditEvents.first.action, 'report_export_requested');
  });

  test('polling unit agent cannot request privileged report export', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);

    final job = reports.requestExport(
      kind: ReportKind.auditTrail,
      format: ExportFormat.csv,
      targetScope: GeographicScope.nigeria,
      actorId: 'AG-001',
      role: TgcgRole.pollingUnitAgent,
      userScope: GeographicScope.nigeria,
    );

    expect(job, isNull);
  });

  test('report type requires its underlying capability', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);

    final auditJob = reports.requestExport(
      kind: ReportKind.auditTrail,
      format: ExportFormat.csv,
      targetScope: GeographicScope.nigeria,
      actorId: 'STATE-001',
      role: TgcgRole.stateCoordinator,
      userScope: GeographicScope.nigeria,
    );
    final incidentJob = reports.requestExport(
      kind: ReportKind.incidentSummary,
      format: ExportFormat.pdf,
      targetScope: GeographicScope.nigeria,
      actorId: 'STATE-001',
      role: TgcgRole.stateCoordinator,
      userScope: GeographicScope.nigeria,
    );

    expect(auditJob, isNull);
    expect(incidentJob, isNotNull);
  });

  test('export target cannot escape operator geographic scope', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    const kaduna = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
    );
    const lagos = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'SW',
      zoneName: 'South West',
      stateId: 'LA',
      stateName: 'Lagos',
    );

    final job = reports.requestExport(
      kind: ReportKind.fieldActivity,
      format: ExportFormat.csv,
      targetScope: lagos,
      actorId: 'ADMIN-KD',
      role: TgcgRole.nationalAdministrator,
      userScope: kaduna,
    );

    expect(job, isNull);
  });

  test('scoped export history does not expose broader national jobs', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    const kaduna = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
    );

    expect(reports.jobsForScope(kaduna), isEmpty);

    final job = reports.requestExport(
      kind: ReportKind.incidentSummary,
      format: ExportFormat.pdf,
      targetScope: kaduna,
      actorId: 'ADMIN-KD',
      role: TgcgRole.nationalAdministrator,
      userScope: kaduna,
    );

    expect(job, isNotNull);
    expect(reports.jobsForScope(kaduna).map((item) => item.id), contains(job!.id));
  });

  test('history hides report kinds the viewer cannot access', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    const kaduna = GeographicScope(
      level: GeographyLevel.state,
      country: 'Nigeria',
      zoneId: 'NW',
      zoneName: 'North West',
      stateId: 'KD',
      stateName: 'Kaduna',
    );

    final auditJob = reports.requestExport(
      kind: ReportKind.auditTrail,
      format: ExportFormat.csv,
      targetScope: kaduna,
      actorId: 'ADMIN-001',
      role: TgcgRole.nationalAdministrator,
      userScope: GeographicScope.nigeria,
    );
    final incidentJob = reports.requestExport(
      kind: ReportKind.incidentSummary,
      format: ExportFormat.pdf,
      targetScope: kaduna,
      actorId: 'ADMIN-001',
      role: TgcgRole.nationalAdministrator,
      userScope: GeographicScope.nigeria,
    );

    expect(auditJob, isNotNull);
    expect(incidentJob, isNotNull);

    final visible = reports.jobsForScope(
      kaduna,
      role: TgcgRole.stateCoordinator,
    );

    expect(visible.map((job) => job.id), contains(incidentJob!.id));
    expect(visible.map((job) => job.id), isNot(contains(auditJob!.id)));
  });

  test('job lifecycle retains artifact provenance and creates audit events', () {
    final governance = GovernanceOperationsController.prototypeSeed();
    final reports = ReportOperationsController.prototypeSeed(governance);
    final job = reports.requestExport(
      kind: ReportKind.evidencePackage,
      format: ExportFormat.zip,
      targetScope: GeographicScope.nigeria,
      actorId: 'LEGAL-001',
      role: TgcgRole.nationalAdministrator,
      userScope: GeographicScope.nigeria,
      recordCount: 3,
    )!;

    reports.markFailed(
      job.id,
      actorId: 'WORKER-01',
      error: 'Prototype worker failure.',
    );
    expect(reports.jobs.first.error, 'Prototype worker failure.');

    reports.markGenerating(job.id, actorId: 'WORKER-01');
    expect(reports.jobs.first.status, ExportJobStatus.generating);
    expect(reports.jobs.first.error, isNull);

    reports.markCompleted(
      job.id,
      actorId: 'WORKER-01',
      fileName: 'evidence-package.zip',
      contentHash: 'sha256:test-hash',
    );

    final completed = reports.jobs.first;
    expect(completed.status, ExportJobStatus.completed);
    expect(completed.fileName, 'evidence-package.zip');
    expect(completed.contentHash, 'sha256:test-hash');
    expect(completed.error, isNull);
    expect(
      governance.auditEvents.any((event) => event.action == 'report_export_completed'),
      isTrue,
    );
  });
}
