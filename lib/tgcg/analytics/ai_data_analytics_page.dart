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
    final evidenceCount = incidents.fold<int>(
          0,
          (total, item) => total + item.evidence.length,
        ) +
        reports.fold<int>(
          0,
          (total, item) => total + item.evidence.length,
        );
    final unresolvedWithEvidence =
        unresolved.where((item) => item.evidence.isNotEmpty).length;
    final approvedAgents = agents
        .where((item) => item.status == AccreditationStatus.approved)
        .length;
    final pendingSync = offline.pendingOutbox.length;

    final zones = _visibleZones(membership.geography, scope)
        .map(
          (zone) => _zoneSummary(
            zone: zone,
            sessionScope: scope,
            membership: membership,
            field: field,
            results: results,
          ),
        )
        .toList(growable: false);

    final arithmeticFlags = submissions
        .where((item) => item.validation?.arithmeticValid == false)
        .length;
    final duplicateFlags = submissions
        .where((item) => item.validation?.duplicateSuspected == true)
        .length;
    final ocrMismatch = submissions
        .where((item) => item.validation?.ocrMatchedManualEntry == false)
        .length;
    final missingForms = submissions.where((item) => item.resultForm == null).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'AI-ASSISTED OPERATIONAL ANALYTICS',
          title: 'AI Data Analytics Centre',
          subtitle:
              '${scope.label}: verification workload, incident pressure, evidence quality, field activity and data-integrity indicators.',
          trailing: const TgcgStatusPill(
            label: 'HUMAN REVIEW',
            color: TgcgColors.ai,
            icon: Icons.psychology_alt_outlined,
          ),
        ),
        const SizedBox(height: 18),
        _MetricGrid(
          operationalRecords:
              incidents.length + reports.length + submissions.length + agents.length,
          reviewQueue: reviewQueue.length,
          highPriority: highPriority.length,
          pendingSync: pendingSync,
        ),
        const SizedBox(height: 16),
        _FocusSelector(
          selected: focus,
          onChanged: (value) => setState(() => focus = value),
        ),
        const SizedBox(height: 16),
        _InsightPanel(
          submissions: submissions.length,
          reviewQueue: reviewQueue.length,
          unresolved: unresolved.length,
          unresolvedWithEvidence: unresolvedWithEvidence,
          approvedAgents: approvedAgents,
          totalAgents: agents.length,
          pendingSync: pendingSync,
          zones: zones,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final distribution = _DistributionPanel(zones: zones, focus: focus);
            final integrity = _IntegrityPanel(
              submissions: submissions.length,
              reviewQueue: reviewQueue.length,
              arithmeticFlags: arithmeticFlags,
              duplicateFlags: duplicateFlags,
              ocrMismatch: ocrMismatch,
              missingForms: missingForms,
              evidenceCount: evidenceCount,
              pendingSync: pendingSync,
            );
            if (constraints.maxWidth < 1030) {
              return Column(
                children: [
                  distribution,
                  const SizedBox(height: 16),
                  integrity,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: distribution),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: integrity),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _AttentionQueue(
          results: reviewQueue,
          incidents: unresolved,
        ),
        const SizedBox(height: 16),
        _CoveragePanel(
          members: members.length,
          agents: agents.length,
          reports: reports.length,
          results: submissions.length,
          incidents: incidents.length,
          evidence: evidenceCount,
        ),
      ],
    );
  }
}

enum _AnalyticsFocus { overview, incidents, verification, fieldActivity }

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.operationalRecords,
    required this.reviewQueue,
    required this.highPriority,
    required this.pendingSync,
  });

  final int operationalRecords;
  final int reviewQueue;
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
                value: '$operationalRecords',
                detail: 'Current authorized scope',
                icon: Icons.dataset_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Human review queue',
                value: '$reviewQueue',
                detail: 'Result-integrity review',
                icon: Icons.fact_check_outlined,
                tone: reviewQueue == 0
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
                detail: pendingSync == 0
                    ? 'No pending mutations'
                    : 'Awaiting synchronization',
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
        subtitle: 'Change the operational signal emphasized in the geographic view.',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(_AnalyticsFocus.overview, 'Overview', Icons.dashboard_outlined),
            _chip(
              _AnalyticsFocus.incidents,
              'Incidents',
              Icons.warning_amber_rounded,
            ),
            _chip(
              _AnalyticsFocus.verification,
              'Verification',
              Icons.fact_check_outlined,
            ),
            _chip(
              _AnalyticsFocus.fieldActivity,
              'Field activity',
              Icons.sensors_outlined,
            ),
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
      side: BorderSide(
        color: active ? TgcgColors.primary : TgcgColors.border,
      ),
      showCheckmark: false,
    );
  }
}

