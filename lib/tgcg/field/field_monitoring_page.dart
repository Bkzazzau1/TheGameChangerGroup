import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/models.dart';
import '../session.dart';
import 'field_operations_store.dart';

class FieldMonitoringPage extends StatefulWidget {
  const FieldMonitoringPage({super.key});

  @override
  State<FieldMonitoringPage> createState() => _FieldMonitoringPageState();
}

class _FieldMonitoringPageState extends State<FieldMonitoringPage> {
  IncidentSeverity? severityFilter;
  IncidentStatus? statusFilter;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = FieldOperations.of(context);
    var incidents = store.incidentsForScope(session.scope);
    final reports = store.reportsForScope(session.scope);

    if (severityFilter != null) {
      incidents = incidents.where((item) => item.severity == severityFilter).toList();
    }
    if (statusFilter != null) {
      incidents = incidents.where((item) => item.status == statusFilter).toList();
    }

    final high = incidents.where((item) =>
        item.severity == IncidentSeverity.high || item.severity == IncidentSeverity.critical).length;
    final evidence = incidents.fold<int>(0, (total, item) => total + item.evidence.length);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text('Field Monitoring',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
        const SizedBox(height: 7),
        Text('${session.scope.label}: incidents, reports, evidence and operational follow-up.',
            style: const TextStyle(color: TgcgApp.muted, height: 1.5)),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric('Open incidents', '${incidents.length}', Icons.warning_amber_rounded),
            _Metric('High priority', '$high', Icons.crisis_alert_rounded),
            _Metric('Field reports', '${reports.length}', Icons.feed_outlined),
            _Metric('Evidence items', '$evidence', Icons.attach_file_rounded),
          ],
        ),
        const SizedBox(height: 16),
        _FilterBar(
          severity: severityFilter,
          status: statusFilter,
          onSeverityChanged: (value) => setState(() => severityFilter = value),
          onStatusChanged: (value) => setState(() => statusFilter = value),
          onClear: () => setState(() {
            severityFilter = null;
            statusFilter = null;
          }),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 930) {
            return Column(
              children: [
                _IncidentPanel(incidents: incidents),
                const SizedBox(height: 14),
                _ReportsPanel(reports: reports),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: _IncidentPanel(incidents: incidents)),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: _ReportsPanel(reports: reports)),
            ],
          );
        }),
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
        width: 210,
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                    Text(label, style: const TextStyle(color: TgcgApp.muted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.severity,
    required this.status,
    required this.onSeverityChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final IncidentSeverity? severity;
  final IncidentStatus? status;
  final ValueChanged<IncidentSeverity?> onSeverityChanged;
  final ValueChanged<IncidentStatus?> onStatusChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<IncidentSeverity?>(
                  initialValue: severity,
                  decoration: const InputDecoration(labelText: 'Severity'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All severities')),
                    ...IncidentSeverity.values.map(
                      (value) => DropdownMenuItem(value: value, child: Text(_label(value.name))),
                    ),
                  ],
                  onChanged: onSeverityChanged,
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<IncidentStatus?>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All statuses')),
                    ...IncidentStatus.values.map(
                      (value) => DropdownMenuItem(value: value, child: Text(_label(value.name))),
                    ),
                  ],
                  onChanged: onStatusChanged,
                ),
              ),
              TextButton.icon(onPressed: onClear, icon: const Icon(Icons.clear_rounded), label: const Text('Clear')),
            ],
          ),
        ),
      );
}

class _IncidentPanel extends StatelessWidget {
  const _IncidentPanel({required this.incidents});
  final List<FieldIncident> incidents;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Incident feed',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
              const SizedBox(height: 4),
              const Text('Operational incidents within your authorized geographic scope.',
                  style: TextStyle(color: TgcgApp.muted, fontSize: 11)),
              const SizedBox(height: 14),
              if (incidents.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: Text('No incidents match the selected filters.')),
                )
              else
                ...incidents.map((incident) => _IncidentTile(incident: incident)),
            ],
          ),
        ),
      );
}

class _IncidentTile extends StatelessWidget {
  const _IncidentTile({required this.incident});
  final FieldIncident incident;

  @override
  Widget build(BuildContext context) {
    final store = FieldOperations.of(context, listen: false);
    final accent = _severityColor(incident.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAE7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(width: 8, height: 42, decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(99))),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(incident.title,
                        style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                    const SizedBox(height: 4),
                    Text('${incident.scope.label} • ${_label(incident.category)}',
                        style: const TextStyle(color: TgcgApp.muted, fontSize: 11)),
                  ],
                ),
              ),
              _Pill(_label(incident.severity.name), accent),
            ],
          ),
          if (incident.summary != null) ...[
            const SizedBox(height: 10),
            Text(incident.summary!, style: const TextStyle(color: TgcgApp.muted, height: 1.45)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(_label(incident.status.name), TgcgApp.primary),
              if (incident.assignedTeam != null)
                _Pill(incident.assignedTeam!, const Color(0xFF52606D)),
              if (incident.evidence.isNotEmpty)
                _Pill('${incident.evidence.length} evidence', const Color(0xFF6B4F9B)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Spacer(),
              PopupMenuButton<IncidentStatus>(
                tooltip: 'Update incident status',
                onSelected: (value) => store.updateIncidentStatus(incident.id, value),
                itemBuilder: (_) => IncidentStatus.values
                    .map((status) => PopupMenuItem(value: status, child: Text(_label(status.name))))
                    .toList(),
                child: const Text('Update status',
                    style: TextStyle(color: TgcgApp.primary, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportsPanel extends StatelessWidget {
  const _ReportsPanel({required this.reports});
  final List<FieldReport> reports;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Field reports',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
              const SizedBox(height: 4),
              const Text('Recent structured updates from field teams.',
                  style: TextStyle(color: TgcgApp.muted, fontSize: 11)),
              const SizedBox(height: 14),
              if (reports.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No reports in this scope.')),
                )
              else
                ...reports.map((report) => Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAF9),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(color: const Color(0xFFE4EAE7)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(report.category,
                              style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                          const SizedBox(height: 4),
                          Text(report.scope.label,
                              style: const TextStyle(color: TgcgApp.muted, fontSize: 10.5)),
                          const SizedBox(height: 8),
                          Text(report.summary,
                              style: const TextStyle(color: TgcgApp.muted, height: 1.45)),
                          const SizedBox(height: 8),
                          _Pill(_label(report.status.name), TgcgApp.primary),
                        ],
                      ),
                    )),
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
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900)),
      );
}

Color _severityColor(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => const Color(0xFFB42318),
      IncidentSeverity.high => const Color(0xFFD92D20),
      IncidentSeverity.medium => const Color(0xFFD97706),
      IncidentSeverity.low => const Color(0xFF2563EB),
      IncidentSeverity.info => const Color(0xFF52606D),
    };

String _label(String value) {
  final spaced = value.replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (match) => '${match.group(1)} ${match.group(2)}');
  return spaced.isEmpty ? spaced : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
