import 'package:flutter/material.dart';

import '../api/member_admin_repository.dart' show verificationLabel;
import '../api/support_groups_repository.dart';
import '../membership/member_search.dart' show channelLabel;
import '../ui/tgcg_design.dart';
import '../ui/tgcg_figures.dart';

String _ageLabel(String band) => switch (band) {
  'under18' => 'Under 18',
  'unknown' => 'Not given',
  _ => band,
};

/// A group's analytics, for those who vet groups: who is in it, as Members
/// & Exco counts members, and the group's own figures: how each came in,
/// where they are by state and how they sign in.
class GroupFigures extends StatelessWidget {
  const GroupFigures({super.key, required this.analysis});

  final GroupAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final members = analysis.members;
    final total = members.total;
    final verified = members.verification['verified'] ?? 0;
    final signedIn = members.profile['signedIn'] ?? 0;
    final cards = [
      _Bars(
        title: 'Where they are',
        total: total,
        rows: [
          for (final state in analysis.states)
            (state.code.isEmpty ? 'No place given' : state.name, state.count),
        ],
        shown: 8,
      ),
      _Bars(
        title: 'How they came into the group',
        total: total,
        rows: [
          for (final MapEntry(:key, :value) in analysis.via.entries) (groupVias[key] ?? key, value),
        ]..sort((a, b) => b.$2.compareTo(a.$2)),
      ),
      _Bars(
        title: 'How they sign in',
        total: total,
        rows: [
          ('With their phone number', analysis.withPhone),
          ('With their VIN', analysis.vinOnly),
          if (analysis.ninOnly > 0) ('With their NIN', analysis.ninOnly),
        ],
        footnote: analysis.pinToChoose == 0
            ? null
            : '${formatCount(analysis.pinToChoose)} with a VIN or NIN have not chosen their own '
                'PIN yet.',
      ),
      _Bars(
        title: 'Gender',
        total: total,
        rows: [
          ('Men', members.gender['male'] ?? 0),
          ('Women', members.gender['female'] ?? 0),
          ('Not given', members.gender[''] ?? 0),
        ],
      ),
      _Bars(
        title: 'Age',
        total: total,
        rows: [for (final MapEntry(:key, :value) in members.age.entries) (_ageLabel(key), value)],
      ),
      if (members.occupationRows().isNotEmpty)
        _Bars(title: 'Profession', total: total, rows: members.occupationRows(), shown: 8),
      _Bars(
        title: 'Identity',
        total: total,
        rows: [
          for (final status in const ['verified', 'pendingReview', 'unverified', 'rejected'])
            (verificationLabel(status), members.verification[status] ?? 0),
        ],
      ),
      _Bars(
        title: 'How they joined TGCG',
        total: total,
        rows: [
          for (final MapEntry(:key, :value) in members.channel.entries) (channelLabel(key), value),
        ]..sort((a, b) => b.$2.compareTo(a.$2)),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TgcgMetricGrid(
          across: const [2, 3, 3],
          cards: [
            TgcgMetricCard(
              label: 'Members',
              value: formatCount(total),
              detail:
                  '+${formatCount(members.new30Days)} in 30 days · '
                  '+${formatCount(members.new7Days)} in 7',
              icon: Icons.groups_2_outlined,
            ),
            TgcgMetricCard(
              label: 'Identity verified',
              value: formatCount(verified),
              detail: '${share(verified, total)} of members',
              icon: Icons.verified_user_outlined,
              tone: TgcgMetricTone.success,
            ),
            TgcgMetricCard(
              label: 'Signed in to the app',
              value: formatCount(signedIn),
              detail: '${share(signedIn, total)} of members',
              icon: Icons.login_rounded,
            ),
            TgcgMetricCard(
              label: 'Men',
              value: formatCount(members.gender['male'] ?? 0),
              detail: '${share(members.gender['male'] ?? 0, total)} of members',
              icon: Icons.man_outlined,
              tone: TgcgMetricTone.neutral,
            ),
            TgcgMetricCard(
              label: 'Women',
              value: formatCount(members.gender['female'] ?? 0),
              detail: '${share(members.gender['female'] ?? 0, total)} of members',
              icon: Icons.woman_outlined,
              tone: TgcgMetricTone.neutral,
            ),
            TgcgMetricCard(
              label: 'Asked, not yet said yes',
              value: formatCount(analysis.waiting),
              detail: 'Already members, asked in the app',
              icon: Icons.hourglass_top_rounded,
              tone: TgcgMetricTone.warning,
            ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 700 ? 2 : 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var column = 0; column < columns; column++) ...[
                  if (column > 0) const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (index, card) in cards.indexed)
                          if (index % columns == column)
                            Padding(padding: const EdgeInsets.only(bottom: 12), child: card),
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// A card of share bars; with [shown], only that many until "Show all".
class _Bars extends StatefulWidget {
  const _Bars({
    required this.title,
    required this.total,
    required this.rows,
    this.shown,
    this.footnote,
  });

  final String title;
  final int total;
  final List<(String, int)> rows;
  final int? shown;
  final String? footnote;

  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  var _all = false;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    final limit = widget.shown;
    final visible = _all || limit == null ? rows : rows.take(limit);
    return TgcgSectionCard(
      padding: const EdgeInsets.all(16),
      title: widget.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isEmpty) const Text('Nobody yet.', style: TgcgType.caption),
          for (final (label, value) in visible)
            ShareBar(label: label, value: value, total: widget.total),
          if (limit != null && rows.length > limit)
            TextButton(
              onPressed: () => setState(() => _all = !_all),
              child: Text(_all ? 'Show fewer' : 'Show all ${rows.length}'),
            ),
          if (widget.footnote case final footnote?) ...[
            const SizedBox(height: 6),
            Text(footnote, style: TgcgType.caption),
          ],
        ],
      ),
    );
  }
}