class _InsightPanel extends StatelessWidget {
  const _InsightPanel({
    required this.submissions,
    required this.reviewQueue,
    required this.unresolved,
    required this.unresolvedWithEvidence,
    required this.approvedAgents,
    required this.totalAgents,
    required this.pendingSync,
    required this.zones,
  });

  final int submissions;
  final int reviewQueue;
  final int unresolved;
  final int unresolvedWithEvidence;
  final int approvedAgents;
  final int totalAgents;
  final int pendingSync;
  final List<_ZoneSummary> zones;

  @override
  Widget build(BuildContext context) {
    final busiest = zones.isEmpty
        ? null
        : zones.reduce((a, b) => a.activity >= b.activity ? a : b);
    final items = <_Insight>[
      _Insight(
        icon: Icons.fact_check_outlined,
        title: 'Verification workload',
        text: submissions == 0
            ? 'No result submissions are available in this scope.'
            : reviewQueue == 0
                ? 'All current submissions are clear of the human-review queue.'
                : '$reviewQueue of $submissions submissions currently require human review.',
        color: reviewQueue == 0 ? TgcgColors.success : TgcgColors.warning,
      ),
      _Insight(
        icon: Icons.crisis_alert_outlined,
        title: 'Incident attention',
        text: unresolved == 0
            ? 'No unresolved field incidents are currently recorded.'
            : '$unresolved unresolved incident${unresolved == 1 ? '' : 's'} require operational follow-up.',
        color: unresolved == 0 ? TgcgColors.success : TgcgColors.danger,
      ),
      _Insight(
        icon: Icons.perm_media_outlined,
        title: 'Evidence coverage',
        text: unresolved == 0
            ? 'No unresolved incident evidence requirement is pending.'
            : '$unresolvedWithEvidence of $unresolved unresolved incidents include attached evidence.',
        color: unresolvedWithEvidence == unresolved && unresolved > 0
            ? TgcgColors.success
            : TgcgColors.info,
      ),
      _Insight(
        icon: Icons.badge_outlined,
        title: 'Operational readiness',
        text: totalAgents == 0
            ? 'No accredited agents are assigned in this scope.'
            : '$approvedAgents of $totalAgents assigned agents are approved.${busiest == null ? '' : ' Highest recorded activity is ${busiest.name}.'}${pendingSync == 0 ? '' : ' $pendingSync local mutation${pendingSync == 1 ? '' : 's'} await sync.'}',
        color: approvedAgents == totalAgents && totalAgents > 0
            ? TgcgColors.success
            : TgcgColors.primary,
      ),
    ];

    return TgcgSectionCard(
      title: 'Operational intelligence summary',
      subtitle:
          'System-derived indicators for human decision support; no election-outcome prediction is performed.',
      trailing: const TgcgStatusPill(
        label: 'CURRENT DATA',
        color: TgcgColors.ai,
        icon: Icons.auto_awesome_rounded,
        compact: true,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 920
              ? 4
              : constraints.maxWidth >= 560
                  ? 2
                  : 1;
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: items
                .map((item) => _InsightCard(item: item, width: width))
                .toList(growable: false),
          );
        },
      ),
    );
  }
}

class _Insight {
  const _Insight({
    required this.icon,
    required this.title,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String text;
  final Color color;
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.item, required this.width});

