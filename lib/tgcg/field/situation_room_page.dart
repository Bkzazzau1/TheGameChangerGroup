import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';

class SituationRoomPage extends StatefulWidget {
  const SituationRoomPage({super.key});

  @override
  State<SituationRoomPage> createState() => _SituationRoomPageState();
}

class _SituationRoomPageState extends State<SituationRoomPage> {
  String? selectedIncidentId;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = FieldOperations.of(context);
    final incidents = store.incidentsForScope(session.scope);
    final reports = store.reportsForScope(session.scope);
    final open = incidents
        .where(
          (item) =>
              item.status != IncidentStatus.resolved &&
              item.status != IncidentStatus.closed,
        )
        .toList(growable: false)
      ..sort((a, b) {
        final severity =
            _severityRank(b.severity).compareTo(_severityRank(a.severity));
        if (severity != 0) return severity;
        return b.reportedAt.compareTo(a.reportedAt);
      });

    if (selectedIncidentId == null ||
        !incidents.any((item) => item.id == selectedIncidentId)) {
      selectedIncidentId = open.isNotEmpty
          ? open.first.id
          : incidents.isNotEmpty
              ? incidents.first.id
              : null;
    }

    final selected = selectedIncidentId == null
        ? null
        : incidents.where((item) => item.id == selectedIncidentId).firstOrNull;
    final critical =
        open.where((item) => item.severity == IncidentSeverity.critical).length;
    final high =
        open.where((item) => item.severity == IncidentSeverity.high).length;
    final unassigned = open.where((item) => item.assignedTeam == null).length;
    final evidence = incidents.fold<int>(
      0,
      (total, item) => total + item.evidence.length,
    );

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TgcgPageHeader(
          eyebrow: 'Live command centre',
          title: 'Situation Room',
          subtitle:
              '${session.scope.label}: real-time incident command, evidence review and field coordination.',
          trailing: const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TgcgStatusPill(
                label: 'LIVE COMMAND',
                color: TgcgColors.success,
                icon: Icons.circle,
              ),
              TgcgStatusPill(
                label: 'DEMO FEED',
                color: TgcgColors.warning,
                icon: Icons.science_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _MetricsStrip(
          open: open.length,
          critical: critical,
          high: high,
          unassigned: unassigned,
          reports: reports.length,
          evidence: evidence,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final priorityRail = _PriorityRail(
              incidents: open,
              selectedIncidentId: selectedIncidentId,
              onSelect: (id) => setState(() => selectedIncidentId = id),
            );
            final map = _CommandMap(
              scope: session.scope,
              incidents: open,
              selectedIncidentId: selectedIncidentId,
              onSelect: (id) => setState(() => selectedIncidentId = id),
            );
            final inspector = _IncidentInspector(
              incident: selected,
              role: session.role!,
            );

            if (constraints.maxWidth < 1180) {
              return Column(
                children: [
                  map,
                  const SizedBox(height: 14),
                  if (constraints.maxWidth >= 760)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: priorityRail),
                        const SizedBox(width: 14),
                        Expanded(child: inspector),
                      ],
                    )
                  else ...[
                    priorityRail,
                    const SizedBox(height: 14),
                    inspector,
                  ],
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 310, child: priorityRail),
                const SizedBox(width: 14),
                Expanded(child: map),
                const SizedBox(width: 14),
                SizedBox(width: 350, child: inspector),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final timeline = _ActivityTimeline(
              incidents: incidents,
              reports: reports,
              onIncidentSelected: (id) =>
                  setState(() => selectedIncidentId = id),
            );
            final ownership = _ResponseOwnership(incidents: open);
            if (constraints.maxWidth < 900) {
              return Column(
                children: [
                  timeline,
                  const SizedBox(height: 14),
                  ownership,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: timeline),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: ownership),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _MetricsStrip extends StatelessWidget {
  const _MetricsStrip({
    required this.open,
    required this.critical,
    required this.high,
    required this.unassigned,
    required this.reports,
    required this.evidence,
  });

  final int open;
  final int critical;
  final int high;
  final int unassigned;
  final int reports;
  final int evidence;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1180
              ? 6
              : constraints.maxWidth >= 760
                  ? 3
                  : constraints.maxWidth >= 480
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
                label: 'Open incidents',
                value: '$open',
                detail: 'Unresolved events in scope',
                icon: Icons.warning_amber_rounded,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Critical',
                value: '$critical',
                detail: 'Immediate command attention',
                icon: Icons.crisis_alert_rounded,
                tone: TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'High priority',
                value: '$high',
                detail: 'High-severity active incidents',
                icon: Icons.priority_high_rounded,
                tone: TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Unassigned',
                value: '$unassigned',
                detail: 'Awaiting response ownership',
                icon: Icons.person_off_outlined,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Field reports',
                value: '$reports',
                detail: 'Structured operational updates',
                icon: Icons.feed_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Evidence retained',
                value: '$evidence',
                detail: 'Linked media/provenance records',
                icon: Icons.perm_media_outlined,
                tone: TgcgMetricTone.success,
              ),
            ],
          );
        },
      );
}

