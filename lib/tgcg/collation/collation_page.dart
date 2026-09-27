import 'package:flutter/material.dart';

import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'collation_engine.dart';

class CollationPage extends StatefulWidget {
  const CollationPage({super.key});

  @override
  State<CollationPage> createState() => _CollationPageState();
}

class _CollationPageState extends State<CollationPage> {
  final engine = CollationEngine.prototypeSeed();
  final List<GeographicScope> path = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (path.isEmpty) {
      path.add(TgcgSession.of(context, listen: false).scope);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resultStore = ResultOperations.of(context);
    final scope = path.last;
    final summary = engine.summarize(scope, resultStore.submissions);
    final children = engine.childScopes(scope);
    final childSummaries = children
        .map((child) => engine.summarize(child, resultStore.submissions))
        .toList(growable: false);
    final included = summary.includedSubmissionIds
        .map(
          (id) => resultStore.submissions
              .where((item) => item.id == id)
              .firstOrNull,
        )
        .whereType<ElectionResultSubmission>()
        .toList(growable: false);
    final excluded = summary.excludedSubmissionIds
        .map(
          (id) => resultStore.submissions
              .where((item) => item.id == id)
              .firstOrNull,
        )
        .whereType<ElectionResultSubmission>()
        .toList(growable: false);
    final expectedUnits = engine.expectedPollingUnits
        .where((unit) => _scopeContains(scope, unit.scope))
        .toList(growable: false)
      ..sort((a, b) => a.scope.label.compareTo(b.scope.label));

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'VERIFIED-ONLY AGGREGATION',
          title: 'Collation Command',
          subtitle:
              '${scope.label}: hierarchical aggregation with completion, missing-unit, conflict and source-provenance controls.',
          trailing: const TgcgStatusPill(
            label: 'UNOFFICIAL FIELD DATA',
            color: TgcgColors.warning,
            icon: Icons.info_outline_rounded,
          ),
        ),
        const SizedBox(height: 16),
        _BreadcrumbBar(
          path: path,
          onSelect: (index) => setState(
            () => path.removeRange(index + 1, path.length),
          ),
        ),
        const SizedBox(height: 14),
        _CollationMetrics(summary: summary),
        const SizedBox(height: 16),
        _CompletionHero(summary: summary),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final hierarchy = _HierarchyPanel(
              summary: summary,
              childSummaries: childSummaries,
              onOpen: (child) => setState(() => path.add(child)),
            );
            final totals = _PartyTotalsPanel(summary: summary);
            if (constraints.maxWidth < 1040) {
              return Column(
                children: [
                  hierarchy,
                  const SizedBox(height: 14),
                  totals,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: hierarchy),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: totals),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _PollingUnitReconciliation(
          units: expectedUnits,
          summary: summary,
          submissions: resultStore.submissions,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final integrity = _IntegrityPanel(summary: summary, engine: engine);
            final excludedPanel = _ExcludedPanel(submissions: excluded);
            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  integrity,
                  const SizedBox(height: 14),
                  excludedPanel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: integrity),
                const SizedBox(width: 14),
                Expanded(child: excludedPanel),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ProvenancePanel(submissions: included),
      ],
    );
  }
}

class _CollationMetrics extends StatelessWidget {
  const _CollationMetrics({required this.summary});

  final CollationSummary summary;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1060
              ? 5
              : constraints.maxWidth >= 680
                  ? 3
                  : constraints.maxWidth >= 430
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
                label: 'Expected PUs',
                value: '${summary.expectedPollingUnitCount}',
                detail: 'Canonical polling units in scope',
                icon: Icons.location_on_outlined,
                tone: TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Verified included',
                value: '${summary.verifiedPollingUnitCount}',
                detail: 'Exactly one verified record per PU',
                icon: Icons.verified_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Missing PUs',
                value: '${summary.missingPollingUnitIds.length}',
                detail: 'No includable verified record yet',
                icon: Icons.location_searching_rounded,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Conflicts',
                value: '${summary.conflictingPollingUnitIds.length}',
                detail: 'Multiple verified records for one PU',
                icon: Icons.sync_problem_rounded,
                tone: TgcgMetricTone.danger,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Excluded records',
                value: '${summary.excludedSubmissionIds.length}',
                detail: 'Retained but outside this snapshot',
                icon: Icons.filter_alt_off_outlined,
                tone: TgcgMetricTone.ai,
              ),
            ],
          );
        },
      );
}

class _CompletionHero extends StatelessWidget {
  const _CompletionHero({required this.summary});

  final CollationSummary summary;

