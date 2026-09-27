import 'package:flutter/material.dart';

import 'app.dart';
import 'domain/models.dart';
import 'field/field_operations_store.dart';
import 'results/result_operations_store.dart';
import 'session.dart';

class TgcgDashboardPage extends StatelessWidget {
  const TgcgDashboardPage({super.key, required this.onOpenModule});

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final fieldStore = FieldOperations.of(context);
    final resultStore = ResultOperations.of(context);
    final role = session.role!;
    final modules = allowedModules(role);
    final scopedIncidents = fieldStore.incidentsForScope(session.scope);
    final scopedReports = fieldStore.reportsForScope(session.scope);
    final scopedResults = resultStore.submissionsForScope(session.scope);
    final reviewResults = resultStore.reviewQueueForScope(session.scope);
    final openIncidents = scopedIncidents
        .where((item) => item.status != IncidentStatus.resolved && item.status != IncidentStatus.closed)
        .toList(growable: false);
    final highPriority = openIncidents
        .where((item) =>
            item.severity == IncidentSeverity.high || item.severity == IncidentSeverity.critical)
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
                  Text(
                    role == TgcgRole.pollingUnitAgent
                        ? 'Polling Unit Workspace'
                        : 'Operations Command',
                    style: const TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.w900,
                      color: TgcgApp.ink,
                      letterSpacing: -.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${roleLabel(role)} • ${session.scope.label}',
                      style: const TextStyle(color: TgcgApp.muted, height: 1.5)),
                ],
              ),
            ),
            const _StatusBadge(),
          ],
        ),
        const SizedBox(height: 22),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth > 1040 ? 4 : constraints.maxWidth > 620 ? 2 : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              _MetricCard(
                width: width,
                label: 'Open incidents',
                value: '${openIncidents.length}',
                detail: 'Live prototype store in your scope',
                icon: Icons.warning_amber_rounded,
                accent: const Color(0xFFB45F06),
              ),
              _MetricCard(
                width: width,
                label: 'High priority',
                value: '$highPriority',
                detail: 'High and critical incidents',
                icon: Icons.crisis_alert_outlined,
                accent: const Color(0xFFD92D20),
              ),
              _MetricCard(
                width: width,
                label: 'Result submissions',
                value: '${scopedResults.length}',
                detail: 'Unofficial field records in current scope',
                icon: Icons.ballot_outlined,
              ),
              _MetricCard(
                width: width,
                label: 'Result review',
                value: '${reviewResults.length}',
                detail: 'Records requiring human verification',
                icon: Icons.fact_check_outlined,
                accent: const Color(0xFF6550B5),
              ),
            ],
          );
        }),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final queue = _OperationalQueue(
            incidents: openIncidents,
            resultReviewCount: reviewResults.length,
            onOpenModule: onOpenModule,
            modules: modules,
          );
          final coverage = _CoveragePanel(onOpenModule: onOpenModule, modules: modules);
          if (constraints.maxWidth < 930) {
            return Column(children: [queue, const SizedBox(height: 16), coverage]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: queue),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: coverage),
            ],
          );
        }),
        const SizedBox(height: 16),
        _QuickActions(onOpenModule: onOpenModule, modules: modules),
        if (scopedReports.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Panel(
            title: 'Field reporting activity',
            subtitle: 'Structured reports received in your current scope',
            child: Text(
              '${scopedReports.length} field report${scopedReports.length == 1 ? '' : 's'} currently available in the shared operational store.',
              style: const TextStyle(color: TgcgApp.muted, height: 1.5),
            ),
          ),
        ],
      ],
    );
  }
}

class _OperationalQueue extends StatelessWidget {
  const _OperationalQueue({
    required this.incidents,
    required this.resultReviewCount,
    required this.onOpenModule,
    required this.modules,
  });

  final List<FieldIncident> incidents;
  final int resultReviewCount;
  final ValueChanged<TgcgModule> onOpenModule;
  final Set<TgcgModule> modules;

