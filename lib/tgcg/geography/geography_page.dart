import 'package:flutter/material.dart';

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

class _GeographyPageState extends State<GeographyPage> {
  final List<GeographicScope> path = [];
  final TextEditingController searchController = TextEditingController();
  String query = '';

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
    final membership = MembershipOperations.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final registry = membership.geography;
    final scope = path.last;
    final children = registry.childScopes(scope);
    final units = registry.pollingUnitsWithin(scope);
    final members = membership.membersForScope(scope);
    final agents = membership.agentsForScope(scope);
    final incidents = field.incidentsForScope(scope);
    final openIncidents = incidents
        .where(
          (item) =>
              item.status != IncidentStatus.resolved &&
              item.status != IncidentStatus.closed,
        )
        .toList(growable: false);
    final submissions = results.submissionsForScope(scope);
    final verifiedResults = submissions
        .where((item) => item.status == RecordStatus.verified)
        .length;

    final needle = query.trim().toLowerCase();
    final visibleChildren = children.where((child) {
      if (needle.isEmpty) return true;
      return child.label.toLowerCase().contains(needle) ||
          (child.zoneName ?? '').toLowerCase().contains(needle) ||
          (child.stateName ?? '').toLowerCase().contains(needle) ||
          (child.lgaName ?? '').toLowerCase().contains(needle) ||
          (child.wardName ?? '').toLowerCase().contains(needle);
    }).toList(growable: false);

    final visibleUnits = units.where((unit) {
      if (needle.isEmpty) return true;
      return unit.code.toLowerCase().contains(needle) ||
          unit.scope.label.toLowerCase().contains(needle);
    }).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'GEOGRAPHIC COMMAND',
          title: 'Geographic Operations',
          subtitle:
              '${scope.label}: membership, field-agent coverage, incidents and result activity across the operational hierarchy.',
          trailing: TgcgStatusPill(
            label: _levelLabel(scope.level).toUpperCase(),
            color: TgcgColors.primary,
            icon: Icons.public_rounded,
          ),
        ),
        const SizedBox(height: 18),
        _BreadcrumbBar(
          path: path,
          onSelect: (index) => setState(() {
            path.removeRange(index + 1, path.length);
            query = '';
            searchController.clear();
          }),
        ),
        const SizedBox(height: 14),
        _MetricGrid(
          childAreas: children.length,
          members: members.length,
          agents: agents.length,
          openIncidents: openIncidents.length,
          submissions: submissions.length,
          verifiedResults: verifiedResults,
        ),
        const SizedBox(height: 16),
        _CoverageHero(
          scope: scope,
          children: children,
          membership: membership,
          field: field,
          results: results,
          onOpen: (child) => setState(() {
            path.add(child);
            query = '';
            searchController.clear();
          }),
        ),
        const SizedBox(height: 16),
        _DirectoryPanel(
          controller: searchController,
          query: query,
          children: visibleChildren,
          units: visibleUnits,
          membership: membership,
          field: field,
          results: results,
          onQueryChanged: (value) => setState(() => query = value),
          onOpenChild: (child) => setState(() {
            path.add(child);
            query = '';
            searchController.clear();
          }),
        ),
        const SizedBox(height: 16),
        _AgentPanel(
          agents: agents,
          membership: membership,
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.childAreas,
    required this.members,
    required this.agents,
    required this.openIncidents,
    required this.submissions,
    required this.verifiedResults,
  });

  final int childAreas;
  final int members;
  final int agents;
  final int openIncidents;
  final int submissions;
  final int verifiedResults;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1120
              ? 6
              : constraints.maxWidth >= 720
                  ? 3
                  : constraints.maxWidth >= 460
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
                label: 'Areas',
                value: '$childAreas',
                detail: 'Direct geographic areas',
                icon: Icons.account_tree_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Members',
                value: '$members',
                detail: 'Registered in this scope',
                icon: Icons.groups_2_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Agents',
                value: '$agents',
                detail: 'Operational assignments',
                icon: Icons.badge_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Open incidents',
                value: '$openIncidents',
                detail: 'Active field incidents',
                icon: Icons.crisis_alert_outlined,
                tone: openIncidents == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Results',
                value: '$submissions',
                detail: 'Submissions received',
                icon: Icons.ballot_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Verified',
                value: '$verifiedResults',
                detail: 'Verified result records',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.success,
              ),
            ],
          );
        },
      );
}

class _CoverageHero extends StatelessWidget {
  const _CoverageHero({
    required this.scope,
    required this.children,
    required this.membership,
    required this.field,
    required this.results,
    required this.onOpen,
  });