  @override
  Widget build(BuildContext context) {
    final progress = summary.completionPercent.clamp(0.0, 1.0).toDouble();
    final percent = progress * 100;
    final healthy = summary.conflictingPollingUnitIds.isEmpty;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: TgcgColors.primaryDark,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final overview = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'VERIFIED COVERAGE',
                style: TextStyle(
                  color: Color(0xFF9EC8BB),
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                '${percent.toStringAsFixed(1)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 42,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1.2,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '${summary.verifiedPollingUnitCount} of ${summary.expectedPollingUnitCount} canonical polling units are included in this verified-only snapshot.',
                style: const TextStyle(
                  color: Color(0xFFD2E1DC),
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 10,
                  color: TgcgColors.accent,
                  backgroundColor: Colors.white.withValues(alpha: .12),
                ),
              ),
            ],
          );

          final rules = Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      healthy
                          ? Icons.shield_outlined
                          : Icons.warning_amber_rounded,
                      color: healthy
                          ? const Color(0xFF8FE0C2)
                          : const Color(0xFFFFC56D),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        healthy
                            ? 'No verified-record conflict in this scope'
                            : '${summary.conflictingPollingUnitIds.length} verified conflict${summary.conflictingPollingUnitIds.length == 1 ? '' : 's'} require reconciliation',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const _DarkRule(
                  icon: Icons.verified_user_outlined,
                  text: 'Only verified records can enter aggregation.',
                ),
                const _DarkRule(
                  icon: Icons.filter_1_rounded,
                  text: 'Exactly one verified record is allowed per canonical PU.',
                ),
                const _DarkRule(
                  icon: Icons.visibility_outlined,
                  text: 'Missing, excluded and conflicting records remain visible.',
                ),
                const _DarkRule(
                  icon: Icons.gavel_outlined,
                  text: 'This workspace does not make an official declaration.',
                ),
              ],
            ),
          );

          if (constraints.maxWidth < 820) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [overview, const SizedBox(height: 18), rules],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 6, child: overview),
              const SizedBox(width: 28),
              Expanded(flex: 5, child: rules),
            ],
          );
        },
      ),
    );
  }
}

class _DarkRule extends StatelessWidget {
  const _DarkRule({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: const Color(0xFF9EC8BB)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Color(0xFFD2E1DC),
                  fontSize: 10.5,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      );
}

class _HierarchyPanel extends StatelessWidget {
  const _HierarchyPanel({
    required this.summary,
    required this.childSummaries,
    required this.onOpen,
  });

  final CollationSummary summary;
  final List<CollationSummary> childSummaries;
  final ValueChanged<GeographicScope> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Hierarchical coverage',
        subtitle:
            'Drill down geographically. Areas are not ordered by vote totals or political performance.',
        trailing: TgcgStatusPill(
          label: _levelLabel(summary.scope.level).toUpperCase(),
          color: TgcgColors.info,
          compact: true,
        ),
        child: childSummaries.isEmpty
            ? _LeafScopeSummary(summary: summary)
            : LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 780
                      ? 3
                      : constraints.maxWidth >= 500
                          ? 2
                          : 1;
                  const gap = 10.0;
                  final width =
                      (constraints.maxWidth - gap * (columns - 1)) / columns;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: childSummaries
                        .map(
                          (child) => _ChildScopeCard(
                            width: width,
                            summary: child,
                            onOpen: () => onOpen(child.scope),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
      );
}

class _LeafScopeSummary extends StatelessWidget {
  const _LeafScopeSummary({required this.summary});

  final CollationSummary summary;

