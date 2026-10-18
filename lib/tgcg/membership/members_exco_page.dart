import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show ConnectToServerNotice, failureMessage, formatDay;
import '../api/access_repository.dart' show ApiPage;
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

/// "12,345".
String formatCount(int value) {
  final digits = '${value.abs()}';
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return value < 0 ? '-$grouped' : '$grouped';
}

/// "42%" of [total]; "0%" when there is nothing to divide.
String share(int part, int total) => total == 0 ? '0%' : '${(part * 100 / total).round()}%';

String levelLabel(GeographyLevel level) => switch (level) {
  GeographyLevel.country => 'Nigeria',
  GeographyLevel.geopoliticalZone => 'Zone',
  GeographyLevel.state => 'State',
  GeographyLevel.senatorialDistrict => 'District',
  GeographyLevel.lga => 'LGA',
  GeographyLevel.ward => 'Ward',
  GeographyLevel.pollingUnit => 'Polling unit',
};

/// "States", "LGAs"...; in a sentence, "states", "LGAs".
String levelsLabel(GeographyLevel level, {bool inSentence = false}) {
  final label = switch (level) {
    GeographyLevel.geopoliticalZone => 'Zones',
    GeographyLevel.state => 'States',
    GeographyLevel.lga => 'LGAs',
    GeographyLevel.ward => 'Wards',
    GeographyLevel.pollingUnit => 'Polling units',
    _ => 'Areas',
  };
  return inSentence && level != GeographyLevel.lga ? label.toLowerCase() : label;
}

String _channelLabel(String channel) => switch (channel) {
  'self' => 'Joined in the app',
  'assisted' => 'By a coordinator',
  'ussd' => 'By USSD',
  'import' => "From chapters' lists",
  'referred' => 'By another member',
  _ => 'Other',
};

String _ageLabel(String band) => switch (band) {
  'under18' => 'Under 18',
  'unknown' => 'Not given',
  _ => band,
};

String _genderLabel(String gender) => switch (gender) {
  'male' => 'Men',
  'female' => 'Women',
  _ => 'Not given',
};

const _profileLabels = {
  'vin': 'VIN',
  'cardPhoto': 'Photo of the card',
  'selfie': 'Selfie',
  'gender': 'Gender',
  'dateOfBirth': 'Date of birth',
  'phoneConfirmed': 'Phone confirmed by SMS',
  'signedIn': 'Signed in to the app',
};

/// The exco posts at one level: a state's include its senatorial districts'.
List<GeographyLevel> _postLevels(GeographyLevel level) => switch (level) {
  GeographyLevel.state => const [GeographyLevel.state, GeographyLevel.senatorialDistrict],
  _ => [level],
};

/// "National exco", "LGA exco"...
String _excoLabel(GeographyLevel level) =>
    level == GeographyLevel.country ? 'National exco' : '${levelLabel(level)} exco';

/// Members and exco, area by area: Nigeria, each state, its LGAs, wards and
/// polling units. Every figure and list comes from the server.
class MembersExcoPage extends StatefulWidget {
  const MembersExcoPage({super.key, this.start});

  /// Where to open; Nigeria by default.
  final AreaRef? start;

  @override
  State<MembersExcoPage> createState() => _MembersExcoPageState();
}

class _MembersExcoPageState extends State<MembersExcoPage> {
  late final _trail = <AreaRef>[widget.start ?? AreaRef.nigeria];
  Future<MemberAnalysis>? _analysis;
  int _tab = 0;

  /// How the area is broken down (Nigeria by state or by zone); null: as usual.
  GeographyLevel? _by;

