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

    reports.markGenerating(job.id, actorId: 'WORKER-01');
    expect(reports.jobs.first.status, ExportJobStatus.generating);

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
    expect(
      governance.auditEvents.any((event) => event.action == 'report_export_completed'),
      isTrue,
    );
  });
}
