import 'package:flutter/material.dart';

import '../collation/collation_engine.dart';
import '../field/field_operations_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'geography_registry.dart';

class GeographyPage extends StatefulWidget {
  const GeographyPage({super.key});

  @override
  State<GeographyPage> createState() => _GeographyPageState();
}

enum _GeoLayer { pollingUnits, agents, incidents, resultProgress, geofence }

class _GeographyPageState extends State<GeographyPage> {
  final List<GeographicScope> path = [];
  final TextEditingController searchController = TextEditingController();
  final Set<_GeoLayer> layers = {
    _GeoLayer.pollingUnits,
    _GeoLayer.agents,
    _GeoLayer.incidents,
    _GeoLayer.resultProgress,
  };

  String? selectedPollingUnitId;
  String search = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (path.isEmpty) {
      path.add(TgcgSession.of(context, listen: false).scope);
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final registry = membership.geography;
    final scope = path.last;
    final children = registry.childScopes(scope);
    final allUnits = registry.pollingUnitsWithin(scope);
    final incidents = field.incidentsForScope(scope);
    final agents = membership.agentsForScope(scope);
    final approvedAgents = agents
        .where((agent) => agent.status == AccreditationStatus.approved)
        .toList(growable: false);
    final readyAgents = approvedAgents
        .where(
          (agent) =>
              agent.trainingCompleted &&
              agent.biometricEnrolled &&
              agent.deviceId != null &&
              agent.simFingerprint != null,
        )
        .toList(growable: false);
    final assignedUnits = membership.assignedPollingUnitsWithin(scope);
    final assignmentCoverage =
        allUnits.isEmpty ? 0.0 : assignedUnits / allUnits.length;
    final collation = CollationEngine.prototypeSeed().summarize(
      scope,
      results.submissions,
    );
    final openIncidents = incidents
        .where(
          (incident) =>
              incident.status != IncidentStatus.resolved &&
              incident.status != IncidentStatus.closed,
        )
        .toList(growable: false);

    final query = search.trim().toLowerCase();
    final units = query.isEmpty
        ? allUnits
        : allUnits
            .where(
              (unit) =>
                  unit.code.toLowerCase().contains(query) ||
                  unit.scope.label.toLowerCase().contains(query),
            )
            .toList(growable: false);

    CanonicalPollingUnit? selectedUnit;
    if (selectedPollingUnitId != null) {
      selectedUnit = registry.pollingUnit(selectedPollingUnitId!);
      if (selectedUnit != null &&
          !GeographyRegistry.scopeContains(scope, selectedUnit.scope)) {
        selectedUnit = null;
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'GIS & FIELD COVERAGE',
          title: 'Geographic Operations',
          subtitle:
              '${scope.label}: map-first view of canonical polling units, agent assignment, incidents and verified-result progress.',
          trailing: const TgcgStatusPill(
            label: 'GIS PREVIEW',
            color: TgcgColors.info,
            icon: Icons.map_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _BreadcrumbBar(
          path: path,
          onSelect: (index) {
            setState(() {
              path.removeRange(index + 1, path.length);
              selectedPollingUnitId = null;
            });
          },
        ),
        const SizedBox(height: 14),
        _Metrics(
          pollingUnits: allUnits.length,
          assignedPollingUnits: assignedUnits,
          approvedAgents: approvedAgents.length,
          readyAgents: readyAgents.length,
          openIncidents: openIncidents.length,
          verifiedPollingUnits: collation.verifiedPollingUnitCount,
          assignmentCoverage: assignmentCoverage,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final map = _GeoMapPanel(
              scope: scope,
              units: units,
              membership: membership,
              field: field,
              results: results,
              layers: layers,
              selectedPollingUnitId: selectedUnit?.code,
              onToggleLayer: _toggleLayer,
              onSelectUnit: (id) => setState(() => selectedPollingUnitId = id),
            );
            final inspector = _GeoInspector(
              scope: scope,
              selectedUnit: selectedUnit,
              membership: membership,
              field: field,
              results: results,
              registry: registry,
              childScopes: children,
              onOpenChild: (child) => setState(() {
                path.add(child);
                selectedPollingUnitId = null;
              }),
            );

            if (constraints.maxWidth < 1050) {
              return Column(
                children: [
                  map,
                  const SizedBox(height: 14),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: map),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: inspector),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (children.isNotEmpty)
          TgcgSectionCard(
            title: 'Hierarchy drill-down',
            subtitle:
                'Navigate the configured Nigeria → Zone → State → Senatorial District → LGA → Ward → Polling Unit hierarchy.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: children.map((child) {
                final childUnits = registry.pollingUnitsWithin(child);
                final childAssigned = membership.assignedPollingUnitsWithin(child);
                final childSummary = CollationEngine.prototypeSeed().summarize(
                  child,
                  results.submissions,
                );
                final childIncidents = field
                    .incidentsForScope(child)
                    .where(
                      (item) =>
                          item.status != IncidentStatus.resolved &&
                          item.status != IncidentStatus.closed,
                    )
                    .length;
                return _ScopeTile(
                  scope: child,
                  pollingUnits: childUnits.length,
                  assigned: childAssigned,
                  verified: childSummary.verifiedPollingUnitCount,
                  incidents: childIncidents,
                  onTap: () => setState(() {
                    path.add(child);
                    selectedPollingUnitId = null;
                  }),
                );
              }).toList(),
            ),
          ),
        const SizedBox(height: 16),
        _PollingUnitDirectory(
          units: units,
          membership: membership,
          results: results,
          controller: searchController,
          query: search,
          onChanged: (value) => setState(() => search = value),
          onSelect: (id) => setState(() => selectedPollingUnitId = id),
        ),
        const SizedBox(height: 16),
        _AgentCoveragePanel(
          agents: agents,
          membership: membership,
          currentScope: session.scope,
        ),
      ],
    );
  }