  final _Insight item;
  final double width;

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
                color: item.color.withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(item.icon, size: 19, color: item.color),
            ),
            const SizedBox(height: 11),
            Text(
              item.title,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              item.text,
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

class _DistributionPanel extends StatelessWidget {
  const _DistributionPanel({required this.zones, required this.focus});

  final List<_ZoneSummary> zones;
  final _AnalyticsFocus focus;

  @override
  Widget build(BuildContext context) {
    final maxValue = zones.fold<int>(1, (current, zone) {
      final value = zone.valueFor(focus);
      return value > current ? value : current;
    });

    return TgcgSectionCard(
      title: 'Geographic operational distribution',
      subtitle: switch (focus) {
        _AnalyticsFocus.overview =>
          'Combined operational activity from approved agents, reports, incidents and result submissions.',
        _AnalyticsFocus.incidents =>
          'Unresolved field incidents by authorized geopolitical scope.',
        _AnalyticsFocus.verification =>
          'Result submissions requiring human integrity review.',
        _AnalyticsFocus.fieldActivity =>
          'Approved agent assignments and field reports.',
      },
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
              message: 'No operational records are available for this scope.',
            )
          : Column(
              children: zones
                  .map(
                    (zone) => _ZoneBar(
                      zone: zone,
                      focus: focus,
                      maxValue: maxValue,
                    ),
                  )
                  .toList(growable: false),
            ),
    );
  }
}

class _ZoneBar extends StatelessWidget {
  const _ZoneBar({
    required this.zone,
    required this.focus,
    required this.maxValue,
  });

  final _ZoneSummary zone;
  final _AnalyticsFocus focus;
  final int maxValue;

  @override
  Widget build(BuildContext context) {
    final value = zone.valueFor(focus);
    final fraction = maxValue == 0 ? 0.0 : value / maxValue;
    final color = focus == _AnalyticsFocus.incidents && zone.highPriority > 0
        ? TgcgColors.danger
        : focus == _AnalyticsFocus.verification
            ? TgcgColors.ai
            : focus == _AnalyticsFocus.fieldActivity
                ? TgcgColors.info
                : TgcgColors.primary;

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
              '${zone.agents} agents • ${zone.reports} reports • ${zone.unresolved} unresolved • ${zone.results} results • ${zone.review} review',
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
}

class _IntegrityPanel extends StatelessWidget {
  const _IntegrityPanel({
    required this.submissions,
    required this.reviewQueue,
    required this.arithmeticFlags,
    required this.duplicateFlags,
    required this.ocrMismatch,
    required this.missingForms,
    required this.evidenceCount,
    required this.pendingSync,
  });

  final int submissions;
  final int reviewQueue;
  final int arithmeticFlags;
  final int duplicateFlags;
  final int ocrMismatch;
  final int missingForms;
  final int evidenceCount;
  final int pendingSync;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Data quality & integrity',
        subtitle: 'Current deterministic checks and review indicators.',
        child: Column(
          children: [
            _IntegrityRow(
              icon: Icons.calculate_outlined,
              label: 'Arithmetic flags',
              value: arithmeticFlags,
              warning: arithmeticFlags > 0,
            ),
            _IntegrityRow(
              icon: Icons.content_copy_outlined,
              label: 'Duplicate flags',
              value: duplicateFlags,
              warning: duplicateFlags > 0,
            ),
            _IntegrityRow(
              icon: Icons.document_scanner_outlined,
              label: 'OCR/manual mismatches',
              value: ocrMismatch,
              warning: ocrMismatch > 0,
            ),
            _IntegrityRow(
              icon: Icons.image_not_supported_outlined,
              label: 'Missing result forms',
              value: missingForms,
              warning: missingForms > 0,
            ),
            _IntegrityRow(
              icon: Icons.manage_search_outlined,
              label: 'Human review queue',
              value: reviewQueue,
              warning: reviewQueue > 0,
            ),
            _IntegrityRow(
              icon: Icons.perm_media_outlined,
              label: 'Evidence indexed',
              value: evidenceCount,
              warning: false,
            ),
            _IntegrityRow(
              icon: Icons.sync_problem_outlined,
              label: 'Pending sync',
              value: pendingSync,
              warning: pendingSync > 0,
            ),
            if (submissions == 0)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Result-integrity indicators will populate when submissions are available.',
                  style: TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 9.5,
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ),
      );
}

class _IntegrityRow extends StatelessWidget {
  const _IntegrityRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.warning,
  });

  final IconData icon;
  final String label;
  final int value;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? TgcgColors.warning : TgcgColors.success;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
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
            '$value',
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
}