  AreaRef get _here => _trail.last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analysis ??= _load();
  }

  Future<MemberAnalysis>? _load() =>
      TgcgBackend.of(context)?.members.analysis(_here, by: _by);

  void _reload() => setState(() => _analysis = _load());

  void _open(AreaRef area) => setState(() {
    _trail.add(area);
    _by = null;
    _analysis = _load();
  });

  void _backTo(int index) => setState(() {
    _trail.removeRange(index + 1, _trail.length);
    _by = null;
    _analysis = _load();
  });

  void _breakDown(GeographyLevel by) => setState(() {
    _by = by;
    _analysis = _load();
  });

  @override
  Widget build(BuildContext context) {
    if (TgcgBackend.of(context) == null) {
      return const ConnectToServerNotice(
        message: 'Members and exco come from the server. Sign in with a server account to see them.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 760 ? 16.0 : 24.0;
        return ListView(
          padding: EdgeInsets.fromLTRB(padding, 22, padding, 36),
          children: [
            TgcgPageHeader(
              eyebrow: 'MEMBERSHIP',
              title: 'Members & Exco',
              subtitle: _here.level == GeographyLevel.country
                  ? (_by == GeographyLevel.geopoliticalZone
                      ? 'Nigeria, zone by zone.'
                      : 'Nigeria, state by state.')
                  : '${_here.name} ${levelLabel(_here.level)}.',
              trailing: IconButton(
                tooltip: 'Load again',
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ),
            const SizedBox(height: 12),
            _Trail(trail: _trail, onTap: _backTo),
            const SizedBox(height: 16),
            FutureBuilder<MemberAnalysis>(
              future: _analysis,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return TgcgEmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'The figures could not be loaded',
                    message: failureMessage(snapshot.error!),
                    action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
                  );
                }
                final analysis = snapshot.data;
                if (analysis == null || snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: LinearProgressIndicator(minHeight: 2),
                  );
                }
                return _Analysis(
                  key: ValueKey('${_here.level.name}:${_here.code}'),
                  area: _here,
                  analysis: analysis,
                  tab: _tab,
                  onTab: (tab) => setState(() => _tab = tab),
                  onOpen: _open,
                  onBreakDown: _breakDown,
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _Trail extends StatelessWidget {
  const _Trail({required this.trail, required this.onTap});

  final List<AreaRef> trail;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 2,
    runSpacing: 2,
    children: [
      for (final (index, area) in trail.indexed) ...[
        if (index > 0) const Icon(Icons.chevron_right_rounded, size: 18, color: TgcgColors.muted),
        index == trail.length - 1
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Text(
                  area.name,
                  style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900),
                ),
              )
            : TextButton(onPressed: () => onTap(index), child: Text(area.name)),
      ],
    ],
  );
}

class _Analysis extends StatelessWidget {
  const _Analysis({
    super.key,
    required this.area,
    required this.analysis,
    required this.tab,
    required this.onTab,
    required this.onOpen,
    required this.onBreakDown,
  });

  final AreaRef area;
  final MemberAnalysis analysis;
  final int tab;
  final ValueChanged<int> onTab;
  final ValueChanged<AreaRef> onOpen;
  final ValueChanged<GeographyLevel> onBreakDown;

  @override
  Widget build(BuildContext context) {
    final members = analysis.members;
    final exco = analysis.exco;
    final by = analysis.by;
    final tabs = [if (by != null) 'Areas', 'Exco', 'Members'];
    final current = tab.clamp(0, tabs.length - 1);
    final total = members.total;
    final verified = members.verification['verified'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Tiles(
          tiles: [
            (
              'Members',
              formatCount(total),
              '+${formatCount(members.new30Days)} in 30 days · '
                  '+${formatCount(members.new7Days)} in 7',
              Icons.groups_2_outlined,
              TgcgMetricTone.info,
            ),
            (
              'Exco',
              formatCount(exco.people),
              [
                '${formatCount(exco.appointments)} posts',
                if (by != null)
                  '${analysis.withExco} of ${analysis.parts.length} '
                      '${levelsLabel(by, inSentence: true)}',
              ].join(' · '),
              Icons.account_tree_outlined,
              TgcgMetricTone.ai,
            ),
            (
              'Identity verified',
              formatCount(verified),
              '${share(verified, total)} · ${formatCount(members.fullyVerified)} fully verified',
              Icons.verified_user_outlined,
              TgcgMetricTone.success,
            ),
            (
              'Women',
              formatCount(members.gender['female'] ?? 0),
              '${share(members.gender['female'] ?? 0, total)} of members',
              Icons.woman_outlined,
              TgcgMetricTone.neutral,
            ),
            (
              'With their PVC',
              formatCount(members.profile['vin'] ?? 0),
              '${share(members.profile['vin'] ?? 0, total)} gave a VIN',
              Icons.badge_outlined,
              TgcgMetricTone.neutral,
            ),
            (
              'Awaiting review',
              formatCount(members.verification['pendingReview'] ?? 0),
              '${formatCount(members.verification['unverified'] ?? 0)} not checked yet',
              Icons.pending_actions_outlined,
              TgcgMetricTone.warning,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Cards(
          cards: [
            _WeeklyCard(weekly: members.weekly),
            _BarsCard(
              title: 'Age',
              total: total,
              rows: [
                for (final MapEntry(:key, :value) in members.age.entries) (_ageLabel(key), value),
              ],
            ),
            _BarsCard(
              title: 'Gender',
              total: total,
              rows: [
                for (final gender in const ['female', 'male', ''])
                  (_genderLabel(gender), members.gender[gender] ?? 0),
              ],
              footnote: members.withDisability == 0
                  ? null
                  : '${formatCount(members.withDisability)} told us of a disability.',
            ),
            _BarsCard(
              title: 'How they joined',
              total: total,
              rows: [
                for (final MapEntry(:key, :value) in members.channel.entries)
                  (_channelLabel(key), value),
              ]..sort((a, b) => b.$2.compareTo(a.$2)),
            ),
            _BarsCard(
              title: 'Identity',
              total: total,
              rows: [
                ('Fully verified', members.fullyVerified),
                for (final status in const ['verified', 'pendingReview', 'unverified', 'rejected'])
                  (verificationLabel(status), members.verification[status] ?? 0),
              ],
              footnote: 'Fully verified: verified, with VIN, card photo, selfie, gender and date '
                  'of birth.',
            ),
            _BarsCard(
              title: 'What their profiles hold',
              total: total,
              rows: [
                for (final MapEntry(:key, :value) in _profileLabels.entries)
                  (value, members.profile[key] ?? 0),
              ],
            ),
            _ExcoCard(exco: exco, by: by, area: area),
          ],
        ),
        const SizedBox(height: 20),
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<int>(
            segments: [
              for (final (index, label) in tabs.indexed)
                ButtonSegment(value: index, label: Text(label)),
            ],
            selected: {current},
            showSelectedIcon: false,
            onSelectionChanged: (selected) => onTab(selected.single),
          ),
        ),
        const SizedBox(height: 12),
        switch (tabs[current]) {
          'Areas' => _AreasList(analysis: analysis, onOpen: onOpen, onBreakDown: onBreakDown),
          'Exco' => _ExcoList(area: area, roles: exco.roles, byLevel: exco.byLevel),
          _ => _MembersList(area: area),
        },
      ],
    );
  }
}

typedef _Tile = (String, String, String, IconData, TgcgMetricTone);

class _Tiles extends StatelessWidget {
  const _Tiles({required this.tiles});

  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1180
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
          for (final (label, value, detail, icon, tone) in tiles)
            TgcgMetricCard(
              width: width,
              label: label,
              value: value,
              detail: detail,
              icon: icon,
              tone: tone,
            ),
        ],
      );
    },
  );
}