  void _toggleLayer(_GeoLayer layer) {
    setState(() {
      if (layers.contains(layer)) {
        layers.remove(layer);
      } else {
        layers.add(layer);
      }
    });
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.pollingUnits,
    required this.assignedPollingUnits,
    required this.approvedAgents,
    required this.readyAgents,
    required this.openIncidents,
    required this.verifiedPollingUnits,
    required this.assignmentCoverage,
  });

  final int pollingUnits;
  final int assignedPollingUnits;
  final int approvedAgents;
  final int readyAgents;
  final int openIncidents;
  final int verifiedPollingUnits;
  final double assignmentCoverage;

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
                label: 'Polling units',
                value: '$pollingUnits',
                detail: 'Canonical units in current scope',
                icon: Icons.location_on_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Assigned PUs',
                value: '$assignedPollingUnits',
                detail: '${(assignmentCoverage * 100).toStringAsFixed(0)}% assignment coverage',
                icon: Icons.assignment_ind_outlined,
                tone: assignmentCoverage >= .8
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Approved agents',
                value: '$approvedAgents',
                detail: '$readyAgents fully ready',
                icon: Icons.verified_user_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Open incidents',
                value: '$openIncidents',
                detail: 'Unresolved operational incidents',
                icon: Icons.crisis_alert_outlined,
                tone: openIncidents == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Verified PUs',
                value: '$verifiedPollingUnits',
                detail: 'Included in verified-only collation',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Geofence',
                value: 'Pending',
                detail: 'Live GPS geometry not connected yet',
                icon: Icons.gps_fixed_rounded,
                tone: TgcgMetricTone.neutral,
              ),
            ],
          );
        },
      );
}

class _GeoMapPanel extends StatelessWidget {
  const _GeoMapPanel({
    required this.scope,
    required this.units,
    required this.membership,
    required this.field,
    required this.results,
    required this.layers,
    required this.selectedPollingUnitId,
    required this.onToggleLayer,
    required this.onSelectUnit,
  });

