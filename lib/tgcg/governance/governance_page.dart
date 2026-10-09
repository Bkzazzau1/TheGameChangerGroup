import 'package:flutter/material.dart';

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

    final canManage = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.manageSystemSettings,
    );
    final canAudit = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.viewAudit,
    );
    final canEvidence = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.viewEvidence,
    );

    final agents = membership.agentsForScope(session.scope);
    final submissions = results.submissionsForScope(session.scope);
    final incidents = field.incidentsForScope(session.scope);
    final reports = field.reportsForScope(session.scope);

    var audit = canAudit
        ? governance.auditForScope(session.scope)
        : const <AuditEvent>[];
    final q = auditSearch.trim().toLowerCase();
    if (q.isNotEmpty) {
      audit = audit.where((event) {
        return event.action.toLowerCase().contains(q) ||
            event.actorId.toLowerCase().contains(q) ||
            event.entityType.toLowerCase().contains(q) ||
            event.entityId.toLowerCase().contains(q) ||
            (event.detail ?? '').toLowerCase().contains(q);
      }).toList(growable: false);
    }

    var outbox = canAudit || canManage
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
    final selected = selectedOutboxId == null
        ? null
        : outbox.where((item) => item.id == selectedOutboxId).firstOrNull;

    var settings = governance.settings;
    if (settingFilter != null) {
      settings = settings
          .where((item) => item.category == settingFilter)
          .toList(growable: false);
    }

    int syncCount(SyncState state) =>
        governance.outbox.where((item) => item.state == state).length;
    final queued = syncCount(SyncState.queued);
    final syncing = syncCount(SyncState.syncing);
    final failed = syncCount(SyncState.failed);
    final conflicts = syncCount(SyncState.conflict);
    final enabledSettings = governance.settings.where((item) => item.value).length;

    final incidentEvidence = incidents.fold<int>(
      0,
      (total, item) => total + item.evidence.length,
    );
    final resultEvidence =
        submissions.where((item) => item.resultForm != null).length;
    final evidenceTotal = incidentEvidence + resultEvidence;
    final hashedEvidence = incidents.fold<int>(
          0,
          (total, item) =>
              total +
              item.evidence
                  .where((evidence) => (evidence.contentHash ?? '').trim().isNotEmpty)
                  .length,
        ) +
        submissions.where((item) {
          final form = item.resultForm;
          return form != null && (form.contentHash ?? '').trim().isNotEmpty;
        }).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'CONTROL & ASSURANCE',
          title: 'Data, Audit & Governance',
          subtitle:
              '${session.scope.label}: sync integrity, evidence provenance, audit visibility and privileged system safeguards.',
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
        _MetricGrid(
          audit: canAudit ? governance.auditForScope(session.scope).length : null,
          queued: queued,
          syncing: syncing,
          failed: failed,
          conflicts: conflicts,
          enabledSettings: enabledSettings,
          settingsTotal: governance.settings.length,
        ),
        const SizedBox(height: 16),
        _ControlSnapshot(
          agents: agents.length,
          incidents: incidents.length,
          reports: reports.length,
          results: submissions.length,
          evidence: canEvidence ? evidenceTotal : null,
          hashes: canEvidence ? hashedEvidence : null,
          pending: governance.pendingOutbox.length,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final list = _OutboxList(
              items: outbox,
              selectedId: selectedOutboxId,
              filter: syncFilter,
              canView: canAudit || canManage,
              onFilter: (value) => setState(() => syncFilter = value),
              onSelect: (value) => setState(() => selectedOutboxId = value),
            );
            final detail = _OutboxDetail(
              item: selected,
              canRetry: canManage,
              onRetry: selected == null
                  ? null
                  : () => governance.queueForRetry(
                        selected.id,
                        actorId: session.accessId.isEmpty
                            ? session.operatorName
                            : session.accessId,
                      ),
            );
            if (constraints.maxWidth < 1030) {
              return Column(children: [list, const SizedBox(height: 14), detail]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: list),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: detail),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final integrity = _EvidencePanel(
              allowed: canEvidence,
              total: evidenceTotal,
              hashed: hashedEvidence,
              incidentEvidence: incidentEvidence,
              resultEvidence: resultEvidence,
            );
            final safeguards = _SettingsPanel(
              settings: settings,
              filter: settingFilter,
              canManage: canManage,
              onFilter: (value) => setState(() => settingFilter = value),
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
                children: [integrity, const SizedBox(height: 14), safeguards],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: integrity),
                const SizedBox(width: 14),
                Expanded(flex: 6, child: safeguards),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _Provenance(
          agents: agents.length,
          incidents: incidents.length,
          reports: reports.length,
          results: submissions.length,
          evidence: canEvidence ? evidenceTotal : null,
        ),
        const SizedBox(height: 16),
        if (canAudit)
          _AuditPanel(
            events: audit,
            search: auditSearch,
            onSearch: (value) => setState(() => auditSearch = value),
          )
        else
          const _Restricted(
            icon: Icons.history_toggle_off_outlined,
            title: 'Audit trail restricted',
            message:
                'This role does not have audit visibility. The same boundary must be enforced server-side.',
          ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.audit,
    required this.queued,
    required this.syncing,
    required this.failed,
    required this.conflicts,
    required this.enabledSettings,
    required this.settingsTotal,
  });

  final int? audit;
  final int queued;
  final int syncing;
  final int failed;
  final int conflicts;
  final int enabledSettings;
  final int settingsTotal;

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
                value: audit?.toString() ?? '—',
                detail: audit == null ? 'Audit permission required' : 'Visible in scope',
                icon: Icons.history_rounded,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Queued',
                value: '$queued',
                detail: 'Waiting for sync attempt',
                icon: Icons.schedule_rounded,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Syncing',
                value: '$syncing',
                detail: 'Currently transmitting',
                icon: Icons.sync_rounded,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Failed',
                value: '$failed',
                detail: 'Retryable transport failures',
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
                value: '$enabledSettings/$settingsTotal',
                detail: 'Configured prototype controls',
                icon: Icons.admin_panel_settings_outlined,
                tone: TgcgMetricTone.success,
              ),
            ],
          );
        },
      );
}

