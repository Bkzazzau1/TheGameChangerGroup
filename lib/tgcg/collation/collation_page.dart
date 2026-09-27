import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/models.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
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
        .map((id) => resultStore.submissions.where((item) => item.id == id).firstOrNull)
        .whereType<ElectionResultSubmission>()
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Collation',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: TgcgApp.ink,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    '${scope.label}: verified-only aggregation with missing-unit, conflict and provenance tracking.',
                    style: const TextStyle(color: TgcgApp.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            const _UnofficialBadge(),
          ],
        ),
        const SizedBox(height: 16),
        _Breadcrumbs(
          path: path,
          onSelect: (index) => setState(() => path.removeRange(index + 1, path.length)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(
              label: 'Expected PUs',
              value: '${summary.expectedPollingUnitCount}',
              icon: Icons.location_on_outlined,
            ),
            _Metric(
              label: 'Verified included',
              value: '${summary.verifiedPollingUnitCount}',
              icon: Icons.verified_outlined,
            ),
            _Metric(
              label: 'Missing PUs',
              value: '${summary.missingPollingUnitIds.length}',
              icon: Icons.location_searching_rounded,
            ),
            _Metric(
              label: 'Reconciliation conflicts',
              value: '${summary.conflictingPollingUnitIds.length}',
              icon: Icons.sync_problem_rounded,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _CompletionPanel(summary: summary),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final totals = _PartyTotals(summary: summary);
            final integrity = _IntegrityPanel(summary: summary, engine: engine);
            if (constraints.maxWidth < 920) {
              return Column(children: [totals, const SizedBox(height: 14), integrity]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 5, child: totals),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: integrity),
              ],
            );
          },
        ),
        if (childSummaries.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Panel(
            title: 'Geographic drill-down',
            subtitle: 'Children are ordered geographically, not by vote totals.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: childSummaries
                  .map(
                    (child) => _ChildScopeCard(
                      summary: child,
                      onOpen: () => setState(() => path.add(child.scope)),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _ProvenancePanel(submissions: included),
        if (summary.excludedSubmissionIds.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Panel(
            title: 'Excluded records',
            subtitle: 'These submissions are retained but are not part of this verified collation snapshot.',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: summary.excludedSubmissionIds
                  .map((id) => _Pill(id, const Color(0xFF7A5A10)))
                  .toList(),
            ),
          ),
        ],
      ],
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.path, required this.onSelect});

  final List<GeographicScope> path;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var index = 0; index < path.length; index++) ...[
            TextButton(
              onPressed: index == path.length - 1 ? null : () => onSelect(index),
              child: Text(path[index].label),
            ),
            if (index != path.length - 1)
              const Icon(Icons.chevron_right_rounded, size: 18, color: TgcgApp.muted),
          ],
        ],
      );
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 215,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: TgcgApp.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: TgcgApp.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: TgcgApp.ink,
                        ),
                      ),
                      Text(label,
                          style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _CompletionPanel extends StatelessWidget {
  const _CompletionPanel({required this.summary});

  final CollationSummary summary;

  @override
  Widget build(BuildContext context) {
    final progress = summary.completionPercent.clamp(0.0, 1.0).toDouble();
    final percent = progress * 100;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Verified polling-unit coverage',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: TgcgApp.ink,
                    ),
                  ),
                ),
                Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: TgcgApp.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              borderRadius: BorderRadius.circular(999),
              backgroundColor: const Color(0xFFE5ECE9),
            ),
            const SizedBox(height: 10),
            const Text(
              'Only one canonical verified submission per expected polling unit is counted. Submitted, under-review, disputed and conflicting verified records remain outside the total.',
              style: TextStyle(color: TgcgApp.muted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartyTotals extends StatelessWidget {
  const _PartyTotals({required this.summary});

  final CollationSummary summary;

  @override
  Widget build(BuildContext context) {
    final keys = summary.partyVotes.keys.toList()..sort();
    return _Panel(
      title: 'Verified vote totals',
      subtitle: 'Party codes are displayed alphabetically; this is not a ranking or official declaration.',
      child: keys.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(child: Text('No verified polling-unit result is included in this scope yet.')),
            )
          : Column(
              children: keys
                  .map(
                    (key) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(key,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                          ),
                          Text(
                            '${summary.partyVotes[key]}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: TgcgApp.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
    );
  }
}

class _IntegrityPanel extends StatelessWidget {
  const _IntegrityPanel({required this.summary, required this.engine});

  final CollationSummary summary;
  final CollationEngine engine;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Coverage & reconciliation',
        subtitle: 'Missing and conflicting polling units are kept visible until resolved.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Missing polling units',
                style: TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
            const SizedBox(height: 8),
            if (summary.missingPollingUnitIds.isEmpty)
              const Text('None in this scope.', style: TextStyle(color: TgcgApp.muted))
            else
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: summary.missingPollingUnitIds
                    .map((id) => _Pill(
                          engine.expectedPollingUnit(id)?.scope.label ?? id,
                          const Color(0xFF7A5A10),
                        ))
                    .toList(),
              ),
            const SizedBox(height: 16),
            const Text('Verified conflicts',
                style: TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
            const SizedBox(height: 8),
            if (summary.conflictingPollingUnitIds.isEmpty)
              const Text('None in this scope.', style: TextStyle(color: TgcgApp.muted))
            else
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: summary.conflictingPollingUnitIds
                    .map((id) => _Pill(id, const Color(0xFFB42318)))
                    .toList(),
              ),
          ],
        ),
      );
}

