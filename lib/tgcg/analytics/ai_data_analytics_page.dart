import 'package:flutter/material.dart';

import '../field/field_operations_store.dart';
import '../geography/geography_registry.dart';
import '../membership/membership_store.dart';
import '../offline/offline_persistence.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

class AiDataAnalyticsPage extends StatefulWidget {
  const AiDataAnalyticsPage({super.key});

  @override
  State<AiDataAnalyticsPage> createState() => _AiDataAnalyticsPageState();
}

class _AiDataAnalyticsPageState extends State<AiDataAnalyticsPage> {
  _AnalyticsFocus focus = _AnalyticsFocus.overview;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final offline = OfflinePersistence.of(context);

    final scope = session.scope;
    final incidents = field.incidentsForScope(scope);
    final reports = field.reportsForScope(scope);
    final submissions = results.submissionsForScope(scope);
    final reviewQueue = results.reviewQueueForScope(scope);
    final agents = membership.agentsForScope(scope);
    final members = membership.membersForScope(scope);
    final pendingSync = offline.pendingOutbox;

    final unresolved = incidents
        .where((item) =>
            item.status != IncidentStatus.resolved &&
            item.status != IncidentStatus.closed)
        .toList(growable: false);
    final highPriority = unresolved
        .where((item) =>
            item.severity == IncidentSeverity.high ||
            item.severity == IncidentSeverity.critical)
        .toList(growable: false);
    final evidenceItems = incidents.fold<int>(
          0,
          (total, item) => total + item.evidence.length,
        ) +
        reports.fold<int>(
          0,
          (total, item) => total + item.evidence.length,
        );

    final visibleZones = _visibleZones(membership.geography, scope)
        .map(
          (zone) => _zoneAnalytics(
            zone: zone,
            sessionScope: scope,
            membership: membership,
            field: field,
            results: results,
          ),
        )
        .toList(growable: false);

    final busiest = visibleZones.isEmpty
        ? null
        : visibleZones.reduce(
            (a, b) => a.activityTotal >= b.activityTotal ? a : b,
          );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'AI-ASSISTED OPERATIONAL ANALYTICS',
          title: 'AI Data Analytics Centre',
          subtitle:
              '${scope.label}: verification workload, field incidents, evidence quality, activity distribution and data-integrity indicators.',
          trailing: const TgcgStatusPill(
            label: 'HUMAN REVIEW',
            color: TgcgColors.ai,
            icon: Icons.psychology_alt_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _MetricGrid(
          dataPoints: incidents.length + reports.length + submissions.length + agents.length,
          reviewItems: reviewQueue.length,
          highPriority: highPriority.length,
          pendingSync: pendingSync.length,
        ),
        const SizedBox(height: 16),
        _FocusSelector(
          selected: focus,
          onChanged: (value) => setState(() => focus = value),
        ),
        const SizedBox(height: 16),
        _ExecutiveInsights(
          submissions: submissions,
          reviewQueue: reviewQueue,
          unresolved: unresolved,
          incidentsWithEvidence:
              incidents.where((item) => item.evidence.isNotEmpty).length,
          evidenceItems: evidenceItems,
          approvedAgents: agents
              .where((item) => item.status == AccreditationStatus.approved)
              .length,
          totalAgents: agents.length,
          busiest: busiest,
          pendingSync: pendingSync.length,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final distribution = _OperationalDistribution(
              zones: visibleZones,
              focus: focus,
            );
            final quality = _DataQualityPanel(
              submissions: submissions,
              reviewQueue: reviewQueue,
              incidents: incidents,
              reports: reports,
              pendingSync: pendingSync.length,
            );
            if (constraints.maxWidth < 1040) {
              return Column(
                children: [
                  distribution,
                  const SizedBox(height: 16),
                  quality,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: distribution),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: quality),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ReviewQueue(
          submissions: reviewQueue,
          incidents: unresolved,
        ),
        const SizedBox(height: 16),
        _ScopeCoverage(
          members: members.length,
          agents: agents.length,
          reports: reports.length,
          results: submissions.length,
          incidents: incidents.length,
          evidence: evidenceItems,
        ),
      ],
    );
  }
}

