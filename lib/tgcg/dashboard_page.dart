import 'package:flutter/material.dart';

import 'collation/collation_engine.dart';
import 'field/field_operations_store.dart';
import 'membership/membership_store.dart';
import 'results/result_operations_store.dart';
import 'session.dart';
import 'ui/tgcg_design.dart';

class TgcgDashboardPage extends StatelessWidget {
  const TgcgDashboardPage({super.key, required this.onOpenModule});

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final membership = MembershipOperations.of(context);
    final modules = allowedModules(session.role!);
    final scope = session.scope;

    final incidents = field.incidentsForScope(scope);
    final fieldReports = field.reportsForScope(scope);
    final submissions = results.submissionsForScope(scope);
    final review = results.reviewQueueForScope(scope);
    final members = membership.membersForScope(scope);
    final agents = membership.agentsForScope(scope);
    final approvedAgents = agents
        .where((agent) => agent.status == AccreditationStatus.approved)
        .toList(growable: false);
    final readyAgents = approvedAgents
        .where(
          (agent) =>
              agent.trainingCompleted &&
              agent.biometricEnrolled &&
              agent.deviceId != null,
        )
        .toList(growable: false);
    final openIncidents = incidents
        .where(
          (item) =>
              item.status != IncidentStatus.resolved &&
              item.status != IncidentStatus.closed,
        )
        .toList(growable: false);
    final highPriority = openIncidents
        .where(
          (item) =>
              item.severity == IncidentSeverity.high ||
              item.severity == IncidentSeverity.critical,
        )
        .length;

    final collationEngine = CollationEngine.prototypeSeed();
    final collation = collationEngine.summarize(scope, results.submissions);

    // Geography navigation comes from the canonical national registry, not
    // from the small result-collation seed. At national level this therefore
    // always exposes all six geopolitical zones.
    final childScopes = membership.geography.childScopes(scope);
    final coverage = childScopes
        .map(
          (child) => _CoverageData(
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
          ),
        )
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final padding = compact ? 16.0 : 24.0;

        return ListView(
          padding: EdgeInsets.fromLTRB(padding, 22, padding, 36),
          children: [
            TgcgPageHeader(
              eyebrow: scope.level == GeographyLevel.country
                  ? 'NATIONAL COMMAND CENTRE'
                  : 'AUTHORIZED OPERATIONAL SCOPE',
              title: 'Operations Command',
              subtitle:
                  '${roleLabel(session.role!)} • ${scope.label}. Membership, field operations, incidents, agents and verified-result activity in one command view.',
              trailing: compact
                  ? null
                  : const TgcgStatusPill(
                      label: 'LIVE OPERATIONS',
                      color: TgcgColors.success,
                      icon: Icons.circle,
                    ),
            ),
            const SizedBox(height: 20),
            _MetricGrid(
              openIncidents: openIncidents.length,
              highPriority: highPriority,
              registeredMembers: members.length,
              submissions: submissions.length,
              review: review.length,
              verifiedPollingUnits: collation.verifiedPollingUnitCount,
              approvedAgents: approvedAgents.length,
              readyAgents: readyAgents.length,
              modules: modules,
              onOpenModule: onOpenModule,
            ),
            const SizedBox(height: 16),
            _CoveragePanel(
              scope: scope,
              coverage: coverage,
              totalMembers: members.length,
              totalAgents: agents.length,
              onOpenMembership: modules.contains(TgcgModule.membershipNetwork)
                  ? () => onOpenModule(TgcgModule.membershipNetwork)
                  : null,
              onOpenGeography: modules.contains(TgcgModule.geography)
                  ? () => onOpenModule(TgcgModule.geography)
                  : null,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, inner) {
                final progress = _OperationsProgressPanel(
                  collation: collation,
                  readyAgents: readyAgents.length,
                  approvedAgents: approvedAgents.length,
                  fieldReports: fieldReports.length,
                  openIncidents: openIncidents.length,
                  onOpenCollation: modules.contains(TgcgModule.collation)
                      ? () => onOpenModule(TgcgModule.collation)
                      : null,
                );
                final events = _PriorityEventsPanel(
                  incidents: openIncidents,
                  reviewCount: review.length,
                  modules: modules,
                  onOpenModule: onOpenModule,
                );

                if (inner.maxWidth < 940) {
                  return Column(
                    children: [
                      progress,
                      const SizedBox(height: 16),
                      events,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 4, child: progress),
                    const SizedBox(width: 16),
                    Expanded(flex: 6, child: events),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            _QuickCommandPanel(
              modules: modules,
              onOpenModule: onOpenModule,
            ),
          ],
        );
      },
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.openIncidents,
    required this.highPriority,
    required this.registeredMembers,
    required this.submissions,
    required this.review,
    required this.verifiedPollingUnits,
    required this.approvedAgents,
    required this.readyAgents,
    required this.modules,
    required this.onOpenModule,
  });

