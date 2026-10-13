import 'dart:async';

import 'package:flutter/material.dart';

import 'access/access_widgets.dart';
import 'api/access_repository.dart';
import 'api/api_client.dart';
import 'api/backend.dart';
import 'api/overview_repository.dart';
import 'api/tracking_repository.dart';
import 'domain/permissions.dart';
import 'field/field_operations_store.dart';
import 'results/result_operations_store.dart';
import 'session.dart';
import 'shell.dart' show openMyAccess;
import 'sync/server_records.dart';
import 'ui/server_feed.dart';
import 'ui/tgcg_design.dart';

/// The command view: every number on it comes from the server, and only
/// what the account may see there.
class TgcgDashboardPage extends StatefulWidget {
  const TgcgDashboardPage({super.key, required this.onOpenModule});

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  State<TgcgDashboardPage> createState() => _TgcgDashboardPageState();
}

class _TgcgDashboardPageState extends State<TgcgDashboardPage> with ServerAutoRefresh {
  @override
  List<ServerRecords<Object?>> refreshedRecords(BuildContext context) => [
        FieldOperations.of(context, listen: false),
        ResultOperations.of(context, listen: false),
      ];

  OverviewRepository? _overview;
  OverviewNumbers? _numbers;
  DateTime? _loadedAt;
  String? _error;
  bool _loading = false;
  bool _started = false;
  Timer? _timer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _overview = TgcgBackend.of(context)?.overview;
    if (!_started) {
      _started = true;
      unawaited(_load());
      _timer = Timer.periodic(const Duration(minutes: 1), (_) => _load());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final overview = _overview;
    if (overview == null || _loading || !mounted) return;
    setState(() => _loading = true);
    try {
      final numbers = await overview.load();
      if (!mounted) return;
      setState(() {
        _numbers = numbers;
        _loadedAt = DateTime.now();
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'The server sent numbers this app cannot read.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final modules = session.modules;
    final scope = session.scope;
    final numbers = _numbers;
    final onOpenModule = widget.onOpenModule;

    final openIncidents = field
        .incidentsForScope(scope)
        .where(
          (item) => item.status != IncidentStatus.resolved && item.status != IncidentStatus.closed,
        )
        .toList(growable: false);
    final highPriority = openIncidents
        .where(
          (item) =>
              item.severity == IncidentSeverity.high || item.severity == IncidentSeverity.critical,
        )
        .length;
    final awaiting = results.awaitingOnServer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        final padding = compact ? 16.0 : 24.0;
        final loadedAt = _loadedAt;

        return ListView(
          padding: EdgeInsets.fromLTRB(padding, 22, padding, 36),
          children: [
            TgcgPageHeader(
              eyebrow: scope.level == GeographyLevel.country
                  ? 'NATIONAL COMMAND CENTRE'
                  : 'YOUR AREAS',
              title: 'Operations Command',
              subtitle: '${session.roleTitle} • ${areaLabel(scope)}. Members, agents, incidents '
                  'and results, as the server holds them now.',
              trailing: Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (loadedAt != null)
                    Text(
                      'Updated ${formatMoment(loadedAt)}',
                      style: const TextStyle(color: TgcgColors.muted, fontSize: 11),
                    ),
                  IconButton(
                    tooltip: 'Load again',
                    onPressed: _loading
                        ? null
                        : () {
                            unawaited(_load());
                            unawaited(field.refresh());
                            unawaited(results.refresh());
                          },
                    icon: _loading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: ServerNote(
                  icon: Icons.cloud_off_rounded,
                  text: 'The numbers could not be loaded from the server: $_error',
                ),
              ),
            const SizedBox(height: 20),
            if (session.grants.isNotEmpty) ...[
              _AccessSummary(grants: session.grants),
              const SizedBox(height: 16),
            ],
            _MetricGrid(
              numbers: numbers,
              loading: _loading && numbers == null,
              openIncidents: field.isLive ? field.openOnServer : openIncidents.length,
              highPriority: highPriority,
              awaiting: awaiting,
              showIncidents: session.can(TgcgCapability.viewIncidents),
              modules: modules,
              onOpenModule: onOpenModule,
            ),
            if (numbers?.coverage case final coverage?) ...[
              const SizedBox(height: 16),
              _CheckInCoverage(
                coverage: coverage,
                onOpen: modules.contains(TgcgModule.agentTracking)
                    ? () => onOpenModule(TgcgModule.agentTracking)
                    : null,
              ),
            ],
            const SizedBox(height: 16),
            _PriorityEventsPanel(
              incidents: openIncidents,
              reviewCount: awaiting,
              modules: modules,
              onOpenModule: onOpenModule,
            ),
            const SizedBox(height: 16),
            _QuickCommandPanel(modules: modules, onOpenModule: onOpenModule),
          ],
        );
      },
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({
    required this.numbers,
    required this.loading,
    required this.openIncidents,
    required this.highPriority,
    required this.awaiting,
    required this.showIncidents,
    required this.modules,
    required this.onOpenModule,
  });

  final OverviewNumbers? numbers;

  /// The first load is running.
  final bool loading;
  final int openIncidents;
  final int highPriority;
  final int awaiting;
  final bool showIncidents;
  final Set<TgcgModule> modules;
  final ValueChanged<TgcgModule> onOpenModule;

  VoidCallback? _open(TgcgModule module) =>
      modules.contains(module) ? () => onOpenModule(module) : null;

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
          final n = numbers;
          final coverage = n?.coverage?.total;

          final cards = <Widget>[
            if (n?.members case final members?)
              TgcgMetricCard(
                width: width,
                label: 'Registered members',
                value: '$members',
                detail: 'In your areas',
                icon: Icons.groups_2_outlined,
                tone: TgcgMetricTone.info,
              ),
            if (coverage != null)
              TgcgMetricCard(
                width: width,
                label: 'Agents checked in today',
                value: '${coverage.checkedIn} of ${coverage.agents}',
                detail: '${coverage.onDutyNow} on duty now',
                icon: Icons.badge_outlined,
                tone: TgcgMetricTone.success,
                onTap: _open(TgcgModule.agentTracking),
              ),
            if (showIncidents)
              TgcgMetricCard(
                width: width,
                label: 'Open incidents',
                value: '$openIncidents',
                detail: '$highPriority high / critical',
                icon: Icons.warning_amber_rounded,
                tone: openIncidents == 0 ? TgcgMetricTone.success : TgcgMetricTone.warning,
                onTap: _open(TgcgModule.situationRoom),
              ),
            if (n?.results case final received?)
              TgcgMetricCard(
                width: width,
                label: 'Results received',
                value: '$received',
                detail: '$awaiting awaiting a decision',
                icon: Icons.ballot_outlined,
                tone: TgcgMetricTone.ai,
                onTap: _open(TgcgModule.resultCapture),
              ),
            if (n?.verifiedResults case final verified?)
              TgcgMetricCard(
                width: width,
                label: 'Verified results',
                value: '$verified',
                detail: 'Counted in collation',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.success,
                onTap: _open(TgcgModule.collation),
              ),
          ];
          if (cards.isEmpty) {
            return loading ? const LinearProgressIndicator(minHeight: 2) : const SizedBox.shrink();
          }
          return Wrap(spacing: gap, runSpacing: gap, children: cards);
        },
      );
}

/// Today's agent check-ins in the account's area, area by area below it.
class _CheckInCoverage extends StatelessWidget {
  const _CheckInCoverage({required this.coverage, required this.onOpen});

  final Coverage coverage;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final total = coverage.total;
    return TgcgSectionCard(
      title: 'Agent check-ins today',
      subtitle: '${total.checkedIn} of ${total.agents} agents in ${areaLabel(coverage.scope)} '
          'checked in; ${total.onSite} at their polling unit.',
      trailing: onOpen == null
          ? null
          : TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.share_location_rounded, size: 17),
              label: const Text('Agents on the Ground'),
            ),
      child: coverage.children.isEmpty
          ? const Text(
              'There is no smaller area below this one.',
              style: TextStyle(color: TgcgColors.muted),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1100
                    ? 3
                    : constraints.maxWidth >= 680
                        ? 2
                        : 1;
                const gap = 10.0;
                final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final area in coverage.children)
                      Container(
                        width: width,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: area.tally.checkedIn > 0
                              ? TgcgColors.primarySoft
                              : TgcgColors.surfaceSoft,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: TgcgColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              area.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${area.tally.checkedIn} of ${area.tally.agents} checked in · '
                              '${area.tally.onSite} on site',
                              style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
                            ),
                            const SizedBox(height: 8),
                            LinearProgressIndicator(
                              value: area.tally.checkedInShare,
                              minHeight: 5,
                              color: TgcgColors.success,
                              backgroundColor: TgcgColors.border,
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
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
                    '$reviewCount result${reviewCount == 1 ? '' : 's'} awaiting a decision',
                subtitle: 'Verify, dispute or reject them in the result workspace',
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
        module: TgcgModule.situationRoom,
        label: 'Situation Room',
        detail: 'Live incident command',
        icon: Icons.radar_rounded,
        tone: TgcgMetricTone.danger,
      ),
      (
        module: TgcgModule.resultCapture,
        label: 'Result Workspace',
        detail: 'Verify, dispute or reject results',
        icon: Icons.ballot_outlined,
        tone: TgcgMetricTone.ai,
      ),
      (
        module: TgcgModule.collation,
        label: 'Collation',
        detail: 'Unofficial totals of verified results',
        icon: Icons.summarize_outlined,
        tone: TgcgMetricTone.success,
      ),
      (
        module: TgcgModule.agentTracking,
        label: 'Agents on the Ground',
        detail: 'Check-ins and live positions',
        icon: Icons.share_location_rounded,
        tone: TgcgMetricTone.info,
      ),
      (
        module: TgcgModule.meetingRoom,
        label: 'Meetings',
        detail: 'Calls for your areas',
        icon: Icons.call_rounded,
        tone: TgcgMetricTone.neutral,
      ),
      (
        module: TgcgModule.memberReview,
        label: 'Member Review',
        detail: 'Identity checks and standing',
        icon: Icons.verified_user_outlined,
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


/// Every appointment the signed-in user holds, each with its own areas: the
/// modules above are what they allow together.
class _AccessSummary extends StatelessWidget {
  const _AccessSummary({required this.grants});

  final List<AccessGrant> grants;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Your access',
        subtitle: 'What you can open comes from these appointments together; each keeps to its '
            'own areas.',
        trailing: TextButton(
          onPressed: () => openMyAccess(context),
          child: const Text('Details'),
        ),
        child: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final grant in grants)
              Container(
                constraints: const BoxConstraints(maxWidth: 360),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: TgcgColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: TgcgColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      grant.protected
                          ? Icons.admin_panel_settings_rounded
                          : grant.source == 'delegation'
                              ? Icons.call_split_rounded
                              : Icons.badge_outlined,
                      color: TgcgColors.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            grant.roleName,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            grant.areas.map(areaLabel).join('; '),
                            style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}