/// Cards side by side where there is room, one under another on a phone.
class _Cards extends StatelessWidget {
  const _Cards({required this.cards});

  final List<Widget> cards;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1100
          ? 3
          : constraints.maxWidth >= 700
              ? 2
              : 1;
      const gap = 12.0;
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final card in cards) SizedBox(width: width, child: card)],
      );
    },
  );
}

const _labelStyle = TextStyle(color: TgcgColors.ink, fontSize: 11.5, fontWeight: FontWeight.w700);
const _valueStyle = TextStyle(color: TgcgColors.muted, fontSize: 11);

/// One bar: [value] out of [total], in a single hue on a pale track.
class ShareBar extends StatelessWidget {
  const ShareBar({super.key, required this.label, required this.value, required this.total});

  final String label;
  final int value;
  final int total;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: _labelStyle)),
            Text('${formatCount(value)} · ${share(value, total)}', style: _valueStyle),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 8,
            child: Stack(
              children: [
                const Positioned.fill(child: ColoredBox(color: TgcgColors.primarySoft)),
                FractionallySizedBox(
                  widthFactor: total == 0 ? 0 : (value / total).clamp(0, 1).toDouble(),
                  child: Container(
                    decoration: BoxDecoration(
                      color: TgcgColors.primaryMid,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _BarsCard extends StatelessWidget {
  const _BarsCard({required this.title, required this.total, required this.rows, this.footnote});

  final String title;
  final int total;
  final List<(String, int)> rows;
  final String? footnote;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    padding: const EdgeInsets.all(16),
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (label, value) in rows) ShareBar(label: label, value: value, total: total),
        if (footnote != null)
          Text(footnote!, style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5)),
      ],
    ),
  );
}

