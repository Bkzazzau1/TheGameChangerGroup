import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart' show failureMessage, showFailure;
import '../api/access_repository.dart' show ApiPage;
import '../api/api_client.dart' show ApiException;
import '../api/backend.dart';
import '../api/support_groups_repository.dart';
import '../membership/member_profile.dart' show showMemberDetails;
import '../ui/tgcg_design.dart';
import 'group_figures.dart';
import 'my_support_groups_page.dart' show groupStatus;

const _filters = [
  ('', 'All groups'),
  ('pending', 'Waiting for vetting'),
  ('approved', 'Approved'),
  ('suspended', 'Suspended'),
  ('rejected', 'Not approved'),
];

String _day(DateTime? moment) =>
    moment == null ? '' : '${moment.day}/${moment.month}/${moment.year}';

/// "3 approved · 1 waiting · 120 people", for a type of group.
String _kindDetail(GroupKindTotals row) => [
  '${row.byStatus['approved'] ?? 0} approved',
  if ((row.byStatus['pending'] ?? 0) > 0) '${row.byStatus['pending']} waiting',
  '${row.people} ${row.people == 1 ? 'person' : 'people'}',
  if (!row.kind.offered) 'not offered to new groups',
].join(' · ');

/// Every support group, for those who vet them nationwide: the totals, with
/// people in several groups counted once, the types of group, each opening
/// its groups, and each group to vet.
class SupportGroupsPage extends StatefulWidget {
  const SupportGroupsPage({super.key});

  @override
  State<SupportGroupsPage> createState() => _SupportGroupsPageState();
}

class _SupportGroupsPageState extends State<SupportGroupsPage> {
  // Every group at first, whatever its state or type.
  String _status = '';
  String _kind = '';
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
        kind: _kind,
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

