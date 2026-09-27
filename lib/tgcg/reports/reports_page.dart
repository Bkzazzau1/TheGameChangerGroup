import 'package:flutter/material.dart';

import '../collation/collation_engine.dart';
import '../domain/models.dart';
import '../field/field_operations_store.dart';
import '../governance/governance_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'report_store.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportKind selectedKind = ReportKind.incidentSummary;
  ReportKind? historyKindFilter;
  ExportJobStatus? historyStatusFilter;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final field = FieldOperations.of(context);
    final membership = MembershipOperations.of(context);
    final results = ResultOperations.of(context);
    final governance = GovernanceOperations.of(context);
    final reportStore = ReportOperations.of(context);
    final scope = session.scope;
    final role = session.role!;

    bool canExport(ReportKind kind) => reportStore.canExportKind(
          kind: kind,
          role: role,
          userScope: scope,
          targetScope: scope,
        );

    final incidents = field.incidentsForScope(scope);
    final fieldReports = field.reportsForScope(scope);
    final agents = membership.agentsForScope(scope);
    final approvedAgents = agents
        .where((agent) => agent.status == AccreditationStatus.approved)
        .toList(growable: false);
    final readyAgents = approvedAgents
        .where(
          (agent) =>
              agent.trainingCompleted &&
              agent.biometricEnrolled &&
              agent.deviceId != null &&
              agent.simFingerprint != null,
        )
        .toList(growable: false);
    final scopedResults = results.submissionsForScope(scope);
    final collation = CollationEngine.prototypeSeed().summarize(
      scope,
      results.submissions,
    );
    final audit = governance.auditForScope(scope);
    final incidentEvidence = incidents.fold<int>(
      0,
      (total, incident) => total + incident.evidence.length,
    );
    final resultEvidence = scopedResults
        .where((submission) => submission.resultForm != null)
        .length;
    final evidenceCount = incidentEvidence + resultEvidence;

    final descriptors = <_ReportDescriptor>[
      _ReportDescriptor(
        kind: ReportKind.incidentSummary,
        title: 'Incident Summary',
        subtitle:
            'Operational incidents, severity, status, ownership and linked evidence.',
        icon: Icons.crisis_alert_outlined,
        recordCount: incidents.length,
        detail:
            '${incidents.where((item) => item.status != IncidentStatus.resolved && item.status != IncidentStatus.closed).length} unresolved incidents',
        formats: const [ExportFormat.pdf, ExportFormat.csv, ExportFormat.json],
        enabled: canExport(ReportKind.incidentSummary),
        tone: TgcgMetricTone.danger,
        previewRows: [
          _PreviewRow('Incidents', '${incidents.length}'),
          _PreviewRow(
            'High / critical',
            '${incidents.where((item) => item.severity == IncidentSeverity.high || item.severity == IncidentSeverity.critical).length}',
          ),
          _PreviewRow('Evidence items', '$incidentEvidence'),
        ],
      ),
      _ReportDescriptor(
        kind: ReportKind.fieldActivity,
        title: 'Field Activity',
        subtitle:
            'Structured reports and operational updates submitted from the field.',
        icon: Icons.dynamic_feed_outlined,
        recordCount: fieldReports.length,
        detail: '${fieldReports.length} structured field reports',
        formats: const [ExportFormat.pdf, ExportFormat.csv, ExportFormat.json],
        enabled: canExport(ReportKind.fieldActivity),
        tone: TgcgMetricTone.info,
        previewRows: [
          _PreviewRow('Field reports', '${fieldReports.length}'),
          _PreviewRow(
            'Verified',
            '${fieldReports.where((item) => item.status == RecordStatus.verified).length}',
          ),
          _PreviewRow(
            'Under review',
            '${fieldReports.where((item) => item.status == RecordStatus.underReview).length}',
          ),
        ],
      ),
      _ReportDescriptor(
        kind: ReportKind.accreditationReadiness,
        title: 'Accreditation & Readiness',
        subtitle:
            'Agent accreditation, assignment, training, identity and device readiness.',
        icon: Icons.badge_outlined,
        recordCount: canExport(ReportKind.accreditationReadiness)
            ? agents.length
            : 0,
        detail: canExport(ReportKind.accreditationReadiness)
            ? '${approvedAgents.length} approved • ${readyAgents.length} operationally ready'
            : 'Additional accreditation permission required',
        formats: const [ExportFormat.pdf, ExportFormat.csv, ExportFormat.json],
        enabled: canExport(ReportKind.accreditationReadiness),
        tone: TgcgMetricTone.success,
        previewRows: canExport(ReportKind.accreditationReadiness)
            ? [
                _PreviewRow('Agents', '${agents.length}'),
                _PreviewRow('Approved', '${approvedAgents.length}'),
                _PreviewRow('Fully ready', '${readyAgents.length}'),
              ]
            : const [],
      ),
      _ReportDescriptor(
        kind: ReportKind.verifiedCollation,
        title: 'Verified Collation',
        subtitle:
            'Unofficial verified-only aggregation with missing-unit and conflict tracking.',
        icon: Icons.account_tree_outlined,
        recordCount: collation.verifiedPollingUnitCount,
        detail:
            '${collation.verifiedPollingUnitCount}/${collation.expectedPollingUnitCount} verified polling units',
        formats: const [ExportFormat.pdf, ExportFormat.csv, ExportFormat.json],
        enabled: canExport(ReportKind.verifiedCollation),
        tone: TgcgMetricTone.warning,
        previewRows: [
          _PreviewRow('Expected PUs', '${collation.expectedPollingUnitCount}'),
          _PreviewRow('Verified included', '${collation.verifiedPollingUnitCount}'),
          _PreviewRow('Missing', '${collation.missingPollingUnitIds.length}'),
          _PreviewRow('Conflicts', '${collation.conflictingPollingUnitIds.length}'),
        ],
      ),
      _ReportDescriptor(
        kind: ReportKind.evidencePackage,
        title: 'Evidence Package',
        subtitle:
            'Incident media and result-form evidence with source IDs and content hashes.',
        icon: Icons.inventory_2_outlined,
        recordCount: evidenceCount,
        detail: '$evidenceCount evidence records',
        formats: const [ExportFormat.zip, ExportFormat.json],
        enabled: canExport(ReportKind.evidencePackage),
        tone: TgcgMetricTone.ai,
        previewRows: [
          _PreviewRow('Incident evidence', '$incidentEvidence'),
          _PreviewRow('Result-form evidence', '$resultEvidence'),
          _PreviewRow('Total evidence', '$evidenceCount'),
        ],
      ),
      _ReportDescriptor(
        kind: ReportKind.auditTrail,
        title: 'Audit Trail',
        subtitle:
            'Operational actions, actors, entities, timestamps and geographic scope.',
        icon: Icons.history_rounded,
        recordCount: canExport(ReportKind.auditTrail) ? audit.length : 0,
        detail: canExport(ReportKind.auditTrail)
            ? '${audit.length} audit events'
            : 'Additional audit permission required',
        formats: const [ExportFormat.csv, ExportFormat.json, ExportFormat.pdf],
        enabled: canExport(ReportKind.auditTrail),
        tone: TgcgMetricTone.neutral,
        previewRows: canExport(ReportKind.auditTrail)
            ? [
                _PreviewRow('Audit events', '${audit.length}'),
                _PreviewRow('Current scope', scope.label),
              ]
            : const [],
      ),
      _ReportDescriptor(
        kind: ReportKind.syncOutbox,
        title: 'Sync Outbox',
        subtitle:
            'Queued, failed and conflicting offline mutations. National/system scope only.',
        icon: Icons.sync_problem_outlined,
        recordCount: canExport(ReportKind.syncOutbox)
            ? governance.outbox.length
            : 0,
        detail: canExport(ReportKind.syncOutbox)
            ? '${governance.pendingOutbox.length} pending mutations'
            : scope.level == GeographyLevel.country
                ? 'Additional audit permission required'
                : 'National/system scope required',
        formats: const [ExportFormat.csv, ExportFormat.json],
        enabled: canExport(ReportKind.syncOutbox),
        tone: TgcgMetricTone.warning,
        previewRows: canExport(ReportKind.syncOutbox)
            ? [
                _PreviewRow('Outbox items', '${governance.outbox.length}'),
                _PreviewRow('Pending', '${governance.pendingOutbox.length}'),
              ]
            : const [],
      ),
    ];

    final selected = descriptors.firstWhere((item) => item.kind == selectedKind);
    final visibleJobs = reportStore.jobsForScope(scope, role: role);
    var history = List<ReportExportJob>.from(visibleJobs);
    if (historyKindFilter != null) {
      history = history
          .where((job) => job.kind == historyKindFilter)
          .toList(growable: false);
    }
    if (historyStatusFilter != null) {
      history = history
          .where((job) => job.status == historyStatusFilter)
          .toList(growable: false);
    }

    final queued = visibleJobs
        .where((job) => job.status == ExportJobStatus.queued)
        .length;
    final generating = visibleJobs
        .where((job) => job.status == ExportJobStatus.generating)
        .length;
    final completed = visibleJobs
        .where((job) => job.status == ExportJobStatus.completed)
        .length;
    final failed = visibleJobs
        .where((job) => job.status == ExportJobStatus.failed)
        .length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'REPORTING & EVIDENCE EXPORTS',
          title: 'Reports & Exports',
          subtitle:
              '${scope.label}: scope-controlled operational reports, verified collation outputs, evidence packages and audit exports.',
          trailing: const TgcgStatusPill(
            label: 'EXPORTS ARE AUDITED',
            color: TgcgColors.primaryMid,
            icon: Icons.verified_user_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(
          reportTypes: descriptors.length,
          queued: queued,
          generating: generating,
          completed: completed,
          failed: failed,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final catalogue = _CataloguePanel(
              descriptors: descriptors,
              selectedKind: selectedKind,
              onSelect: (kind) => setState(() => selectedKind = kind),
            );
            final preview = _ReportPreviewPanel(
              descriptor: selected,
              scope: scope,
              onExport: (format) => _requestExport(
                context,
                selected,
                format,
              ),
            );

            if (constraints.maxWidth < 1080) {
              return Column(
                children: [
                  catalogue,
                  const SizedBox(height: 14),
                  preview,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 390, child: catalogue),
                const SizedBox(width: 14),
                Expanded(child: preview),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _JobHistoryPanel(
          jobs: history,
          kind: historyKindFilter,
          status: historyStatusFilter,
          onKindChanged: (value) => setState(() => historyKindFilter = value),
          onStatusChanged: (value) =>
              setState(() => historyStatusFilter = value),
          onClear: () => setState(() {
            historyKindFilter = null;
            historyStatusFilter = null;
          }),
        ),
        const SizedBox(height: 16),
        const _SafeguardsPanel(),
      ],
    );
  }

  void _requestExport(
    BuildContext context,
    _ReportDescriptor descriptor,
    ExportFormat format,
  ) {
    final session = TgcgSession.of(context, listen: false);
    final store = ReportOperations.of(context, listen: false);
    final job = store.requestExport(
      kind: descriptor.kind,
      format: format,
      targetScope: session.scope,
      actorId:
          session.accessId.isEmpty ? session.operatorName : session.accessId,
      role: session.role!,
      userScope: session.scope,
      recordCount: descriptor.recordCount,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          job == null
              ? 'Export request was not authorized for this report type or scope.'
              : '${job.id} queued. Artifact download remains unavailable until the export worker completes it.',
        ),
      ),
    );
  }
}