/// New members week by week: one column per week, the latest on the right.
class _WeeklyCard extends StatelessWidget {
  const _WeeklyCard({required this.weekly});

  final List<(DateTime, int)> weekly;

  @override
  Widget build(BuildContext context) {
    final most = weekly.fold<int>(0, (top, week) => week.$2 > top ? week.$2 : top);
    final total = weekly.fold<int>(0, (sum, week) => sum + week.$2);
    return TgcgSectionCard(
      padding: const EdgeInsets.all(16),
      title: 'New members',
      subtitle: '${formatCount(total)} in the last ${weekly.length} weeks',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 120,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final (week, count) in weekly)
                  Expanded(
                    child: Tooltip(
                      message: 'Week of ${formatDay(week)}: ${formatCount(count)} new',
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (count == most && most > 0)
                              Text(formatCount(count), style: _valueStyle),
                            const SizedBox(height: 2),
                            Container(
                              height: most == 0 ? 2 : 2 + 78 * count / most,
                              constraints: const BoxConstraints(maxWidth: 24),
                              decoration: const BoxDecoration(
                                color: TgcgColors.primaryMid,
                                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1, color: TgcgColors.border),
          const SizedBox(height: 4),
          if (weekly.isNotEmpty)
            Row(
              children: [
                Text(formatDay(weekly.first.$1), style: _valueStyle),
                const Spacer(),
                Text('This week: ${formatCount(weekly.last.$2)}', style: _valueStyle),
              ],
            ),
        ],
      ),
    );
  }
}

class _ExcoCard extends StatelessWidget {
  const _ExcoCard({required this.exco, required this.by, required this.area});

  final ExcoFigures exco;
  final GeographyLevel? by;
  final AreaRef area;