  final int openIncidents;
  final int highPriority;
  final int registeredMembers;
  final int submissions;
  final int review;
  final int verifiedPollingUnits;
  final int approvedAgents;
  final int readyAgents;
  final Set<TgcgModule> modules;
  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1180
              ? 4
              : constraints.maxWidth >= 780
                  ? 3
                  : constraints.maxWidth >= 500
                      ? 2
                      : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;

          final cards = <Widget>[
            TgcgMetricCard(
              width: width,
              label: 'Registered members',
              value: '$registeredMembers',
              detail: 'Membership in current scope',
              icon: Icons.groups_2_outlined,
              tone: TgcgMetricTone.info,
              onTap: modules.contains(TgcgModule.membershipNetwork)
                  ? () => onOpenModule(TgcgModule.membershipNetwork)
                  : null,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Approved agents',
              value: '$approvedAgents',
              detail: '$readyAgents operationally ready',
              icon: Icons.badge_outlined,
              tone: TgcgMetricTone.success,
              onTap: modules.contains(TgcgModule.accreditation)
                  ? () => onOpenModule(TgcgModule.accreditation)
                  : null,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Open incidents',
              value: '$openIncidents',
              detail: '$highPriority high / critical',
              icon: Icons.warning_amber_rounded,
              tone: openIncidents == 0
                  ? TgcgMetricTone.success
                  : TgcgMetricTone.warning,
              onTap: modules.contains(TgcgModule.situationRoom)
                  ? () => onOpenModule(TgcgModule.situationRoom)
                  : null,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Results received',
              value: '$submissions',
              detail: '$review awaiting review',
              icon: Icons.ballot_outlined,
              tone: TgcgMetricTone.ai,
              onTap: modules.contains(TgcgModule.resultCapture)
                  ? () => onOpenModule(TgcgModule.resultCapture)
                  : null,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Verified result PUs',
              value: '$verifiedPollingUnits',
              detail: 'Verified submissions included',
              icon: Icons.fact_check_outlined,
              tone: TgcgMetricTone.success,
              onTap: modules.contains(TgcgModule.collation)
                  ? () => onOpenModule(TgcgModule.collation)
                  : null,
            ),
            TgcgMetricCard(
              width: width,
              label: 'Agent readiness',
              value: approvedAgents == 0
                  ? '0%'
                  : '${((readyAgents / approvedAgents) * 100).round()}%',
              detail: 'Training + identity + device',
              icon: Icons.verified_user_outlined,
              tone: TgcgMetricTone.neutral,
              onTap: modules.contains(TgcgModule.accreditation)
                  ? () => onOpenModule(TgcgModule.accreditation)
                  : null,
            ),
          ];

          return Wrap(spacing: gap, runSpacing: gap, children: cards);
        },
      );
}

class _CoverageData {
  const _CoverageData({
    required this.scope,
    required this.members,
    required this.agents,
    required this.incidents,
    required this.results,
  });

  final GeographicScope scope;
  final int members;
  final int agents;
  final int incidents;
  final int results;
}

class _CoveragePanel extends StatelessWidget {
  const _CoveragePanel({
    required this.scope,
    required this.coverage,
    required this.totalMembers,
    required this.totalAgents,
    required this.onOpenMembership,
    required this.onOpenGeography,
  });

  final GeographicScope scope;
  final List<_CoverageData> coverage;
  final int totalMembers;
  final int totalAgents;
  final VoidCallback? onOpenMembership;
  final VoidCallback? onOpenGeography;