class _ControlSnapshot extends StatelessWidget {
  const _ControlSnapshot({
    required this.agents,
    required this.incidents,
    required this.reports,
    required this.results,
    required this.evidence,
    required this.hashes,
    required this.pending,
  });

  final int agents;
  final int incidents;
  final int reports;
  final int results;
  final int? evidence;
  final int? hashes;
  final int pending;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: TgcgColors.primaryDark,
          borderRadius: BorderRadius.circular(20),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final text = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'CONTROL SNAPSHOT',
                  style: TextStyle(
                    color: TgcgColors.accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Operational records remain usable locally while synchronization is pending.',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 7),
                Text(
                  'Queued does not mean synced. Synced does not mean verified, approved, published or legally declared.',
                  style: TextStyle(
                    color: Color(0xFFC6CAD3),
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
                _DarkStat('Agents', '$agents'),
                _DarkStat('Incidents', '$incidents'),
                _DarkStat('Field reports', '$reports'),
                _DarkStat('Results', '$results'),
                _DarkStat(
                  'Evidence hashes',
                  evidence == null ? 'Restricted' : '$hashes/$evidence',
                ),
                _DarkStat('Pending outbox', '$pending'),
              ],
            );
            if (constraints.maxWidth < 860) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [text, const SizedBox(height: 16), stats],
              );
            }
            return Row(
              children: [
                Expanded(flex: 6, child: text),
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
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF9EA4B2),
                fontSize: 9.5,
              ),
            ),
          ],
        ),
      );
}

class _OutboxList extends StatelessWidget {
  const _OutboxList({
    required this.items,
    required this.selectedId,
    required this.filter,
    required this.canView,
    required this.onFilter,
    required this.onSelect,
  });