  @override
  Widget build(BuildContext context) {
    final levels = [
      for (final level in GeographyLevel.values)
        if ((exco.byLevel[level.name] ?? 0) > 0) (levelLabel(level), exco.byLevel[level.name]!),
    ];
    return TgcgSectionCard(
      padding: const EdgeInsets.all(16),
      title: 'Exco',
      subtitle: '${formatCount(exco.people)} people in ${formatCount(exco.appointments)} posts'
          '${area.level == GeographyLevel.country ? '' : ' · ${formatCount(exco.here)} at the '
              '${levelLabel(area.level).toLowerCase()} itself'}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (exco.appointments == 0)
            const Text('No exco here yet.', style: _valueStyle)
          else ...[
            for (final (label, value) in levels)
              ShareBar(label: label, value: value, total: exco.appointments),
            const SizedBox(height: 4),
            ShareBar(label: 'Identity verified', value: exco.verified, total: exco.people),
            ShareBar(label: 'Fully verified', value: exco.fullyVerified, total: exco.people),
            ShareBar(
              label: 'Signed in to the app',
              value: exco.profile['signedIn'] ?? 0,
              total: exco.people,
            ),
            ShareBar(label: 'Women', value: exco.women, total: exco.people),
            if (exco.suspended > 0)
              Text('${formatCount(exco.suspended)} posts suspended.', style: _valueStyle),
            const SizedBox(height: 6),
            const Text('Positions held most', style: _labelStyle),
            const SizedBox(height: 4),
            for (final (_, name, count) in exco.roles.take(6))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(name, style: _valueStyle)),
                    Text(formatCount(count), style: _valueStyle),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// --- the smaller areas --------------------------------------------------------------

enum _AreaOrder { members, exco, name }

class _AreasList extends StatefulWidget {
  const _AreasList({required this.analysis, required this.onOpen, required this.onBreakDown});

  final MemberAnalysis analysis;
  final ValueChanged<AreaRef> onOpen;
  final ValueChanged<GeographyLevel> onBreakDown;

  @override
  State<_AreasList> createState() => _AreasListState();
}

class _AreasListState extends State<_AreasList> {
  _AreaOrder _order = _AreaOrder.members;
  final _filter = TextEditingController();

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.analysis;
    final needle = _filter.text.trim().toLowerCase();
    final parts = [
      for (final part in analysis.parts)
        if (needle.isEmpty || part.area.name.toLowerCase().contains(needle)) part,
    ]..sort(
        (a, b) => switch (_order) {
          _AreaOrder.members => b.members.compareTo(a.members),
          _AreaOrder.exco => b.exco.compareTo(a.exco),
          _AreaOrder.name => a.area.name.compareTo(b.area.name),
        },
      );
    final most = analysis.parts.fold<int>(
      0,
      (top, part) => part.members > top ? part.members : top,
    );
    final by = analysis.by!;
    return TgcgSectionCard(
      padding: const EdgeInsets.all(16),
      title: levelsLabel(by),
      subtitle: '${analysis.withMembers} of ${analysis.parts.length} have members, '
          '${analysis.withExco} have exco.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (analysis.breakdowns.length > 1)
                SegmentedButton<GeographyLevel>(
                  segments: [
                    for (final level in analysis.breakdowns)
                      ButtonSegment(value: level, label: Text(levelsLabel(level))),
                  ],
                  selected: {by},
                  showSelectedIcon: false,
                  onSelectionChanged: (selected) => widget.onBreakDown(selected.single),
                ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: _filter,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    labelText: 'Find by name',
                  ),
                ),
              ),
              for (final (order, label) in const [
                (_AreaOrder.members, 'Most members'),
                (_AreaOrder.exco, 'Most exco'),
                (_AreaOrder.name, 'A to Z'),
              ])
                ChoiceChip(
                  label: Text(label),
                  selected: _order == order,
                  onSelected: (_) => setState(() => _order = order),
                ),
            ],
          ),
          const SizedBox(height: 10),
          for (final part in parts)
            _AreaRow(part: part, most: most, onOpen: () => widget.onOpen(part.area)),
        ],
      ),
    );
  }
}

class _AreaRow extends StatelessWidget {
  const _AreaRow({required this.part, required this.most, required this.onOpen});

  final AreaFigures part;
  final int most;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => InkWell(
    key: ValueKey('area-${part.area.code}'),
    onTap: onOpen,
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(part.area.name, style: _labelStyle)),
                    Text('${formatCount(part.members)} members', style: _labelStyle),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: SizedBox(
                    height: 6,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: most == 0 ? 0 : part.members / most,
                        child: const ColoredBox(color: TgcgColors.primaryMid),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    '${formatCount(part.exco)} exco posts',
                    '${share(part.verified, part.members)} verified',
                    '${share(part.women, part.members)} women',
                    '+${formatCount(part.new30Days)} in 30 days',
                  ].join(' · '),
                  style: _valueStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right_rounded, color: TgcgColors.muted),
        ],
      ),
    ),
  );
}

// --- exco ---------------------------------------------------------------------------

const _excoFilters = [
  (null, 'All'),
  ('notFullyVerified', 'Not fully verified'),
  ('neverSignedIn', 'Never signed in'),
];

class _ExcoList extends StatefulWidget {
  const _ExcoList({required this.area, required this.roles, required this.byLevel});

  final AreaRef area;
  final List<(String, String, int)> roles;

  /// Posts at each level in the area.
  final Map<String, int> byLevel;

  @override
  State<_ExcoList> createState() => _ExcoListState();
}