enum _AnalyticsFocus { overview, incidents, verification, fieldActivity }

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.dataPoints,
    required this.reviewItems,
    required this.highPriority,
    required this.pendingSync,
  });

  final int dataPoints;
  final int reviewItems;
  final int highPriority;
  final int pendingSync;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 520
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
                label: 'Operational records',
                value: '$dataPoints',
                detail: 'Current authorized scope',
                icon: Icons.dataset_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Human review queue',
                value: '$reviewItems',
                detail: 'Result integrity review',
                icon: Icons.fact_check_outlined,
                tone: reviewItems == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'High-priority incidents',
                value: '$highPriority',
                detail: 'Unresolved high / critical',
                icon: Icons.crisis_alert_outlined,
                tone: highPriority == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Offline queue',
                value: '$pendingSync',
                detail: pendingSync == 0 ? 'No pending mutations' : 'Awaiting synchronization',
                icon: Icons.sync_outlined,
                tone: pendingSync == 0
                    ? TgcgMetricTone.success
                    : TgcgMetricTone.warning,
              ),
            ],
          );
        },
      );
}

class _FocusSelector extends StatelessWidget {
  const _FocusSelector({required this.selected, required this.onChanged});

  final _AnalyticsFocus selected;
  final ValueChanged<_AnalyticsFocus> onChanged;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Analysis focus',
        subtitle: 'Change the operational signal emphasized in the distribution view.',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(_AnalyticsFocus.overview, 'Overview', Icons.dashboard_outlined),
            _chip(_AnalyticsFocus.incidents, 'Incidents', Icons.warning_amber_rounded),
            _chip(_AnalyticsFocus.verification, 'Verification', Icons.fact_check_outlined),
            _chip(_AnalyticsFocus.fieldActivity, 'Field activity', Icons.sensors_outlined),
          ],
        ),
      );

  Widget _chip(_AnalyticsFocus value, String label, IconData icon) {
    final active = value == selected;
    return ChoiceChip(
      selected: active,
      onSelected: (_) => onChanged(value),
      avatar: Icon(
        icon,
        size: 17,
        color: active ? Colors.white : TgcgColors.primary,
      ),
      label: Text(label),
      labelStyle: TextStyle(
        color: active ? Colors.white : TgcgColors.ink,
        fontWeight: FontWeight.w800,
      ),
      selectedColor: TgcgColors.primary,
      backgroundColor: TgcgColors.surfaceSoft,
      side: BorderSide(color: active ? TgcgColors.primary : TgcgColors.border),
      showCheckmark: false,
    );
  }
}

class _ExecutiveInsights extends StatelessWidget {
  const _ExecutiveInsights({
    required this.submissions,
    required this.reviewQueue,
    required this.unresolved,
    required this.incidentsWithEvidence,
    required this.evidenceItems,
    required this.approvedAgents,
    required this.totalAgents,
    required this.busiest,
    required this.pendingSync,
  });

  final List<ElectionResultSubmission> submissions;
  final List<ElectionResultSubmission> reviewQueue;
  final List<FieldIncident> unresolved;
  final int incidentsWithEvidence;
  final int evidenceItems;
  final int approvedAgents;
  final int totalAgents;
  final _ZoneAnalytics? busiest;
  final int pendingSync;