  @override
  Widget build(BuildContext context) {
    final sorted = [...incidents]
      ..sort((a, b) => _severityRank(b.severity).compareTo(_severityRank(a.severity)));
    return _Panel(
      title: 'Operational queue',
      subtitle: 'Current field and result-review items in your authorized scope',
      child: Column(
        children: [
          if (sorted.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No unresolved field incidents in this scope.'),
            )
          else
            ...sorted.take(3).map((incident) => _QueueItem(
                  icon: Icons.crisis_alert_outlined,
                  title: incident.title,
                  subtitle:
                      '${incident.scope.label} • ${_label(incident.severity.name)} • ${_label(incident.status.name)}',
                  action: modules.contains(TgcgModule.situationRoom)
                      ? () => onOpenModule(TgcgModule.situationRoom)
                      : modules.contains(TgcgModule.fieldMonitoring)
                          ? () => onOpenModule(TgcgModule.fieldMonitoring)
                          : null,
                )),
          if (modules.contains(TgcgModule.resultCapture))
            _QueueItem(
              icon: Icons.document_scanner_outlined,
              title: resultReviewCount == 0
                  ? 'No flagged result submissions'
                  : '$resultReviewCount result submission${resultReviewCount == 1 ? '' : 's'} require human review',
              subtitle: resultReviewCount == 0
                  ? 'Automated integrity flags are clear in the current scope.'
                  : 'Review arithmetic, duplicate and OCR/manual-entry flags.',
              action: () => onOpenModule(TgcgModule.resultCapture),
            ),
        ],
      ),
    );
  }
}

class _CoveragePanel extends StatelessWidget {
  const _CoveragePanel({required this.onOpenModule, required this.modules});
  final ValueChanged<TgcgModule> onOpenModule;
  final Set<TgcgModule> modules;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'National readiness snapshot',
        subtitle: 'Prototype readiness values until verified operational feeds are connected',
        child: Column(
          children: [
            const _ProgressRow('Agent assignment', .76, '76%'),
            const _ProgressRow('Communication readiness', .68, '68%'),
            const _ProgressRow('Evidence capture readiness', .72, '72%'),
            const _ProgressRow('Result workflow readiness', .64, '64%'),
            const SizedBox(height: 12),
            if (modules.contains(TgcgModule.geography))
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => onOpenModule(TgcgModule.geography),
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('Open geographic operations'),
                ),
              ),
          ],
        ),
      );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onOpenModule, required this.modules});
  final ValueChanged<TgcgModule> onOpenModule;
  final Set<TgcgModule> modules;

  @override
  Widget build(BuildContext context) {
    final actions = <({TgcgModule module, String label, IconData icon})>[
      (module: TgcgModule.fieldMonitoring, label: 'Open field monitoring', icon: Icons.radar_outlined),
      (module: TgcgModule.situationRoom, label: 'Situation room', icon: Icons.dashboard_customize_outlined),
      (module: TgcgModule.resultCapture, label: 'Result workspace', icon: Icons.ballot_outlined),
      (module: TgcgModule.collation, label: 'Open collation', icon: Icons.account_tree_outlined),
      (module: TgcgModule.accreditation, label: 'Manage agents', icon: Icons.badge_outlined),
      (module: TgcgModule.governance, label: 'Audit & sync', icon: Icons.shield_outlined),
    ].where((item) => modules.contains(item.module)).toList();

    return _Panel(
      title: 'Quick actions',
      subtitle: 'Actions are filtered by the current role',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: actions
            .map((action) => OutlinedButton.icon(
                  onPressed: () => onOpenModule(action.module),
                  icon: Icon(action.icon),
                  label: Text(action.label),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14)),
                ))
            .toList(),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.width,
    required this.label,
    required this.value,
    required this.detail,
    required this.icon,
    this.accent = TgcgApp.primary,
  });
  final double width;
  final String label;
  final String value;
  final String detail;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .09),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: accent),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(value,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                      Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(detail,
                          style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted)),
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
  const _Panel({required this.title, required this.subtitle, required this.child});
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
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: TgcgApp.muted)),
              const SizedBox(height: 15),
              child,
            ],
          ),
        ),
      );
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({required this.icon, required this.title, required this.subtitle, this.action});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? action;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F9F8),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFE4E9E7)),
          ),
          child: Row(
            children: [
              Icon(icon, color: TgcgApp.primary),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: TgcgApp.ink)),
                    const SizedBox(height: 3),
                    Text(subtitle,
                        style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted)),
                  ],
                ),
              ),
              if (action != null) const Icon(Icons.chevron_right_rounded, color: TgcgApp.muted),
            ],
          ),
        ),
      );
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow(this.label, this.value, this.valueLabel);
  final String label;
  final double value;
  final String valueLabel;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(valueLabel,
                  style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.primary)),
            ]),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: value,
              minHeight: 8,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: const Color(0xFFE6ECE9),
            ),
          ],
        ),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF8B6513).withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF8B6513).withValues(alpha: .22)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.science_outlined, size: 15, color: Color(0xFF8B6513)),
            SizedBox(width: 6),
            Text('PROTOTYPE DATA',
                style: TextStyle(
                    color: Color(0xFF8B6513),
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .5)),
          ],
        ),
      );
}

int _severityRank(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => 5,
      IncidentSeverity.high => 4,
      IncidentSeverity.medium => 3,
      IncidentSeverity.low => 2,
      IncidentSeverity.info => 1,
    };

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty ? spaced : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