  final List<SyncOutboxItem> items;
  final String? selectedId;
  final SyncState? filter;
  final bool canView;
  final ValueChanged<SyncState?> onFilter;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Durable sync outbox',
        subtitle:
            'Every local mutation retains its version and transport state until server acknowledgement or reconciliation.',
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
            onChanged: canView ? onFilter : null,
          ),
        ),
        child: !canView
            ? const _Restricted(
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
                      final color = _syncColor(item.state);
                      final selected = item.id == selectedId;
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
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: .09),
                                    borderRadius: BorderRadius.circular(11),
                                  ),
                                  child: Icon(_syncIcon(item.state), color: color, size: 18),
                                ),
                                const SizedBox(width: 10),
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

class _OutboxDetail extends StatelessWidget {
  const _OutboxDetail({
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

    final value = item!;
    final color = _syncColor(value.state);
    final retryable =
        value.state == SyncState.failed || value.state == SyncState.conflict;
    return TgcgSectionCard(
      title: 'Mutation inspector',
      subtitle: 'Transport state is not workflow approval state.',
      trailing: TgcgStatusPill(
        label: _label(value.state.name).toUpperCase(),
        color: color,
        icon: _syncIcon(value.state),
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
                  value.id,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${value.entityType}/${value.entityId}',
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _Detail('Mutation', _label(value.mutationType.name)),
          _Detail('Mutation version', '${value.mutationVersion}'),
          _Detail('Attempts', '${value.attemptCount}'),
          _Detail('Created', _time(value.createdAt)),
          _Detail(
            'Last attempt',
            value.lastAttemptAt == null ? 'Not attempted' : _time(value.lastAttemptAt!),
          ),
          if (value.lastError != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TgcgColors.danger.withValues(alpha: .055),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: TgcgColors.danger.withValues(alpha: .16)),
              ),
              child: Text(
                value.lastError!,
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
            'Payload bodies are intentionally hidden here. Production debugging should use protected server tooling with least-privilege access.',
            style: TextStyle(color: TgcgColors.muted, fontSize: 10, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({
    required this.allowed,
    required this.total,
    required this.hashed,
    required this.incidentEvidence,
    required this.resultEvidence,
  });

  final bool allowed;
  final int total;
  final int hashed;
  final int incidentEvidence;
  final int resultEvidence;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 1.0 : hashed / total;
    final safeProgress = progress.clamp(0.0, 1.0).toDouble();
    return TgcgSectionCard(
      title: 'Evidence integrity',
      subtitle:
          'Evidence metadata stays separate from operational records and retains cryptographic provenance references.',
      trailing: allowed
          ? TgcgStatusPill(
              label: total == 0
                  ? 'NO EVIDENCE IN SCOPE'
                  : hashed == total
                      ? 'HASH TRACKED'
                      : 'REVIEW HASH COVERAGE',
              color: total == 0 || hashed == total
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
          ? const _Restricted(
              icon: Icons.inventory_2_outlined,
              title: 'Evidence metadata restricted',
              message: 'Evidence-view permission is required for this panel.',
              embedded: true,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Hash coverage',
                        style: TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      '${(safeProgress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: TgcgColors.primary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                LinearProgressIndicator(
                  value: safeProgress,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: TgcgColors.border,
                ),
                const SizedBox(height: 6),
                Text(
                  '$hashed of $total evidence records retain a content-hash reference.',
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _SmallStat('Incident evidence', '$incidentEvidence', Icons.warning_amber_rounded),
                    _SmallStat('Result forms', '$resultEvidence', Icons.document_scanner_outlined),
                  ],
                ),
                const SizedBox(height: 14),
                const _Note(
                  icon: Icons.lock_outline_rounded,
                  title: 'Original evidence preserved',
                  detail:
                      'AI/OCR-derived values must never replace original media or its provenance reference.',
                ),
                const _Note(
                  icon: Icons.visibility_off_outlined,
                  title: 'No raw biometrics here',
                  detail:
                      'This governance surface does not expose face templates or other raw biometric material.',
                ),
              ],
            ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.settings,
    required this.filter,
    required this.canManage,
    required this.onFilter,
    required this.onChanged,
  });

  final List<SystemSettingRecord> settings;
  final SystemSettingCategory? filter;
  final bool canManage;
  final ValueChanged<SystemSettingCategory?> onFilter;
  final void Function(SystemSettingRecord, bool) onChanged;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'System safeguards',
        subtitle: canManage
            ? 'Privileged prototype controls. Production enforcement remains server-side.'
            : 'Read-only configuration view.',
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
            onChanged: onFilter,
          ),
        ),
        child: settings.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.admin_panel_settings_outlined,
                title: 'No safeguard in this category',
                message: 'Change the filter to see other controls.',
              )
            : Column(
                children: settings.map((setting) {
                  final color = setting.value ? TgcgColors.success : TgcgColors.warning;
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
                          child: Icon(_settingIcon(setting.category), color: color, size: 19),
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
                                style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: setting.value,
                          onChanged: canManage ? (value) => onChanged(setting, value) : null,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      );
}

class _Provenance extends StatelessWidget {
  const _Provenance({
    required this.agents,
    required this.incidents,
    required this.reports,
    required this.results,
    required this.evidence,
  });

  final int agents;
  final int incidents;
  final int reports;
  final int results;
  final int? evidence;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Data provenance model',
        subtitle:
            'Entity types remain distinct so source, scope, workflow state and authorization are preserved.',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _Chip('Agents', '$agents', Icons.badge_outlined),
            _Chip('Incidents', '$incidents', Icons.warning_amber_rounded),
            _Chip('Field reports', '$reports', Icons.feed_outlined),
            _Chip('Result submissions', '$results', Icons.ballot_outlined),
            _Chip('Evidence', evidence?.toString() ?? 'Restricted', Icons.fingerprint_rounded),
            const _Chip('Offline writes', 'Versioned', Icons.offline_bolt_outlined),
            const _Chip('Audit events', 'Append-style', Icons.history_rounded),
            const _Chip('Authorization', 'Scope-aware', Icons.lock_outline_rounded),
          ],
        ),
      );
}