  @override
  Widget build(BuildContext context) {
    final verificationText = submissions.isEmpty
        ? 'No result submissions are available in this scope.'
        : reviewQueue.isEmpty
            ? 'All current result submissions are clear of the human-review queue.'
            : '${reviewQueue.length} of ${submissions.length} result submissions currently require human review.';
    final incidentText = unresolved.isEmpty
        ? 'No unresolved field incidents are currently recorded in this scope.'
        : '${unresolved.length} unresolved incident${unresolved.length == 1 ? '' : 's'} require operational follow-up.';
    final evidenceText = unresolved.isEmpty
        ? 'No unresolved incident evidence requirement is pending.'
        : '$incidentsWithEvidence of ${unresolved.length} recorded incidents currently include attached evidence; $evidenceItems evidence item${evidenceItems == 1 ? '' : 's'} are indexed.';
    final readinessText = totalAgents == 0
        ? 'No accredited agents are currently assigned in this scope.'
        : '$approvedAgents of $totalAgents assigned agents are approved for operations.';

    return TgcgSectionCard(
      title: 'Operational intelligence summary',
      subtitle: 'System-derived indicators for human decision support; these are not election-outcome predictions.',
      trailing: const TgcgStatusPill(
        label: 'CURRENT DATA',
        color: TgcgColors.ai,
        icon: Icons.auto_awesome_rounded,
        compact: true,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 920 ? 4 : constraints.maxWidth >= 560 ? 2 : 1;
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              _InsightCard(
                width: width,
                icon: Icons.fact_check_outlined,
                title: 'Verification workload',
                body: verificationText,
                tone: reviewQueue.isEmpty ? TgcgColors.success : TgcgColors.warning,
              ),
              _InsightCard(
                width: width,
                icon: Icons.crisis_alert_outlined,
                title: 'Incident attention',
                body: incidentText,
                tone: unresolved.isEmpty ? TgcgColors.success : TgcgColors.danger,
              ),
              _InsightCard(
                width: width,
                icon: Icons.perm_media_outlined,
                title: 'Evidence coverage',
                body: evidenceText,
                tone: evidenceItems > 0 ? TgcgColors.info : TgcgColors.muted,
              ),
              _InsightCard(
                width: width,
                icon: Icons.badge_outlined,
                title: 'Agent readiness',
                body: '$readinessText${busiest == null ? '' : ' Highest recorded activity: ${busiest!.name}.'}${pendingSync == 0 ? '' : ' $pendingSync local mutation${pendingSync == 1 ? '' : 's'} await sync.'}',
                tone: approvedAgents == totalAgents && totalAgents > 0
                    ? TgcgColors.success
                    : TgcgColors.primary,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.width,
    required this.icon,
    required this.title,
    required this.body,
    required this.tone,
  });

  final double width;
  final IconData icon;
  final String title;
  final String body;
  final Color tone;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        constraints: const BoxConstraints(minHeight: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: tone),
            ),
            const SizedBox(height: 11),
            Text(
              title,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
}

class _OperationalDistribution extends StatelessWidget {
  const _OperationalDistribution({required this.zones, required this.focus});

  final List<_ZoneAnalytics> zones;
  final _AnalyticsFocus focus;

  @override
  Widget build(BuildContext context) {
    final maxValue = zones.fold<int>(1, (current, item) {
      final value = item.valueFor(focus);
      return value > current ? value : current;
    });

    return TgcgSectionCard(
      title: 'Geographic operational distribution',
      subtitle: _focusSubtitle(focus),
      trailing: TgcgStatusPill(
        label: '${zones.length} ZONE${zones.length == 1 ? '' : 'S'}',
        color: TgcgColors.primary,
        icon: Icons.public_rounded,
        compact: true,
      ),
      child: zones.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.public_off_outlined,
              title: 'No geographic analytics available',
              message: 'No operational records are available for the current scope.',
            )
          : Column(
              children: zones
                  .map(
                    (zone) => _DistributionBar(
                      zone: zone,
                      value: zone.valueFor(focus),
                      maxValue: maxValue,
                      focus: focus,
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }

  String _focusSubtitle(_AnalyticsFocus value) => switch (value) {
        _AnalyticsFocus.overview =>
          'Combined operational activity from agents, reports, incidents and result submissions.',
        _AnalyticsFocus.incidents =>
          'Recorded unresolved field incidents by geopolitical zone.',
        _AnalyticsFocus.verification =>
          'Result submissions requiring human integrity review by geopolitical zone.',
        _AnalyticsFocus.fieldActivity =>
          'Field reports and approved agent assignments by geopolitical zone.',
      };
}

class _DistributionBar extends StatelessWidget {
  const _DistributionBar({
    required this.zone,
    required this.value,
    required this.maxValue,
    required this.focus,
  });

  final _ZoneAnalytics zone;
  final int value;
  final int maxValue;
  final _AnalyticsFocus focus;

  @override
  Widget build(BuildContext context) {
    final fraction = maxValue <= 0 ? 0.0 : value / maxValue;
    final color = _barColor(focus, zone);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 118,
                child: Text(
                  zone.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 12,
                    color: TgcgColors.surfaceSoft,
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: fraction.clamp(0.0, 1.0),
                      child: Container(color: color),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 30,
                child: Text(
                  '$value',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 118),
            child: Text(
              '${zone.agents} agents • ${zone.reports} reports • ${zone.unresolvedIncidents} unresolved • ${zone.results} results • ${zone.reviewItems} review',
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 8.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _barColor(_AnalyticsFocus focus, _ZoneAnalytics zone) {
    if (focus == _AnalyticsFocus.incidents) {
      return zone.highPriorityIncidents > 0 ? TgcgColors.danger : TgcgColors.warning;
    }
    if (focus == _AnalyticsFocus.verification) {
      return zone.reviewItems > 0 ? TgcgColors.ai : TgcgColors.success;
    }
    if (focus == _AnalyticsFocus.fieldActivity) return TgcgColors.info;
    return TgcgColors.primary;
  }
}

class _DataQualityPanel extends StatelessWidget {
  const _DataQualityPanel({
    required this.submissions,
    required this.reviewQueue,
    required this.incidents,
    required this.reports,
    required this.pendingSync,
  });

  final List<ElectionResultSubmission> submissions;
  final List<ElectionResultSubmission> reviewQueue;
  final List<FieldIncident> incidents;
  final List<FieldReport> reports;
  final int pendingSync;

  @override
  Widget build(BuildContext context) {
    final verified = submissions
        .where((item) => item.status == RecordStatus.verified)
        .length;
    final resultEvidence = submissions
        .where((item) => item.resultForm != null)
        .length;
    final incidentEvidence = incidents
        .where((item) => item.evidence.isNotEmpty)
        .length;
    final reviewedReports = reports
        .where((item) =>
            item.status == RecordStatus.verified ||
            item.status == RecordStatus.underReview)
        .length;

    return TgcgSectionCard(
      title: 'Data quality & integrity',
      subtitle: 'Rule-based indicators from current records.',
      child: Column(
        children: [
          _QualityRow(
            icon: Icons.verified_outlined,
            label: 'Verified results',
            value: '$verified / ${submissions.length}',
            color: verified == submissions.length && submissions.isNotEmpty
                ? TgcgColors.success
                : TgcgColors.info,
          ),
          _QualityRow(
            icon: Icons.manage_search_outlined,
            label: 'Human review required',
            value: '${reviewQueue.length}',
            color: reviewQueue.isEmpty ? TgcgColors.success : TgcgColors.warning,
          ),
          _QualityRow(
            icon: Icons.image_outlined,
            label: 'Result forms attached',
            value: '$resultEvidence / ${submissions.length}',
            color: resultEvidence == submissions.length && submissions.isNotEmpty
                ? TgcgColors.success
                : TgcgColors.info,
          ),
          _QualityRow(
            icon: Icons.perm_media_outlined,
            label: 'Incidents with evidence',
            value: '$incidentEvidence / ${incidents.length}',
            color: incidentEvidence == incidents.length && incidents.isNotEmpty
                ? TgcgColors.success
                : TgcgColors.warning,
          ),
          _QualityRow(
            icon: Icons.assignment_turned_in_outlined,
            label: 'Reports reviewed',
            value: '$reviewedReports / ${reports.length}',
            color: TgcgColors.info,
          ),
          _QualityRow(
            icon: Icons.sync_problem_outlined,
            label: 'Pending sync mutations',
            value: '$pendingSync',
            color: pendingSync == 0 ? TgcgColors.success : TgcgColors.warning,
          ),
        ],
      ),
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      );
}

class _ReviewQueue extends StatelessWidget {
  const _ReviewQueue({required this.submissions, required this.incidents});

  final List<ElectionResultSubmission> submissions;
  final List<FieldIncident> incidents;

  @override
  Widget build(BuildContext context) {
    final priorityIncidents = incidents
        .where((item) =>
            item.severity == IncidentSeverity.high ||
            item.severity == IncidentSeverity.critical ||
            item.category.toLowerCase().contains('evidence') ||
            item.category.toLowerCase().contains('technical'))
        .take(4)
        .toList(growable: false);
    final reviewResults = submissions.take(4).toList(growable: false);

    return TgcgSectionCard(
      title: 'AI-assisted review queue',
      subtitle: 'Records surfaced for human attention based on existing integrity and operational rules.',
      trailing: TgcgStatusPill(
        label: '${reviewResults.length + priorityIncidents.length} ITEMS',
        color: reviewResults.isEmpty && priorityIncidents.isEmpty
            ? TgcgColors.success
            : TgcgColors.warning,
        compact: true,
      ),
      child: reviewResults.isEmpty && priorityIncidents.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.task_alt_rounded,
              title: 'No review items',
              message: 'No current result-integrity or priority operational item requires attention.',
            )
          : Column(
              children: [
                ...reviewResults.map(
                  (item) => _QueueRow(
                    icon: Icons.fact_check_outlined,
                    color: TgcgColors.ai,
                    title: '${item.id} • Result integrity review',
                    detail:
                        '${item.pollingUnitScope.stateName ?? 'State'} • ${item.pollingUnitScope.lgaName ?? 'LGA'} • ${item.pollingUnitScope.pollingUnitName ?? 'Polling Unit'}',
                    status: 'HUMAN REVIEW',
                  ),
                ),
                ...priorityIncidents.map(
                  (item) => _QueueRow(
                    icon: Icons.warning_amber_rounded,
                    color: item.severity == IncidentSeverity.critical ||
                            item.severity == IncidentSeverity.high
                        ? TgcgColors.danger
                        : TgcgColors.warning,
                    title: '${item.id} • ${item.title}',
                    detail:
                        '${item.scope.stateName ?? 'State'} • ${item.scope.lgaName ?? 'LGA'} • ${item.category}',
                    status: _incidentLabel(item.severity),
                  ),
                ),
              ],
            ),
    );
  }

  String _incidentLabel(IncidentSeverity severity) => switch (severity) {
        IncidentSeverity.critical => 'CRITICAL',
        IncidentSeverity.high => 'HIGH',
        IncidentSeverity.medium => 'REVIEW',
        IncidentSeverity.low => 'INFO',
      };
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.detail,
    required this.status,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String detail;
  final String status;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(12),
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
                color: color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
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
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            TgcgStatusPill(label: status, color: color, compact: true),
          ],
        ),
      );
}

class _ScopeCoverage extends StatelessWidget {
  const _ScopeCoverage({
    required this.members,
    required this.agents,
    required this.reports,
    required this.results,
    required this.incidents,
    required this.evidence,
  });

  final int members;
  final int agents;
  final int reports;
  final int results;
  final int incidents;
  final int evidence;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Authorized data coverage',
        subtitle: 'Record volumes currently available to analytics in this operator scope.',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 900 ? 6 : constraints.maxWidth >= 560 ? 3 : 2;
            const gap = 9.0;
            final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
            final values = <(String, int, IconData)>[
              ('Members', members, Icons.groups_2_outlined),
              ('Agents', agents, Icons.badge_outlined),
              ('Reports', reports, Icons.description_outlined),
              ('Results', results, Icons.ballot_outlined),
              ('Incidents', incidents, Icons.warning_amber_outlined),
              ('Evidence', evidence, Icons.perm_media_outlined),
            ];
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: values
                  .map(
                    (item) => Container(
                      width: width,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: TgcgColors.surfaceSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: TgcgColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(item.$3, size: 18, color: TgcgColors.primary),
                          const SizedBox(height: 8),
                          Text(
                            '${item.$2}',
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            item.$1,
                            style: const TextStyle(
                              color: TgcgColors.muted,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      );
}

class _ZoneAnalytics {
  const _ZoneAnalytics({
    required this.name,
    required this.code,
    required this.agents,
    required this.reports,
    required this.unresolvedIncidents,
    required this.highPriorityIncidents,
    required this.results,
    required this.reviewItems,
  });

  final String name;
  final String code;
  final int agents;
  final int reports;
  final int unresolvedIncidents;
  final int highPriorityIncidents;
  final int results;
  final int reviewItems;

  int get activityTotal =>
      agents + reports + unresolvedIncidents + results + reviewItems;

  int valueFor(_AnalyticsFocus focus) => switch (focus) {
        _AnalyticsFocus.overview => activityTotal,
        _AnalyticsFocus.incidents => unresolvedIncidents,
        _AnalyticsFocus.verification => reviewItems,
        _AnalyticsFocus.fieldActivity => agents + reports,
      };
}

List<CanonicalZone> _visibleZones(
  GeographyRegistry geography,
  GeographicScope sessionScope,
) {
  if (sessionScope.level == GeographyLevel.country) {
    return geography.zones;
  }
  final zoneId = sessionScope.zoneId;
  if (zoneId == null) return const [];
  return geography.zones
      .where((zone) => zone.id == zoneId)
      .toList(growable: false);
}

_ZoneAnalytics _zoneAnalytics({
  required CanonicalZone zone,
  required GeographicScope sessionScope,
  required MembershipOperationsController membership,
  required FieldOperationsController field,
  required ResultOperationsController results,
}) {
  final scope = sessionScope.level == GeographyLevel.country
      ? zone.scope
      : sessionScope;
  final incidents = field.incidentsForScope(scope);
  final unresolved = incidents
      .where((item) =>
          item.status != IncidentStatus.resolved &&
          item.status != IncidentStatus.closed)
      .toList(growable: false);
  return _ZoneAnalytics(
    name: zone.name,
    code: zone.id,
    agents: membership
        .agentsForScope(scope)
        .where((item) => item.status == AccreditationStatus.approved)
        .length,
    reports: field.reportsForScope(scope).length,
    unresolvedIncidents: unresolved.length,
    highPriorityIncidents: unresolved
        .where((item) =>
            item.severity == IncidentSeverity.high ||
            item.severity == IncidentSeverity.critical)
        .length,
    results: results.submissionsForScope(scope).length,
    reviewItems: results.reviewQueueForScope(scope).length,
  );
}