  @override
  Widget build(BuildContext context) {
    final complete = summary.complete;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: complete
            ? TgcgColors.success.withValues(alpha: .05)
            : TgcgColors.warning.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: complete
              ? TgcgColors.success.withValues(alpha: .18)
              : TgcgColors.warning.withValues(alpha: .18),
        ),
      ),
      child: Row(
        children: [
          Icon(
            complete ? Icons.verified_outlined : Icons.pending_actions_outlined,
            color: complete ? TgcgColors.success : TgcgColors.warning,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              complete
                  ? 'This polling-unit scope has one includable verified result.'
                  : 'This polling-unit scope is not yet complete for verified-only collation.',
              style: const TextStyle(
                color: TgcgColors.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChildScopeCard extends StatelessWidget {
  const _ChildScopeCard({
    required this.width,
    required this.summary,
    required this.onOpen,
  });

  final double width;
  final CollationSummary summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = summary.completionPercent.clamp(0.0, 1.0).toDouble();
    final hasConflict = summary.conflictingPollingUnitIds.isNotEmpty;
    final color = hasConflict
        ? TgcgColors.danger
        : summary.complete
            ? TgcgColors.success
            : summary.verifiedPollingUnitCount > 0
                ? TgcgColors.info
                : TgcgColors.warning;

    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: TgcgColors.surfaceSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: .18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(_levelIcon(summary.scope.level), color: color, size: 17),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      summary.scope.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: TgcgColors.muted,
                    size: 18,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '${(progress * 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: color,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${summary.verifiedPollingUnitCount}/${summary.expectedPollingUnitCount} PUs',
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  color: color,
                  backgroundColor: TgcgColors.border,
                ),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  if (summary.missingPollingUnitIds.isNotEmpty)
                    TgcgStatusPill(
                      label: '${summary.missingPollingUnitIds.length} MISSING',
                      color: TgcgColors.warning,
                      compact: true,
                    ),
                  if (summary.conflictingPollingUnitIds.isNotEmpty)
                    TgcgStatusPill(
                      label:
                          '${summary.conflictingPollingUnitIds.length} CONFLICT',
                      color: TgcgColors.danger,
                      compact: true,
                    ),
                  if (summary.complete)
                    const TgcgStatusPill(
                      label: 'COMPLETE',
                      color: TgcgColors.success,
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
}

class _PartyTotalsPanel extends StatelessWidget {
  const _PartyTotalsPanel({required this.summary});

  final CollationSummary summary;

  @override
  Widget build(BuildContext context) {
    final partyCodes = summary.partyVotes.keys.toList()..sort();
    final totalVotes = summary.partyVotes.values.fold<int>(0, (a, b) => a + b);

    return TgcgSectionCard(
      title: 'Verified vote totals',
      subtitle:
          'Party codes are shown alphabetically. This panel does not rank parties or declare an outcome.',
      trailing: const TgcgStatusPill(
        label: 'ALPHABETICAL',
        color: TgcgColors.muted,
        compact: true,
      ),
      child: partyCodes.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.ballot_outlined,
              title: 'No included verified totals',
              message:
                  'Verified polling-unit results will appear here once they satisfy collation integrity rules.',
            )
          : Column(
              children: [
                for (final code in partyCodes)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: TgcgColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: TgcgColors.primarySoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            code,
                            style: const TextStyle(
                              color: TgcgColors.primary,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Verified field total',
                            style: TextStyle(
                              color: TgcgColors.muted,
                              fontSize: 10.5,
                            ),
                          ),
                        ),
                        Text(
                          '${summary.partyVotes[code]}',
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                const Divider(height: 24),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Votes represented in this snapshot',
                        style: TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '$totalVotes',
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _PollingUnitReconciliation extends StatelessWidget {
  const _PollingUnitReconciliation({
    required this.units,
    required this.summary,
    required this.submissions,
  });

  final List<ExpectedPollingUnit> units;
  final CollationSummary summary;
  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Polling-unit reconciliation',
        subtitle:
            'Every expected polling unit remains visible, including units awaiting verification or conflict resolution.',
        trailing: TgcgStatusPill(
          label: '${units.length} EXPECTED',
          color: TgcgColors.info,
          compact: true,
        ),
        child: units.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.location_off_outlined,
                title: 'No canonical polling units in this scope',
                message: 'The prototype registry has no polling units under this selection.',
              )
            : Column(
                children: units.map((unit) {
                  final unitSubmissions = submissions
                      .where(
                        (item) =>
                            item.pollingUnitScope.pollingUnitId == unit.id,
                      )
                      .toList(growable: false);
                  final included = unitSubmissions.any(
                    (item) => summary.includedSubmissionIds.contains(item.id),
                  );
                  final conflict =
                      summary.conflictingPollingUnitIds.contains(unit.id);
                  final waiting = !included && !conflict && unitSubmissions.isNotEmpty;
                  final state = conflict
                      ? _PuState.conflict
                      : included
                          ? _PuState.verified
                          : waiting
                              ? _PuState.awaitingReview
                              : _PuState.missing;

                  return _PollingUnitRow(
                    unit: unit,
                    state: state,
                    submissions: unitSubmissions,
                  );
                }).toList(),
              ),
      );
}

enum _PuState { verified, awaitingReview, missing, conflict }

class _PollingUnitRow extends StatelessWidget {
  const _PollingUnitRow({
    required this.unit,
    required this.state,
    required this.submissions,
  });

  final ExpectedPollingUnit unit;
  final _PuState state;
  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      _PuState.verified => TgcgColors.success,
      _PuState.awaitingReview => TgcgColors.ai,
      _PuState.missing => TgcgColors.warning,
      _PuState.conflict => TgcgColors.danger,
    };
    final label = switch (state) {
      _PuState.verified => 'VERIFIED INCLUDED',
      _PuState.awaitingReview => 'AWAITING VERIFICATION',
      _PuState.missing => 'MISSING',
      _PuState.conflict => 'VERIFIED CONFLICT',
    };
    final icon = switch (state) {
      _PuState.verified => Icons.verified_outlined,
      _PuState.awaitingReview => Icons.fact_check_outlined,
      _PuState.missing => Icons.location_searching_rounded,
      _PuState.conflict => Icons.sync_problem_rounded,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final location = Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${unit.id} • ${unit.name}',
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      unit.scope.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final meta = Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TgcgStatusPill(label: label, color: color, compact: true),
              TgcgStatusPill(
                label:
                    '${submissions.length} SUBMISSION${submissions.length == 1 ? '' : 'S'}',
                color: TgcgColors.muted,
                compact: true,
              ),
            ],
          );

          if (constraints.maxWidth < 700) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [location, const SizedBox(height: 9), meta],
            );
          }
          return Row(
            children: [
              Expanded(child: location),
              const SizedBox(width: 12),
              meta,
            ],
          );
        },
      ),
    );
  }
}