class _PriorityRail extends StatelessWidget {
  const _PriorityRail({
    required this.incidents,
    required this.selectedIncidentId,
    required this.onSelect,
  });

  final List<FieldIncident> incidents;
  final String? selectedIncidentId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Priority queue',
        subtitle: 'Severity first, then most recent.',
        child: incidents.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.task_alt_rounded,
                title: 'No active incidents',
                message: 'There are no unresolved incidents in this scope.',
              )
            : Column(
                children: incidents
                    .map(
                      (incident) => _PriorityItem(
                        incident: incident,
                        selected: incident.id == selectedIncidentId,
                        onTap: () => onSelect(incident.id),
                      ),
                    )
                    .toList(),
              ),
      );
}

class _PriorityItem extends StatelessWidget {
  const _PriorityItem({
    required this.incident,
    required this.selected,
    required this.onTap,
  });

  final FieldIncident incident;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(incident.severity);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: selected ? color.withValues(alpha: .06) : TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? color.withValues(alpha: .45) : TgcgColors.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(Icons.crisis_alert_outlined, color: color, size: 19),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incident.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        incident.scope.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          TgcgStatusPill(
                            label: _label(incident.severity.name),
                            color: color,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label: _label(incident.status.name),
                            color: TgcgColors.primaryMid,
                            compact: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandMap extends StatelessWidget {
  const _CommandMap({
    required this.scope,
    required this.incidents,
    required this.selectedIncidentId,
    required this.onSelect,
  });

  final GeographicScope scope;
  final List<FieldIncident> incidents;
  final String? selectedIncidentId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Live operational map',
        subtitle:
            'Incident command surface. Production polling-unit geometry and heatmaps will be rendered from the GIS/PostGIS layer.',
        trailing: const TgcgStatusPill(
          label: 'GIS PREVIEW',
          color: TgcgColors.info,
          icon: Icons.map_outlined,
          compact: true,
        ),
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          children: [
            Container(
              height: 430,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: TgcgColors.primaryDark,
                borderRadius: BorderRadius.circular(18),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const positions = <Offset>[
                    Offset(.18, .26),
                    Offset(.56, .20),
                    Offset(.76, .46),
                    Offset(.32, .63),
                    Offset(.60, .72),
                    Offset(.84, .76),
                    Offset(.15, .78),
                  ];
                  return Stack(
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: _CommandGridPainter()),
                      ),
                      Positioned(
                        left: 18,
                        top: 16,
                        child: TgcgStatusPill(
                          label: scope.label.toUpperCase(),
                          color: TgcgColors.accent,
                          icon: Icons.location_on_outlined,
                          compact: true,
                        ),
                      ),
                      Positioned(
                        right: 18,
                        top: 16,
                        child: Wrap(
                          spacing: 10,
                          children: const [
                            _MapLegend(label: 'Critical / high', color: TgcgColors.danger),
                            _MapLegend(label: 'Medium', color: TgcgColors.warning),
                            _MapLegend(label: 'Low / info', color: TgcgColors.info),
                          ],
                        ),
                      ),
                      ...List.generate(incidents.length, (index) {
                        final incident = incidents[index];
                        final p = positions[index % positions.length];
                        final selected = incident.id == selectedIncidentId;
                        final color = _severityColor(incident.severity);
                        final maxLeft = constraints.maxWidth - 150;
                        final maxTop = constraints.maxHeight - 95;
                        return Positioned(
                          left: (p.dx * maxLeft).clamp(8, maxLeft).toDouble(),
                          top: (p.dy * maxTop).clamp(55, maxTop).toDouble(),
                          child: _MapIncidentNode(
                            incident: incident,
                            color: color,
                            selected: selected,
                            onTap: () => onSelect(incident.id),
                          ),
                        );
                      }),
                      if (incidents.isEmpty)
                        const Center(
                          child: Text(
                            'No active incident markers in this scope',
                            style: TextStyle(
                              color: Color(0xFFB8CEC6),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      const Positioned(
                        left: 18,
                        right: 18,
                        bottom: 14,
                        child: Row(
                          children: [
                            Icon(Icons.layers_outlined, color: Color(0xFFB8CEC6), size: 16),
                            SizedBox(width: 6),
                            Text(
                              'Polling units  •  Incidents  •  Agent positions  •  Result progress',
                              style: TextStyle(
                                color: Color(0xFFB8CEC6),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, size: 16, color: TgcgColors.muted),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '${incidents.length} active incident marker${incidents.length == 1 ? '' : 's'} in the authorized scope. Marker positions are prototype layout positions until GIS geometry is connected.',
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10.5,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _MapIncidentNode extends StatelessWidget {
  const _MapIncidentNode({
    required this.incident,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final FieldIncident incident;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: selected ? 142 : 42,
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: selected ? 9 : 0),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF173B34) : color,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? color : Colors.white.withValues(alpha: .3),
              width: selected ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: .25),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: selected
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              const Icon(Icons.location_on_rounded, color: Colors.white, size: 19),
              if (selected) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    incident.scope.lgaName ?? incident.scope.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 9.5,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFB8CEC6), fontSize: 9.5),
          ),
        ],
      );
}

class _IncidentInspector extends StatelessWidget {
  const _IncidentInspector({required this.incident, required this.role});

  final FieldIncident? incident;
  final TgcgRole role;

  @override
  Widget build(BuildContext context) {
    final item = incident;
    if (item == null) {
      return const TgcgSectionCard(
        title: 'Incident inspector',
        subtitle: 'Select an incident from the queue or map.',
        child: TgcgEmptyState(
          icon: Icons.touch_app_outlined,
          title: 'Nothing selected',
          message: 'Select an incident to inspect evidence and command actions.',
        ),
      );
    }

    final color = _severityColor(item.severity);
    final canAcknowledge = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.acknowledgeIncident,
    );
    final canAssign = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.assignIncident,
    );
    final canClose = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.closeIncident,
    );

    return TgcgSectionCard(
      title: 'Incident inspector',
      subtitle: item.id,
      trailing: TgcgStatusPill(
        label: _label(item.severity.name),
        color: color,
        compact: true,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.summary ?? 'No additional incident summary was supplied.',
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 11,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 14),
          _InspectorLine(
            icon: Icons.category_outlined,
            label: 'Category',
            value: item.category,
          ),
          _InspectorLine(
            icon: Icons.location_on_outlined,
            label: 'Location',
            value: item.scope.label,
          ),
          _InspectorLine(
            icon: Icons.person_outline_rounded,
            label: 'Reporter',
            value: item.reporterId,
          ),
          _InspectorLine(
            icon: Icons.groups_2_outlined,
            label: 'Response owner',
            value: item.assignedTeam ?? 'Unassigned',
          ),
          _InspectorLine(
            icon: Icons.schedule_rounded,
            label: 'Reported',
            value: _timeLabel(item.reportedAt),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TgcgStatusPill(
                label: _label(item.status.name),
                color: TgcgColors.primaryMid,
                compact: true,
              ),
              const Spacer(),
              Text(
                '${item.evidence.length} evidence',
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (item.evidence.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: TgcgColors.surfaceSoft,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: TgcgColors.border),
              ),
              child: const Text(
                'No linked media evidence for this incident.',
                style: TextStyle(color: TgcgColors.muted, fontSize: 10.5),
              ),
            )
          else
            ...item.evidence.map((evidence) => _EvidenceTile(evidence: evidence)),
          if (canAcknowledge || canAssign || canClose) ...[
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 14),
            const Text(
              'Command actions',
              style: TextStyle(
                color: TgcgColors.ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canAcknowledge && item.status == IncidentStatus.reported)
                  FilledButton.icon(
                    onPressed: () => FieldOperations.of(context, listen: false)
                        .updateIncidentStatus(
                      item.id,
                      IncidentStatus.acknowledged,
                    ),
                    icon: const Icon(Icons.done_rounded, size: 17),
                    label: const Text('Acknowledge'),
                  ),
                if (canAssign &&
                    item.status != IncidentStatus.investigating &&
                    item.status != IncidentStatus.resolved &&
                    item.status != IncidentStatus.closed)
                  OutlinedButton.icon(
                    onPressed: () => FieldOperations.of(context, listen: false)
                        .updateIncidentStatus(
                      item.id,
                      IncidentStatus.investigating,
                    ),
                    icon: const Icon(Icons.manage_search_rounded, size: 17),
                    label: const Text('Investigate'),
                  ),
                if (canAssign &&
                    (item.severity == IncidentSeverity.high ||
                        item.severity == IncidentSeverity.critical) &&
                    item.status != IncidentStatus.escalated)
                  OutlinedButton.icon(
                    onPressed: () => FieldOperations.of(context, listen: false)
                        .updateIncidentStatus(
                      item.id,
                      IncidentStatus.escalated,
                    ),
                    icon: const Icon(Icons.arrow_upward_rounded, size: 17),
                    label: const Text('Escalate'),
                  ),
                if (canClose &&
                    item.status != IncidentStatus.resolved &&
                    item.status != IncidentStatus.closed)
                  OutlinedButton.icon(
                    onPressed: () => FieldOperations.of(context, listen: false)
                        .updateIncidentStatus(
                      item.id,
                      IncidentStatus.resolved,
                    ),
                    icon: const Icon(Icons.task_alt_rounded, size: 17),
                    label: const Text('Resolve'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _EvidenceTile extends StatelessWidget {
  const _EvidenceTile({required this.evidence});

  final EvidenceAttachment evidence;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: TgcgColors.primaryDark,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                _evidenceIcon(evidence.type),
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    evidence.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _label(evidence.type.name),
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                  ),
                  if (evidence.contentHash != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      evidence.contentHash!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TgcgColors.success,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w800,
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

class _InspectorLine extends StatelessWidget {
  const _InspectorLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: TgcgColors.muted),
            const SizedBox(width: 8),
            SizedBox(
              width: 86,
              child: Text(
                label,
                style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
              ),
            ),
            Expanded(
              child: Text(
                value,
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

class _ActivityTimeline extends StatelessWidget {
  const _ActivityTimeline({
    required this.incidents,
    required this.reports,
    required this.onIncidentSelected,
  });

  final List<FieldIncident> incidents;
  final List<FieldReport> reports;
  final ValueChanged<String> onIncidentSelected;

  @override
  Widget build(BuildContext context) {
    final events = <_ActivityEvent>[
      ...incidents.map(
        (incident) => _ActivityEvent(
          title: incident.title,
          subtitle:
              '${incident.scope.label} • ${_label(incident.status.name)}',
          timestamp: incident.reportedAt,
          icon: Icons.crisis_alert_outlined,
          color: _severityColor(incident.severity),
          incidentId: incident.id,
        ),
      ),
      ...reports.map(
        (report) => _ActivityEvent(
          title: report.category,
          subtitle: '${report.scope.label} • ${report.summary}',
          timestamp: report.reportedAt,
          icon: Icons.feed_outlined,
          color: TgcgColors.info,
          incidentId: report.incidentId,
        ),
      ),
    ]..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return TgcgSectionCard(
      title: 'Live event stream',
      subtitle: 'Latest incidents and structured field reports in this scope.',
      child: events.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.timeline_outlined,
              title: 'No activity yet',
              message: 'New incidents and field reports will appear here.',
            )
          : Column(
              children: events.take(8).map((event) {
                return InkWell(
                  onTap: event.incidentId == null
                      ? null
                      : () => onIncidentSelected(event.incidentId!),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: event.color.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(event.icon, color: event.color, size: 17),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                event.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TgcgColors.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                event.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 9.5,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _timeLabel(event.timestamp),
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _ResponseOwnership extends StatelessWidget {
  const _ResponseOwnership({required this.incidents});

  final List<FieldIncident> incidents;

  @override
  Widget build(BuildContext context) {
    final groups = <String, int>{};
    for (final incident in incidents) {
      final key = incident.assignedTeam ?? 'Unassigned';
      groups[key] = (groups[key] ?? 0) + 1;
    }
    final entries = groups.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return TgcgSectionCard(
      title: 'Response ownership',
      subtitle: 'Open incidents by current response desk.',
      child: entries.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.groups_2_outlined,
              title: 'No active ownership',
              message: 'There are no open incidents assigned in this scope.',
            )
          : Column(
              children: entries.map((entry) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: TgcgColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: TgcgColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 35,
                        height: 35,
                        decoration: BoxDecoration(
                          color: TgcgColors.primarySoft,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.groups_2_outlined,
                          color: TgcgColors.primary,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          entry.key,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: entry.key == 'Unassigned'
                              ? TgcgColors.warning.withValues(alpha: .09)
                              : TgcgColors.primarySoft,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${entry.value}',
                          style: TextStyle(
                            color: entry.key == 'Unassigned'
                                ? TgcgColors.warning
                                : TgcgColors.primary,
                            fontWeight: FontWeight.w900,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _ActivityEvent {
  const _ActivityEvent({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.icon,
    required this.color,
    this.incidentId,
  });

  final String title;
  final String subtitle;
  final DateTime timestamp;
  final IconData icon;
  final Color color;
  final String? incidentId;
}

class _CommandGridPainter extends CustomPainter {
  const _CommandGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF31584F).withValues(alpha: .34)
      ..strokeWidth = 1;
    for (double x = 0; x < size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final sweep = Paint()
      ..color = TgcgColors.success.withValues(alpha: .055)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * .52, size.height * .48),
      size.shortestSide * .36,
      sweep,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

int _severityRank(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => 5,
      IncidentSeverity.high => 4,
      IncidentSeverity.medium => 3,
      IncidentSeverity.low => 2,
      IncidentSeverity.info => 1,
    };

Color _severityColor(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => TgcgColors.danger,
      IncidentSeverity.high => const Color(0xFFD92D20),
      IncidentSeverity.medium => TgcgColors.warning,
      IncidentSeverity.low => TgcgColors.info,
      IncidentSeverity.info => TgcgColors.muted,
    };

IconData _evidenceIcon(EvidenceType type) => switch (type) {
      EvidenceType.photo => Icons.image_outlined,
      EvidenceType.video => Icons.videocam_outlined,
      EvidenceType.audio => Icons.mic_none_rounded,
      EvidenceType.document => Icons.attach_file_rounded,
      EvidenceType.resultForm => Icons.description_outlined,
      EvidenceType.location => Icons.location_on_outlined,
    };

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
