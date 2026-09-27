import 'package:flutter/material.dart';

import '../app.dart';
import '../collation/collation_engine.dart';
import '../domain/models.dart';
import '../field/field_operations_store.dart';
import '../governance/governance_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import 'report_store.dart';

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  ReportKind? kindFilter;
  ExportJobStatus? statusFilter;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final field = FieldOperations.of(context);
    final membership = MembershipOperations.of(context);
    final results = ResultOperations.of(context);
    final governance = GovernanceOperations.of(context);
    final reports = ReportOperations.of(context);
    final scope = session.scope;

    final incidents = field.incidentsForScope(scope);
    final fieldReports = field.reportsForScope(scope);
    final agents = membership.agentsForScope(scope);
    final approvedAgents = agents
        .where((agent) => agent.status == AccreditationStatus.approved)
        .toList(growable: false);
    final readyAgents = approvedAgents
        .where((agent) =>
            agent.trainingCompleted &&
            agent.biometricEnrolled &&
            agent.deviceId != null)
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

    final catalogue = <_ReportDescriptor>[
      _ReportDescriptor(
        kind: ReportKind.incidentSummary,
        title: 'Incident summary',
        subtitle:
            'Operational incidents, severity, status, assignment and linked evidence.',
        icon: Icons.warning_amber_rounded,
        recordCount: incidents.length,
        detail:
            '${incidents.where((i) => i.status != IncidentStatus.resolved && i.status != IncidentStatus.closed).length} unresolved',
        formats: const [ExportFormat.pdf, ExportFormat.csv, ExportFormat.json],
      ),
      _ReportDescriptor(
        kind: ReportKind.fieldActivity,
        title: 'Field activity',
        subtitle:
            'Structured field reports and operational updates within the current scope.',
        icon: Icons.feed_outlined,
        recordCount: fieldReports.length,
        detail: '${fieldReports.length} structured reports',
        formats: const [ExportFormat.pdf, ExportFormat.csv, ExportFormat.json],
      ),
      _ReportDescriptor(
        kind: ReportKind.accreditationReadiness,
        title: 'Accreditation & readiness',
        subtitle:
            'Agent accreditation, assignment, training and device-readiness status.',
        icon: Icons.badge_outlined,
        recordCount: agents.length,
        detail:
            '${approvedAgents.length} approved • ${readyAgents.length} ready',
        formats: const [ExportFormat.pdf, ExportFormat.csv, ExportFormat.json],
      ),
      _ReportDescriptor(
        kind: ReportKind.verifiedCollation,
        title: 'Verified collation',
        subtitle:
            'Unofficial verified-only aggregation with missing-unit and conflict tracking.',
        icon: Icons.account_tree_outlined,
        recordCount: collation.verifiedPollingUnitCount,
        detail:
            '${collation.verifiedPollingUnitCount}/${collation.expectedPollingUnitCount} verified PUs',
        formats: const [ExportFormat.pdf, ExportFormat.csv, ExportFormat.json],
      ),
      _ReportDescriptor(
        kind: ReportKind.evidencePackage,
        title: 'Evidence package',
        subtitle:
            'Linked incident media and result-form evidence with provenance metadata.',
        icon: Icons.inventory_2_outlined,
        recordCount: evidenceCount,
        detail: '$evidenceCount evidence records',
        formats: const [ExportFormat.zip, ExportFormat.json],
      ),
      _ReportDescriptor(
        kind: ReportKind.auditTrail,
        title: 'Audit trail',
        subtitle:
            'Append-style operational actions, actors, entities, scope and timestamps.',
        icon: Icons.history_rounded,
        recordCount: audit.length,
        detail: '${audit.length} audit events',
        formats: const [ExportFormat.csv, ExportFormat.json, ExportFormat.pdf],
      ),
      _ReportDescriptor(
        kind: ReportKind.syncOutbox,
        title: 'Sync outbox',
        subtitle:
            'Queued, failed and conflicting offline mutations. National/system scope only.',
        icon: Icons.sync_problem_outlined,
        recordCount: scope.level == GeographyLevel.country
            ? governance.outbox.length
            : 0,
        detail: scope.level == GeographyLevel.country
            ? '${governance.pendingOutbox.length} pending items'
            : 'Scope metadata required for narrower export',
        formats: const [ExportFormat.csv, ExportFormat.json],
        enabled: scope.level == GeographyLevel.country,
      ),
    ];

    var history = reports.jobsForScope(scope);
    if (kindFilter != null) {
      history = history.where((job) => job.kind == kindFilter).toList();
    }
    if (statusFilter != null) {
      history = history.where((job) => job.status == statusFilter).toList();
    }

    final queued = reports
        .jobsForScope(scope)
        .where((job) => job.status == ExportJobStatus.queued)
        .length;
    final completed = reports
        .jobsForScope(scope)
        .where((job) => job.status == ExportJobStatus.completed)
        .length;

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Reports & Exports',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: TgcgApp.ink,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${scope.label}: operational summaries, evidence packages, audit exports and verified collation reports.',
                    style: const TextStyle(color: TgcgApp.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const _Badge(
              label: 'EXPORTS ARE AUDITED',
              icon: Icons.verified_user_outlined,
              color: Color(0xFF305F52),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric('Report types', '${catalogue.length}', Icons.description_outlined),
            _Metric('Queued exports', '$queued', Icons.schedule_rounded),
            _Metric('Completed exports', '$completed', Icons.task_alt_rounded),
            _Metric('Evidence records', '$evidenceCount', Icons.attach_file_rounded),
          ],
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Report catalogue',
          subtitle:
              'Counts come from the shared operational stores. New exports remain queued until a backend worker generates an artifact.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: catalogue
                .map(
                  (descriptor) => _ReportCard(
                    descriptor: descriptor,
                    onExport: (format) => _requestExport(
                      context,
                      descriptor,
                      format,
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Export job history',
          subtitle:
              'Completed artifact metadata is historical prototype data; newly requested jobs stay queued until worker integration.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Filters(
                kind: kindFilter,
                status: statusFilter,
                onKindChanged: (value) => setState(() => kindFilter = value),
                onStatusChanged: (value) => setState(() => statusFilter = value),
                onClear: () => setState(() {
                  kindFilter = null;
                  statusFilter = null;
                }),
              ),
              const SizedBox(height: 14),
              if (history.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No export jobs match the selected filters.')),
                )
              else
                ...history.map((job) => _JobRow(job: job)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _Panel(
          title: 'Reporting safeguards',
          subtitle: 'Production export workers must preserve these guarantees.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Safeguard(
                icon: Icons.fact_check_outlined,
                title: 'Verified-only collation',
                detail:
                    'Collation reports must exclude submitted, disputed, under-review and reconciliation-conflict records.',
              ),
              _Safeguard(
                icon: Icons.fingerprint_rounded,
                title: 'Evidence provenance',
                detail:
                    'Evidence packages should retain source record IDs and cryptographic content hashes.',
              ),
              _Safeguard(
                icon: Icons.lock_outline_rounded,
                title: 'Scope enforcement',
                detail:
                    'Export authorization must be rechecked server-side; Flutter visibility is not an authorization boundary.',
              ),
              _Safeguard(
                icon: Icons.info_outline_rounded,
                title: 'Unofficial result data',
                detail:
                    'Field and collation outputs remain operational/unofficial until legally authorized declaration.',
              ),
            ],
          ),
        ),
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
      actorId: session.accessId.isEmpty ? session.operatorName : session.accessId,
      role: session.role!,
      userScope: session.scope,
      recordCount: descriptor.recordCount,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          job == null
              ? 'Export request was not authorized for this role or scope.'
              : '${job.id} queued. No download is shown until a worker completes the artifact.',
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
    this.enabled = true,
  });

  final ReportKind kind;
  final String title;
  final String subtitle;
  final IconData icon;
  final int recordCount;
  final String detail;
  final List<ExportFormat> formats;
  final bool enabled;
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.descriptor,
    required this.onExport,
  });

  final _ReportDescriptor descriptor;
  final ValueChanged<ExportFormat> onExport;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 340,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAF9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1E8E5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: TgcgApp.primary.withValues(alpha: .08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(descriptor.icon, color: TgcgApp.primary),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      descriptor.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: TgcgApp.ink,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              Text(
                descriptor.subtitle,
                style: const TextStyle(color: TgcgApp.muted, height: 1.4),
              ),
              const SizedBox(height: 12),
              Text(
                '${descriptor.recordCount}',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: TgcgApp.ink,
                ),
              ),
              Text(
                descriptor.detail,
                style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
              ),
              const SizedBox(height: 13),
              Align(
                alignment: Alignment.centerRight,
                child: PopupMenuButton<ExportFormat>(
                  enabled: descriptor.enabled,
                  onSelected: onExport,
                  itemBuilder: (_) => descriptor.formats
                      .map(
                        (format) => PopupMenuItem(
                          value: format,
                          child: Text('Queue ${format.name.toUpperCase()} export'),
                        ),
                      )
                      .toList(),
                  child: IgnorePointer(
                    child: OutlinedButton.icon(
                      onPressed: descriptor.enabled ? () {} : null,
                      icon: const Icon(Icons.file_download_outlined),
                      label: Text(descriptor.enabled ? 'Export' : 'Unavailable'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.kind,
    required this.status,
    required this.onKindChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final ReportKind? kind;
  final ExportJobStatus? status;
  final ValueChanged<ReportKind?> onKindChanged;
  final ValueChanged<ExportJobStatus?> onStatusChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 230,
            child: DropdownButtonFormField<ReportKind?>(
              initialValue: kind,
              decoration: const InputDecoration(labelText: 'Report type'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All report types')),
                ...ReportKind.values.map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_label(value.name)),
                  ),
                ),
              ],
              onChanged: onKindChanged,
            ),
          ),
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<ExportJobStatus?>(
              initialValue: status,
              decoration: const InputDecoration(labelText: 'Job status'),
              items: [
                const DropdownMenuItem(value: null, child: Text('All statuses')),
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
      );
}

class _JobRow extends StatelessWidget {
  const _JobRow({required this.job});

  final ReportExportJob job;

  @override
  Widget build(BuildContext context) {
    final color = switch (job.status) {
      ExportJobStatus.queued => const Color(0xFF7A5A10),
      ExportJobStatus.generating => const Color(0xFF2563EB),
      ExportJobStatus.completed => const Color(0xFF18794E),
      ExportJobStatus.failed => const Color(0xFFB42318),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFE2E8E5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.description_outlined, color: color),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job.id} • ${_label(job.kind.name)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: TgcgApp.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${job.format.name.toUpperCase()} • ${job.scope.label} • requested by ${job.requestedBy}',
                  style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                ),
                if (job.recordCount != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${job.recordCount} source records',
                    style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                  ),
                ],
                if (job.fileName != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    '${job.fileName} • ${job.contentHash ?? 'hash unavailable'}',
                    style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                  ),
                ],
                if (job.error != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    job.error!,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFFB42318)),
                  ),
                ],
              ],
            ),
          ),
          _Pill(_label(job.status.name), color),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 210,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: TgcgApp.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: TgcgApp.ink,
                        ),
                      ),
                      Text(
                        label,
                        style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: TgcgApp.ink,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: TgcgApp.muted),
              ),
              const SizedBox(height: 15),
              child,
            ],
          ),
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
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: TgcgApp.primary, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: TgcgApp.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: const TextStyle(color: TgcgApp.muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .22)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .4,
              ),
            ),
          ],
        ),
      );
}

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