  final GeographicScope scope;
  final List<CanonicalPollingUnit> units;
  final MembershipOperationsController membership;
  final FieldOperationsController field;
  final ResultOperationsController results;
  final Set<_GeoLayer> layers;
  final String? selectedPollingUnitId;
  final ValueChanged<_GeoLayer> onToggleLayer;
  final ValueChanged<String> onSelectUnit;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Operational map',
        subtitle:
            'Layered GIS workspace. Marker positions are illustrative until production coordinates and PostGIS geometry are connected.',
        trailing: const TgcgStatusPill(
          label: 'GEOMETRY PENDING',
          color: TgcgColors.warning,
          icon: Icons.gps_not_fixed_rounded,
          compact: true,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _GeoLayer.values
                  .map(
                    (layer) => FilterChip(
                      selected: layers.contains(layer),
                      avatar: Icon(_layerIcon(layer), size: 16),
                      label: Text(_layerLabel(layer)),
                      onSelected: (_) => onToggleLayer(layer),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final visibleUnits = units.take(10).toList(growable: false);
                return Container(
                  height: 430,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: const Color(0xFF102E28),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Stack(
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: _MapGridPainter()),
                      ),
                      Positioned(
                        left: 18,
                        top: 16,
                        child: TgcgStatusPill(
                          label: scope.label.toUpperCase(),
                          color: TgcgColors.accent,
                          icon: Icons.public_rounded,
                          compact: true,
                        ),
                      ),
                      Positioned(
                        right: 18,
                        top: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text(
                            'GIS PREVIEW • NOT GPS GEOMETRY',
                            style: TextStyle(
                              color: Color(0xFFC8D9D3),
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .5,
                            ),
                          ),
                        ),
                      ),
                      if (layers.contains(_GeoLayer.pollingUnits))
                        ...List.generate(visibleUnits.length, (index) {
                          final unit = visibleUnits[index];
                          final positions = _markerPositions;
                          final point = positions[index % positions.length];
                          final assigned = membership
                              .agentsForScope(unit.scope)
                              .where(
                                (agent) =>
                                    agent.role == TgcgRole.pollingUnitAgent &&
                                    agent.status == AccreditationStatus.approved &&
                                    agent.scope.pollingUnitId ==
                                        unit.scope.pollingUnitId,
                              )
                              .isNotEmpty;
                          final verified = results
                              .submissionsForScope(unit.scope)
                              .any((item) => item.status == RecordStatus.verified);
                          final selected = selectedPollingUnitId == unit.code;
                          return Positioned(
                            left: point.dx * (constraints.maxWidth - 96),
                            top: 55 + point.dy * 285,
                            child: _PollingUnitMarker(
                              unit: unit,
                              assigned: assigned,
                              verified: verified,
                              selected: selected,
                              showAgent: layers.contains(_GeoLayer.agents),
                              showResult: layers.contains(_GeoLayer.resultProgress),
                              onTap: () => onSelectUnit(unit.code),
                            ),
                          );
                        }),
                      if (layers.contains(_GeoLayer.incidents))
                        ...List.generate(
                          field
                              .incidentsForScope(scope)
                              .where(
                                (item) =>
                                    item.status != IncidentStatus.resolved &&
                                    item.status != IncidentStatus.closed,
                              )
                              .take(5)
                              .length,
                          (index) {
                            final incident = field
                                .incidentsForScope(scope)
                                .where(
                                  (item) =>
                                      item.status != IncidentStatus.resolved &&
                                      item.status != IncidentStatus.closed,
                                )
                                .take(5)
                                .toList(growable: false)[index];
                            final point = _incidentPositions[
                                index % _incidentPositions.length];
                            return Positioned(
                              left: point.dx * (constraints.maxWidth - 80),
                              top: 72 + point.dy * 280,
                              child: _IncidentHeatMarker(incident: incident),
                            );
                          },
                        ),
                      if (layers.contains(_GeoLayer.geofence))
                        Positioned(
                          left: 18,
                          right: 18,
                          bottom: 50,
                          child: Container(
                            padding: const EdgeInsets.all(11),
                            decoration: BoxDecoration(
                              color: TgcgColors.warning.withValues(alpha: .16),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: TgcgColors.warning.withValues(alpha: .35),
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.gps_not_fixed_rounded,
                                  color: Color(0xFFF2C96D),
                                  size: 18,
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Geofence layer is visible, but live coordinates are not present in the prototype registry yet.',
                                    style: TextStyle(
                                      color: Color(0xFFF4E2B4),
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      Positioned(
                        left: 18,
                        right: 18,
                        bottom: 14,
                        child: Row(
                          children: [
                            const _LegendDot(
                              color: TgcgColors.info,
                              label: 'Polling unit',
                            ),
                            if (layers.contains(_GeoLayer.agents)) ...[
                              const SizedBox(width: 12),
                              const _LegendDot(
                                color: TgcgColors.success,
                                label: 'Agent assigned',
                              ),
                            ],
                            if (layers.contains(_GeoLayer.incidents)) ...[
                              const SizedBox(width: 12),
                              const _LegendDot(
                                color: TgcgColors.danger,
                                label: 'Incident',
                              ),
                            ],
                            const Spacer(),
                            Text(
                              '${units.length} PU${units.length == 1 ? '' : 's'} in view',
                              style: const TextStyle(
                                color: Color(0xFFB7CAC4),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      );
}

class _GeoInspector extends StatelessWidget {
  const _GeoInspector({
    required this.scope,
    required this.selectedUnit,
    required this.membership,
    required this.field,
    required this.results,
    required this.registry,
    required this.childScopes,
    required this.onOpenChild,
  });

  final GeographicScope scope;
  final CanonicalPollingUnit? selectedUnit;
  final MembershipOperationsController membership;
  final FieldOperationsController field;
  final ResultOperationsController results;
  final GeographyRegistry registry;
  final List<GeographicScope> childScopes;
  final ValueChanged<GeographicScope> onOpenChild;

  @override
  Widget build(BuildContext context) {
    if (selectedUnit != null) {
      final unit = selectedUnit!;
      final agents = membership
          .agentsForScope(unit.scope)
          .where((agent) => agent.scope.pollingUnitId == unit.scope.pollingUnitId)
          .toList(growable: false);
      final submissions = results.submissionsForScope(unit.scope);
      final verified = submissions.where((item) => item.status == RecordStatus.verified);
      final directIncidents = field.incidentsForScope(unit.scope);

      return TgcgSectionCard(
        title: 'Polling-unit inspector',
        subtitle: 'Canonical record, assignment and result status.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              unit.scope.pollingUnitName ?? unit.code,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: TgcgColors.ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              unit.code,
              style: const TextStyle(
                color: TgcgColors.primaryMid,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            _InfoLine('Ward', unit.scope.wardName ?? '—'),
            _InfoLine('LGA', unit.scope.lgaName ?? '—'),
            _InfoLine('State', unit.scope.stateName ?? '—'),
            _InfoLine(
              'Registered voters',
              unit.registeredVoters?.toString() ?? 'Not configured',
            ),
            const Divider(height: 26),
            _InfoLine('Assigned agents', '${agents.length}'),
            _InfoLine('Result submissions', '${submissions.length}'),
            _InfoLine('Verified result', verified.isEmpty ? 'No' : 'Yes'),
            _InfoLine('Direct incidents', '${directIncidents.length}'),
            const SizedBox(height: 12),
            const TgcgStatusPill(
              label: 'GPS / GEOFENCE NOT MEASURED',
              color: TgcgColors.warning,
              icon: Icons.gps_not_fixed_rounded,
              compact: true,
            ),
            if (agents.isNotEmpty) ...[
              const Divider(height: 26),
              const Text(
                'Assigned personnel',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: TgcgColors.ink,
                ),
              ),
              const SizedBox(height: 9),
              ...agents.map((agent) {
                final member = membership.memberById(agent.memberId);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: TgcgColors.primarySoft,
                        child: Icon(
                          roleIcon(agent.role),
                          size: 16,
                          color: TgcgColors.primary,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member?.fullName ?? agent.agentId,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              agent.agentId,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: TgcgColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TgcgStatusPill(
                        label: _label(agent.status.name),
                        color: _accreditationColor(agent.status),
                        compact: true,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      );
    }

    final units = registry.pollingUnitsWithin(scope);
    final assigned = membership.assignedPollingUnitsWithin(scope);
    final summary = CollationEngine.prototypeSeed().summarize(
      scope,
      results.submissions,
    );
    final incidentCount = field
        .incidentsForScope(scope)
        .where(
          (item) =>
              item.status != IncidentStatus.resolved &&
              item.status != IncidentStatus.closed,
        )
        .length;

    return TgcgSectionCard(
      title: 'Scope inspector',
      subtitle: scope.label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoLine('Polling units', '${units.length}'),
          _InfoLine('Assigned PUs', '$assigned'),
          _InfoLine('Verified PUs', '${summary.verifiedPollingUnitCount}'),
          _InfoLine('Missing results', '${summary.missingPollingUnitIds.length}'),
          _InfoLine('Open incidents', '$incidentCount'),
          const Divider(height: 26),
          const Text(
            'Drill down',
            style: TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 9),
          if (childScopes.isEmpty)
            const Text(
              'This is the lowest configured geography in the current scope.',
              style: TextStyle(color: TgcgColors.muted, fontSize: 11),
            )
          else
            ...childScopes.take(6).map(
                  (child) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: TgcgColors.primary,
                      size: 19,
                    ),
                    title: Text(
                      child.label,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                    onTap: () => onOpenChild(child),
                  ),
                ),
        ],
      ),
    );
  }
}

class _ScopeTile extends StatelessWidget {
  const _ScopeTile({
    required this.scope,
    required this.pollingUnits,
    required this.assigned,
    required this.verified,
    required this.incidents,
    required this.onTap,
  });

  final GeographicScope scope;
  final int pollingUnits;
  final int assigned;
  final int verified;
  final int incidents;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 280,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: TgcgColors.surfaceSoft,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: TgcgColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.map_outlined,
                        color: TgcgColors.primary,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        scope.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: TgcgColors.ink,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: TgcgColors.muted,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    TgcgStatusPill(
                      label: '$pollingUnits PUs',
                      color: TgcgColors.info,
                      compact: true,
                    ),
                    TgcgStatusPill(
                      label: '$assigned assigned',
                      color: TgcgColors.success,
                      compact: true,
                    ),
                    TgcgStatusPill(
                      label: '$verified verified',
                      color: TgcgColors.primary,
                      compact: true,
                    ),
                    if (incidents > 0)
                      TgcgStatusPill(
                        label: '$incidents incidents',
                        color: TgcgColors.danger,
                        compact: true,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _PollingUnitDirectory extends StatelessWidget {
  const _PollingUnitDirectory({
    required this.units,
    required this.membership,
    required this.results,
    required this.controller,
    required this.query,
    required this.onChanged,
    required this.onSelect,
  });

  final List<CanonicalPollingUnit> units;
  final MembershipOperationsController membership;
  final ResultOperationsController results;
  final TextEditingController controller;
  final String query;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Polling-unit directory',
        subtitle:
            'Canonical polling-unit records, assignment state and verified-result status.',
        trailing: SizedBox(
          width: 245,
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search PU code or location',
              prefixIcon: const Icon(Icons.search_rounded, size: 19),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        controller.clear();
                        onChanged('');
                      },
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
            ),
          ),
        ),
        child: units.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.location_off_outlined,
                title: 'No polling units found',
                message: 'Change the search or move to a broader geographic scope.',
              )
            : Column(
                children: units.map((unit) {
                  final assignedAgents = membership
                      .agentsForScope(unit.scope)
                      .where(
                        (agent) =>
                            agent.role == TgcgRole.pollingUnitAgent &&
                            agent.status == AccreditationStatus.approved &&
                            agent.scope.pollingUnitId == unit.scope.pollingUnitId,
                      )
                      .toList(growable: false);
                  final submissions = results.submissionsForScope(unit.scope);
                  final verified = submissions.any(
                    (item) => item.status == RecordStatus.verified,
                  );
                  return InkWell(
                    onTap: () => onSelect(unit.code),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: TgcgColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: TgcgColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: TgcgColors.primarySoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.location_on_outlined,
                              color: TgcgColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  unit.code,
                                  style: const TextStyle(
                                    color: TgcgColors.ink,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${unit.scope.label}${unit.registeredVoters == null ? '' : ' • ${unit.registeredVoters} registered'}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10.5,
                                    color: TgcgColors.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              TgcgStatusPill(
                                label: assignedAgents.isEmpty
                                    ? 'UNASSIGNED'
                                    : '${assignedAgents.length} AGENT${assignedAgents.length == 1 ? '' : 'S'}',
                                color: assignedAgents.isEmpty
                                    ? TgcgColors.warning
                                    : TgcgColors.success,
                                compact: true,
                              ),
                              TgcgStatusPill(
                                label: verified ? 'RESULT VERIFIED' : 'RESULT PENDING',
                                color: verified
                                    ? TgcgColors.success
                                    : TgcgColors.muted,
                                compact: true,
                              ),
                            ],
                          ),
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: TgcgColors.muted,
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
      );
}

class _AgentCoveragePanel extends StatelessWidget {
  const _AgentCoveragePanel({
    required this.agents,
    required this.membership,
    required this.currentScope,
  });

  final List<AccreditedAgent> agents;
  final MembershipOperationsController membership;
  final GeographicScope currentScope;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Agent coverage & field readiness',
        subtitle:
            'Operational personnel assigned inside ${currentScope.label}. Raw biometric templates are not exposed here.',
        child: agents.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.person_off_outlined,
                title: 'No agents in this scope',
                message: 'Agent assignments will appear after accreditation and geographic assignment.',
              )
            : Wrap(
                spacing: 10,
                runSpacing: 10,
                children: agents.map((agent) {
                  final member = membership.memberById(agent.memberId);
                  final ready =
                      agent.status == AccreditationStatus.approved &&
                      agent.trainingCompleted &&
                      agent.biometricEnrolled &&
                      agent.deviceId != null &&
                      agent.simFingerprint != null;
                  return Container(
                    width: 320,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: TgcgColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 19,
                              backgroundColor: TgcgColors.primarySoft,
                              child: Icon(
                                roleIcon(agent.role),
                                color: TgcgColors.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    member?.fullName ?? agent.memberId,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: TgcgColors.ink,
                                    ),
                                  ),
                                  Text(
                                    '${agent.agentId} • ${roleLabel(agent.role)}',
                                    style: const TextStyle(
                                      color: TgcgColors.muted,
                                      fontSize: 9.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TgcgStatusPill(
                              label: ready ? 'READY' : _label(agent.status.name).toUpperCase(),
                              color: ready
                                  ? TgcgColors.success
                                  : _accreditationColor(agent.status),
                              compact: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 11),
                        Text(
                          agent.scope.label,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 9),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _MiniCheck('Training', agent.trainingCompleted),
                            _MiniCheck('Identity', agent.biometricEnrolled),
                            _MiniCheck('Device', agent.deviceId != null),
                            _MiniCheck('SIM', agent.simFingerprint != null),
                          ],
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      );
}

class _MiniCheck extends StatelessWidget {
  const _MiniCheck(this.label, this.ok);

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: (ok ? TgcgColors.success : TgcgColors.warning)
              .withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              ok ? Icons.check_circle_rounded : Icons.schedule_rounded,
              size: 12,
              color: ok ? TgcgColors.success : TgcgColors.warning,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: ok ? TgcgColors.success : TgcgColors.warning,
              ),
            ),
          ],
        ),
      );
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({required this.path, required this.onSelect});

  final List<GeographicScope> path;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 5),
              child: Icon(
                Icons.account_tree_outlined,
                size: 17,
                color: TgcgColors.primary,
              ),
            ),
            for (var index = 0; index < path.length; index++) ...[
              TextButton(
                onPressed:
                    index == path.length - 1 ? null : () => onSelect(index),
                child: Text(path[index].label),
              ),
              if (index != path.length - 1)
                const Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: TgcgColors.muted,
                ),
            ],
          ],
        ),
      );
}

class _PollingUnitMarker extends StatelessWidget {
  const _PollingUnitMarker({
    required this.unit,
    required this.assigned,
    required this.verified,
    required this.selected,
    required this.showAgent,
    required this.showResult,
    required this.onTap,
  });

  final CanonicalPollingUnit unit;
  final bool assigned;
  final bool verified;
  final bool selected;
  final bool showAgent;
  final bool showResult;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? TgcgColors.accent : TgcgColors.info;
    return Tooltip(
      message: unit.code,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: selected ? 38 : 32,
              height: selected ? 38 : 32,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: selected ? 3 : 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x35000000), blurRadius: 10),
                ],
              ),
              child: const Icon(
                Icons.location_on_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            if (showAgent && assigned)
              const Positioned(
                right: -5,
                top: -5,
                child: _MarkerBadge(
                  color: TgcgColors.success,
                  icon: Icons.person_rounded,
                ),
              ),
            if (showResult && verified)
              const Positioned(
                left: -5,
                bottom: -5,
                child: _MarkerBadge(
                  color: TgcgColors.primaryMid,
                  icon: Icons.check_rounded,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MarkerBadge extends StatelessWidget {
  const _MarkerBadge({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Icon(icon, size: 9, color: Colors.white),
      );
}

class _IncidentHeatMarker extends StatelessWidget {
  const _IncidentHeatMarker({required this.incident});

  final FieldIncident incident;

  @override
  Widget build(BuildContext context) {
    final color = switch (incident.severity) {
      IncidentSeverity.critical => TgcgColors.danger,
      IncidentSeverity.high => const Color(0xFFD92D20),
      IncidentSeverity.medium => TgcgColors.warning,
      IncidentSeverity.low => TgcgColors.info,
      IncidentSeverity.info => TgcgColors.muted,
    };
    return Tooltip(
      message: '${incident.title}\n${incident.scope.label}',
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .18),
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.5),
        ),
        child: Icon(Icons.warning_amber_rounded, size: 15, color: color),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(color: Color(0xFFB7CAC4), fontSize: 9.5),
          ),
        ],
      );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
}

class _MapGridPainter extends CustomPainter {
  const _MapGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = const Color(0xFF1B433A)
      ..strokeWidth = 1;
    final major = Paint()
      ..color = const Color(0xFF28564B)
      ..strokeWidth = 1.2;