class _AuditPanel extends StatelessWidget {
  const _AuditPanel({
    required this.events,
    required this.search,
    required this.onSearch,
  });

  final List<AuditEvent> events;
  final String search;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Audit timeline',
        subtitle:
            'Prototype append-style event history. Production storage must be immutable and server-backed.',
        trailing: TgcgStatusPill(
          label: '${events.length} VISIBLE',
          color: TgcgColors.primary,
          icon: Icons.history_rounded,
          compact: true,
        ),
        child: Column(
          children: [
            TextField(
              onChanged: onSearch,
              decoration: const InputDecoration(
                labelText: 'Search audit events',
                hintText: 'Action, actor, entity or detail',
                prefixIcon: Icon(Icons.search_rounded),
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
  Widget build(BuildContext context) => Container(
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
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: TgcgColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.history_rounded, color: TgcgColors.primary, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
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
                        style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${event.actorId} • ${event.entityType}/${event.entityId}',
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
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
                    const SizedBox(height: 6),
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
          ],
        ),
      );
}

class _SmallStat extends StatelessWidget {
  const _SmallStat(this.label, this.value, this.icon);
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
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: TgcgColors.primary, size: 18),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5)),
              ],
            ),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.title, required this.detail});
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
            const SizedBox(width: 8),
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

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value, this.icon);
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
            Text('$label: ', style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5)),
            Text(value, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

class _Restricted extends StatelessWidget {
  const _Restricted({
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
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 3),
              Text(
                message,
                style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5, height: 1.4),
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

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5)),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
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
  final h = local.hour.toString().padLeft(2, '0');
  final m = local.minute.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  final mo = local.month.toString().padLeft(2, '0');
  return '$d/$mo/${local.year} $h:$m';
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