class _ChildScopeCard extends StatelessWidget {
  const _ChildScopeCard({required this.summary, required this.onOpen});

  final CollationSummary summary;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final progress = summary.completionPercent.clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: 280,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAF9),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1E8E5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summary.scope.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: TgcgApp.ink,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: TgcgApp.muted),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '${summary.verifiedPollingUnitCount}/${summary.expectedPollingUnitCount} verified PUs',
                style: const TextStyle(fontSize: 11, color: TgcgApp.muted),
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: const Color(0xFFE5ECE9),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProvenancePanel extends StatelessWidget {
  const _ProvenancePanel({required this.submissions});

  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Included submission provenance',
        subtitle: 'Every aggregated total remains traceable to its verified polling-unit source.',
        child: submissions.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: Text('No verified submission is included in this scope.')),
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
  Widget build(BuildContext context) => InkWell(
        onTap: () => _showSubmission(context),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAF9),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: const Color(0xFFE2E8E5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.verified_user_outlined, color: TgcgApp.primary),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${submission.id} • ${submission.pollingUnitScope.label}',
                      style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${submission.source.name.toUpperCase()} • agent ${submission.submittedBy} • verifier ${submission.verifiedBy ?? 'prototype-seed'}',
                      style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                    ),
                    if (submission.resultForm != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${submission.resultForm!.fileName} • ${submission.resultForm!.contentHash ?? 'hash pending'}',
                        style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.open_in_new_rounded, size: 18, color: TgcgApp.muted),
            ],
          ),
        ),
      );

  void _showSubmission(BuildContext context) {
    final voteKeys = submission.partyVotes.keys.toList()..sort();
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${submission.id} • ${submission.pollingUnitScope.pollingUnitName ?? 'Polling unit'}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _DetailRow('Scope', submission.pollingUnitScope.label),
                _DetailRow('Source', submission.source.name.toUpperCase()),
                _DetailRow('Submitted by', submission.submittedBy),
                _DetailRow('Status', submission.status.name),
                _DetailRow('Verified by', submission.verifiedBy ?? 'Prototype seed'),
                _DetailRow('Accredited voters', '${submission.accreditedVoters}'),
                _DetailRow('Valid votes', '${submission.totalVotesRecorded}'),
                _DetailRow('Rejected votes', '${submission.rejectedVotes ?? 0}'),
                const Divider(height: 24),
                const Text('Party-code figures',
                    style: TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                const SizedBox(height: 8),
                ...voteKeys.map((key) => _DetailRow(key, '${submission.partyVotes[key]}')),
                if (submission.resultForm != null) ...[
                  const Divider(height: 24),
                  _DetailRow('Evidence file', submission.resultForm!.fileName),
                  _DetailRow('Evidence hash', submission.resultForm!.contentHash ?? 'Pending'),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 135,
              child: Text(label,
                  style: const TextStyle(fontSize: 11, color: TgcgApp.muted)),
            ),
            Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w700, color: TgcgApp.ink)),
            ),
          ],
        ),
      );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.subtitle, required this.child});

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: TgcgApp.muted)),
              const SizedBox(height: 15),
              child,
            ],
          ),
        ),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w900),
        ),
      );
}

class _UnofficialBadge extends StatelessWidget {
  const _UnofficialBadge();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF7A5A10).withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF7A5A10).withValues(alpha: .22)),
        ),
        child: const Text(
          'UNOFFICIAL FIELD COLLATION',
          style: TextStyle(
            color: Color(0xFF7A5A10),
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