class _ExcoListState extends State<_ExcoList> {
  final _search = TextEditingController();
  final _posts = <ExcoPost>[];
  /// The level whose exco is listed; null for everyone in the area.
  late GeographyLevel? _level = widget.area.level;
  String? _show;
  String? _role;
  int _count = 0;
  bool _more = false;
  bool _loading = false;
  Object? _error;
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading && _posts.isEmpty && _error == null) unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final backend = TgcgBackend.of(context);
    if (backend == null) return;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _posts.clear();
    });
    try {
      final page = await backend.members.exco(
        widget.area,
        at: _level == null ? const [] : _postLevels(_level!),
        role: _role,
        show: _show,
        search: _search.text,
        offset: more ? _posts.length : 0,
      );
      if (!mounted) return;
      setState(() {
        _posts.addAll(page.items);
        _count = page.count;
        _more = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  /// Each level's own exco, from the area's own down, with its posts; then
  /// everyone in the area.
  List<(GeographyLevel?, int)> get _levels {
    final here = widget.area.level;
    final counts = widget.byLevel;
    int posts(GeographyLevel level) =>
        _postLevels(level).fold(0, (sum, at) => sum + (counts[at.name] ?? 0));
    return [
      for (final level in GeographyLevel.values)
        if (level.index >= here.index &&
            (level != GeographyLevel.senatorialDistrict || here == level) &&
            (level == here || posts(level) > 0))
          (level, posts(level)),
      (null, counts.values.fold(0, (sum, n) => sum + n)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.area;
    final rows = <Widget>[];
    String? lastArea;
    for (final post in _posts) {
      final group = '${post.area.level.name}:${post.areaName}';
      if (_level != area.level && group != lastArea) {
        lastArea = group;
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
            child: Text(
              '${post.areaName} ${levelLabel(post.area.level)}'.toUpperCase(),
              style: const TextStyle(
                color: TgcgColors.primaryMid,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                letterSpacing: .8,
              ),
            ),
          ),
        );
      }
      rows.add(_ExcoRow(post: post));
    }
    return TgcgSectionCard(
      padding: const EdgeInsets.all(16),
      title: _level == area.level
          ? (area.level == GeographyLevel.country ? 'National exco' : '${area.name} exco')
          : _level == null
              ? 'Exco in ${area.name}'
              : '${_excoLabel(_level!)} in ${area.name}',
      subtitle: _loading && _posts.isEmpty ? null : '${formatCount(_count)} posts',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _search,
                  onChanged: (_) => _searchSoon(),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    labelText: 'Name, number or position',
                  ),
                ),
              ),
              if (widget.roles.isNotEmpty)
                DropdownButton<String?>(
                  value: _role,
                  hint: const Text('All positions'),
                  onChanged: (role) {
                    _role = role;
                    unawaited(_load());
                  },
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All positions')),
                    for (final (code, name, count) in widget.roles)
                      DropdownMenuItem(value: code, child: Text('$name ($count)')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (level, count) in _levels)
                ChoiceChip(
                  key: ValueKey('exco-level-${level?.name ?? 'all'}'),
                  label: Text('${level == null ? 'Everyone' : _excoLabel(level)} ($count)'),
                  selected: _level == level,
                  onSelected: (_) {
                    _level = level;
                    unawaited(_load());
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (show, label) in _excoFilters)
                ChoiceChip(
                  label: Text(label),
                  selected: _show == show,
                  onSelected: (_) {
                    _show = show;
                    unawaited(_load());
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                failureMessage(_error!),
                style: const TextStyle(color: TgcgColors.danger),
              ),
            ),
          if (!_loading && _error == null && _posts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('No exco found.', style: _valueStyle),
            ),
          ...rows,
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_more && !_loading)
            TextButton(onPressed: () => _load(more: true), child: const Text('Show more')),
        ],
      ),
    );
  }
}

/// Chips saying where someone's identity and profile stand.
List<Widget> standingChips({
  required String verificationStatus,
  required String? verifiedHow,
  required List<String> gaps,
  required bool signedIn,
  String membershipState = 'active',
}) {
  final verified = verificationStatus == 'verified';
  final how = verifiedHowLabel(verifiedHow);
  return [
    TgcgStatusPill(
      label: verified && gaps.isEmpty
          ? 'Fully verified'
          : verified
              ? 'Verified${how.isEmpty ? '' : ' $how'}'
              : verificationLabel(verificationStatus),
      color: verified
          ? (gaps.isEmpty ? TgcgColors.success : TgcgColors.info)
          : verificationStatus == 'rejected'
              ? TgcgColors.danger
              : TgcgColors.warning,
      compact: true,
    ),
    if (membershipState != 'active')
      TgcgStatusPill(
        label: membershipStateLabel(membershipState),
        color: TgcgColors.danger,
        compact: true,
      ),
    for (final gap in gaps)
      TgcgStatusPill(label: gapLabel(gap), color: TgcgColors.muted, compact: true),
    if (!signedIn)
      const TgcgStatusPill(label: 'Never signed in', color: TgcgColors.muted, compact: true),
  ];
}

