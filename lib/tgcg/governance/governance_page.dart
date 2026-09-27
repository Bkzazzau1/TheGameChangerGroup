import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../field/field_operations_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../sync/sync_models.dart';
import 'governance_store.dart';

class GovernancePage extends StatefulWidget {
  const GovernancePage({super.key});

  @override
  State<GovernancePage> createState() => _GovernancePageState();
}

class _GovernancePageState extends State<GovernancePage> {
  String auditSearch = '';

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

    var auditEvents = governance.auditForScope(session.scope);
    final query = auditSearch.trim().toLowerCase();
    if (query.isNotEmpty) {
      auditEvents = auditEvents
          .where((event) =>
              event.action.toLowerCase().contains(query) ||
              event.actorId.toLowerCase().contains(query) ||
              event.entityType.toLowerCase().contains(query) ||
              event.entityId.toLowerCase().contains(query) ||
              (event.detail ?? '').toLowerCase().contains(query))
          .toList(growable: false);
    }

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text(
          'Data, Audit & Governance',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: TgcgApp.ink,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '${session.scope.label}: audit visibility, offline sync state, access readiness and system safeguards.',
          style: const TextStyle(color: TgcgApp.muted, height: 1.5),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(
              'Audit events',
              '${governance.auditForScope(session.scope).length}',
              Icons.history_rounded,
            ),
            _Metric(
              'Pending sync',
              '${governance.pendingOutbox.length}',
              Icons.sync_problem_rounded,
            ),
            _Metric(
              'Agents',
              '${membership.agentsForScope(session.scope).length}',
              Icons.badge_outlined,
            ),
            _Metric(
              'Result records',
              '${results.submissionsForScope(session.scope).length}',
              Icons.ballot_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final sync = _SyncPanel(
              items: governance.outbox,
              canRetry: mayManageSettings,
              onRetry: (item) => governance.queueForRetry(
                item.id,
                actorId: session.accessId.isEmpty
                    ? session.operatorName
                    : session.accessId,
              ),
            );
            final safeguards = _SafeguardsPanel(
              settings: governance.settings,
              canManage: mayManageSettings,
              onChanged: (setting, value) => governance.setSetting(
                settingId: setting.id,
                value: value,
                actorId: session.accessId.isEmpty
                    ? session.operatorName
                    : session.accessId,
              ),
            );
            if (constraints.maxWidth < 960) {
              return Column(
                children: [
                  sync,
                  const SizedBox(height: 14),
                  safeguards,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: sync),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: safeguards),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ProvenancePanel(
          incidentCount: field.incidentsForScope(session.scope).length,
          reportCount: field.reportsForScope(session.scope).length,
          resultCount: results.submissionsForScope(session.scope).length,
          agentCount: membership.agentsForScope(session.scope).length,
        ),
        if (mayViewAudit) ...[
          const SizedBox(height: 16),
          _AuditPanel(
            events: auditEvents,
            onSearchChanged: (value) => setState(() => auditSearch = value),
          ),
        ],
      ],
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
        width: 215,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: TgcgApp.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: TgcgApp.primary),
                ),
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

class _SyncPanel extends StatelessWidget {
  const _SyncPanel({
    required this.items,
    required this.canRetry,
    required this.onRetry,
  });