class _ReportDescriptor {
  const _ReportDescriptor({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.recordCount,
    required this.detail,
    required this.formats,
    required this.enabled,
    required this.tone,
    required this.previewRows,
  });

  final ReportKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final int recordCount;
  final String detail;
  final List<ExportFormat> formats;
  final bool enabled;
  final TgcgMetricTone tone;
  final List<_PreviewRow> previewRows;
}

class _PreviewRow {
  const _PreviewRow(this.label, this.value);
  final String label;
  final String value;
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.reportTypes,
    required this.queued,
    required this.generating,
    required this.completed,
    required this.failed,
  });

  final int reportTypes;
  final int queued;
  final int generating;
  final int completed;
  final int failed;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1080
              ? 5
              : constraints.maxWidth >= 700
                  ? 3
                  : constraints.maxWidth >= 430
                      ? 2
                      : 1;
          const gap = 12.0;
          final width =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Report types',
                value: '$reportTypes',
                detail: 'Operational report catalogue',
                icon: Icons.description_outlined,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Queued',
                value: '$queued',
                detail: 'Waiting for export worker',
                icon: Icons.schedule_rounded,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Generating',
                value: '$generating',
                detail: 'Worker processing state',
                icon: Icons.autorenew_rounded,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Completed',
                value: '$completed',
                detail: 'Artifact metadata available',
                icon: Icons.task_alt_rounded,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Failed',
                value: '$failed',
                detail: 'Export worker failures',
                icon: Icons.error_outline_rounded,
                tone: TgcgMetricTone.danger,
              ),
            ],
          );
        },
      );
}