class _ExcoRow extends StatelessWidget {
  const _ExcoRow({required this.post});

  final ExcoPost post;

  @override
  Widget build(BuildContext context) {
    final holder = post.holder;
    return InkWell(
      onTap: () => showMemberDetails(context, holder.membershipNumber),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  post.roleName,
                  style: const TextStyle(
                    color: TgcgColors.primaryMid,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (post.state != 'active')
                  TgcgStatusPill(
                    label: post.state == 'suspended' ? 'Post suspended' : 'Starts later',
                    color: TgcgColors.warning,
                    compact: true,
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(holder.fullName, style: _labelStyle),
            Text(
              [
                holder.membershipNumber,
                ?holder.phoneNumber,
                if (holder.gender.isNotEmpty) holder.gender == 'female' ? 'Woman' : 'Man',
                if (post.area.level != GeographyLevel.country) post.areaName,
              ].join(' · '),
              style: _valueStyle,
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: standingChips(
                verificationStatus: holder.verificationStatus,
                verifiedHow: holder.verifiedHow,
                gaps: holder.gaps,
                signedIn: holder.signedIn,
                membershipState: holder.membershipState,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- members ------------------------------------------------------------------------

const _memberFilters = [
  (null, null, 'Everyone'),
  ('notFullyVerified', null, 'Not fully verified'),
  (null, 'pendingReview', 'Awaiting review'),
  ('withRole', null, 'Exco'),
  ('withoutRole', null, 'Not exco'),
  ('neverSignedIn', null, 'Never signed in'),
];

class _MembersList extends StatefulWidget {
  const _MembersList({required this.area});

  final AreaRef area;

  @override
  State<_MembersList> createState() => _MembersListState();
}

class _MembersListState extends State<_MembersList> {
  final _search = TextEditingController();
  final _members = <StaffMember>[];
  int _filter = 0;
  int _count = 0;
  bool _more = false;
  bool _loading = false;
  Object? _error;
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loading && _members.isEmpty && _error == null) unawaited(_load());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final backend = TgcgBackend.of(context);
    if (backend == null) return;
    final (show, verification, _) = _memberFilters[_filter];
    setState(() {
      _loading = true;
      _error = null;
      if (!more) _members.clear();
    });
    try {
      final ApiPage<StaffMember> page = await backend.members.members(
        search: _search.text,
        show: show,
        verificationStatus: verification,
        area: widget.area,
        offset: more ? _members.length : 0,
      );
      if (!mounted) return;
      setState(() {
        _members.addAll(page.items);
        _count = page.count;
        _more = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _searchSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _load);
  }

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    padding: const EdgeInsets.all(16),
    title: 'Members in ${widget.area.name}',
    subtitle: _loading && _members.isEmpty ? null : '${formatCount(_count)} found',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: TextField(
            controller: _search,
            onChanged: (_) => _searchSoon(),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              labelText: 'Name or membership number',
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, (_, _, label)) in _memberFilters.indexed)
              ChoiceChip(
                label: Text(label),
                selected: _filter == index,
                onSelected: (_) {
                  _filter = index;
                  unawaited(_load());
                },
              ),
          ],
        ),
        const SizedBox(height: 6),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(failureMessage(_error!), style: const TextStyle(color: TgcgColors.danger)),
          ),
        if (!_loading && _error == null && _members.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('No members found.', style: _valueStyle),
          ),
        for (final member in _members) _MemberRow(member: member),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_more && !_loading)
          TextButton(onPressed: () => _load(more: true), child: const Text('Show more')),
      ],
    ),
  );
}