class _IntegrityPanel extends StatelessWidget {
  const _IntegrityPanel({required this.summary, required this.engine});

  final CollationSummary summary;
  final CollationEngine engine;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Coverage & reconciliation exceptions',
        subtitle:
            'Missing and conflicting polling units remain outside aggregation until their integrity state changes.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ExceptionGroup(
              icon: Icons.location_searching_rounded,
              title: 'Missing polling units',
              emptyText: 'No missing polling units in this scope.',
              color: TgcgColors.warning,
              values: summary.missingPollingUnitIds
                  .map(
                    (id) => engine.expectedPollingUnit(id)?.scope.label ?? id,
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            _ExceptionGroup(
              icon: Icons.sync_problem_rounded,
              title: 'Verified conflicts',
              emptyText: 'No verified-record conflict in this scope.',
              color: TgcgColors.danger,
              values: summary.conflictingPollingUnitIds,
            ),
          ],
        ),
      );
}

class _ExceptionGroup extends StatelessWidget {
  const _ExceptionGroup({
    required this.icon,
    required this.title,
    required this.emptyText,
    required this.color,
    required this.values,
  });

  final IconData icon;
  final String title;
  final String emptyText;
  final Color color;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 7),
              Text(
                title,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          if (values.isEmpty)
            Text(
              emptyText,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 11,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: values
                  .map(
                    (value) => TgcgStatusPill(
                      label: value,
                      color: color,
                      compact: true,
                    ),
                  )
                  .toList(),
            ),
        ],
      );
}

