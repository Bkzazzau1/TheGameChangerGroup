import 'dart:async';

import 'package:flutter/material.dart';

import 'access/access_widgets.dart';
import 'api/access_repository.dart';
import 'api/api_client.dart';
import 'api/backend.dart';
import 'api/overview_repository.dart';
import 'api/tracking_repository.dart';
import 'domain/permissions.dart';
import 'api/member_admin_repository.dart' show AreaRef, MemberAnalysis;
import 'election/election_countdown.dart';
import 'field/field_operations_store.dart';
import 'field/incident_actions.dart' show incidentStatusLabel;
import 'field/incident_report.dart'
    show incidentSeverityColor, incidentSeverityLabel, incidentSeverityRank, isOpenIncident;
import 'membership/members_exco_page.dart' show levelLabel, levelsLabel;
import 'results/result_operations_store.dart';
import 'session.dart';
import 'shell.dart' show openMyAccess;
import 'sync/server_records.dart';
import 'ui/app_on_screen.dart';
import 'ui/server_feed.dart';
import 'ui/tgcg_design.dart';
import 'ui/tgcg_figures.dart';

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
      _timer = Timer.periodic(const Duration(minutes: 3), (_) {
        if (appOnScreen) _load();
      });
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
    final area = AreaRef.of(TgcgSession.of(context, listen: false).scope);
    setState(() => _loading = true);
    try {
      final numbers = await overview.load(area: area);
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

    final showIncidents = session.can(TgcgCapability.viewIncidents);
    final openIncidents =
        field.incidentsForScope(scope).where(isOpenIncident).toList(growable: false);
    final highPriority = openIncidents
        .where(
          (item) =>
              item.severity == IncidentSeverity.high || item.severity == IncidentSeverity.critical,
        )
        .length;
    final awaiting = results.awaitingOnServer;
    final shortcuts = _quickCommands(modules);
    // An empty list is only good news once the server has said so. Results
    // count when the account may see them at all.
    final seesResults = numbers?.results != null;
    final notChecked = (showIncidents && field.loadError != null) ||
        (seesResults && results.loadError != null);
    final stillChecking =
        (showIncidents && !field.recordsKnown) || (seesResults && !results.recordsKnown);

    return TgcgPageList(
      maxWidth: tgcgCommandWidth,
      bottomPadding: 36,
      children: [
        _CommandBand(
          national: scope.level == GeographyLevel.country,
          who: '${session.roleTitle} • ${areaLabel(scope)}',
          loadedAt: _loadedAt,
          loading: _loading,
          onReload: () {
            unawaited(_load());
            unawaited(field.refresh());
            unawaited(results.refresh());
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: ServerNote(
              icon: Icons.cloud_off_rounded,
              text: 'The numbers could not be loaded from the server: $_error',
            ),
          ),
        const SizedBox(height: TgcgSpacing.md),
        _MetricGrid(
          numbers: numbers,
          loading: _loading && numbers == null,
          openIncidents: field.isLive ? field.openOnServer : openIncidents.length,
          highPriority: highPriority,
          awaiting: awaiting,
          awaitingKnown: results.recordsKnown,
          showIncidents: showIncidents && field.recordsKnown,
          modules: modules,
          onOpenModule: onOpenModule,
        ),
        const SizedBox(height: TgcgSpacing.lg),
        _Attention(
          events: showIncidents || awaiting > 0
              ? _PriorityEvents(
                  incidents: openIncidents,
                  reviewCount: awaiting,
                  notChecked: notChecked,
                  stillChecking: stillChecking,
                  modules: modules,
                  onOpenModule: onOpenModule,
                )
              : null,
          shortcuts: shortcuts.isEmpty
              ? null
              : _QuickCommand(actions: shortcuts, onOpenModule: onOpenModule),
        ),
        if (numbers?.coverage case final coverage?) ...[
          const SizedBox(height: TgcgSpacing.lg),
          _CheckInCoverage(
            coverage: coverage,
            onOpen: modules.contains(TgcgModule.agentTracking)
                ? () => onOpenModule(TgcgModule.agentTracking)
                : null,
          ),
        ],
        if (numbers?.analysis case final analysis?) ...[
          const SizedBox(height: TgcgSpacing.lg),
          _MembersAndExco(
            analysis: analysis,
            onOpen: modules.contains(TgcgModule.membershipNetwork)
                ? () => onOpenModule(TgcgModule.membershipNetwork)
                : null,
          ),
        ],
        if (session.grants.isNotEmpty) ...[
          const SizedBox(height: TgcgSpacing.lg),
          _AccessSummary(grants: session.grants),
        ],
      ],
    );
  }
}

