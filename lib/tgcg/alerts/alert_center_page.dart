import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/tgcg_design.dart';

enum _AlertSeverity { critical, warning, info, success }

class _OpsAlert {
  const _OpsAlert({
    required this.id,
    required this.title,
    required this.detail,
    required this.location,
    required this.time,
    required this.severity,
    this.acknowledged = false,
  });

  final String id;
  final String title;
  final String detail;
  final String location;
  final String time;
  final _AlertSeverity severity;
  final bool acknowledged;

  _OpsAlert copyWith({bool? acknowledged}) => _OpsAlert(
        id: id,
        title: title,
        detail: detail,
        location: location,
        time: time,
        severity: severity,
        acknowledged: acknowledged ?? this.acknowledged,
      );
}

class AlertCenterPage extends StatefulWidget {
  const AlertCenterPage({super.key});

  @override
  State<AlertCenterPage> createState() => _AlertCenterPageState();
}

class _AlertCenterPageState extends State<AlertCenterPage> {
  late List<_OpsAlert> alerts = const [
    _OpsAlert(
      id: 'ALT-001',
      title: 'Critical incident requires acknowledgement',
      detail: 'High-priority field incident has been escalated for coordinator review.',
      location: 'Makurdi • Ward 01',
      time: '2 min ago',
      severity: _AlertSeverity.critical,
    ),
    _OpsAlert(
      id: 'ALT-002',
      title: 'Result OCR mismatch requires review',
      detail: 'Manual figures and extracted result-form totals need human confirmation.',
      location: 'Kaduna North • PU 002',
      time: '5 min ago',
      severity: _AlertSeverity.warning,
    ),
    _OpsAlert(
      id: 'ALT-003',
      title: 'Evidence package received',
      detail: 'Photo, video and GPS evidence have been linked to a field report.',
      location: 'Kaduna North • Ward 01',
      time: '8 min ago',
      severity: _AlertSeverity.info,
    ),
    _OpsAlert(
      id: 'ALT-004',
      title: 'Polling-unit agent checked in',
      detail: 'Assigned device and field account are active for election-day duty.',
      location: 'Kaduna North • PU 001',
      time: '11 min ago',
      severity: _AlertSeverity.success,
    ),
    _OpsAlert(
      id: 'ALT-005',
      title: 'Local coordination meeting starts soon',
      detail: 'Ward field briefing is scheduled to begin in five minutes.',
      location: 'Makurdi • Ward 01',
      time: '14 min ago',
      severity: _AlertSeverity.info,
    ),
  ];