  final List<SyncOutboxItem> items;
  final bool canRetry;
  final ValueChanged<SyncOutboxItem> onRetry;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Durable sync outbox',
        subtitle: 'Queued does not mean synced. Local records remain authoritative until server acknowledgement.',
        child: items.isEmpty
            ? const Text('No outbox records in the prototype store.')
            : Column(
                children: items.map((item) {
                  final color = switch (item.state) {
                    SyncState.synced => const Color(0xFF26734D),
                    SyncState.queued => const Color(0xFF8B6513),
                    SyncState.syncing => const Color(0xFF2563EB),
                    SyncState.failed => const Color(0xFFB42318),
                    SyncState.conflict => const Color(0xFF8A3FFC),
                  };
                  return Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAF9),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFFE2E8E5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${item.entityType} • ${item.entityId}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: TgcgApp.ink,
                                ),
                              ),
                            ),
                            _Pill(_label(item.state.name), color),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${_label(item.mutationType.name)} • version ${item.mutationVersion} • attempts ${item.attemptCount}',
                          style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                        ),
                        if (item.lastError != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            item.lastError!,
                            style: const TextStyle(
                              color: Color(0xFF9C2A22),
                              fontSize: 10.5,
                              height: 1.4,
                            ),
                          ),
                        ],
                        if (canRetry &&
                            (item.state == SyncState.failed ||
                                item.state == SyncState.conflict)) ...[
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: () => onRetry(item),
                            icon: const Icon(Icons.refresh_rounded, size: 17),
                            label: const Text('Return to retry queue'),
                          ),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              ),
      );
}

class _SafeguardsPanel extends StatelessWidget {
  const _SafeguardsPanel({
    required this.settings,
    required this.canManage,
    required this.onChanged,
  });

  final List<SystemSettingRecord> settings;
  final bool canManage;
  final void Function(SystemSettingRecord, bool) onChanged;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'System safeguards',
        subtitle: canManage
            ? 'Privileged prototype controls. Production enforcement remains server-side.'
            : 'Read-only view of configured safeguards.',
        child: Column(
          children: settings.map((setting) {
            return SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                setting.label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                setting.description ?? _label(setting.category.name),
                style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
              ),
              value: setting.value,
              onChanged: canManage ? (value) => onChanged(setting, value) : null,
            );
          }).toList(),
        ),
      );
}

class _ProvenancePanel extends StatelessWidget {
  const _ProvenancePanel({
    required this.incidentCount,
    required this.reportCount,
    required this.resultCount,
    required this.agentCount,
  });

  final int incidentCount;
  final int reportCount;
  final int resultCount;
  final int agentCount;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Data provenance snapshot',
        subtitle: 'Operational data types stay distinct and retain source, scope and workflow state.',
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _DataChip('Incidents', '$incidentCount', Icons.warning_amber_rounded),
            _DataChip('Field reports', '$reportCount', Icons.feed_outlined),
            _DataChip('Result submissions', '$resultCount', Icons.ballot_outlined),
            _DataChip('Accredited agents', '$agentCount', Icons.badge_outlined),
            const _DataChip('Evidence', 'hash-tracked', Icons.fingerprint_rounded),
            const _DataChip('Offline writes', 'versioned', Icons.offline_bolt_outlined),
          ],
        ),
      );
}

class _AuditPanel extends StatelessWidget {
  const _AuditPanel({required this.events, required this.onSearchChanged});

  final List<AuditEvent> events;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Audit trail',
        subtitle: 'Prototype append-only event view. Production storage must be immutable and server-backed.',
        child: Column(
          children: [
            TextField(
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                labelText: 'Search audit events',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (events.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Text('No audit event matches this filter.'),
              )
            else
              ...events.take(30).map(
                (event) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFE2E8E5)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.history_rounded, color: TgcgApp.primary, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _label(event.action),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: TgcgApp.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${event.actorId} • ${event.entityType}/${event.entityId}',
                              style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                            ),
                            if (event.detail != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                event.detail!,
                                style: const TextStyle(color: TgcgApp.muted, height: 1.4),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
          color: const Color(0xFFF7F9F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E8E5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: TgcgApp.primary),
            const SizedBox(width: 8),
            Text('$label: ', style: const TextStyle(fontSize: 11, color: TgcgApp.muted)),
            Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
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
              Text(subtitle, style: const TextStyle(fontSize: 11, color: TgcgApp.muted)),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900),
        ),
      );
}

String _label(String value) {
  final spaced = value
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m.group(1)} ${m.group(2)}');
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