  String get _title => switch (scope.level) {
        GeographyLevel.country => 'National coverage by geopolitical zone',
        GeographyLevel.geopoliticalZone => 'Zone coverage by state',
        GeographyLevel.state => 'State operational geography',
        GeographyLevel.senatorialDistrict => 'Senatorial district coverage',
        GeographyLevel.lga => 'LGA coverage',
        GeographyLevel.ward => 'Ward coverage',
        GeographyLevel.pollingUnit => 'Polling unit',
      };

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: _title,
        subtitle:
            '$totalMembers registered members • $totalAgents agents • ${scope.label}',
        trailing: Wrap(
          spacing: 6,
          children: [
            if (onOpenMembership != null)
              TextButton.icon(
                onPressed: onOpenMembership,
                icon: const Icon(Icons.groups_2_outlined, size: 17),
                label: const Text('Members'),
              ),
            if (onOpenGeography != null)
              TextButton.icon(
                onPressed: onOpenGeography,
                icon: const Icon(Icons.public_outlined, size: 17),
                label: const Text('Geography'),
              ),
          ],
        ),
        child: coverage.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.location_on_outlined,
                title: 'Current operational scope',
                message: 'This is the lowest geographic level available here.',
              )
            : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 1100
                      ? 3
                      : constraints.maxWidth >= 680
                          ? 2
                          : 1;
                  const gap = 10.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: coverage.map((item) {
                      final active = item.members > 0 ||
                          item.agents > 0 ||
                          item.incidents > 0 ||
                          item.results > 0;
                      return Container(
                        width: width,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: active
                              ? TgcgColors.primarySoft
                              : TgcgColors.surfaceSoft,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: TgcgColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  item.scope.level == GeographyLevel.state
                                      ? Icons.location_city_outlined
                                      : Icons.public_outlined,
                                  color: TgcgColors.primary,
                                  size: 18,
                                ),
                                const SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    item.scope.level == GeographyLevel.state
                                        ? item.scope.stateName ?? item.scope.label
                                        : item.scope.zoneName ?? item.scope.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: TgcgColors.ink,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                if (active)
                                  const Icon(
                                    Icons.circle,
                                    color: TgcgColors.success,
                                    size: 8,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _CoverageMetric(
                                    label: 'Members',
                                    value: item.members,
                                  ),
                                ),
                                Expanded(
                                  child: _CoverageMetric(
                                    label: 'Agents',
                                    value: item.agents,
                                  ),
                                ),
                                Expanded(
                                  child: _CoverageMetric(
                                    label: 'Incidents',
                                    value: item.incidents,
                                  ),
                                ),
                                Expanded(
                                  child: _CoverageMetric(
                                    label: 'Results',
                                    value: item.results,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
      );
}

class _CoverageMetric extends StatelessWidget {
  const _CoverageMetric({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
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

class _OperationsProgressPanel extends StatelessWidget {
  const _OperationsProgressPanel({
    required this.collation,
    required this.readyAgents,
    required this.approvedAgents,
    required this.fieldReports,
    required this.openIncidents,
    required this.onOpenCollation,
  });

  final CollationSummary collation;
  final int readyAgents;
  final int approvedAgents;
  final int fieldReports;
  final int openIncidents;
  final VoidCallback? onOpenCollation;

  @override
  Widget build(BuildContext context) {
    final readiness = approvedAgents == 0 ? 0.0 : readyAgents / approvedAgents;
    return TgcgSectionCard(
      title: 'Operational readiness',
      subtitle: 'Current field readiness and verified result activity.',
      trailing: onOpenCollation == null
          ? null
          : IconButton(
              tooltip: 'Open collation',
              onPressed: onOpenCollation,
              icon: const Icon(Icons.arrow_outward_rounded),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${(readiness * 100).round()}%',
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'agent readiness',
                  style: TextStyle(color: TgcgColors.muted, fontSize: 10.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: readiness.clamp(0, 1).toDouble(),
              minHeight: 10,
              backgroundColor: const Color(0xFFE5E7EC),
              valueColor: const AlwaysStoppedAnimation(TgcgColors.success),
            ),
          ),
          const SizedBox(height: 16),
          _ProgressRow('Ready agents', '$readyAgents / $approvedAgents'),
          _ProgressRow('Field reports', '$fieldReports'),
          _ProgressRow('Open incidents', '$openIncidents'),
          _ProgressRow(
            'Verified result PUs',
            '${collation.verifiedPollingUnitCount}',
          ),
          _ProgressRow(
            'Reconciliation conflicts',
            '${collation.conflictingPollingUnitIds.length}',
            warning: collation.conflictingPollingUnitIds.isNotEmpty,
          ),
          const SizedBox(height: 10),
          const TgcgStatusPill(
            label: 'UNOFFICIAL FIELD DATA',
            color: TgcgColors.warning,
            icon: Icons.info_outline_rounded,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow(this.label, this.value, {this.warning = false});

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
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
            Text(
              value,
              style: TextStyle(
                color: warning ? TgcgColors.warning : TgcgColors.ink,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
}

class _PriorityEventsPanel extends StatelessWidget {
  const _PriorityEventsPanel({
    required this.incidents,
    required this.reviewCount,
    required this.modules,
    required this.onOpenModule,
  });

  final List<FieldIncident> incidents;
  final int reviewCount;
  final Set<TgcgModule> modules;
  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final sorted = [...incidents]
      ..sort((a, b) {
        final severity =
            _severityRank(b.severity).compareTo(_severityRank(a.severity));
        if (severity != 0) return severity;
        return b.reportedAt.compareTo(a.reportedAt);
      });

    return TgcgSectionCard(
      title: 'Priority events',
      subtitle: 'Operational items requiring command attention.',
      child: Column(
        children: [
          if (sorted.isEmpty && reviewCount == 0)
            const TgcgEmptyState(
              icon: Icons.task_alt_rounded,
              title: 'No command exceptions',
              message: 'No unresolved incidents or result-review items in this scope.',
            )
          else ...[
            ...sorted.take(5).map(
                  (incident) => _EventRow(
                    color: _severityColor(incident.severity),
                    title: incident.title,
                    subtitle:
                        '${incident.scope.label} • ${_label(incident.status.name)}',
                    trailing: _label(incident.severity.name),
                    onTap: modules.contains(TgcgModule.situationRoom)
                        ? () => onOpenModule(TgcgModule.situationRoom)
                        : null,
                  ),
                ),
            if (reviewCount > 0)
              _EventRow(
                color: TgcgColors.ai,
                title:
                    '$reviewCount result submission${reviewCount == 1 ? '' : 's'} awaiting human review',
                subtitle: 'OCR, duplicate and arithmetic review queue',
                trailing: 'REVIEW',
                onTap: modules.contains(TgcgModule.resultCapture)
                    ? () => onOpenModule(TgcgModule.resultCapture)
                    : null,
              ),
          ],
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final Color color;
  final String title;
  final String subtitle;
  final String trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.crisis_alert_outlined, color: color, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: TextStyle(
                  color: color,
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: TgcgColors.muted,
                  size: 18,
                ),
            ],
          ),
        ),
      );
}

class _QuickCommandPanel extends StatelessWidget {
  const _QuickCommandPanel({
    required this.modules,
    required this.onOpenModule,
  });

  final Set<TgcgModule> modules;
  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final actions = <({
      TgcgModule module,
      String label,
      String detail,
      IconData icon,
      TgcgMetricTone tone,
    })>[
      (
        module: TgcgModule.membershipNetwork,
        label: 'Registered Members',
        detail: 'Zones, states, members and agents',
        icon: Icons.groups_2_outlined,
        tone: TgcgMetricTone.info,
      ),
      (
        module: TgcgModule.situationRoom,
        label: 'Situation Room',
        detail: 'Live incident command',
        icon: Icons.radar_rounded,
        tone: TgcgMetricTone.danger,
      ),
      (
        module: TgcgModule.geography,
        label: 'Geographic Operations',
        detail: 'National operational coverage',
        icon: Icons.public_rounded,
        tone: TgcgMetricTone.neutral,
      ),
      (
        module: TgcgModule.resultCapture,
        label: 'Result Workspace',
        detail: 'Capture and human review',
        icon: Icons.ballot_outlined,
        tone: TgcgMetricTone.ai,
      ),
      (
        module: TgcgModule.communications,
        label: 'Communications',
        detail: 'Operational coordination',
        icon: Icons.forum_outlined,
        tone: TgcgMetricTone.success,
      ),
      (
        module: TgcgModule.systemMonitoring,
        label: 'System Monitoring',
        detail: 'Health and synchronization',
        icon: Icons.monitor_heart_outlined,
        tone: TgcgMetricTone.warning,
      ),
    ].where((item) => modules.contains(item.module)).toList(growable: false);

    return TgcgSectionCard(
      title: 'Quick command',
      subtitle: 'Role-aware shortcuts to operational workspaces.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 980
              ? 3
              : constraints.maxWidth >= 620
                  ? 2
                  : 1;
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: actions.map((action) {
              final color = tgcgToneColor(action.tone);
              return SizedBox(
                width: width,
                child: InkWell(
                  onTap: () => onOpenModule(action.module),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: TgcgColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .09),
                            borderRadius: BorderRadius.circular(11),
                          ),
                          child: Icon(action.icon, color: color, size: 19),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                action.label,
                                style: const TextStyle(
                                  color: TgcgColors.ink,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                action.detail,
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios_rounded,
                          color: TgcgColors.muted,
                          size: 13,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
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

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