int? ageOn(DateTime? born, DateTime today) {
  if (born == null) return null;
  var age = today.year - born.year;
  if (today.month < born.month || (today.month == born.month && today.day < born.day)) age--;
  return age;
}

String _placeOf(GeographicScope scope) => [
  ?scope.pollingUnitName,
  ?scope.wardName,
  ?scope.lgaName,
  ?scope.stateName,
].join(', ');

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member});

  final StaffMember member;

  @override
  Widget build(BuildContext context) {
    final age = ageOn(member.dateOfBirth, DateTime.now());
    return InkWell(
      onTap: () => showMemberDetails(context, member.membershipNumber, member: member),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(member.displayName, style: _labelStyle),
            Text(
              [
                member.membershipNumber,
                ?member.phoneNumber,
                if (member.gender.isNotEmpty) member.gender == 'female' ? 'Woman' : 'Man',
                if (age != null) '$age years',
                if (_placeOf(member.scope).isNotEmpty) _placeOf(member.scope),
              ].join(' · '),
              style: _valueStyle,
            ),
            if (member.roles.isNotEmpty)
              Text(
                member.roles.join(', '),
                style: const TextStyle(
                  color: TgcgColors.primaryMid,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: standingChips(
                verificationStatus: member.verificationStatus,
                verifiedHow: member.verifiedHow,
                gaps: member.gaps,
                signedIn: member.signedIn,
                membershipState: member.membershipState,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- one member ---------------------------------------------------------------------

/// Everything on record about a member that this account may see.
Future<void> showMemberDetails(BuildContext context, String number, {StaffMember? member}) =>
    showDialog<void>(
      context: context,
      builder: (_) => _MemberDetails(number: number, member: member),
    );

class _MemberDetails extends StatefulWidget {
  const _MemberDetails({required this.number, this.member});

  final String number;
  final StaffMember? member;

  @override
  State<_MemberDetails> createState() => _MemberDetailsState();
}

class _MemberDetailsState extends State<_MemberDetails> {
  Future<StaffMember>? _member;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _member ??= widget.member != null
        ? Future.value(widget.member)
        : TgcgBackend.of(context)!.members.member(widget.number);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: Text(widget.member?.displayName ?? widget.number),
    content: SizedBox(
      width: 440,
      child: FutureBuilder<StaffMember>(
        future: _member,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Text(
              failureMessage(snapshot.error!),
              style: const TextStyle(color: TgcgColors.danger),
            );
          }
          final member = snapshot.data;
          if (member == null) return const LinearProgressIndicator(minHeight: 2);
          final age = ageOn(member.dateOfBirth, DateTime.now());
          final rows = <(String, String)>[
            ('Membership number', member.membershipNumber),
            if (member.phoneNumber != null) ('Phone', member.phoneNumber!),
            if (member.gender.isNotEmpty) ('Gender', member.gender == 'female' ? 'Woman' : 'Man'),
            if (member.dateOfBirth != null)
              ('Born', '${formatDay(member.dateOfBirth!)}${age == null ? '' : ' ($age years)'}'),
            if (member.occupation.isNotEmpty) ('Occupation', member.occupation),
            ('Registered in', _placeOf(member.scope).isEmpty ? 'Nigeria' : _placeOf(member.scope)),
            if (member.createdAt != null) ('Joined', formatDay(member.createdAt!)),
            ('How they joined', _channelLabel(member.registrationChannel)),
            ('Exco posts', member.roles.isEmpty ? 'None' : member.roles.join(', ')),
            ('Phone confirmed', member.phoneVerified ? 'Yes' : 'No'),
            (
              'App',
              member.signedIn
                  ? 'Has signed in'
                  : member.hasAppAccount
                      ? 'Never signed in'
                      : 'No account',
            ),
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: standingChips(
                  verificationStatus: member.verificationStatus,
                  verifiedHow: member.verifiedHow,
                  gaps: member.gaps,
                  signedIn: member.signedIn,
                  membershipState: member.membershipState,
                ),
              ),
              const SizedBox(height: 12),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 130, child: Text(label, style: _valueStyle)),
                      Expanded(child: Text(value, style: _labelStyle)),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
  );
}