  final GeographicScope scope;
  final List<GeographicScope> children;
  final MembershipOperationsController membership;
  final FieldOperationsController field;
  final ResultOperationsController results;
  final ValueChanged<GeographicScope> onOpen;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: TgcgColors.primaryDark,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: TgcgColors.accent.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.public_rounded,
                    color: TgcgColors.accent,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        scope.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _coverageSubtitle(scope.level, children.length),
                        style: const TextStyle(
                          color: Color(0xFFAFC2BB),
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (children.isNotEmpty) ...[
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1050
                      ? 3
                      : constraints.maxWidth >= 620
                          ? 2
                          : 1;
                  const gap = 10.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: children.map((child) {
                      final members = membership.memberCountForScope(child);
                      final agents = membership.agentCountForScope(child);
                      final openIncidents = field
                          .incidentsForScope(child)
                          .where(
                            (item) =>
                                item.status != IncidentStatus.resolved &&
                                item.status != IncidentStatus.closed,
                          )
                          .length;
                      final resultCount =
                          results.submissionsForScope(child).length;

                      return SizedBox(
                        width: width,
                        child: Material(
                          color: Colors.white.withValues(alpha: .055),
                          borderRadius: BorderRadius.circular(15),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(15),
                            onTap: () => onOpen(child),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        _scopeIcon(child.level),
                                        color: TgcgColors.accent,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          _shortLabel(child),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                      const Icon(
                                        Icons.chevron_right_rounded,
                                        color: Color(0xFF9CB2AA),
                                        size: 18,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _DarkMetric(
                                          value: members,
                                          label: 'Members',
                                        ),
                                      ),
                                      Expanded(
                                        child: _DarkMetric(
                                          value: agents,
                                          label: 'Agents',
                                        ),
                                      ),
                                      Expanded(
                                        child: _DarkMetric(
                                          value: openIncidents,
                                          label: 'Incidents',
                                        ),
                                      ),
                                      Expanded(
                                        child: _DarkMetric(
                                          value: resultCount,
                                          label: 'Results',
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ],
        ),
      );
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF9FB4AD),
              fontSize: 8.5,
            ),
          ),
        ],
      );
}

class _DirectoryPanel extends StatelessWidget {
  const _DirectoryPanel({
    required this.controller,
    required this.query,
    required this.children,
    required this.units,
    required this.membership,
    required this.field,
    required this.results,
    required this.onQueryChanged,
    required this.onOpenChild,
  });

  final TextEditingController controller;
  final String query;
  final List<GeographicScope> children;
  final List<CanonicalPollingUnit> units;
  final MembershipOperationsController membership;
  final FieldOperationsController field;
  final ResultOperationsController results;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<GeographicScope> onOpenChild;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: children.isNotEmpty ? 'Geographic directory' : 'Polling units',
        subtitle: children.isNotEmpty
            ? 'Search and open the next level of the operational hierarchy.'
            : 'Polling units recorded within the selected scope.',
        child: Column(
          children: [
            TextField(
              controller: controller,
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                hintText: 'Search geographic area or polling unit',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (children.isNotEmpty)
              ...children.map((child) => _AreaRow(
                    scope: child,
                    members: membership.memberCountForScope(child),
                    agents: membership.agentCountForScope(child),
                    incidents: field
                        .incidentsForScope(child)
                        .where(
                          (item) =>
                              item.status != IncidentStatus.resolved &&
                              item.status != IncidentStatus.closed,
                        )
                        .length,
                    results: results.submissionsForScope(child).length,
                    onTap: () => onOpenChild(child),
                  ))
            else if (units.isNotEmpty)
              ...units.map((unit) {
                final agents = membership.agentsForScope(unit.scope);
                final submissions = results.submissionsForScope(unit.scope);
                final verified = submissions.any(
                  (item) => item.status == RecordStatus.verified,
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: TgcgColors.primarySoft,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: const Icon(
                      Icons.location_on_outlined,
                      color: TgcgColors.primary,
                      size: 19,
                    ),
                  ),
                  title: Text(
                    unit.code,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: Text(unit.scope.label),
                  trailing: Wrap(
                    spacing: 6,
                    children: [
                      TgcgStatusPill(
                        label: '${agents.length} AGENT${agents.length == 1 ? '' : 'S'}',
                        color: TgcgColors.info,
                        compact: true,
                      ),
                      TgcgStatusPill(
                        label: verified ? 'VERIFIED' : 'AWAITING',
                        color: verified
                            ? TgcgColors.success
                            : TgcgColors.warning,
                        compact: true,
                      ),
                    ],
                  ),
                );
              })
            else
              const TgcgEmptyState(
                icon: Icons.map_outlined,
                title: 'State overview',
                message: 'Membership and agent activity for this area is shown above.',
              ),
          ],
        ),
      );
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({
    required this.scope,
    required this.members,
    required this.agents,
    required this.incidents,
    required this.results,
    required this.onTap,
  });