/// What this page is, whose it is, and how long to the election.
class _CommandBand extends StatelessWidget {
  const _CommandBand({
    required this.national,
    required this.who,
    required this.loadedAt,
    required this.loading,
    required this.onReload,
  });

  final bool national;
  final String who;
  final DateTime? loadedAt;
  final bool loading;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final loaded = loadedAt;
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          national ? 'NATIONAL COMMAND CENTRE' : 'YOUR AREAS',
          style: TgcgType.eyebrow.copyWith(color: TgcgColors.accentBright),
        ),
        const SizedBox(height: 7),
        Text('Operations Command', style: TgcgType.display.copyWith(color: Colors.white)),
        const SizedBox(height: 6),
        Text(who, style: TgcgType.support.copyWith(color: TgcgColors.onNavyMuted)),
        if (loaded != null)
          Text(
            'Updated ${formatMoment(loaded)}',
            style: TgcgType.caption.copyWith(color: TgcgColors.onNavyMuted),
          ),
      ],
    );
    final reload = TgcgReloadButton(loading: loading, onPressed: onReload, color: Colors.white);
    const countdown = ElectionCountdown(size: ElectionCountdownSize.band);
    return TgcgNavyPanel(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 680) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Expanded(child: title), reload],
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: Colors.white.withValues(alpha: .16)),
                const SizedBox(height: 12),
                countdown,
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: TgcgSpacing.lg),
              const Flexible(flex: 0, child: countdown),
              const SizedBox(width: 8),
              reload,
            ],
          );
        },
      ),
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
    required this.awaitingKnown,
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
  final bool awaitingKnown;
  final bool showIncidents;
  final Set<TgcgModule> modules;
  final ValueChanged<TgcgModule> onOpenModule;

  VoidCallback? _open(TgcgModule module) =>
      modules.contains(module) ? () => onOpenModule(module) : null;

  @override
  Widget build(BuildContext context) {
    final n = numbers;
    final coverage = n?.coverage?.total;
    final cards = <Widget>[
      if (n?.members case final members?)
        TgcgMetricCard(
          label: 'Registered members',
          value: formatCount(members),
          detail: 'In your areas',
          icon: Icons.groups_2_outlined,
          tone: TgcgMetricTone.info,
          onTap: _open(TgcgModule.membershipNetwork),
        ),
      if (n?.analysis?.exco case final exco?)
        TgcgMetricCard(
          label: 'Exco',
          value: formatCount(exco.people),
          detail: '${formatCount(exco.appointments)} posts · '
              '${formatCount(exco.fullyVerified)} fully verified',
          icon: Icons.account_tree_outlined,
          tone: TgcgMetricTone.ai,
          onTap: _open(TgcgModule.membershipNetwork),
        ),
      if (coverage != null)
        TgcgMetricCard(
          label: 'Agents checked in today',
          value: '${formatCount(coverage.checkedIn)} of ${formatCount(coverage.agents)}',
          detail: '${formatCount(coverage.onDutyNow)} on duty now',
          icon: Icons.badge_outlined,
          tone: TgcgMetricTone.success,
          onTap: _open(TgcgModule.agentTracking),
        ),
      if (showIncidents)
        TgcgMetricCard(
          label: 'Open incidents',
          value: formatCount(openIncidents),
          detail: '${formatCount(highPriority)} high / critical',
          icon: Icons.warning_amber_rounded,
          tone: openIncidents == 0 ? TgcgMetricTone.success : TgcgMetricTone.warning,
          onTap: _open(TgcgModule.situationRoom),
        ),
      if (n?.results case final received?)
        TgcgMetricCard(
          label: 'Results received',
          value: formatCount(received),
          detail: awaitingKnown ? '${formatCount(awaiting)} awaiting a decision' : null,
          icon: Icons.ballot_outlined,
          tone: TgcgMetricTone.ai,
          onTap: _open(TgcgModule.resultCapture),
        ),
      if (n?.verifiedResults case final verified?)
        TgcgMetricCard(
          label: 'Verified results',
          value: formatCount(verified),
          detail: 'Counted in collation',
          icon: Icons.fact_check_outlined,
          tone: TgcgMetricTone.success,
          onTap: _open(TgcgModule.collation),
        ),
    ];
    if (cards.isEmpty) {
      return loading ? const LinearProgressIndicator(minHeight: 2) : const SizedBox.shrink();
    }
    return TgcgMetricGrid(cards: cards);
  }
}

