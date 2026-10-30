import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show formatMoment;
import '../geography/geography_registry.dart';
import '../geography/nigeria_map.dart';
import '../geography/state_lga_map_dialog.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../sync/server_records.dart';
import '../ui/server_feed.dart';
import '../ui/tgcg_design.dart';
import '../ui/tgcg_figures.dart';
import 'field_operations_store.dart';
import 'incident_actions.dart';
import 'incident_report.dart';

class SituationRoomPage extends StatefulWidget {
  const SituationRoomPage({super.key});

  @override
  State<SituationRoomPage> createState() => _SituationRoomPageState();
}

class _SituationRoomPageState extends State<SituationRoomPage> with ServerAutoRefresh {
  @override
  List<ServerRecords<Object?>> refreshedRecords(BuildContext context) =>
      [FieldOperations.of(context, listen: false)];

  String? selectedIncidentId;
  final _inspector = GlobalKey();

  /// Selects an incident; [reveal] brings its details into view when they
  /// may be off screen, so that the tap visibly does something.
  void _select(String id, {bool reveal = true}) {
    setState(() => selectedIncidentId = id);
    if (!reveal) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _inspector.currentContext;
      if (!mounted || target == null) return;
      unawaited(Scrollable.ensureVisible(target, duration: const Duration(milliseconds: 250)));
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = FieldOperations.of(context);
    final incidents = store.incidentsForScope(session.scope);
    final reports = store.reportsForScope(session.scope);
    final open = incidents.where(isOpenIncident).toList(growable: false)
      ..sort((a, b) {
        final severity =
            incidentSeverityRank(b.severity).compareTo(incidentSeverityRank(a.severity));
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

    return TgcgPageList(
      maxWidth: tgcgCommandWidth,
      bottomPadding: 36,
      children: [
        TgcgPageHeader(
          eyebrow: 'Live command centre',
          title: 'Situation Room',
          subtitle: '${session.scope.label}: open incidents, evidence and response.',
          trailing: const FieldFeedStatus(),
        ),
        const FieldLoadNotice(),
        const SizedBox(height: TgcgSpacing.md),
        // Zeros and "no incidents" are only ever what the server said.
        if (!store.recordsKnown && incidents.isEmpty) ...[
          _NotKnownYet(store: store),
        ] else ...[
          _MetricsStrip(
            open: open.length,
            critical: critical,
            high: high,
            unassigned: unassigned,
            reports: reports.length,
            evidence: evidence,
          ),
          const SizedBox(height: TgcgSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final sideBySide = constraints.maxWidth >= 760;
              final priorityRail = _PriorityRail(
                incidents: open,
                selectedIncidentId: selectedIncidentId,
                onSelect: (id) => _select(id, reveal: !sideBySide),
              );
              final geography = MembershipOperations.of(context).geography;
              final map = _CommandMap(
                scope: session.scope,
                focusStateIds: _focusStateIds(session.scope, geography.states),
                stateNames: {
                  for (final state in geography.states) state.id: state.name,
                },
                onOpenState: (stateId) {
                  final state = geography.state(stateId);
                  if (state == null) return;
                  showStateLgaMap(
                    context,
                    state: state,
                    lgas: geography.lgasForState(stateId),
                    incidents: incidents,
                  );
                },
                incidents: open,
                selectedIncidentId: selectedIncidentId,
                onSelect: _select,
              );
              final inspector = KeyedSubtree(
                key: _inspector,
                child: _IncidentInspector(incident: selected),
              );

              // The map takes the full width; queue and inspector sit below it.
              return Column(
                children: [
                  map,
                  const SizedBox(height: 14),
                  if (sideBySide)
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
            },
          ),
          const SizedBox(height: TgcgSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final timeline = _ActivityTimeline(
                incidents: incidents,
                reports: reports,
                onIncidentSelected: _select,
              );
              final ownership = _ResponseOwnership(incidents: open);
              if (constraints.maxWidth < 860) {
                return Column(
                  children: [
                    timeline,
                    const SizedBox(height: TgcgSpacing.lg),
                    ownership,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 7, child: timeline),
                  const SizedBox(width: TgcgSpacing.md),
                  Expanded(flex: 4, child: ownership),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

/// In place of the figures until the server has answered once.
class _NotKnownYet extends StatelessWidget {
  const _NotKnownYet({required this.store});

  final FieldOperationsController store;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        child: store.loadError == null
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: TgcgSpacing.xl),
                child: Center(child: CircularProgressIndicator()),
              )
            : TgcgEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Incidents could not be loaded',
                message: 'Nothing is shown here until the server answers.',
                action: OutlinedButton(
                  onPressed: () => unawaited(store.refresh()),
                  child: const Text('Try again'),
                ),
              ),
      );
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
  Widget build(BuildContext context) => TgcgMetricGrid(
        cards: [
          TgcgMetricCard(
            label: 'Open incidents',
            value: formatCount(open),
            detail: 'Unresolved in your areas',
            icon: Icons.warning_amber_rounded,
            tone: open == 0 ? TgcgMetricTone.success : TgcgMetricTone.warning,
          ),
          TgcgMetricCard(
            label: 'Critical',
            value: formatCount(critical),
            detail: 'Immediate attention',
            icon: Icons.crisis_alert_rounded,
            tone: critical == 0 ? TgcgMetricTone.neutral : TgcgMetricTone.danger,
          ),
          TgcgMetricCard(
            label: 'High priority',
            value: formatCount(high),
            detail: 'High severity, still open',
            icon: Icons.priority_high_rounded,
            tone: high == 0 ? TgcgMetricTone.neutral : TgcgMetricTone.danger,
          ),
          TgcgMetricCard(
            label: 'Unassigned',
            value: formatCount(unassigned),
            detail: 'No response team yet',
            icon: Icons.person_off_outlined,
            tone: unassigned == 0 ? TgcgMetricTone.neutral : TgcgMetricTone.warning,
          ),
          TgcgMetricCard(
            label: 'Field reports',
            value: formatCount(reports),
            detail: 'From the field',
            icon: Icons.feed_outlined,
            tone: TgcgMetricTone.info,
          ),
          TgcgMetricCard(
            label: 'Evidence retained',
            value: formatCount(evidence),
            detail: 'Linked media records',
            icon: Icons.perm_media_outlined,
            tone: TgcgMetricTone.success,
          ),
        ],
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
                message: 'There are no unresolved incidents in your areas.',
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
    final color = incidentSeverityColor(incident.severity);
    final radius = BorderRadius.circular(TgcgRadius.md);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? color.withValues(alpha: .06) : TgcgColors.surface,
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: selected ? color.withValues(alpha: .5) : TgcgColors.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TgcgIconBadge(icon: Icons.crisis_alert_outlined, color: color, size: 38),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        incident.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TgcgType.bodyStrong,
                      ),
                      const SizedBox(height: 2),
                      Text(incident.scope.label, style: TgcgType.caption),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          if (incident.isLive)
                            const TgcgStatusPill(
                              label: 'LIVE',
                              color: TgcgColors.danger,
                              icon: Icons.live_tv_rounded,
                              compact: true,
                            ),
                          TgcgStatusPill(
                            label: incidentSeverityLabel(incident.severity),
                            color: color,
                            compact: true,
                          ),
                          TgcgStatusPill(
                            label: incidentStatusLabel(incident.status),
                            color: TgcgColors.primaryMid,
                            compact: true,
                          ),
                          if (FieldOperations.of(context).isOnDevice(incident.id))
                            const TgcgStatusPill(
                              label: 'On this device',
                              color: TgcgColors.accentDeep,
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
    required this.focusStateIds,
    required this.stateNames,
    required this.onOpenState,
    required this.incidents,
    required this.selectedIncidentId,
    required this.onSelect,
  });

  final GeographicScope scope;
  final List<String> focusStateIds;
  final Map<String, String> stateNames;
  final ValueChanged<String> onOpenState;
  final List<FieldIncident> incidents;
  final String? selectedIncidentId;
  final ValueChanged<String> onSelect;

  Map<String, IncidentSeverity> get worstByState {
    final result = <String, IncidentSeverity>{};
    for (final incident in incidents) {
      final id = incident.scope.stateId;
      if (id == null) continue;
      final current = result[id];
      if (current == null ||
          incidentSeverityRank(incident.severity) > incidentSeverityRank(current)) {
        result[id] = incident.severity;
      }
    }
    return result;
  }

  Map<String, int> get openByState {
    final result = <String, int>{};
    for (final incident in incidents) {
      final id = incident.scope.stateId;
      if (id != null) result[id] = (result[id] ?? 0) + 1;
    }
    return result;
  }

  List<Widget> _incidentMarkers(
    GeoShapeSet geometry,
    GeoProjection projection,
  ) {
    // Incidents without a GPS fix are fanned out around their state's
    // interior label point so they never land outside the state.
    final unfixedTotals = <String, int>{};
    for (final incident in incidents) {
      final id = incident.scope.stateId;
      if (!_hasFix(incident) && id != null) {
        unfixedTotals[id] = (unfixedTotals[id] ?? 0) + 1;
      }
    }
    final unfixedSeen = <String, int>{};

    final placed = <({FieldIncident incident, Offset point, bool exact})>[];
    for (final incident in incidents) {
      if (_hasFix(incident)) {
        placed.add((
          incident: incident,
          point: projection.project(incident.latitude!, incident.longitude!),
          exact: true,
        ));
        continue;
      }
      final shape = geometry.shapes[incident.scope.stateId];
      if (shape == null) continue;
      final index = unfixedSeen[shape.id] ?? 0;
      unfixedSeen[shape.id] = index + 1;
      final total = unfixedTotals[shape.id]!;
      final center =
          projection.projectGeo(shape.labelPoint) + const Offset(0, 18);
      final radius = total == 1 ? 0.0 : 16.0;
      final angle = index * 2 * math.pi / total - math.pi / 2;
      placed.add((
        incident: incident,
        point: center + Offset(math.cos(angle), math.sin(angle)) * radius,
        exact: false,
      ));
    }
    // Paint the selected marker last so it sits above its neighbours.
    int selectedLast(FieldIncident incident) =>
        incident.id == selectedIncidentId ? 1 : 0;
    placed.sort((a, b) =>
        selectedLast(a.incident).compareTo(selectedLast(b.incident)));

    final size = projection.size;
    const half = _MapIncidentNode.touchSize / 2;
    const wide = _MapIncidentNode.selectedWidth;
    final pins = <Widget>[];
    for (final item in placed) {
      final selected = item.incident.id == selectedIncidentId;
      // A pin marks a place: near the right edge a selected pin's label runs
      // to the left of it, so that the pin itself does not move.
      final labelLeft = selected && item.point.dx - half + wide > size.width;
      final left = labelLeft ? item.point.dx + half - wide : item.point.dx - half;
      final width = selected ? wide : _MapIncidentNode.touchSize;
      pins.add(
        Positioned(
          left: left.clamp(0.0, math.max(0.0, size.width - width)).toDouble(),
          top: (item.point.dy - half)
              .clamp(0.0, math.max(0.0, size.height - _MapIncidentNode.touchSize))
              .toDouble(),
          child: _MapIncidentNode(
            incident: item.incident,
            color: incidentSeverityColor(item.incident.severity),
            selected: selected,
            labelLeft: labelLeft,
            exact: item.exact,
            onTap: () => onSelect(item.incident.id),
          ),
        ),
      );
    }
    return pins;
  }

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Live operational map',
        subtitle: 'States are shaded by their most severe open incident.',
        trailing: TgcgStatusPill(
          label: '${formatCount(incidents.length)} OPEN',
          color: incidents.isEmpty ? TgcgColors.success : TgcgColors.warning,
          icon: Icons.map_outlined,
          compact: true,
        ),
        trailingBeside: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            LayoutBuilder(
              // Nigeria is ~1.27x wider than tall; size the map to fill the width.
              builder: (context, constraints) => Container(
                height: (constraints.maxWidth / 1.3).clamp(260.0, 720.0),
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: TgcgColors.primaryDark,
                  borderRadius: BorderRadius.circular(TgcgRadius.lg),
                ),
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GeoShapeMapView(
                        source: GeoShapeSet.nigeriaStates(),
                        style: GeoMapStyle.dark,
                        padding: constraints.maxWidth < 560 ? 14 : 44,
                        focusIds: focusStateIds,
                        onTap: onOpenState,
                        isInteractive: (id) =>
                            focusStateIds.isEmpty || focusStateIds.contains(id),
                        fillFor: (id) {
                          final severity = worstByState[id];
                          if (severity == null) return null;
                          return Color.alphaBlend(
                            incidentSeverityColor(severity).withValues(alpha: .42),
                            GeoMapStyle.dark.mutedFill,
                          );
                        },
                        labelFor: (id) => id,
                        tooltipFor: (id) {
                          final name = stateNames[id] ?? id;
                          final count = openByState[id] ?? 0;
                          return '$name'
                              '${count == 0 ? '' : ' • $count open incident${count == 1 ? '' : 's'}'}'
                              ' • click for LGA map';
                        },
                        overlayBuilder: _incidentMarkers,
                      ),
                    ),
                    if (constraints.maxWidth >= 560)
                      Positioned(
                        left: 12,
                        top: 12,
                        child: TgcgStatusPill(
                          label: scope.label.toUpperCase(),
                          color: TgcgColors.accentBright,
                          icon: Icons.location_on_outlined,
                          compact: true,
                        ),
                      ),
                    if (incidents.isEmpty)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 22,
                        child: IgnorePointer(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: TgcgColors.primaryDark.withValues(alpha: .88),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'No open incidents in your areas',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _MapLegend(label: 'Critical / high', color: TgcgColors.danger),
                _MapLegend(label: 'Medium', color: TgcgColors.warning),
                _MapLegend(label: 'Low / info', color: TgcgColors.info),
                _MapLegend(label: 'GPS fix', icon: Icons.location_on_rounded),
                _MapLegend(
                  label: 'No GPS fix: placed in its state',
                  icon: Icons.location_searching_rounded,
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
    required this.labelLeft,
    required this.exact,
    required this.onTap,
  });

  static const pinSize = 24.0;

  /// Pins sit close: the touch area reaches a little past each one.
  static const touchSize = 36.0;
  static const _labelWidth = 136.0;
  static const selectedWidth = _labelWidth + touchSize - pinSize;

  final FieldIncident incident;
  final Color color;
  final bool selected;

  /// The selected pin's label runs to its left, for a pin near the right edge.
  final bool labelLeft;
  final bool exact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '${incident.title}\n'
            '${incident.scope.lgaName ?? incident.scope.label}'
            '${exact ? '' : ' (no GPS fix)'}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(touchSize / 2),
          child: Padding(
            padding: const EdgeInsets.all((touchSize - pinSize) / 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: selected ? _labelWidth : pinSize,
              height: pinSize,
              padding: EdgeInsets.only(
                left: !selected ? 0 : (labelLeft ? 8 : 3),
                right: !selected ? 0 : (labelLeft ? 3 : 8),
              ),
              decoration: BoxDecoration(
                color: selected
                    ? TgcgColors.primaryDark
                    : exact
                        ? color
                        : TgcgColors.primaryDark,
                borderRadius: BorderRadius.circular(pinSize / 2),
                border: Border.all(
                  color: selected || !exact ? color : Colors.white,
                  width: selected || !exact ? 2.4 : 1.6,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .45),
                    blurRadius: 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                textDirection: labelLeft ? TextDirection.rtl : TextDirection.ltr,
                mainAxisAlignment: selected ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Icon(
                    exact ? Icons.location_on_rounded : Icons.location_searching_rounded,
                    color: exact || selected ? Colors.white : color,
                    size: 14,
                  ),
                  if (selected) ...[
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        incident.scope.lgaName ?? incident.scope.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: labelLeft ? TextAlign.end : TextAlign.start,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}

/// What a colour or a pin on the map means.
class _MapLegend extends StatelessWidget {
  const _MapLegend({required this.label, this.color, this.icon});

  final String label;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon case final shape?)
            Icon(shape, size: 14, color: TgcgColors.muted)
          else
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: TgcgType.caption)),
        ],
      );
}

class _IncidentInspector extends StatelessWidget {
  const _IncidentInspector({required this.incident});

  final FieldIncident? incident;

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
    return IncidentReportCard(incident: item);
  }
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
          subtitle: '${incident.scope.label} • ${incidentStatusLabel(incident.status)}',
          timestamp: incident.reportedAt,
          icon: Icons.crisis_alert_outlined,
          color: incidentSeverityColor(incident.severity),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TgcgSectionHeading(title: 'Live event stream'),
        if (events.isEmpty)
          const TgcgSectionCard(
            child: TgcgEmptyState(
              icon: Icons.timeline_outlined,
              title: 'No activity yet',
              message: 'New incidents and field reports will appear here.',
            ),
          )
        else
          TgcgRowGroup(
            children: [
              for (final event in events.take(8))
                TgcgActionRow(
                  icon: event.icon,
                  color: event.color,
                  title: event.title,
                  detail: '${event.subtitle}\n${formatMoment(event.timestamp.toLocal())}',
                  onTap: event.incidentId == null
                      ? null
                      : () => onIncidentSelected(event.incidentId!),
                ),
            ],
          ),
      ],
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
    final entries = groups.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TgcgSectionHeading(title: 'Response ownership'),
        if (entries.isEmpty)
          const TgcgSectionCard(
            child: TgcgEmptyState(
              icon: Icons.groups_2_outlined,
              title: 'No active ownership',
              message: 'There are no open incidents assigned in your areas.',
            ),
          )
        else
          TgcgRowGroup(
            children: [
              for (final entry in entries)
                TgcgActionRow(
                  icon: Icons.groups_2_outlined,
                  color: entry.key == 'Unassigned' ? TgcgColors.warning : TgcgColors.primary,
                  title: entry.key,
                  trailing: Text(formatCount(entry.value), style: TgcgType.section),
                ),
            ],
          ),
      ],
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

bool _hasFix(FieldIncident incident) =>
    incident.latitude != null && incident.longitude != null;

List<String> _focusStateIds(
  GeographicScope scope,
  List<CanonicalState> states,
) {
  if (scope.level == GeographyLevel.country) return const [];
  if (scope.level == GeographyLevel.geopoliticalZone) {
    return [
      for (final state in states)
        if (state.zoneId == scope.zoneId) state.id,
    ];
  }
  final stateId = scope.stateId;
  return stateId == null ? const [] : [stateId];
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
