import 'package:flutter/material.dart';

import 'app.dart';
import 'session.dart';

class TgcgDashboardPage extends StatelessWidget {
  const TgcgDashboardPage({super.key, required this.onOpenModule});

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final role = session.role!;
    final modules = allowedModules(role);

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
                  Text(
                    '${roleLabel(role)} • ${session.scope.label}',
                    style: const TextStyle(color: TgcgApp.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            _StatusBadge(
              label: 'PROTOTYPE DATA',
              icon: Icons.science_outlined,
              color: const Color(0xFF8B6513),
            ),
          ],
        ),
        const SizedBox(height: 22),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth > 1040
                ? 4
                : constraints.maxWidth > 620
                    ? 2
                    : 1;
            const gap = 12.0;
            final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                _MetricCard(
                  width: width,
                  label: 'Polling units',
                  value: '176,846',
                  detail: 'National master-data target',
                  icon: Icons.location_on_outlined,
                ),
                _MetricCard(
                  width: width,
                  label: 'LGAs',
                  value: '774',
                  detail: 'National geographic coverage',
                  icon: Icons.location_city_outlined,
                ),
                _MetricCard(
                  width: width,
                  label: 'Open incidents',
                  value: '24',
                  detail: 'Demonstration operational feed',
                  icon: Icons.warning_amber_rounded,
                  accent: const Color(0xFFB45F06),
                ),
                _MetricCard(
                  width: width,
                  label: 'Pending review',
                  value: '17',
                  detail: 'Demo result/evidence queue',
                  icon: Icons.fact_check_outlined,
                  accent: const Color(0xFF6550B5),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 930) {
              return Column(
                children: [
                  _OperationalQueue(onOpenModule: onOpenModule, modules: modules),
                  const SizedBox(height: 16),
                  _CoveragePanel(onOpenModule: onOpenModule, modules: modules),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 6,
                  child: _OperationalQueue(onOpenModule: onOpenModule, modules: modules),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 5,
                  child: _CoveragePanel(onOpenModule: onOpenModule, modules: modules),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _QuickActions(onOpenModule: onOpenModule, modules: modules),
      ],
    );
  }
}

class _OperationalQueue extends StatelessWidget {
  const _OperationalQueue({required this.onOpenModule, required this.modules});

  final ValueChanged<TgcgModule> onOpenModule;
  final Set<TgcgModule> modules;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Operational queue',
        subtitle: 'Prototype items showing the command workflow structure',
        child: Column(
          children: [
            _QueueItem(
              icon: Icons.crisis_alert_outlined,
              title: 'Critical incident requires acknowledgement',
              subtitle: 'Field monitoring • High priority • 8 min ago',
              action: modules.contains(TgcgModule.situationRoom)
                  ? () => onOpenModule(TgcgModule.situationRoom)
                  : null,
            ),
            _QueueItem(
              icon: Icons.document_scanner_outlined,
              title: 'Result submission requires human review',
              subtitle: 'OCR/manual-entry disagreement • Demo record',
              action: modules.contains(TgcgModule.resultCapture)
                  ? () => onOpenModule(TgcgModule.resultCapture)
                  : null,
            ),
            _QueueItem(
              icon: Icons.badge_outlined,
              title: 'Agent assignment pending verification',
              subtitle: 'Accreditation • Geographic scope incomplete',
              action: modules.contains(TgcgModule.accreditation)
                  ? () => onOpenModule(TgcgModule.accreditation)
                  : null,
            ),
            _QueueItem(
              icon: Icons.sync_problem_outlined,
              title: 'Offline sync queue contains unsent records',
              subtitle: 'Durable outbox • Awaiting connectivity',
              action: modules.contains(TgcgModule.governance)
                  ? () => onOpenModule(TgcgModule.governance)
                  : null,
            ),
          ],
        ),
      );
}

class _CoveragePanel extends StatelessWidget {
  const _CoveragePanel({required this.onOpenModule, required this.modules});

  final ValueChanged<TgcgModule> onOpenModule;
  final Set<TgcgModule> modules;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'National readiness snapshot',
        subtitle: 'Demonstration values until connected to verified operational data',
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
      (module: TgcgModule.fieldMonitoring, label: 'Report incident', icon: Icons.add_alert_outlined),
      (module: TgcgModule.resultCapture, label: 'Submit result', icon: Icons.ballot_outlined),
      (module: TgcgModule.collation, label: 'Open collation', icon: Icons.account_tree_outlined),
      (module: TgcgModule.accreditation, label: 'Manage agents', icon: Icons.badge_outlined),
      (module: TgcgModule.communications, label: 'Communications', icon: Icons.chat_bubble_outline_rounded),
      (module: TgcgModule.governance, label: 'Audit & sync', icon: Icons.shield_outlined),
    ].where((item) => modules.contains(item.module)).toList();

    return _Panel(
      title: 'Quick actions',
      subtitle: 'Actions shown are filtered by the current role',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: actions
            .map(
              (action) => OutlinedButton.icon(
                onPressed: () => onOpenModule(action.module),
                icon: Icon(action.icon),
                label: Text(action.label),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            )
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
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: TgcgApp.ink,
                          )),
                      Text(label,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
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
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    color: TgcgApp.ink,
                  )),
              const SizedBox(height: 4),
              Text(subtitle,
                  style: const TextStyle(fontSize: 11, color: TgcgApp.muted)),
              const SizedBox(height: 15),
              child,
            ],
          ),
        ),
      );
}

class _QueueItem extends StatelessWidget {
  const _QueueItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

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
              if (action != null)
                const Icon(Icons.chevron_right_rounded, color: TgcgApp.muted),
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
            Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(valueLabel,
                    style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.primary)),
              ],
            ),
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
  const _StatusBadge({required this.label, required this.icon, required this.color});

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
            Text(label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: .5,
                )),
          ],
        ),
      );
}
