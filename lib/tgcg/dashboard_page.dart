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
    final agents = membership.agentsForScope(scope);
    final approvedAgents = agents
        .where((agent) => agent.status == AccreditationStatus.approved)
        .toList(growable: false);
    final readyAgents = approvedAgents
        .where((agent) =>
            agent.trainingCompleted &&
            agent.biometricEnrolled &&
            agent.deviceId != null)
        .toList(growable: false);
    final openIncidents = incidents
        .where((item) =>
            item.status != IncidentStatus.resolved &&
            item.status != IncidentStatus.closed)
        .toList(growable: false);
    final criticalAndHigh = openIncidents
        .where((item) =>
            item.severity == IncidentSeverity.critical ||
            item.severity == IncidentSeverity.high)
        .toList(growable: false);

    final collationEngine = CollationEngine.prototypeSeed();
    final collation = collationEngine.summarize(scope, results.submissions);
    final childScopes = collationEngine.childScopes(scope);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final pagePadding = compact ? 16.0 : 24.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(pagePadding, 22, pagePadding, 32),
          children: [
            TgcgPageHeader(
              eyebrow: scope.level == GeographyLevel.country
                  ? 'National command centre'
                  : 'Authorized operational scope',
              title: session.role == TgcgRole.pollingUnitAgent
                  ? 'Polling Unit Workspace'
                  : 'Operations Command',
              subtitle:
                  '${roleLabel(session.role!)} • ${scope.label}. Live field operations, verified result progress and command exceptions in one workspace.',
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
              incidents: openIncidents.length,
              highPriority: criticalAndHigh.length,
              submissions: submissions.length,
              review: review.length,
              approvedAgents: approvedAgents.length,
              readyAgents: readyAgents.length,
              verifiedPollingUnits: collation.verifiedPollingUnitCount,
              expectedPollingUnits: collation.expectedPollingUnitCount,
              modules: modules,
              onOpenModule: onOpenModule,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, inner) {
                final map = _OperationsMapPanel(
                  scope: scope,
                  engine: collationEngine,
                  submissions: results.submissions,
                  childScopes: childScopes,
                  incidentCount: openIncidents.length,
                  onOpenGeography: modules.contains(TgcgModule.geography)
                      ? () => onOpenModule(TgcgModule.geography)
                      : null,
                );
                final progress = _ElectionProgressPanel(
                  summary: collation,
                  readyAgents: readyAgents.length,
                  approvedAgents: approvedAgents.length,
                  fieldReports: fieldReports.length,
                  onOpenCollation: modules.contains(TgcgModule.collation)
                      ? () => onOpenModule(TgcgModule.collation)
                      : null,
                );
                if (inner.maxWidth < 980) {
                  return Column(
                    children: [map, const SizedBox(height: 16), progress],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 7, child: map),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: progress),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, inner) {
                final events = _CriticalEventFeed(
                  incidents: openIncidents,
                  reviewCount: review.length,
                  modules: modules,
                  onOpenModule: onOpenModule,
                );
                final actions = _QuickCommandPanel(
                  modules: modules,
                  onOpenModule: onOpenModule,
                );
                if (inner.maxWidth < 900) {
                  return Column(
                    children: [events, const SizedBox(height: 16), actions],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 6, child: events),
                    const SizedBox(width: 16),
                    Expanded(flex: 4, child: actions),
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.incidents,
    required this.highPriority,
    required this.submissions,
    required this.review,
    required this.approvedAgents,
    required this.readyAgents,
    required this.verifiedPollingUnits,
    required this.expectedPollingUnits,
    required this.modules,
    required this.onOpenModule,
  });

  final int incidents;
  final int highPriority;
  final int submissions;
  final int review;
  final int approvedAgents;
  final int readyAgents;
  final int verifiedPollingUnits;
  final int expectedPollingUnits;
  final Set<TgcgModule> modules;
  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1180
              ? 6
              : constraints.maxWidth >= 780
                  ? 3
                  : constraints.maxWidth >= 500
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
                label: 'Open incidents',
                value: '$incidents',
                detail: '$highPriority high / critical',
                icon: Icons.warning_amber_rounded,
                tone: incidents == 0 ? TgcgMetricTone.success : TgcgMetricTone.warning,
                onTap: modules.contains(TgcgModule.situationRoom)
                    ? () => onOpenModule(TgcgModule.situationRoom)
                    : null,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Results received',
                value: '$submissions',
                detail: '$review awaiting human review',
                icon: Icons.ballot_outlined,
                tone: TgcgMetricTone.info,
                onTap: modules.contains(TgcgModule.resultCapture)
                    ? () => onOpenModule(TgcgModule.resultCapture)
                    : null,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Verified polling units',
                value: '$verifiedPollingUnits',
                detail: '$expectedPollingUnits expected in prototype registry',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.success,
                onTap: modules.contains(TgcgModule.collation)
                    ? () => onOpenModule(TgcgModule.collation)
                    : null,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Approved agents',
                value: '$approvedAgents',
                detail: '$readyAgents operationally ready',
                icon: Icons.badge_outlined,
                tone: TgcgMetricTone.neutral,
                onTap: modules.contains(TgcgModule.accreditation)
                    ? () => onOpenModule(TgcgModule.accreditation)
                    : null,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Human review',
                value: '$review',
                detail: 'OCR, duplicate or arithmetic flags',
                icon: Icons.psychology_alt_outlined,
                tone: TgcgMetricTone.ai,
                onTap: modules.contains(TgcgModule.resultCapture)
                    ? () => onOpenModule(TgcgModule.resultCapture)
                    : null,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Agent readiness',
                value: approvedAgents == 0
                    ? '0%'
                    : '${((readyAgents / approvedAgents) * 100).round()}%',
                detail: 'Training + identity + bound device',
                icon: Icons.verified_user_outlined,
                tone: TgcgMetricTone.success,
                onTap: modules.contains(TgcgModule.accreditation)
                    ? () => onOpenModule(TgcgModule.accreditation)
                    : null,
              ),
            ],
          );
        },
      );
}