class _AttentionQueue extends StatelessWidget {
  const _AttentionQueue({required this.results, required this.incidents});

  final List<ElectionResultSubmission> results;
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
    final reviewResults = results.take(4).toList(growable: false);
    final count = priorityIncidents.length + reviewResults.length;

    return TgcgSectionCard(
      title: 'AI-assisted attention queue',
      subtitle:
          'Records surfaced for human attention from existing integrity and operational rules.',
      trailing: TgcgStatusPill(
        label: '$count ITEMS',
        color: count == 0 ? TgcgColors.success : TgcgColors.warning,
        compact: true,
      ),
      child: count == 0
          ? const TgcgEmptyState(
              icon: Icons.task_alt_rounded,
              title: 'No attention items',
              message:
                  'No current result-integrity or priority operational item requires attention.',
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
                    color: item.severity == IncidentSeverity.high ||
                            item.severity == IncidentSeverity.critical
                        ? TgcgColors.danger
                        : TgcgColors.warning,
                    title: '${item.id} • ${item.title}',
                    detail:
                        '${item.scope.stateName ?? 'State'} • ${item.scope.lgaName ?? 'LGA'} • ${item.category}',
                    status: _severityLabel(item.severity),
                  ),
                ),
              ],
            ),
    );
  }

  String _severityLabel(IncidentSeverity severity) => severity == IncidentSeverity.critical
      ? 'CRITICAL'
      : severity == IncidentSeverity.high
          ? 'HIGH'
          : severity == IncidentSeverity.medium
              ? 'REVIEW'
              : severity == IncidentSeverity.low
                  ? 'LOW'
                  : 'INFO';
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

class _CoveragePanel extends StatelessWidget {
  const _CoveragePanel({
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
  Widget build(BuildContext context) {
    final values = <(String, int, IconData)>[
      ('Members', members, Icons.groups_2_outlined),
      ('Agents', agents, Icons.badge_outlined),
      ('Reports', reports, Icons.description_outlined),
      ('Results', results, Icons.ballot_outlined),
      ('Incidents', incidents, Icons.warning_amber_outlined),
      ('Evidence', evidence, Icons.perm_media_outlined),
    ];

    return TgcgSectionCard(
      title: 'Authorized data coverage',
      subtitle: 'Record volumes available to analytics in this operator scope.',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 6
              : constraints.maxWidth >= 560
                  ? 3
                  : 2;
          const gap = 9.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
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
}

class _ZoneSummary {
  const _ZoneSummary({
    required this.name,
    required this.agents,
    required this.reports,
    required this.unresolved,
    required this.highPriority,
    required this.results,
    required this.review,
  });

  final String name;
  final int agents;
  final int reports;
  final int unresolved;
  final int highPriority;
  final int results;
  final int review;

  int get activity => agents + reports + unresolved + results + review;

  int valueFor(_AnalyticsFocus focus) => switch (focus) {
        _AnalyticsFocus.overview => activity,
        _AnalyticsFocus.incidents => unresolved,
        _AnalyticsFocus.verification => review,
        _AnalyticsFocus.fieldActivity => agents + reports,
      };
}

List<CanonicalZone> _visibleZones(
  GeographyRegistry geography,
  GeographicScope sessionScope,
) {
  if (sessionScope.level == GeographyLevel.country) return geography.zones;
  final zoneId = sessionScope.zoneId;
  if (zoneId == null) return const [];
  return geography.zones
      .where((zone) => zone.id == zoneId)
      .toList(growable: false);
}

_ZoneSummary _zoneSummary({
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

  return _ZoneSummary(
    name: zone.name,
    agents: membership
        .agentsForScope(scope)
        .where((item) => item.status == AccreditationStatus.approved)
        .length,
    reports: field.reportsForScope(scope).length,
    unresolved: unresolved.length,
    highPriority: unresolved
        .where((item) =>
            item.severity == IncidentSeverity.high ||
            item.severity == IncidentSeverity.critical)
        .length,
    results: results.submissionsForScope(scope).length,
    review: results.reviewQueueForScope(scope).length,
  );
}