    for (double x = 0; x <= size.width; x += 34) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minor);
    }
    for (double y = 0; y <= size.height; y += 34) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minor);
    }
    for (double x = 0; x <= size.width; x += 136) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), major);
    }
    for (double y = 0; y <= size.height; y += 136) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), major);
    }

    final route = Paint()
      ..color = const Color(0xFF2C6758)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * .08, size.height * .72)
      ..cubicTo(
        size.width * .28,
        size.height * .5,
        size.width * .46,
        size.height * .76,
        size.width * .62,
        size.height * .44,
      )
      ..cubicTo(
        size.width * .72,
        size.height * .25,
        size.width * .84,
        size.height * .43,
        size.width * .94,
        size.height * .22,
      );
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const _markerPositions = <Offset>[
  Offset(.12, .23),
  Offset(.34, .18),
  Offset(.58, .29),
  Offset(.78, .18),
  Offset(.21, .54),
  Offset(.45, .48),
  Offset(.69, .61),
  Offset(.84, .49),
  Offset(.35, .76),
  Offset(.72, .79),
];

const _incidentPositions = <Offset>[
  Offset(.26, .33),
  Offset(.62, .2),
  Offset(.76, .58),
  Offset(.42, .68),
  Offset(.87, .34),
];

IconData _layerIcon(_GeoLayer layer) => switch (layer) {
      _GeoLayer.pollingUnits => Icons.location_on_outlined,
      _GeoLayer.agents => Icons.people_outline_rounded,
      _GeoLayer.incidents => Icons.warning_amber_rounded,
      _GeoLayer.resultProgress => Icons.fact_check_outlined,
      _GeoLayer.geofence => Icons.gps_fixed_rounded,
    };

String _layerLabel(_GeoLayer layer) => switch (layer) {
      _GeoLayer.pollingUnits => 'Polling Units',
      _GeoLayer.agents => 'Agents',
      _GeoLayer.incidents => 'Incidents',
      _GeoLayer.resultProgress => 'Result Progress',
      _GeoLayer.geofence => 'Geofence',
    };

Color _accreditationColor(AccreditationStatus status) => switch (status) {
      AccreditationStatus.approved => TgcgColors.success,
      AccreditationStatus.pending => TgcgColors.warning,
      AccreditationStatus.suspended => const Color(0xFFB54708),
      AccreditationStatus.revoked => TgcgColors.danger,
    };

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
