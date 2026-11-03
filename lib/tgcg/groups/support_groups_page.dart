import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show failureMessage, showFailure;
import '../api/access_repository.dart' show ApiPage;
import '../api/backend.dart';
import '../api/support_groups_repository.dart';
import '../ui/tgcg_design.dart';
import 'my_support_groups_page.dart' show groupStatus;

const _filters = [
  ('pending', 'Waiting for vetting'),
  ('approved', 'Approved'),
  ('suspended', 'Suspended'),
  ('rejected', 'Not approved'),
  ('', 'All'),
];

String _day(DateTime? moment) =>
    moment == null ? '' : '${moment.day}/${moment.month}/${moment.year}';

/// Every support group, for those who vet them nationwide: the totals, with
/// people in several groups counted once, and each group to vet.
class SupportGroupsPage extends StatefulWidget {
  const SupportGroupsPage({super.key});

  @override
  State<SupportGroupsPage> createState() => _SupportGroupsPageState();
}

class _SupportGroupsPageState extends State<SupportGroupsPage> {
  String _status = 'pending';
  final _search = TextEditingController();
  Future<SupportGroupTotals>? _totals;
  final _items = <SupportGroup>[];
  bool _loading = false;
  bool _more = false;
  Object? _error;

  SupportGroupsRepository get _groups => TgcgBackend.of(context)!.supportGroups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_totals == null) _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _totals = _groups.totals();
      _items.clear();
      _more = false;
      _error = null;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final ApiPage<SupportGroup> page = await _groups.all(
        status: _status,
        search: _search.text,
        offset: _items.length,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _more = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(SupportGroup group) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => VettedGroupPage(group: group)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListView(
      padding: tgcgPagePadding(constraints.maxWidth, bottom: 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'MEMBERSHIP',
          title: 'Support Groups',
          subtitle: 'Organizations allied with TGCG, and who is in them.',
          trailing: TgcgReloadButton(loading: _loading, onPressed: _reload),
        ),
        const SizedBox(height: 16),
        FutureBuilder<SupportGroupTotals>(
          future: _totals,
          builder: (context, snapshot) {
            final totals = snapshot.data;
            if (totals == null) {
              return snapshot.hasError
                  ? TgcgNotice(
                      icon: Icons.cloud_off_outlined,
                      color: TgcgColors.danger,
                      child: Text(failureMessage(snapshot.error!)),
                    )
                  : const LinearProgressIndicator(minHeight: 2);
            }
            return TgcgMetricGrid(
              across: const [2, 4, 4],
              cards: [
                TgcgMetricCard(
                  label: 'Approved groups',
                  value: '${totals.byStatus['approved'] ?? 0}',
                  icon: Icons.diversity_3_outlined,
                ),
                TgcgMetricCard(
                  label: 'Waiting for vetting',
                  value: '${totals.byStatus['pending'] ?? 0}',
                  icon: Icons.pending_actions_outlined,
                  tone: TgcgMetricTone.warning,
                ),
                TgcgMetricCard(
                  label: 'People in groups',
                  value: '${totals.people}',
                  detail: 'Each person counted once',
                  icon: Icons.groups_outlined,
                ),
                TgcgMetricCard(
                  label: 'Approved by TGCG',
                  value: '${totals.approvedPeople}',
                  icon: Icons.verified_outlined,
                  tone: TgcgMetricTone.success,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (code, label) in _filters)
              ChoiceChip(
                label: Text(label),
                selected: _status == code,
                onSelected: (_) {
                  _status = code;
                  _reload();
                },
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _search,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => _reload(),
          decoration: const InputDecoration(
            labelText: 'Find by name or serial number',
            prefixIcon: Icon(Icons.search_rounded),
            isDense: true,
          ),
        ),
        const SizedBox(height: 14),
        if (_error != null && _items.isEmpty)
          TgcgEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'The groups could not be loaded',
            message: failureMessage(_error!),
            action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
          )
        else if (_items.isEmpty && _loading)
          const LinearProgressIndicator(minHeight: 2)
        else if (_items.isEmpty)
          const TgcgEmptyState(
            icon: Icons.diversity_3_outlined,
            title: 'No groups here',
            message: 'Organizations registered on the joining page or by members show here.',
          )
        else
          TgcgRowGroup(
            children: [
              for (final group in _items)
                TgcgActionRow(
                  icon: Icons.diversity_3_outlined,
                  title: group.name,
                  detail:
                      '${group.serialNumber} · ${group.area} · ${group.leader.fullName} · '
                      '${group.members ?? 0} in it',
                  trailing: TgcgStatusPill(
                    compact: true,
                    label: groupStatus(group).$1,
                    color: groupStatus(group).$2,
                  ),
                  onTap: () => _open(group),
                ),
            ],
          ),
        if (_more) ...[
          const SizedBox(height: 10),
          Center(
            child: OutlinedButton(
              onPressed: _loading ? null : _load,
              child: const Text('Show more'),
            ),
          ),
        ],
      ],
    ),
  );
}

/// One group, to vet: its registration form's details, the decision, and
/// everyone in it.
class VettedGroupPage extends StatefulWidget {
  const VettedGroupPage({super.key, required this.group});

  final SupportGroup group;

  @override
  State<VettedGroupPage> createState() => _VettedGroupPageState();
}

class _VettedGroupPageState extends State<VettedGroupPage> {
  late SupportGroup _group = widget.group;
  bool _deciding = false;
  final _people = <GroupPerson>[];
  bool _loading = false;
  bool _more = false;
  Object? _error;

  SupportGroupsRepository get _groups => TgcgBackend.of(context)!.supportGroups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_people.isEmpty && !_loading && _error == null) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final page = await _groups.groupPeople(_group.id, offset: _people.length);
      if (!mounted) return;
      setState(() {
        _people.addAll(page.items);
        _more = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String?> _askReason(String title, String action) => showDialog<String>(
    context: context,
    builder: (_) => _ReasonDialog(title: title, action: action),
  );

  Future<void> _decide(String decision) async {
    String reason = '';
    if (decision == 'reject' || decision == 'suspend') {
      final given = await _askReason(
        decision == 'reject' ? 'Turn down ${_group.name}?' : 'Suspend ${_group.name}?',
        decision == 'reject' ? 'Turn down' : 'Suspend',
      );
      if (given == null || !mounted) return;
      reason = given;
    }
    setState(() => _deciding = true);
    try {
      final decided = await _groups.decide(_group.id, decision, reason: reason);
      if (mounted) setState(() => _group = decided);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _deciding = false);
    }
  }

  Widget _fact(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 130, child: Text(label, style: TgcgType.caption)),
        Expanded(child: SelectableText(value.isEmpty ? '—' : value, style: TgcgType.body)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final group = _group;
    final (status, color) = groupStatus(group);
    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(title: Text(group.serialNumber)),
      body: SafeArea(
        child: TgcgPageList(
          children: [
            TgcgSectionCard(
              title: group.name,
              subtitle: '${group.coverageLabel} · ${group.area}',
              trailing: TgcgStatusPill(label: status, color: color),
              trailingBeside: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _fact('Serial number', group.serialNumber),
                  _fact('Leader', group.leader.fullName),
                  _fact("Leader's phone", group.leader.phoneNumber),
                  _fact("Leader's place", group.leader.place),
                  _fact('Email', group.email),
                  _fact('Registered by', group.registeredBy),
                  _fact('Registered on', _day(group.createdAt)),
                  if (group.decidedBy.isNotEmpty)
                    _fact('Decided by', '${group.decidedBy}, ${_day(group.decidedAt)}'),
                  if (group.decisionReason.isNotEmpty) _fact('Reason', group.decisionReason),
                  if (!group.leaderConfirmed)
                    const TgcgNotice(
                      icon: Icons.hourglass_top_rounded,
                      color: TgcgColors.warning,
                      child: Text(
                        'The person named as leader has not said yes in the app yet. It can be '
                        'approved after they do.',
                      ),
                    ),
                ],
              ),
            ),
            if (group.officials.isNotEmpty) ...[
              const SizedBox(height: 14),
              TgcgSectionCard(
                title: 'Other leaders',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final official in group.officials)
                      _fact(
                        official.position.isEmpty ? 'Leader' : official.position,
                        [
                          official.name,
                          official.phone,
                        ].where((part) => part.isNotEmpty).join(' · '),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                if (group.isPending) ...[
                  FilledButton.icon(
                    onPressed: _deciding || !group.leaderConfirmed
                        ? null
                        : () => _decide('approve'),
                    icon: const Icon(Icons.verified_outlined),
                    label: const Text('Approve'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _deciding ? null : () => _decide('reject'),
                    icon: const Icon(Icons.block_rounded),
                    label: const Text('Turn down'),
                  ),
                ],
                if (group.isApproved)
                  OutlinedButton.icon(
                    onPressed: _deciding ? null : () => _decide('suspend'),
                    icon: const Icon(Icons.pause_circle_outline_rounded),
                    label: const Text('Suspend'),
                  ),
                if (group.isSuspended)
                  FilledButton.icon(
                    onPressed: _deciding ? null : () => _decide('restore'),
                    icon: const Icon(Icons.play_circle_outline_rounded),
                    label: const Text('Lift the suspension'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            TgcgSectionHeading(
              title: group.members == null ? 'People' : 'People (${group.members} in it)',
            ),
            if (_error != null && _people.isEmpty)
              TgcgNotice(
                icon: Icons.cloud_off_outlined,
                color: TgcgColors.danger,
                child: Text(failureMessage(_error!)),
              )
            else if (_people.isEmpty && _loading)
              const LinearProgressIndicator(minHeight: 2)
            else
              TgcgRowGroup(
                children: [
                  for (final person in _people)
                    TgcgActionRow(
                      icon: person.isWaiting
                          ? Icons.hourglass_top_rounded
                          : Icons.person_outline_rounded,
                      color: person.isWaiting ? TgcgColors.warning : TgcgColors.primary,
                      title: person.fullName.isEmpty ? person.phoneNumber : person.fullName,
                      detail: [
                        ?person.membershipNumber,
                        person.phoneNumber,
                        if (person.place.isNotEmpty) person.place,
                        person.viaLabel,
                      ].join(' · '),
                      trailing: TgcgStatusPill(
                        compact: true,
                        label: person.isWaiting
                            ? 'Waiting to say yes'
                            : person.approved == true
                            ? 'Approved'
                            : 'Not yet approved',
                        color: person.isWaiting
                            ? TgcgColors.warning
                            : person.approved == true
                            ? TgcgColors.success
                            : TgcgColors.muted,
                      ),
                    ),
                ],
              ),
            if (_more) ...[
              const SizedBox(height: 10),
              Center(
                child: OutlinedButton(
                  onPressed: _loading ? null : _load,
                  child: const Text('Show more'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.action});

  final String title;
  final String action;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _reason,
      autofocus: true,
      minLines: 2,
      maxLines: 5,
      maxLength: 1000,
      decoration: InputDecoration(
        labelText: 'Why',
        helperText: 'The leader sees this in their messages.',
        errorText: _error,
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          if (_reason.text.trim().isEmpty) {
            setState(() => _error = 'Say why.');
            return;
          }
          Navigator.pop(context, _reason.text.trim());
        },
        child: Text(widget.action),
      ),
    ],
  );
}