  final GeographicScope scope;
  final int members;
  final int agents;
  final int incidents;
  final int results;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TgcgColors.surfaceSoft,
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: TgcgColors.primarySoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    _scopeIcon(scope.level),
                    color: TgcgColors.primary,
                    size: 19,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _shortLabel(scope),
                        style: const TextStyle(
                          color: TgcgColors.ink,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _levelLabel(scope.level),
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                _Count(value: members, label: 'Members'),
                const SizedBox(width: 14),
                _Count(value: agents, label: 'Agents'),
                const SizedBox(width: 14),
                _Count(value: incidents, label: 'Incidents'),
                const SizedBox(width: 14),
                _Count(value: results, label: 'Results'),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: TgcgColors.muted,
                ),
              ],
            ),
          ),
        ),
      );
}

class _Count extends StatelessWidget {
  const _Count({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 8.5,
            ),
          ),
        ],
      );
}

class _AgentPanel extends StatelessWidget {
  const _AgentPanel({required this.agents, required this.membership});

  final List<AccreditedAgent> agents;
  final MembershipOperationsController membership;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Agent coverage',
        subtitle: 'Operational agents assigned within the selected geography.',
        child: agents.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.badge_outlined,
                title: 'No agents in this scope',
                message: 'Agent assignments will appear here.',
              )
            : Column(
                children: agents.take(10).map((agent) {
                  final member = membership.memberById(agent.memberId);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const CircleAvatar(
                      child: Icon(Icons.badge_outlined),
                    ),
                    title: Text(
                      member?.fullName ?? agent.agentId,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${agent.agentId} • ${roleLabel(agent.role)} • ${agent.scope.label}',
                    ),
                    trailing: TgcgStatusPill(
                      label: agent.status.name.toUpperCase(),
                      color: agent.status == AccreditationStatus.approved
                          ? TgcgColors.success
                          : TgcgColors.warning,
                      compact: true,
                    ),
                  );
                }).toList(),
              ),
      );
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({required this.path, required this.onSelect});

  final List<GeographicScope> path;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(path.length, (index) {
            final scope = path[index];
            return Row(
              children: [
                TextButton.icon(
                  onPressed: index == path.length - 1
                      ? null
                      : () => onSelect(index),
                  icon: Icon(_scopeIcon(scope.level), size: 15),
                  label: Text(_shortLabel(scope)),
                ),
                if (index < path.length - 1)
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: TgcgColors.muted,
                    size: 17,
                  ),
              ],
            );
          }),
        ),
      );
}

String _shortLabel(GeographicScope scope) => switch (scope.level) {
      GeographyLevel.country => scope.country,
      GeographyLevel.geopoliticalZone => scope.zoneName ?? scope.label,
      GeographyLevel.state => scope.stateName ?? scope.label,
      GeographyLevel.senatorialDistrict =>
        scope.senatorialDistrictName ?? scope.label,
      GeographyLevel.lga => scope.lgaName ?? scope.label,
      GeographyLevel.ward => scope.wardName ?? scope.label,
      GeographyLevel.pollingUnit => scope.pollingUnitName ?? scope.label,
    };

String _levelLabel(GeographyLevel level) => switch (level) {
      GeographyLevel.country => 'National coverage',
      GeographyLevel.geopoliticalZone => 'Geopolitical zone',
      GeographyLevel.state => 'State / FCT',
      GeographyLevel.senatorialDistrict => 'Senatorial district',
      GeographyLevel.lga => 'Local government area',
      GeographyLevel.ward => 'Ward',
      GeographyLevel.pollingUnit => 'Polling unit',
    };

String _coverageSubtitle(GeographyLevel level, int children) => switch (level) {
      GeographyLevel.country => '$children geopolitical zones',
      GeographyLevel.geopoliticalZone => '$children states / FCT',
      GeographyLevel.state => '$children senatorial districts',
      GeographyLevel.senatorialDistrict => '$children local government areas',
      GeographyLevel.lga => '$children wards',
      GeographyLevel.ward => '$children polling units',
      GeographyLevel.pollingUnit => 'Polling-unit operations',
    };

IconData _scopeIcon(GeographyLevel level) => switch (level) {
      GeographyLevel.country => Icons.flag_outlined,
      GeographyLevel.geopoliticalZone => Icons.public_outlined,
      GeographyLevel.state => Icons.map_outlined,
      GeographyLevel.senatorialDistrict => Icons.grid_view_outlined,
      GeographyLevel.lga => Icons.location_city_outlined,
      GeographyLevel.ward => Icons.hub_outlined,
      GeographyLevel.pollingUnit => Icons.location_on_outlined,
    };
