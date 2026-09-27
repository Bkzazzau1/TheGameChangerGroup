import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../session.dart';
import 'field_operations_store.dart';

class SituationRoomPage extends StatelessWidget {
  const SituationRoomPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = FieldOperations.of(context);
    final incidents = store.incidentsForScope(session.scope);
    final reports = store.reportsForScope(session.scope);
    final open = incidents
        .where((item) => item.status != IncidentStatus.resolved && item.status != IncidentStatus.closed)
        .toList(growable: false);
    final critical = open.where((item) => item.severity == IncidentSeverity.critical).length;
    final high = open.where((item) => item.severity == IncidentSeverity.high).length;
    final unassigned = open.where((item) => item.assignedTeam == null).length;
    final mayCommand = TgcgPermissionPolicy.allows(session.role!, TgcgCapability.assignIncident);

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
                  const Text('Situation Room',
                      style: TextStyle(
                          fontSize: 28, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                  const SizedBox(height: 7),
                  Text('${session.scope.label}: live incident command, verification and field coordination.',
                      style: const TextStyle(color: TgcgApp.muted, height: 1.5)),
                ],
              ),
            ),
            const _LiveBadge(),
          ],
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _CommandMetric('Open incidents', '${open.length}', Icons.warning_amber_rounded),
            _CommandMetric('Critical', '$critical', Icons.crisis_alert_rounded,
                color: const Color(0xFFB42318)),
            _CommandMetric('High priority', '$high', Icons.priority_high_rounded,
                color: const Color(0xFFD92D20)),
            _CommandMetric('Unassigned', '$unassigned', Icons.person_off_outlined,
                color: const Color(0xFFD97706)),
            _CommandMetric('Field reports', '${reports.length}', Icons.feed_outlined),
          ],
        ),
        const SizedBox(height: 16),
        if (mayCommand) ...[
          _CommandBar(openIncidents: open),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(builder: (context, constraints) {
          if (constraints.maxWidth < 980) {
            return Column(
              children: [
                _PriorityQueue(incidents: open),
                const SizedBox(height: 14),
                _CommandSummary(incidents: open, reports: reports),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 7, child: _PriorityQueue(incidents: open)),
              const SizedBox(width: 14),
              Expanded(flex: 4, child: _CommandSummary(incidents: open, reports: reports)),
            ],
          );
        }),
        const SizedBox(height: 14),
        _ResponseMatrix(incidents: open),
      ],
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFECFDF3),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFABEFC6)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.circle, size: 8, color: Color(0xFF079455)),
            SizedBox(width: 7),
            Text('LIVE COMMAND',
                style: TextStyle(
                    color: Color(0xFF067647), fontSize: 10, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

class _CommandMetric extends StatelessWidget {
  const _CommandMetric(this.label, this.value, this.icon, {this.color = TgcgApp.primary});
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                    Text(label, style: const TextStyle(color: TgcgApp.muted, fontSize: 10.5)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _CommandBar extends StatelessWidget {
  const _CommandBar({required this.openIncidents});
  final List<FieldIncident> openIncidents;

  @override
  Widget build(BuildContext context) {
    final store = FieldOperations.of(context, listen: false);
    final reported = openIncidents.where((item) => item.status == IncidentStatus.reported).toList();
    final escalatable = openIncidents
        .where((item) =>
            item.status != IncidentStatus.escalated &&
            (item.severity == IncidentSeverity.high || item.severity == IncidentSeverity.critical))
        .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text('Command actions',
                  style: TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
            ),
            FilledButton.icon(
              onPressed: reported.isEmpty
                  ? null
                  : () => store.updateIncidentStatus(reported.first.id, IncidentStatus.acknowledged),
              icon: const Icon(Icons.done_rounded),
              label: Text('Acknowledge next (${reported.length})'),
            ),
            OutlinedButton.icon(
              onPressed: escalatable.isEmpty
                  ? null
                  : () => store.updateIncidentStatus(escalatable.first.id, IncidentStatus.escalated),
              icon: const Icon(Icons.arrow_upward_rounded),
              label: Text('Escalate priority (${escalatable.length})'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PriorityQueue extends StatelessWidget {
  const _PriorityQueue({required this.incidents});
  final List<FieldIncident> incidents;

  @override
  Widget build(BuildContext context) {
    final sorted = [...incidents]
      ..sort((a, b) {
        final severity = _severityRank(b.severity).compareTo(_severityRank(a.severity));
        if (severity != 0) return severity;
        return b.reportedAt.compareTo(a.reportedAt);
      });

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Priority command queue',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
            const SizedBox(height: 4),
            const Text('Sorted by severity, then latest report time.',
                style: TextStyle(color: TgcgApp.muted, fontSize: 11)),
            const SizedBox(height: 14),
            if (sorted.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: Text('No unresolved incidents in this scope.')),
              )
            else
              ...sorted.map((incident) => _PriorityRow(incident: incident)),
          ],
        ),
      ),
    );
  }
}

class _PriorityRow extends StatelessWidget {
  const _PriorityRow({required this.incident});
  final FieldIncident incident;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(incident.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAF9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE4EAE7)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.crisis_alert_outlined, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(incident.title,
                    style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                const SizedBox(height: 4),
                Text(incident.scope.label,
                    style: const TextStyle(color: TgcgApp.muted, fontSize: 10.5)),
                const SizedBox(height: 7),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    _Chip(_label(incident.severity.name), color),
                    _Chip(_label(incident.status.name), TgcgApp.primary),
                    if (incident.assignedTeam != null)
                      _Chip(incident.assignedTeam!, const Color(0xFF52606D)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CommandSummary extends StatelessWidget {
  const _CommandSummary({required this.incidents, required this.reports});
  final List<FieldIncident> incidents;
  final List<FieldReport> reports;

  @override
  Widget build(BuildContext context) {
    final investigating = incidents.where((item) => item.status == IncidentStatus.investigating).length;
    final escalated = incidents.where((item) => item.status == IncidentStatus.escalated).length;
    final evidence = incidents.fold<int>(0, (total, item) => total + item.evidence.length);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Command summary',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
            const SizedBox(height: 14),
            _SummaryLine('Investigating', '$investigating'),
            _SummaryLine('Escalated', '$escalated'),
            _SummaryLine('Evidence retained', '$evidence'),
            _SummaryLine('Field reports', '${reports.length}'),
            const Divider(height: 28),
            const Text('Data note',
                style: TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
            const SizedBox(height: 5),
            const Text(
              'Current records are clearly labelled prototype operational data. Production entries will be supplied by authenticated field personnel and backend services.',
              style: TextStyle(color: TgcgApp.muted, height: 1.45, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: TgcgApp.muted))),
            Text(value,
                style: const TextStyle(color: TgcgApp.ink, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

class _ResponseMatrix extends StatelessWidget {
  const _ResponseMatrix({required this.incidents});
  final List<FieldIncident> incidents;

  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    for (final incident in incidents) {
      final key = incident.assignedTeam ?? 'Unassigned';
      groups[key] = (groups[key] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Response ownership',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
            const SizedBox(height: 4),
            const Text('Open incidents grouped by current response owner.',
                style: TextStyle(color: TgcgApp.muted, fontSize: 11)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: groups.entries
                  .map((entry) => Container(
                        width: 230,
                        padding: const EdgeInsets.all(13),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAF9),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: const Color(0xFFE4EAE7)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.groups_2_outlined, color: TgcgApp.primary),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(entry.key,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: TgcgApp.ink, fontWeight: FontWeight.w800, fontSize: 11.5)),
                            ),
                            Text('${entry.value}',
                                style: const TextStyle(
                                    color: TgcgApp.primary, fontWeight: FontWeight.w900)),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(color: color.withValues(alpha: .09), borderRadius: BorderRadius.circular(999)),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w900)),
      );
}

int _severityRank(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => 5,
      IncidentSeverity.high => 4,
      IncidentSeverity.medium => 3,
      IncidentSeverity.low => 2,
      IncidentSeverity.info => 1,
    };

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
