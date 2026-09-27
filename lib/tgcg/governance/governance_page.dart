import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../domain/permissions.dart';
import '../field/field_operations_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../sync/sync_models.dart';
import '../ui/tgcg_design.dart';
import 'governance_store.dart';

class GovernancePage extends StatefulWidget {
  const GovernancePage({super.key});

  @override
  State<GovernancePage> createState() => _GovernancePageState();
}

class _GovernancePageState extends State<GovernancePage> {
  String auditSearch = '';
  SyncState? syncFilter;
  SystemSettingCategory? settingFilter;
  String? selectedOutboxId;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final governance = GovernanceOperations.of(context);
    final membership = MembershipOperations.of(context);
    final results = ResultOperations.of(context);
    final field = FieldOperations.of(context);
    final role = session.role!;

    final mayManageSettings = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.manageSystemSettings,
    );
    final mayViewAudit = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.viewAudit,
    );
    final mayViewEvidence = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.viewEvidence,
    );

    final scopedAgents = membership.agentsForScope(session.scope);
    final scopedResults = results.submissionsForScope(session.scope);
    final scopedIncidents = field.incidentsForScope(session.scope);
    final scopedReports = field.reportsForScope(session.scope);
    final auditAll = mayViewAudit
        ? governance.auditForScope(session.scope)
        : const <AuditEvent>[];

    var auditEvents = List<AuditEvent>.from(auditAll);
    final auditQuery = auditSearch.trim().toLowerCase();
    if (auditQuery.isNotEmpty) {
      auditEvents = auditEvents
          .where(
            (event) =>
                event.action.toLowerCase().contains(auditQuery) ||
                event.actorId.toLowerCase().contains(auditQuery) ||
                event.entityType.toLowerCase().contains(auditQuery) ||
                event.entityId.toLowerCase().contains(auditQuery) ||
                (event.detail ?? '').toLowerCase().contains(auditQuery),
          )
          .toList(growable: false);
    }

    var outbox = mayViewAudit || mayManageSettings
        ? List<SyncOutboxItem>.from(governance.outbox)
        : const <SyncOutboxItem>[];
    if (syncFilter != null) {
      outbox = outbox
          .where((item) => item.state == syncFilter)
          .toList(growable: false);
    }

    if (outbox.isNotEmpty &&
        !outbox.any((item) => item.id == selectedOutboxId)) {
      selectedOutboxId = outbox.first.id;
    }
    final selectedOutbox = selectedOutboxId == null
        ? null
        : outbox.where((item) => item.id == selectedOutboxId).firstOrNull;

    var settings = governance.settings;
    if (settingFilter != null) {
      settings = settings
          .where((item) => item.category == settingFilter)
          .toList(growable: false);
    }

    final queued = governance.outbox
        .where((item) => item.state == SyncState.queued)
        .length;
    final syncing = governance.outbox
        .where((item) => item.state == SyncState.syncing)
        .length;
    final failed = governance.outbox
        .where((item) => item.state == SyncState.failed)
        .length;
    final conflicts = governance.outbox
        .where((item) => item.state == SyncState.conflict)
        .length;
    final enabledSafeguards = governance.settings.where((item) => item.value).length;

    final incidentEvidence = scopedIncidents.fold<int>(
      0,
      (total, incident) => total + incident.evidence.length,
    );
    final resultEvidence = scopedResults
        .where((submission) => submission.resultForm != null)
        .length;
    final evidenceCount = incidentEvidence + resultEvidence;
    final hashTrackedEvidence = scopedIncidents.fold<int>(
          0,
          (total, incident) =>
              total +
              incident.evidence
                  .where((item) => item.contentHash.trim().isNotEmpty)
                  .length,
        ) +
        scopedResults.where((submission) {
          final form = submission.resultForm;
          return form != null && form.contentHash.trim().isNotEmpty;
        }).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'CONTROL & ASSURANCE',
          title: 'Data, Audit & Governance',
          subtitle:
              '${session.scope.label}: sync integrity, evidence provenance, immutable-event visibility and privileged system safeguards.',
          trailing: TgcgStatusPill(
            label: failed > 0 || conflicts > 0
                ? 'ATTENTION REQUIRED'
                : 'CONTROL STATE HEALTHY',
            color: failed > 0 || conflicts > 0
                ? TgcgColors.warning
                : TgcgColors.success,
            icon: failed > 0 || conflicts > 0
                ? Icons.gpp_maybe_outlined
                : Icons.verified_user_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(
          auditCount: mayViewAudit ? auditAll.length : null,
          queued: queued,
          syncing: syncing,
          failed: failed,
          conflicts: conflicts,
          safeguardCount: enabledSafeguards,
          totalSafeguards: governance.settings.length,
        ),
        const SizedBox(height: 16),
        _GovernanceSummary(
          agentCount: scopedAgents.length,
          incidentCount: scopedIncidents.length,
          reportCount: scopedReports.length,
          resultCount: scopedResults.length,
          evidenceCount: mayViewEvidence ? evidenceCount : null,
          hashTrackedEvidence: mayViewEvidence ? hashTrackedEvidence : null,
          pendingOutbox: governance.pendingOutbox.length,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final queue = _OutboxPanel(
              items: outbox,
              selectedId: selectedOutboxId,
              filter: syncFilter,
              canView: mayViewAudit || mayManageSettings,
              onFilterChanged: (value) => setState(() => syncFilter = value),
              onSelect: (id) => setState(() => selectedOutboxId = id),
            );
            final inspector = _OutboxInspector(
              item: selectedOutbox,
              canRetry: mayManageSettings,
              onRetry: selectedOutbox == null
                  ? null
                  : () {
                      governance.queueForRetry(
                        selectedOutbox.id,
                        actorId: session.accessId.isEmpty
                            ? session.operatorName
                            : session.accessId,
                      );
                    },
            );

            if (constraints.maxWidth < 1030) {
              return Column(
                children: [
                  queue,
                  const SizedBox(height: 14),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: queue),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: inspector),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final evidence = _EvidenceIntegrityPanel(
              allowed: mayViewEvidence,
              evidenceCount: evidenceCount,
              hashTracked: hashTrackedEvidence,
              resultEvidence: resultEvidence,
              incidentEvidence: incidentEvidence,
            );
            final safeguards = _SafeguardsPanel(
              settings: settings,
              filter: settingFilter,
              canManage: mayManageSettings,
              onFilterChanged: (value) =>
                  setState(() => settingFilter = value),
              onChanged: (setting, value) => governance.setSetting(
                settingId: setting.id,
                value: value,
                actorId: session.accessId.isEmpty
                    ? session.operatorName
                    : session.accessId,
              ),
            );
            if (constraints.maxWidth < 1030) {
              return Column(
                children: [
                  evidence,
                  const SizedBox(height: 14),
                  safeguards,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: evidence),
                const SizedBox(width: 14),
                Expanded(flex: 6, child: safeguards),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _DataProvenancePanel(
          agentCount: scopedAgents.length,
          incidentCount: scopedIncidents.length,
          reportCount: scopedReports.length,
          resultCount: scopedResults.length,
          evidenceCount: mayViewEvidence ? evidenceCount : null,
        ),
        const SizedBox(height: 16),
        if (mayViewAudit)
          _AuditTimeline(
            events: auditEvents,
            search: auditSearch,
            onSearchChanged: (value) => setState(() => auditSearch = value),
          )
        else
          const _AccessRestricted(
            icon: Icons.history_toggle_off_outlined,
            title: 'Audit trail restricted',
            message:
                'This role does not have audit visibility. Server-side authorization must enforce the same boundary.',
          ),
      ],
    );
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.auditCount,
    required this.queued,
    required this.syncing,
    required this.failed,
    required this.conflicts,
    required this.safeguardCount,
    required this.totalSafeguards,
  });

  final int? auditCount;
  final int queued;
  final int syncing;
  final int failed;
  final int conflicts;
  final int safeguardCount;
  final int totalSafeguards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1180
              ? 6
              : constraints.maxWidth >= 760
                  ? 3
                  : constraints.maxWidth >= 440
                      ? 2
                      : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Audit events',
                value: auditCount?.toString() ?? '—',
                detail: auditCount == null
                    ? 'Audit permission required'
                    : 'Visible in current scope',
                icon: Icons.history_rounded,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Queued',
                value: '$queued',
                detail: 'Waiting for server attempt',
                icon: Icons.schedule_rounded,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Syncing',
                value: '$syncing',
                detail: 'Currently in transmission',
                icon: Icons.sync_rounded,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Failed',
                value: '$failed',
                detail: 'Retryable delivery failures',
                icon: Icons.error_outline_rounded,
                tone: failed > 0 ? TgcgMetricTone.danger : TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Conflicts',
                value: '$conflicts',
                detail: 'Version/reconciliation attention',
                icon: Icons.merge_type_rounded,
                tone: conflicts > 0 ? TgcgMetricTone.ai : TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Safeguards enabled',
                value: '$safeguardCount/$totalSafeguards',
                detail: 'Configured prototype controls',
                icon: Icons.admin_panel_settings_outlined,
                tone: TgcgMetricTone.success,
              ),
            ],
          );
        },
      );
}