/// What needs a decision, beside where to go: one above the other on a phone.
class _Attention extends StatelessWidget {
  const _Attention({required this.events, required this.shortcuts});

  final Widget? events;
  final Widget? shortcuts;

  @override
  Widget build(BuildContext context) {
    final first = events;
    final second = shortcuts;
    if (first == null || second == null) return first ?? second ?? const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [first, const SizedBox(height: TgcgSpacing.lg), second],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: first),
            const SizedBox(width: TgcgSpacing.md),
            Expanded(flex: 2, child: second),
          ],
        );
      },
    );
  }
}

class _PriorityEvents extends StatelessWidget {
  const _PriorityEvents({
    required this.incidents,
    required this.reviewCount,
    required this.notChecked,
    required this.stillChecking,
    required this.modules,
    required this.onOpenModule,
  });

  final List<FieldIncident> incidents;
  final int reviewCount;

  /// The server could not be asked, so an empty list proves nothing.
  final bool notChecked;

  /// The first answer has not come yet.
  final bool stillChecking;
  final Set<TgcgModule> modules;
  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final sorted = [...incidents]
      ..sort((a, b) {
        final severity =
            incidentSeverityRank(b.severity).compareTo(incidentSeverityRank(a.severity));
        if (severity != 0) return severity;
        return b.reportedAt.compareTo(a.reportedAt);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TgcgSectionHeading(title: 'Priority events'),
        if (sorted.isEmpty && reviewCount == 0)
          TgcgSectionCard(
            child: notChecked
                ? const TgcgEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not be checked',
                    message: 'Incidents and results could not be loaded from the server.',
                  )
                : stillChecking
                    ? const LinearProgressIndicator(minHeight: 2)
                    : const TgcgEmptyState(
                        icon: Icons.task_alt_rounded,
                        title: 'Nothing waiting',
                        message: 'No open incidents or results awaiting a decision in your areas.',
                      ),
          )
        else
          TgcgRowGroup(
            children: [
              for (final incident in sorted.take(5))
                TgcgActionRow(
                  icon: Icons.crisis_alert_outlined,
                  color: incidentSeverityColor(incident.severity),
                  title: incident.title,
                  detail: '${incidentSeverityLabel(incident.severity)} • '
                      '${incidentStatusLabel(incident.status)} • ${incident.scope.label}',
                  onTap: modules.contains(TgcgModule.situationRoom)
                      ? () => onOpenModule(TgcgModule.situationRoom)
                      : null,
                ),
              if (reviewCount > 0)
                TgcgActionRow(
                  icon: Icons.fact_check_outlined,
                  color: TgcgColors.ai,
                  title: '${formatCount(reviewCount)} result${reviewCount == 1 ? '' : 's'} '
                      'awaiting a decision',
                  detail: 'Verify, dispute or reject them',
                  onTap: modules.contains(TgcgModule.resultCapture)
                      ? () => onOpenModule(TgcgModule.resultCapture)
                      : null,
                ),
            ],
          ),
      ],
    );
  }
}

typedef _Shortcut = ({
  TgcgModule module,
  String label,
  String detail,
  IconData icon,
  TgcgMetricTone tone,
});