  Future<void> _manageKinds() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const GroupKindsPage()));
    if (mounted) _reload();
  }

  void _showKind(String code) {
    _kind = _kind == code ? '' : code;
    _reload();
  }

  Widget _kinds(SupportGroupTotals totals) => TgcgSectionCard(
    title: 'Types of group',
    trailing: TextButton.icon(
      onPressed: _manageKinds,
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: const Text('Manage types'),
    ),
    child: TgcgRowGroup(
      children: [
        for (final row in totals.kinds)
          TgcgActionRow(
            key: ValueKey('kind-${row.kind.code}'),
            icon: _kind == row.kind.code ? Icons.check_circle_rounded : Icons.diversity_3_outlined,
            color: _kind == row.kind.code ? TgcgColors.success : TgcgColors.primary,
            title: row.kind.name,
            detail: _kindDetail(row),
            onTap: () => _showKind(row.kind.code),
          ),
      ],
    ),
  );

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
            final grid = TgcgMetricGrid(
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
            if (totals.kinds.isEmpty) return grid;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [grid, const SizedBox(height: 16), _kinds(totals)],
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
                  detail: [
                    group.serialNumber,
                    if (_kind.isEmpty && group.kindName.isNotEmpty) group.kindName,
                    group.area,
                    group.leader.fullName,
                    '${group.members ?? 0} in it',
                  ].join(' · '),
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
  Future<GroupAnalysis?>? _analysis;
  final _search = TextEditingController();
  Timer? _debounce;

  /// Counts the answers, so a late one for an old search is dropped.
  int _generation = 0;

  SupportGroupsRepository get _groups => TgcgBackend.of(context)!.supportGroups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _analysis ??= _groups.analysis(_group.id);
    if (_people.isEmpty && !_loading && _error == null) _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool fresh = false}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (fresh) {
        _people.clear();
        _more = false;
      }
    });
    try {
      final page = await _groups.groupPeople(
        _group.id,
        offset: _people.length,
        query: _search.text,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        // Newest first: people added since the last page push the list down,
        // so a page can repeat some of the one before.
        final shown = {for (final person in _people) person.id};
        _people.addAll(page.items.where((person) => shown.add(person.id)));
        _more = page.hasMore;
      });
    } catch (error) {
      if (mounted && generation == _generation) setState(() => _error = error);
    } finally {
      if (mounted && generation == _generation) setState(() => _loading = false);
    }
  }

  void _searchSoon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _load(fresh: true));
  }

  /// The member's full profile, as Members & Exco opens it; a decision there
  /// shows here at once, in the list and the analytics.
  Future<void> _openPerson(GroupPerson person) async {
    final number = person.membershipNumber;
    if (number == null) return;
    var changed = false;
    await showMemberDetails(context, number, onChanged: () => changed = true);
    if (!changed || !mounted) return;
    setState(() => _analysis = _groups.analysis(_group.id));
    await _load(fresh: true);
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

  /// Moves the group to another type, one offered to groups or its own.
  Future<void> _changeKind() async {
    setState(() => _deciding = true);
    try {
      final kinds = await _groups.kinds();
      if (!mounted) return;
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('Type of ${_group.name}'),
          children: [
            for (final kind in kinds)
              if (kind.offered || kind.code == _group.kind)
                ListTile(
                  leading: Icon(
                    kind.code == _group.kind
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: TgcgColors.primary,
                  ),
                  title: Text(kind.name),
                  onTap: () => Navigator.pop(context, kind.code),
                ),
          ],
        ),
      );
      if (chosen == null || chosen == _group.kind || !mounted) return;
      final moved = await _groups.changeKind(_group.id, chosen);
      if (mounted) setState(() => _group = moved);
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
                  _fact('Type', group.kindName),
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
                OutlinedButton.icon(
                  onPressed: _deciding ? null : _changeKind,
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('Change type'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            FutureBuilder<GroupAnalysis?>(
              future: _analysis,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return TgcgNotice(
                    icon: Icons.cloud_off_outlined,
                    color: TgcgColors.danger,
                    child: Text(failureMessage(snapshot.error!)),
                  );
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LinearProgressIndicator(minHeight: 2);
                }
                final analysis = snapshot.data;
                if (analysis == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TgcgSectionHeading(title: 'Analytics'),
                    GroupFigures(analysis: analysis),
                    const SizedBox(height: 6),
                  ],
                );
              },
            ),
            TgcgSectionHeading(
              title: group.members == null ? 'People' : 'People (${group.members} in it)',
            ),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onChanged: (_) => _searchSoon(),
              decoration: const InputDecoration(
                labelText: 'Find by name, membership number, phone or VIN',
                prefixIcon: Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            if (_error != null && _people.isEmpty)
              TgcgNotice(
                icon: Icons.cloud_off_outlined,
                color: TgcgColors.danger,
                child: Text(failureMessage(_error!)),
              )
            else if (_people.isEmpty && _loading)
              const LinearProgressIndicator(minHeight: 2)
            else if (_people.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text('Nobody found.', style: TgcgType.caption),
              )
            else
              TgcgRowGroup(
                children: [
                  for (final person in _people)
                    TgcgActionRow(
                      key: ValueKey('group-person-${person.id}'),
                      onTap: person.membershipNumber == null ? null : () => _openPerson(person),
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
                  onPressed: _loading ? null : () => _load(),
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

/// The types of group, for those who vet groups: add one, rename one, and
/// stop or start offering one to groups registering. Groups already of a
/// type keep it either way.
class GroupKindsPage extends StatefulWidget {
  const GroupKindsPage({super.key});

  @override
  State<GroupKindsPage> createState() => _GroupKindsPageState();
}

class _GroupKindsPageState extends State<GroupKindsPage> {
  List<GroupKind>? _kinds;
  Object? _error;
  bool _busy = false;
  final _name = TextEditingController();
  String? _nameError;

  SupportGroupsRepository get _groups => TgcgBackend.of(context)!.supportGroups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_kinds == null && _error == null && !_busy) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final kinds = await _groups.kinds();
      if (mounted) setState(() => _kinds = kinds);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Runs [work], then lists the types again; a refusal shows by the field.
  Future<void> _change(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
      if (mounted) await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      final field = error.fieldError('name');
      if (field != null) {
        setState(() => _nameError = field);
      } else {
        showFailure(context, error);
      }
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.length < 3) {
      setState(() => _nameError = 'Name the type of group.');
      return;
    }
    setState(() => _nameError = null);
    await _change(() async {
      await _groups.addKind(name);
      _name.clear();
    });
  }

  Future<void> _rename(GroupKind kind) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(name: kind.name),
    );
    if (name == null || name == kind.name || !mounted) return;
    await _change(() => _groups.updateKind(kind.code, name: name));
  }

  @override
  Widget build(BuildContext context) {
    final kinds = _kinds;
    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(title: const Text('Types of group')),
      body: SafeArea(
        child: TgcgPageList(
          children: [
            TgcgSectionCard(
              title: 'Add a type',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                    onSubmitted: (_) => _add(),
                    decoration: InputDecoration(
                      labelText: 'Name, e.g. Traders Groups',
                      errorText: _nameError,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : _add,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_error != null && kinds == null)
              TgcgNotice(
                icon: Icons.cloud_off_outlined,
                color: TgcgColors.danger,
                child: Text(failureMessage(_error!)),
              )
            else if (kinds == null)
              const LinearProgressIndicator(minHeight: 2)
            else
              TgcgRowGroup(
                children: [
                  for (final kind in kinds)
                    TgcgActionRow(
                      key: ValueKey('manage-kind-${kind.code}'),
                      icon: Icons.diversity_3_outlined,
                      color: kind.offered ? TgcgColors.primary : TgcgColors.muted,
                      title: kind.name,
                      detail: kind.offered
                          ? 'Offered to groups registering'
                          : 'Not offered to new groups',
                      onTap: _busy ? null : () => _rename(kind),
                      trailing: Switch(
                        value: kind.offered,
                        onChanged: _busy
                            ? null
                            : (offered) =>
                                  _change(() => _groups.updateKind(kind.code, offered: offered)),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.name});

  final String name;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.name);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename the type'),
    content: TextField(
      controller: _name,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(labelText: 'Name'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () => Navigator.pop(context, _name.text.trim()),
        child: const Text('Rename'),
      ),
    ],
  );
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