class _GovernanceSummary extends StatelessWidget {
  const _GovernanceSummary({
    required this.agentCount,
    required this.incidentCount,
    required this.reportCount,
    required this.resultCount,
    required this.evidenceCount,
    required this.hashTrackedEvidence,
    required this.pendingOutbox,
  });

  final int agentCount;
  final int incidentCount;
  final int reportCount;
  final int resultCount;
  final int? evidenceCount;
  final int? hashTrackedEvidence;
  final int pendingOutbox;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: TgcgColors.primaryDark,
          borderRadius: BorderRadius.circular(20),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final summary = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'CONTROL SNAPSHOT',
                  style: TextStyle(
                    color: TgcgColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Operational data remains locally usable while synchronization is pending.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Queued does not mean synced. Synced does not mean verified, approved, published or legally declared.',
                  style: TextStyle(
                    color: Color(0xFFC6D3CF),
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            );
            final stats = Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                _DarkStat('Agents', '$agentCount'),
                _DarkStat('Incidents', '$incidentCount'),
                _DarkStat('Field reports', '$reportCount'),
                _DarkStat('Results', '$resultCount'),
                _DarkStat(
                  'Evidence hashes',
                  evidenceCount == null
                      ? 'Restricted'
                      : '$hashTrackedEvidence/$evidenceCount',
                ),
                _DarkStat('Pending outbox', '$pendingOutbox'),
              ],
            );
            if (constraints.maxWidth < 860) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  summary,
                  const SizedBox(height: 16),
                  stats,
                ],
              );
            }
            return Row(
              children: [
                Expanded(flex: 6, child: summary),
                const SizedBox(width: 24),
                Expanded(flex: 5, child: stats),
              ],
            );
          },
        ),
      );
}