  _AlertSeverity? filter;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final visible = filter == null
        ? alerts
        : alerts.where((item) => item.severity == filter).toList(growable: false);
    final pending = alerts.where((item) => !item.acknowledged).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'OPERATIONAL ATTENTION',
          title: 'Alert Centre',
          subtitle:
              '${session.scope.label}: incidents, verification events, field activity and coordination notices requiring attention.',
          trailing: TgcgStatusPill(
            label: '$pending OPEN',
            color: pending == 0 ? TgcgColors.success : TgcgColors.warning,
            icon: Icons.notifications_active_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _AlertMetrics(alerts: alerts),
        const SizedBox(height: 16),
        TgcgSectionCard(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: 'All',
                active: filter == null,
                onTap: () => setState(() => filter = null),
              ),
              for (final severity in _AlertSeverity.values)
                _FilterChip(
                  label: _severityLabel(severity),
                  active: filter == severity,
                  onTap: () => setState(() => filter = severity),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TgcgSectionCard(
          title: 'Operational feed',
          subtitle: '${visible.length} alert${visible.length == 1 ? '' : 's'} in the current view.',
          trailing: pending == 0
              ? null
              : TextButton.icon(
                  onPressed: _acknowledgeAll,
                  icon: const Icon(Icons.done_all_rounded, size: 17),
                  label: const Text('Acknowledge all'),
                ),
          child: Column(
            children: visible
                .map(
                  (alert) => _AlertRow(
                    alert: alert,
                    onAcknowledge: alert.acknowledged ? null : () => _acknowledge(alert.id),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  void _acknowledge(String id) {
    setState(() {
      alerts = alerts
          .map((item) => item.id == id ? item.copyWith(acknowledged: true) : item)
          .toList(growable: false);
    });
  }

  void _acknowledgeAll() {
    setState(() {
      alerts = alerts.map((item) => item.copyWith(acknowledged: true)).toList(growable: false);
    });
  }
}

class _AlertMetrics extends StatelessWidget {
  const _AlertMetrics({required this.alerts});
  final List<_OpsAlert> alerts;

  @override
  Widget build(BuildContext context) {
    int count(_AlertSeverity severity) => alerts.where((item) => item.severity == severity && !item.acknowledged).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 4 : constraints.maxWidth >= 520 ? 2 : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            TgcgMetricCard(
              width: width,
              label: 'Critical',
              value: '${count(_AlertSeverity.critical)}',
              detail: 'Immediate attention',
              icon: Icons.crisis_alert_rounded,
              tone: TgcgMetricTone.danger,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Review needed',
              value: '${count(_AlertSeverity.warning)}',
              detail: 'Human review or follow-up',
              icon: Icons.warning_amber_rounded,
              tone: TgcgMetricTone.warning,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Information',
              value: '${count(_AlertSeverity.info)}',
              detail: 'Operational updates',
              icon: Icons.info_outline_rounded,
              tone: TgcgMetricTone.info,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Positive events',
              value: '${count(_AlertSeverity.success)}',
              detail: 'Completed operational activity',
              icon: Icons.check_circle_outline_rounded,
              tone: TgcgMetricTone.success,
            ),
          ],
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.active, required this.onTap});
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: active ? TgcgColors.primary : TgcgColors.surfaceSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? TgcgColors.primary : TgcgColors.border),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: active ? Colors.white : TgcgColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
          ),
        ),
      );
}

class _AlertRow extends StatelessWidget {
  const _AlertRow({required this.alert, required this.onAcknowledge});
  final _OpsAlert alert;
  final VoidCallback? onAcknowledge;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(alert.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: alert.acknowledged ? TgcgColors.surfaceSoft : color.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: alert.acknowledged ? TgcgColors.border : color.withValues(alpha: .25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: color.withValues(alpha: .11), borderRadius: BorderRadius.circular(13)),
              child: Icon(_severityIcon(alert.severity), color: color, size: 21),
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
                          alert.title,
                          style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TgcgStatusPill(
                        label: alert.acknowledged ? 'ACKNOWLEDGED' : _severityLabel(alert.severity).toUpperCase(),
                        color: alert.acknowledged ? TgcgColors.success : color,
                        compact: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(alert.detail, style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5, height: 1.35)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on_outlined, size: 14, color: TgcgColors.muted),
                      const SizedBox(width: 4),
                      Expanded(child: Text(alert.location, style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5))),
                      Text(alert.time, style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5)),
                      if (onAcknowledge != null) ...[
                        const SizedBox(width: 10),
                        TextButton(onPressed: onAcknowledge, child: const Text('Acknowledge')),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _severityLabel(_AlertSeverity value) => switch (value) {
      _AlertSeverity.critical => 'Critical',
      _AlertSeverity.warning => 'Review',
      _AlertSeverity.info => 'Info',
      _AlertSeverity.success => 'Completed',
    };

Color _severityColor(_AlertSeverity value) => switch (value) {
      _AlertSeverity.critical => TgcgColors.danger,
      _AlertSeverity.warning => TgcgColors.warning,
      _AlertSeverity.info => TgcgColors.info,
      _AlertSeverity.success => TgcgColors.success,
    };

IconData _severityIcon(_AlertSeverity value) => switch (value) {
      _AlertSeverity.critical => Icons.crisis_alert_rounded,
      _AlertSeverity.warning => Icons.warning_amber_rounded,
      _AlertSeverity.info => Icons.info_outline_rounded,
      _AlertSeverity.success => Icons.check_circle_outline_rounded,
    };