class _ExcludedPanel extends StatelessWidget {
  const _ExcludedPanel({required this.submissions});

  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Excluded records',
        subtitle:
            'Records are retained for review and audit even when they do not enter the verified-only snapshot.',
        trailing: TgcgStatusPill(
          label: '${submissions.length} EXCLUDED',
          color: submissions.isEmpty ? TgcgColors.success : TgcgColors.ai,
          compact: true,
        ),
        child: submissions.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'No excluded records',
                message: 'Every in-scope submission currently qualifies for inclusion.',
              )
            : Column(
                children: submissions.map((submission) {
                  final color = _recordStatusColor(submission.status);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: TgcgColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.filter_alt_off_outlined, color: color, size: 18),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                submission.id,
                                style: const TextStyle(
                                  color: TgcgColors.ink,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                submission.pollingUnitScope.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        TgcgStatusPill(
                          label: _label(submission.status.name).toUpperCase(),
                          color: color,
                          compact: true,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      );
}

class _ProvenancePanel extends StatelessWidget {
  const _ProvenancePanel({required this.submissions});

  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Included submission provenance',
        subtitle:
            'Every aggregated value remains traceable to its verified polling-unit record, source, reviewer and evidence reference.',
        trailing: TgcgStatusPill(
          label: '${submissions.length} INCLUDED',
          color: TgcgColors.success,
          icon: Icons.verified_user_outlined,
          compact: true,
        ),
        child: submissions.isEmpty
            ? const TgcgEmptyState(
                icon: Icons.manage_search_outlined,
                title: 'No included provenance yet',
                message:
                    'Verified source records will appear here when they enter the collation snapshot.',
              )
            : Column(
                children: submissions
                    .map((submission) => _ProvenanceRow(submission: submission))
                    .toList(),
              ),
      );
}

class _ProvenanceRow extends StatelessWidget {
  const _ProvenanceRow({required this.submission});

  final ElectionResultSubmission submission;

  @override
  Widget build(BuildContext context) {
    final evidence = submission.resultForm;
    final validation = submission.validation;
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 4),
      childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: TgcgColors.success.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(
          Icons.verified_user_outlined,
          color: TgcgColors.success,
          size: 19,
        ),
      ),
      title: Text(
        '${submission.id} • ${submission.pollingUnitScope.pollingUnitId ?? submission.pollingUnitScope.label}',
        style: const TextStyle(
          color: TgcgColors.ink,
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
      subtitle: Text(
        '${submission.source.name.toUpperCase()} • submitted by ${submission.submittedBy}',
        style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
      ),
      trailing: const TgcgStatusPill(
        label: 'INCLUDED',
        color: TgcgColors.success,
        compact: true,
      ),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: TgcgColors.surfaceSoft,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: TgcgColors.border),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 10,
            children: [
              _ProvenanceValue(
                label: 'Verifier',
                value: submission.verifiedBy ?? 'Not recorded',
              ),
              _ProvenanceValue(
                label: 'Evidence',
                value: evidence?.fileName ?? 'No result-form attachment',
              ),
              _ProvenanceValue(
                label: 'SHA-256',
                value: evidence?.contentHash ?? 'Not available',
              ),
              _ProvenanceValue(
                label: 'OCR confidence',
                value: validation?.ocrConfidence == null
                    ? 'Not available'
                    : '${(validation!.ocrConfidence! * 100).toStringAsFixed(1)}%',
              ),
              _ProvenanceValue(
                label: 'Integrity',
                value: validation == null
                    ? 'No validation summary'
                    : validation.requiresHumanReview
                        ? 'Reviewer accepted after flags'
                        : 'Automated checks passed',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProvenanceValue extends StatelessWidget {
  const _ProvenanceValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 190,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 8.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: TgcgColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var index = 0; index < path.length; index++) ...[
              TextButton.icon(
                onPressed: index == path.length - 1
                    ? null
                    : () => onSelect(index),
                icon: Icon(_levelIcon(path[index].level), size: 15),
                label: Text(
                  path[index].label,
                  style: const TextStyle(fontSize: 10.5),
                ),
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

Color _recordStatusColor(RecordStatus status) => switch (status) {
      RecordStatus.verified => TgcgColors.success,
      RecordStatus.disputed || RecordStatus.rejected => TgcgColors.danger,
      RecordStatus.underReview => TgcgColors.ai,
      RecordStatus.submitted => TgcgColors.info,
      _ => TgcgColors.muted,
    };

IconData _levelIcon(GeographyLevel level) => switch (level) {
      GeographyLevel.country => Icons.public_rounded,
      GeographyLevel.geopoliticalZone => Icons.language_rounded,
      GeographyLevel.state => Icons.map_outlined,
      GeographyLevel.senatorialDistrict => Icons.account_balance_outlined,
      GeographyLevel.lga => Icons.location_city_outlined,
      GeographyLevel.ward => Icons.grid_view_rounded,
      GeographyLevel.pollingUnit => Icons.location_on_outlined,
    };

String _levelLabel(GeographyLevel level) => switch (level) {
      GeographyLevel.country => 'Country',
      GeographyLevel.geopoliticalZone => 'Zone',
      GeographyLevel.state => 'State',
      GeographyLevel.senatorialDistrict => 'Senatorial District',
      GeographyLevel.lga => 'LGA',
      GeographyLevel.ward => 'Ward',
      GeographyLevel.pollingUnit => 'Polling Unit',
    };

bool _scopeContains(GeographicScope parent, GeographicScope child) {
  if (parent.country != child.country) return false;
  if (parent.level == GeographyLevel.country) return true;
  if (parent.zoneId != null && parent.zoneId != child.zoneId) return false;
  if (parent.level == GeographyLevel.geopoliticalZone) return true;
  if (parent.stateId != null && parent.stateId != child.stateId) return false;
  if (parent.level == GeographyLevel.state) return true;
  if (parent.senatorialDistrictId != null &&
      parent.senatorialDistrictId != child.senatorialDistrictId) {
    return false;
  }
  if (parent.level == GeographyLevel.senatorialDistrict) return true;
  if (parent.lgaId != null && parent.lgaId != child.lgaId) return false;
  if (parent.level == GeographyLevel.lga) return true;
  if (parent.wardId != null && parent.wardId != child.wardId) return false;
  if (parent.level == GeographyLevel.ward) return true;
  return parent.pollingUnitId == child.pollingUnitId;
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