class _DarkStat extends StatelessWidget {
  const _DarkStat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Colors.white.withValues(alpha: .09)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9FB1AB),
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
}

class _OutboxPanel extends StatelessWidget {
  const _OutboxPanel({
    required this.items,
    required this.selectedId,
    required this.filter,
    required this.canView,
    required this.onFilterChanged,
    required this.onSelect,
  });

  final List<SyncOutboxItem> items;
  final String? selectedId;
  final SyncState? filter;
  final bool canView;
  final ValueChanged<SyncState?> onFilterChanged;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Durable sync outbox',
        subtitle:
            'Each mutation keeps its own version and state until the server acknowledges or a conflict is resolved.',
        trailing: SizedBox(
          width: 170,
          child: DropdownButtonFormField<SyncState?>(
            initialValue: filter,
            decoration: const InputDecoration(labelText: 'State'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All states')),
              ...SyncState.values.map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_label(value.name)),
                ),
              ),
            ],
            onChanged: canView ? onFilterChanged : null,
          ),
        ),
        child: !canView
            ? const _AccessRestricted(
                icon: Icons.lock_outline_rounded,
                title: 'Sync records restricted',
                message: 'Audit or system-management access is required.',
                embedded: true,
              )
            : items.isEmpty
                ? const TgcgEmptyState(
                    icon: Icons.cloud_done_outlined,
                    title: 'No outbox item in this view',
                    message: 'Change the state filter to inspect other mutations.',
                  )
                : Column(
                    children: items.map((item) {
                      final selected = item.id == selectedId;
                      final color = _syncColor(item.state);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: InkWell(
                          onTap: () => onSelect(item.id),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(13),
                            decoration: BoxDecoration(
                              color: selected
                                  ? color.withValues(alpha: .055)
                                  : TgcgColors.surfaceSoft,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: selected
                                    ? color.withValues(alpha: .24)
                                    : TgcgColors.border,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 39,
                                  height: 39,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: .09),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Icon(
                                    _syncIcon(item.state),
                                    color: color,
                                    size: 19,
                                  ),
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${item.entityType} • ${item.entityId}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: TgcgColors.ink,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        '${_label(item.mutationType.name)} • v${item.mutationVersion} • ${item.attemptCount} attempts',
                                        style: const TextStyle(
                                          color: TgcgColors.muted,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                TgcgStatusPill(
                                  label: _label(item.state.name).toUpperCase(),
                                  color: color,
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

class _OutboxInspector extends StatelessWidget {
  const _OutboxInspector({
    required this.item,
    required this.canRetry,
    required this.onRetry,
  });

  final SyncOutboxItem? item;
  final bool canRetry;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (item == null) {
      return const TgcgSectionCard(
        title: 'Mutation inspector',
        subtitle: 'Select an outbox record to inspect its lifecycle.',
        child: TgcgEmptyState(
          icon: Icons.storage_outlined,
          title: 'No mutation selected',
          message: 'Choose an outbox record from the queue.',
        ),
      );
    }

    final current = item!;
    final color = _syncColor(current.state);
    final retryable = current.state == SyncState.failed ||
        current.state == SyncState.conflict;
    return TgcgSectionCard(
      title: 'Mutation inspector',
      subtitle: 'Sync state is transport state only; it does not imply workflow approval.',
      trailing: TgcgStatusPill(
        label: _label(current.state.name).toUpperCase(),
        color: color,
        icon: _syncIcon(current.state),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withValues(alpha: .16)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  current.id,
                  style: const TextStyle(
                    fontSize: 19,
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${current.entityType}/${current.entityId}',
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _DetailRow('Mutation', _label(current.mutationType.name)),
          _DetailRow('Mutation version', '${current.mutationVersion}'),
          _DetailRow('Attempt count', '${current.attemptCount}'),
          _DetailRow('Created', _time(current.createdAt)),
          _DetailRow(
            'Last attempt',
            current.lastAttemptAt == null ? 'Not attempted' : _time(current.lastAttemptAt!),
          ),
          if (current.lastError != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TgcgColors.danger.withValues(alpha: .055),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: TgcgColors.danger.withValues(alpha: .16),
                ),
              ),
              child: Text(
                current.lastError!,
                style: const TextStyle(
                  color: TgcgColors.danger,
                  fontSize: 10.5,
                  height: 1.4,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
          if (retryable) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canRetry ? onRetry : null,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  canRetry
                      ? 'Return to retry queue'
                      : 'System-management permission required',
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Payload bodies are intentionally not rendered in the governance UI. Production debugging should use protected server tooling with least-privilege access.',
            style: TextStyle(
              color: TgcgColors.muted,
              fontSize: 10,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceIntegrityPanel extends StatelessWidget {
  const _EvidenceIntegrityPanel({
    required this.allowed,
    required this.evidenceCount,
    required this.hashTracked,
    required this.resultEvidence,
    required this.incidentEvidence,
  });

  final bool allowed;
  final int evidenceCount;
  final int hashTracked;
  final int resultEvidence;
  final int incidentEvidence;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Evidence integrity',
        subtitle:
            'Evidence metadata stays separate from operational records and retains cryptographic provenance references.',
        trailing: allowed
            ? TgcgStatusPill(
                label: evidenceCount == 0
                    ? 'NO EVIDENCE IN SCOPE'
                    : hashTracked == evidenceCount
                        ? 'HASH TRACKED'
                        : 'REVIEW HASH COVERAGE',
                color: evidenceCount == 0 || hashTracked == evidenceCount
                    ? TgcgColors.success
                    : TgcgColors.warning,
                icon: Icons.fingerprint_rounded,
                compact: true,
              )
            : const TgcgStatusPill(
                label: 'RESTRICTED',
                color: TgcgColors.muted,
                icon: Icons.lock_outline_rounded,
                compact: true,
              ),
        child: !allowed
            ? const _AccessRestricted(
                icon: Icons.inventory_2_outlined,
                title: 'Evidence metadata restricted',
                message: 'Evidence-view permission is required for this panel.',
                embedded: true,
              )
            : Column(
                children: [
                  _ProgressLine(
                    label: 'Hash coverage',
                    value: evidenceCount == 0 ? 1 : hashTracked / evidenceCount,
                    detail: '$hashTracked of $evidenceCount evidence records',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _EvidenceStat(
                          label: 'Incident evidence',
                          value: '$incidentEvidence',
                          icon: Icons.warning_amber_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _EvidenceStat(
                          label: 'Result forms',
                          value: '$resultEvidence',
                          icon: Icons.document_scanner_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const _IntegrityStatement(
                    icon: Icons.lock_outline_rounded,
                    title: 'Original evidence preserved',
                    detail:
                        'AI/OCR-derived values must never replace original source media or its provenance reference.',
                  ),
                  const _IntegrityStatement(
                    icon: Icons.visibility_off_outlined,
                    title: 'No raw biometrics here',
                    detail:
                        'This governance surface does not expose face templates or other raw biometric material.',
                  ),
                ],
              ),
      );
}

class _EvidenceStat extends StatelessWidget {
  const _EvidenceStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: TgcgColors.primary, size: 19),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    required this.detail,
  });

  final String label;
  final double value;
  final String detail;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '${(value.clamp(0.0, 1.0) * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  color: TgcgColors.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          LinearProgressIndicator(
            value: value.clamp(0.0, 1.0),
            minHeight: 8,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: TgcgColors.border,
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
          ),
        ],
      );
}

class _IntegrityStatement extends StatelessWidget {
  const _IntegrityStatement({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: TgcgColors.primary, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10,
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

class _SafeguardsPanel extends StatelessWidget {
  const _SafeguardsPanel({
    required this.settings,
    required this.filter,
    required this.canManage,
    required this.onFilterChanged,
    required this.onChanged,
  });

  final List<SystemSettingRecord> settings;
  final SystemSettingCategory? filter;
  final bool canManage;
  final ValueChanged<SystemSettingCategory?> onFilterChanged;
  final void Function(SystemSettingRecord, bool) onChanged;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'System safeguards',
        subtitle: canManage
            ? 'Privileged prototype controls. Production enforcement still belongs on the server.'
            : 'Read-only configuration view; changes require system-management permission.',
        trailing: SizedBox(
          width: 185,
          child: DropdownButtonFormField<SystemSettingCategory?>(
            initialValue: filter,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All categories')),
              ...SystemSettingCategory.values.map(
                (value) => DropdownMenuItem(
                  value: value,
                  child: Text(_label(value.name)),
                ),
              ),
            ],
            onChanged: onFilterChanged,
          ),
        ),
        child: settings.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.admin_panel_settings_outlined,
                title: 'No safeguard in this category',
                message: 'Change the category filter to see other controls.',
              )
            : Column(
                children: settings.map((setting) {
                  final color = setting.value
                      ? TgcgColors.success
                      : TgcgColors.warning;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: TgcgColors.border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(
                            _settingIcon(setting.category),
                            color: color,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                setting.label,
                                style: const TextStyle(
                                  color: TgcgColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                setting.description ?? _label(setting.category.name),
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 10.5,
                                  height: 1.4,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Updated by ${setting.updatedBy} • ${_time(setting.updatedAt)}',
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: setting.value,
                          onChanged: canManage
                              ? (value) => onChanged(setting, value)
                              : null,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      );
}

class _DataProvenancePanel extends StatelessWidget {
  const _DataProvenancePanel({
    required this.agentCount,
    required this.incidentCount,
    required this.reportCount,
    required this.resultCount,
    required this.evidenceCount,
  });

  final int agentCount;
  final int incidentCount;
  final int reportCount;
  final int resultCount;
  final int? evidenceCount;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Data provenance model',
        subtitle:
            'Operational entity types remain distinct so workflow state, source and authorization are not collapsed into one generic record.',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _DataChip('Agents', '$agentCount', Icons.badge_outlined),
            _DataChip('Incidents', '$incidentCount', Icons.warning_amber_rounded),
            _DataChip('Field reports', '$reportCount', Icons.feed_outlined),
            _DataChip('Result submissions', '$resultCount', Icons.ballot_outlined),
            _DataChip(
              'Evidence',
              evidenceCount?.toString() ?? 'Restricted',
              Icons.fingerprint_rounded,
            ),
            const _DataChip(
              'Offline writes',
              'Versioned',
              Icons.offline_bolt_outlined,
            ),
            const _DataChip(
              'Audit events',
              'Append-style',
              Icons.history_rounded,
            ),
            const _DataChip(
              'Authorization',
              'Scope-aware',
              Icons.lock_outline_rounded,
            ),
          ],
        ),
      );
}

class _DataChip extends StatelessWidget {
  const _DataChip(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: TgcgColors.primary),
            const SizedBox(width: 7),
            Text(
              '$label: ',
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _AuditTimeline extends StatelessWidget {
  const _AuditTimeline({
    required this.events,
    required this.search,
    required this.onSearchChanged,
  });

  final List<AuditEvent> events;
  final String search;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Audit timeline',
        subtitle:
            'Prototype append-style event history. Production audit storage must be immutable and server-backed.',
        trailing: TgcgStatusPill(
          label: '${events.length} VISIBLE',
          color: TgcgColors.primary,
          icon: Icons.history_rounded,
          compact: true,
        ),
        child: Column(
          children: [
            TextField(
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                labelText: 'Search audit events',
                hintText: 'Action, actor, entity or detail',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: search.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => onSearchChanged(''),
                        icon: const Icon(Icons.clear_rounded),
                      ),
              ),
            ),
            const SizedBox(height: 14),
            if (events.isEmpty)
              const TgcgEmptyState(
                icon: Icons.manage_search_rounded,
                title: 'No matching audit event',
                message: 'Change the search phrase to inspect other events.',
              )
            else
              ...events.take(40).map((event) => _AuditRow(event: event)),
          ],
        ),
      );
}

class _AuditRow extends StatelessWidget {
  const _AuditRow({required this.event});

  final AuditEvent event;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: TgcgColors.primarySoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.history_rounded,
                    color: TgcgColors.primary,
                    size: 17,
                  ),
                ),
                Container(
                  width: 1,
                  height: 38,
                  color: TgcgColors.border,
                ),
              ],
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: TgcgColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: TgcgColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _label(event.action),
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Text(
                          _time(event.timestamp),
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${event.actorId} • ${event.entityType}/${event.entityId}',
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                    if (event.scope != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        event.scope!.label,
                        style: const TextStyle(
                          color: TgcgColors.primaryMid,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (event.detail != null) ...[
                      const SizedBox(height: 7),
                      Text(
                        event.detail!,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _AccessRestricted extends StatelessWidget {
  const _AccessRestricted({
    required this.icon,
    required this.title,
    required this.message,
    this.embedded = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final body = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: TgcgColors.muted.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: TgcgColors.muted),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                message,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
    if (embedded) return Padding(padding: const EdgeInsets.all(8), child: body);
    return TgcgSectionCard(child: body);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 132,
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10.5,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
}

Color _syncColor(SyncState state) => switch (state) {
      SyncState.queued => TgcgColors.warning,
      SyncState.syncing => TgcgColors.info,
      SyncState.synced => TgcgColors.success,
      SyncState.failed => TgcgColors.danger,
      SyncState.conflict => TgcgColors.ai,
    };

IconData _syncIcon(SyncState state) => switch (state) {
      SyncState.queued => Icons.schedule_rounded,
      SyncState.syncing => Icons.sync_rounded,
      SyncState.synced => Icons.cloud_done_outlined,
      SyncState.failed => Icons.cloud_off_outlined,
      SyncState.conflict => Icons.merge_type_rounded,
    };

IconData _settingIcon(SystemSettingCategory category) => switch (category) {
      SystemSettingCategory.security => Icons.security_outlined,
      SystemSettingCategory.sync => Icons.sync_lock_outlined,
      SystemSettingCategory.evidence => Icons.fingerprint_rounded,
      SystemSettingCategory.communications => Icons.forum_outlined,
    };

String _time(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  return '$day/$month/${local.year} $hour:$minute';
}

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  final clean = spaced.replaceAll('_', ' ');
  return clean.isEmpty
      ? clean
      : '${clean[0].toUpperCase()}${clean.substring(1)}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