class _CataloguePanel extends StatelessWidget {
  const _CataloguePanel({
    required this.descriptors,
    required this.selectedKind,
    required this.onSelect,
  });

  final List<_ReportDescriptor> descriptors;
  final ReportKind selectedKind;
  final ValueChanged<ReportKind> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Report catalogue',
        subtitle:
            'Select a report to preview its current scope, contents and available export formats.',
        child: Column(
          children: descriptors.map((item) {
            final selected = item.kind == selectedKind;
            final tone = tgcgToneColor(item.tone);
            return Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: InkWell(
                onTap: () => onSelect(item.kind),
                borderRadius: BorderRadius.circular(15),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: selected
                        ? tone.withValues(alpha: .065)
                        : TgcgColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: selected
                          ? tone.withValues(alpha: .25)
                          : TgcgColors.border,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 39,
                        height: 39,
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(item.icon, color: tone, size: 20),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              item.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      item.enabled
                          ? TgcgStatusPill(
                              label: '${item.recordCount}',
                              color: tone,
                              compact: true,
                            )
                          : const TgcgStatusPill(
                              label: 'LOCKED',
                              color: TgcgColors.muted,
                              icon: Icons.lock_outline_rounded,
                              compact: true,
                            ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      );
}

class _ReportPreviewPanel extends StatelessWidget {
  const _ReportPreviewPanel({
    required this.descriptor,
    required this.scope,
    required this.onExport,
  });

  final _ReportDescriptor descriptor;
  final GeographicScope scope;
  final ValueChanged<ExportFormat> onExport;

  @override
  Widget build(BuildContext context) {
    final tone = tgcgToneColor(descriptor.tone);
    return TgcgSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  TgcgColors.primaryDark,
                  TgcgColors.primary,
                  tone.withValues(alpha: .88),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(19),
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final titleBlock = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 45,
                          height: 45,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .11),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(
                            descriptor.icon,
                            color: Colors.white,
                            size: 23,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                descriptor.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                scope.label,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: .76),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 13),
                    Text(
                      descriptor.subtitle,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .82),
                        height: 1.45,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
                final count = Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${descriptor.recordCount}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'records in current snapshot',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .68),
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 620) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      titleBlock,
                      const SizedBox(height: 14),
                      Align(alignment: Alignment.centerLeft, child: count),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: 20),
                    count,
                  ],
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Snapshot preview',
                  style: TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 10),
                if (!descriptor.enabled)
                  const _LockedReportNotice()
                else if (descriptor.previewRows.isEmpty)
                  const TgcgEmptyState(
                    icon: Icons.description_outlined,
                    title: 'No preview data available',
                    message:
                        'This report is authorized but the current scope contains no previewable records.',
                  )
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: descriptor.previewRows
                        .map((row) => _PreviewStat(row: row))
                        .toList(),
                  ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 18),
                const Text(
                  'Export formats',
                  style: TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'A request creates an audited export job. Queued does not mean the file has been generated.',
                  style: TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 10.5,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: descriptor.formats
                      .map(
                        (format) => OutlinedButton.icon(
                          onPressed: descriptor.enabled
                              ? () => onExport(format)
                              : null,
                          icon: Icon(_formatIcon(format), size: 17),
                          label: Text(
                            'Queue ${format.name.toUpperCase()}',
                          ),
                        ),
                      )
                      .toList(),
                ),
                if (descriptor.kind == ReportKind.verifiedCollation) ...[
                  const SizedBox(height: 14),
                  const TgcgStatusPill(
                    label: 'UNOFFICIAL FIELD COLLATION',
                    color: TgcgColors.warning,
                    icon: Icons.info_outline_rounded,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedReportNotice extends StatelessWidget {
  const _LockedReportNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TgcgColors.border),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline_rounded, color: TgcgColors.muted),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'This role or geographic scope does not have access to export this report.',
                style: TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

class _PreviewStat extends StatelessWidget {
  const _PreviewStat({required this.row});

  final _PreviewRow row;

  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              row.label,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _JobHistoryPanel extends StatelessWidget {
  const _JobHistoryPanel({
    required this.jobs,
    required this.kind,
    required this.status,
    required this.onKindChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final List<ReportExportJob> jobs;
  final ReportKind? kind;
  final ExportJobStatus? status;
  final ValueChanged<ReportKind?> onKindChanged;
  final ValueChanged<ExportJobStatus?> onStatusChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Export job history',
        subtitle:
            'Track request status, artifact metadata and cryptographic provenance for exports visible to your role and scope.',
        trailing: TgcgStatusPill(
          label: '${jobs.length} VISIBLE',
          color: TgcgColors.info,
          icon: Icons.receipt_long_outlined,
          compact: true,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<ReportKind?>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Report type'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All report types'),
                      ),
                      ...ReportKind.values.map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_kindLabel(value)),
                        ),
                      ),
                    ],
                    onChanged: onKindChanged,
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<ExportJobStatus?>(
                    initialValue: status,
                    decoration: const InputDecoration(labelText: 'Job status'),
                    items: [
                      const DropdownMenuItem(
                        value: null,
                        child: Text('All statuses'),
                      ),
                      ...ExportJobStatus.values.map(
                        (value) => DropdownMenuItem(
                          value: value,
                          child: Text(_label(value.name)),
                        ),
                      ),
                    ],
                    onChanged: onStatusChanged,
                  ),
                ),
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear_rounded),
                  label: const Text('Clear'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (jobs.isEmpty)
              const TgcgEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'No export jobs in this view',
                message:
                    'Change the filters or queue a report export from the catalogue above.',
              )
            else
              ...jobs.map((job) => _JobRow(job: job)),
          ],
        ),
      );
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});

  final ReportExportJob job;

  @override
  Widget build(BuildContext context) {
    final color = _jobColor(job.status);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_jobIcon(job.status), color: color, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${job.id} • ${_kindLabel(job.kind)}',
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    TgcgStatusPill(
                      label: job.status.name.toUpperCase(),
                      color: color,
                      compact: true,
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  '${job.format.name.toUpperCase()} • ${job.scope.label} • ${job.requestedBy}',
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 10.5,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'Requested ${_time(job.requestedAt)}${job.recordCount == null ? '' : ' • ${job.recordCount} records'}',
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 9.5,
                  ),
                ),
                if (job.fileName != null) ...[
                  const SizedBox(height: 8),
                  _ArtifactLine(
                    icon: Icons.insert_drive_file_outlined,
                    label: job.fileName!,
                  ),
                ],
                if (job.contentHash != null) ...[
                  const SizedBox(height: 5),
                  _ArtifactLine(
                    icon: Icons.fingerprint_rounded,
                    label: job.contentHash!,
                  ),
                ],
                if (job.error != null) ...[
                  const SizedBox(height: 7),
                  Text(
                    job.error!,
                    style: const TextStyle(
                      color: TgcgColors.danger,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ArtifactLine extends StatelessWidget {
  const _ArtifactLine({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: TgcgColors.primaryMid),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      );
}

class _SafeguardsPanel extends StatelessWidget {
  const _SafeguardsPanel();

  @override
  Widget build(BuildContext context) => const TgcgSectionCard(
        title: 'Reporting safeguards',
        subtitle:
            'Production export workers and backend APIs must preserve these boundaries.',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Safeguard(
              icon: Icons.fact_check_outlined,
              title: 'Verified-only collation',
              detail:
                  'Submitted, disputed, under-review and conflicting records stay outside verified collation exports.',
            ),
            _Safeguard(
              icon: Icons.fingerprint_rounded,
              title: 'Evidence provenance',
              detail:
                  'Evidence packages retain source record IDs and cryptographic content hashes.',
            ),
            _Safeguard(
              icon: Icons.lock_outline_rounded,
              title: 'Scope authorization',
              detail:
                  'The backend must recheck role and geographic scope before generating any artifact.',
            ),
            _Safeguard(
              icon: Icons.info_outline_rounded,
              title: 'Unofficial results',
              detail:
                  'Operational field and collation exports do not constitute an official result declaration.',
            ),
          ],
        ),
      );
}

class _Safeguard extends StatelessWidget {
  const _Safeguard({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Container(
        width: 280,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: TgcgColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: TgcgColors.primary),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 10.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

IconData _formatIcon(ExportFormat format) => switch (format) {
      ExportFormat.pdf => Icons.picture_as_pdf_outlined,
      ExportFormat.csv => Icons.table_chart_outlined,
      ExportFormat.json => Icons.data_object_rounded,
      ExportFormat.zip => Icons.folder_zip_outlined,
    };

Color _jobColor(ExportJobStatus status) => switch (status) {
      ExportJobStatus.queued => TgcgColors.warning,
      ExportJobStatus.generating => TgcgColors.info,
      ExportJobStatus.completed => TgcgColors.success,
      ExportJobStatus.failed => TgcgColors.danger,
    };

IconData _jobIcon(ExportJobStatus status) => switch (status) {
      ExportJobStatus.queued => Icons.schedule_rounded,
      ExportJobStatus.generating => Icons.autorenew_rounded,
      ExportJobStatus.completed => Icons.task_alt_rounded,
      ExportJobStatus.failed => Icons.error_outline_rounded,
    };

String _kindLabel(ReportKind kind) => switch (kind) {
      ReportKind.incidentSummary => 'Incident Summary',
      ReportKind.fieldActivity => 'Field Activity',
      ReportKind.accreditationReadiness => 'Accreditation & Readiness',
      ReportKind.verifiedCollation => 'Verified Collation',
      ReportKind.evidencePackage => 'Evidence Package',
      ReportKind.auditTrail => 'Audit Trail',
      ReportKind.syncOutbox => 'Sync Outbox',
    };

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

String _time(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
}