class _OperationsMapPanel extends StatelessWidget {
  const _OperationsMapPanel({
    required this.scope,
    required this.engine,
    required this.submissions,
    required this.childScopes,
    required this.incidentCount,
    required this.onOpenGeography,
  });

  final GeographicScope scope;
  final CollationEngine engine;
  final List<ElectionResultSubmission> submissions;
  final List<GeographicScope> childScopes;
  final int incidentCount;
  final VoidCallback? onOpenGeography;

  @override
  Widget build(BuildContext context) {
    final visibleChildren = childScopes.take(6).toList(growable: false);
    return TgcgSectionCard(
      title: 'Operational geography',
      subtitle:
          'GIS command preview for polling-unit coverage, incidents and result progress. Production geometry will come from PostGIS/Mapbox.',
      trailing: onOpenGeography == null
          ? null
          : TextButton.icon(
              onPressed: onOpenGeography,
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open GIS'),
            ),
      child: Column(
        children: [
          Container(
            height: 290,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              color: const Color(0xFF102E28),
            ),
            child: Stack(
              children: [
                const Positioned.fill(child: CustomPaint(painter: _GridPainter())),
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
                  child: Row(
                    children: [
                      _MapLegendDot(label: 'Result', color: TgcgColors.success),
                      const SizedBox(width: 10),
                      _MapLegendDot(label: 'Incident', color: TgcgColors.danger),
                    ],
                  ),
                ),
                ...List.generate(visibleChildren.length, (index) {
                  final child = visibleChildren[index];
                  final childSummary = engine.summarize(child, submissions);
                  final positions = const [
                    Offset(.18, .32),
                    Offset(.49, .25),
                    Offset(.75, .37),
                    Offset(.28, .65),
                    Offset(.57, .62),
                    Offset(.82, .70),
                  ];
                  final p = positions[index];
                  return Positioned(
                    left: p.dx * 610,
                    top: p.dy * 230,
                    child: _MapNode(
                      label: child.label,
                      progress: childSummary.completionPercent,
                    ),
                  );
                }),
                if (visibleChildren.isEmpty)
                  const Center(
                    child: TgcgStatusPill(
                      label: 'POLLING UNIT VIEW',
                      color: TgcgColors.info,
                      icon: Icons.pin_drop_outlined,
                    ),
                  ),
                Positioned(
                  left: 18,
                  right: 18,
                  bottom: 16,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${visibleChildren.length} geographic areas visible • $incidentCount unresolved incident${incidentCount == 1 ? '' : 's'}',
                          style: const TextStyle(
                            color: Color(0xFFB8CEC6),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(Icons.layers_outlined, color: Color(0xFFB8CEC6), size: 17),
                      const SizedBox(width: 6),
                      const Text(
                        'Coverage  •  Incidents  •  Results',
                        style: TextStyle(color: Color(0xFFB8CEC6), fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (visibleChildren.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: visibleChildren.map((child) {
                final summary = engine.summarize(child, submissions);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: TgcgColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: TgcgColors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 15, color: TgcgColors.primary),
                      const SizedBox(width: 5),
                      Text(
                        child.label,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${(summary.completionPercent * 100).round()}%',
                        style: const TextStyle(
                          color: TgcgColors.success,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _MapNode extends StatelessWidget {
  const _MapNode({required this.label, required this.progress});

  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: '$label • ${(progress * 100).round()}% verified coverage',
        child: Column(
          children: [
            Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                color: progress > 0 ? TgcgColors.success : TgcgColors.warning,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2.5),
                boxShadow: const [
                  BoxShadow(color: Colors.black38, blurRadius: 10),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Container(
              constraints: const BoxConstraints(maxWidth: 120),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xDD0B2520),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
}

class _MapLegendDot extends StatelessWidget {
  const _MapLegendDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Color(0xFFB8CEC6), fontSize: 9.5)),
        ],
      );
}

class _GridPainter extends CustomPainter {
  const _GridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0x142FC09B)
      ..strokeWidth = 1;
    for (double x = 0; x <= size.width; x += 44) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y <= size.height; y += 44) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final route = Paint()
      ..color = const Color(0x5535B893)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(size.width * .12, size.height * .56)
      ..quadraticBezierTo(
        size.width * .34,
        size.height * .14,
        size.width * .52,
        size.height * .47,
      )
      ..quadraticBezierTo(
        size.width * .72,
        size.height * .77,
        size.width * .9,
        size.height * .36,
      );
    canvas.drawPath(path, route);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ElectionProgressPanel extends StatelessWidget {
  const _ElectionProgressPanel({
    required this.summary,
    required this.readyAgents,
    required this.approvedAgents,
    required this.fieldReports,
    required this.onOpenCollation,
  });

  final CollationSummary summary;
  final int readyAgents;
  final int approvedAgents;
  final int fieldReports;
  final VoidCallback? onOpenCollation;

  @override
  Widget build(BuildContext context) {
    final percent = summary.completionPercent.clamp(0, 1).toDouble();
    return TgcgSectionCard(
      title: 'Election progress',
      subtitle: 'Verified-only operational progress in the current scope.',
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
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${(percent * 100).round()}%',
                style: const TextStyle(
                  fontSize: 38,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  color: TgcgColors.ink,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 8),
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text('verified PU coverage', style: TextStyle(color: TgcgColors.muted, fontSize: 10.5)),
              ),
            ],
          ),
          const SizedBox(height: 13),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: percent,
              minHeight: 10,
              backgroundColor: const Color(0xFFE5ECE9),
              valueColor: const AlwaysStoppedAnimation(TgcgColors.success),
            ),
          ),
          const SizedBox(height: 18),
          _ProgressStat('Verified polling units', '${summary.verifiedPollingUnitCount}'),
          _ProgressStat('Expected polling units', '${summary.expectedPollingUnitCount}'),
          _ProgressStat('Missing polling units', '${summary.missingPollingUnitIds.length}', warning: summary.missingPollingUnitIds.isNotEmpty),
          _ProgressStat('Reconciliation conflicts', '${summary.conflictingPollingUnitIds.length}', warning: summary.conflictingPollingUnitIds.isNotEmpty),
          const Divider(),
          _ProgressStat('Ready agents', '$readyAgents / $approvedAgents'),
          _ProgressStat('Field reports', '$fieldReports'),
          const SizedBox(height: 12),
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

class _ProgressStat extends StatelessWidget {
  const _ProgressStat(this.label, this.value, {this.warning = false});

  final String label;
  final String value;
  final bool warning;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 11))),
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

class _CriticalEventFeed extends StatelessWidget {
  const _CriticalEventFeed({
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
        final severity = _severityRank(b.severity).compareTo(_severityRank(a.severity));
        if (severity != 0) return severity;
        return b.reportedAt.compareTo(a.reportedAt);
      });

    return TgcgSectionCard(
      title: 'Critical events & review queue',
      subtitle: 'Highest-priority operational exceptions requiring attention.',
      child: Column(
        children: [
          if (sorted.isEmpty && reviewCount == 0)
            const TgcgEmptyState(
              icon: Icons.task_alt_rounded,
              title: 'No command exceptions',
              message: 'There are no unresolved incidents or result-review items in this scope.',
            )
          else ...[
            ...sorted.take(4).map((incident) {
              final color = _severityColor(incident.severity);
              return _EventRow(
                icon: Icons.crisis_alert_outlined,
                iconColor: color,
                title: incident.title,
                subtitle: '${incident.scope.label} • ${_label(incident.status.name)}',
                trailing: _label(incident.severity.name),
                onTap: modules.contains(TgcgModule.situationRoom)
                    ? () => onOpenModule(TgcgModule.situationRoom)
                    : null,
              );
            }),
            if (reviewCount > 0)
              _EventRow(
                icon: Icons.document_scanner_outlined,
                iconColor: TgcgColors.ai,
                title: '$reviewCount result submission${reviewCount == 1 ? '' : 's'} awaiting human review',
                subtitle: 'Inspect OCR/manual differences, duplicates and arithmetic warnings.',
                trailing: 'AI REVIEW',
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
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
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
                  color: iconColor.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: TgcgColors.ink)),
                    const SizedBox(height: 3),
                    Text(subtitle, style: const TextStyle(fontSize: 10, color: TgcgColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                trailing,
                style: TextStyle(color: iconColor, fontSize: 8.5, fontWeight: FontWeight.w900, letterSpacing: .4),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 5),
                const Icon(Icons.chevron_right_rounded, color: TgcgColors.muted, size: 18),
              ],
            ],
          ),
        ),
      );
}

class _QuickCommandPanel extends StatelessWidget {
  const _QuickCommandPanel({required this.modules, required this.onOpenModule});

  final Set<TgcgModule> modules;
  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final actions = <({TgcgModule module, String label, String detail, IconData icon, TgcgMetricTone tone})>[
      (
        module: TgcgModule.situationRoom,
        label: 'Situation Room',
        detail: 'Live incident command',
        icon: Icons.radar_rounded,
        tone: TgcgMetricTone.danger,
      ),
      (
        module: TgcgModule.resultCapture,
        label: 'Result Workspace',
        detail: 'Capture & human review',
        icon: Icons.ballot_outlined,
        tone: TgcgMetricTone.ai,
      ),
      (
        module: TgcgModule.geography,
        label: 'Geographic Operations',
        detail: 'Polling-unit coverage',
        icon: Icons.public_rounded,
        tone: TgcgMetricTone.info,
      ),
      (
        module: TgcgModule.communications,
        label: 'Communications',
        detail: 'Operational coordination',
        icon: Icons.forum_outlined,
        tone: TgcgMetricTone.success,
      ),
      (
        module: TgcgModule.reports,
        label: 'Reports & Exports',
        detail: 'Audited operational packages',
        icon: Icons.description_outlined,
        tone: TgcgMetricTone.neutral,
      ),
    ].where((item) => modules.contains(item.module)).toList(growable: false);

    return TgcgSectionCard(
      title: 'Quick command',
      subtitle: 'Role-aware shortcuts to your operational tools.',
      child: Column(
        children: actions.map((action) {
          final color = tgcgToneColor(action.tone);
          return InkWell(
            onTap: () => onOpenModule(action.module),
            borderRadius: BorderRadius.circular(13),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: TgcgColors.surfaceSoft,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: TgcgColors.border),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(action.icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(action.label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 2),
                        Text(action.detail, style: const TextStyle(fontSize: 9.5, color: TgcgColors.muted)),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios_rounded, size: 13, color: TgcgColors.muted),
                ],
              ),
            ),
          );
        }).toList(),
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
  return spaced.isEmpty ? spaced : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