List<_Shortcut> _quickCommands(Set<TgcgModule> modules) => <_Shortcut>[
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

class _QuickCommand extends StatelessWidget {
  const _QuickCommand({required this.actions, required this.onOpenModule});

  final List<_Shortcut> actions;
  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TgcgSectionHeading(title: 'Quick command'),
          TgcgRowGroup(
            children: [
              for (final action in actions)
                TgcgActionRow(
                  icon: action.icon,
                  color: tgcgToneColor(action.tone),
                  title: action.label,
                  detail: action.detail,
                  onTap: () => onOpenModule(action.module),
                ),
            ],
          ),
        ],
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
      subtitle: '${formatCount(total.checkedIn)} of ${formatCount(total.agents)} agents in '
          '${areaLabel(coverage.scope)} checked in; ${formatCount(total.onSite)} at their '
          'polling unit.',
      trailing: onOpen == null
          ? null
          : TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.share_location_rounded, size: 17),
              label: const Text('Agents on the Ground'),
            ),
      child: coverage.children.isEmpty
          ? const Text('There is no smaller area below this one.', style: TgcgType.support)
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1100
                    ? 3
                    : constraints.maxWidth >= 640
                        ? 2
                        : 1;
                const gap = TgcgSpacing.lg;
                final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: 14,
                  children: [
                    for (final area in coverage.children)
                      SizedBox(
                        width: width,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              area.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TgcgType.label,
                            ),
                            const SizedBox(height: 5),
                            TgcgBar(value: area.tally.checkedInShare, color: TgcgColors.success),
                            const SizedBox(height: 5),
                            Text(
                              '${formatCount(area.tally.checkedIn)} of '
                              '${formatCount(area.tally.agents)} checked in · '
                              '${formatCount(area.tally.onSite)} on site',
                              style: TgcgType.caption,
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

/// Members and exco in the account's area: exco by level, and the smaller
/// areas with the most members.
class _MembersAndExco extends StatelessWidget {
  const _MembersAndExco({required this.analysis, required this.onOpen});

  final MemberAnalysis analysis;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final members = analysis.members;
    final exco = analysis.exco;
    final by = analysis.by;
    final top = [...analysis.parts]..sort((a, b) => b.members.compareTo(a.members));
    final levels = [
      for (final level in GeographyLevel.values)
        if ((exco.byLevel[level.name] ?? 0) > 0) (level, exco.byLevel[level.name]!),
    ];
    final panels = <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatCount(exco.people)} exco in ${formatCount(exco.appointments)} posts',
            style: TgcgType.bodyStrong,
          ),
          const SizedBox(height: 6),
          for (final (level, count) in levels)
            ShareBar(label: levelLabel(level), value: count, total: exco.appointments),
          ShareBar(label: 'Fully verified', value: exco.fullyVerified, total: exco.people),
          ShareBar(
            label: 'Signed in to the app',
            value: exco.profile['signedIn'] ?? 0,
            total: exco.people,
          ),
        ],
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${formatCount(members.total)} members · +${formatCount(members.new30Days)} '
            'in 30 days',
            style: TgcgType.bodyStrong,
          ),
          const SizedBox(height: 6),
          ShareBar(
            label: 'Identity verified',
            value: members.verification['verified'] ?? 0,
            total: members.total,
          ),
          ShareBar(label: 'Fully verified', value: members.fullyVerified, total: members.total),
          if (by != null && top.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Most members', style: TgcgType.label),
            const SizedBox(height: 4),
            for (final part in top.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Expanded(flex: 2, child: Text(part.area.name, style: TgcgType.caption)),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${formatCount(part.members)} · ${formatCount(part.exco)} exco · '
                        '${share(part.verified, part.members)} verified',
                        textAlign: TextAlign.end,
                        style: TgcgType.caption,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    ];
    final jobs = members.occupationRows(limit: 6);
    final columns = <Widget>[
      ...panels,
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Gender', style: TgcgType.bodyStrong),
          const SizedBox(height: 6),
          ShareBar(label: 'Men', value: members.gender['male'] ?? 0, total: members.total),
          ShareBar(label: 'Women', value: members.gender['female'] ?? 0, total: members.total),
          ShareBar(label: 'Not given', value: members.gender[''] ?? 0, total: members.total),
        ],
      ),
      if (jobs.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Profession', style: TgcgType.bodyStrong),
            const SizedBox(height: 6),
            for (final (label, count) in jobs)
              ShareBar(label: label, value: count, total: members.total),
          ],
        ),
    ];
    return TgcgSectionCard(
      title: 'Members and exco',
      subtitle: by == null
          ? null
          : '${analysis.withExco} of ${analysis.parts.length} '
              '${levelsLabel(by, inSentence: true)} have exco; ${analysis.withMembers} have '
              'members.',
      trailing: onOpen == null
          ? null
          : TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.groups_2_outlined, size: 17),
              label: const Text('Members & Exco'),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 680) {
            return Column(
              children: [
                for (final (index, column) in columns.indexed) ...[
                  if (index > 0) const SizedBox(height: TgcgSpacing.md),
                  column,
                ],
              ],
            );
          }
          // Two across; Gender and Profession stand under Exco and Members.
          return Column(
            children: [
              for (var row = 0; row < columns.length; row += 2) ...[
                if (row > 0) const SizedBox(height: TgcgSpacing.md),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: columns[row]),
                    const SizedBox(width: TgcgSpacing.lg),
                    Expanded(
                      child: row + 1 < columns.length ? columns[row + 1] : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
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
        trailingBeside: true,
        child: Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            spacing: TgcgSpacing.lg,
            runSpacing: 12,
            children: [
              for (final grant in grants)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TgcgIconBadge(
                        icon: grant.protected
                            ? Icons.admin_panel_settings_rounded
                            : grant.source == 'delegation'
                                ? Icons.call_split_rounded
                                : Icons.badge_outlined,
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(grant.roleName, style: TgcgType.label),
                            Text(grant.areas.map(areaLabel).join('; '), style: TgcgType.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
}
