import 'package:flutter/material.dart';

import '../api/access_repository.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'access_widgets.dart';
import 'appointments_tab.dart';
import 'roles_tab.dart';

/// Delegated authority the caller made or received, or that lies in their
/// delegating reach. Revoking one never revokes what was made from it.
class DelegationsTab extends StatefulWidget {
  const DelegationsTab({super.key});

  @override
  State<DelegationsTab> createState() => _DelegationsTabState();
}

class _DelegationsTabState extends State<DelegationsTab> {
  String? _status = 'active';
  Future<ApiPage<Delegation>>? _grants;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _grants ??= _load();
  }

  Future<ApiPage<Delegation>> _load() =>
      TgcgBackend.of(context)!.access.delegations(status: _status);

  void _reload() => setState(() {
    _grants = _load();
  });

  Future<void> _delegate() async {
    final made = await showDialog<Delegation>(
      context: context,
      builder: (_) => const DelegateDialog(),
    );
    if (made != null && mounted) {
      showDone(context, 'Authority delegated to ${made.recipientName}.');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Delegated authority lets a member appoint, create roles, manage appointments or '
          'delegate further, within the limits set here. It never gives them the operational '
          'permissions it lists; those are the ceiling for the roles they handle.',
          style: TextStyle(color: TgcgColors.muted, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (value, label) in const [
              ('active', 'Active'),
              ('revoked', 'Revoked'),
              (null, 'All'),
            ])
              ChoiceChip(
                label: Text(label),
                selected: _status == value,
                onSelected: (_) {
                  _status = value;
                  _reload();
                },
              ),
            if (session.can(TgcgCapability.delegateAuthority))
              FilledButton.icon(
                onPressed: _delegate,
                icon: const Icon(Icons.call_split_rounded),
                label: const Text('Delegate authority'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<ApiPage<Delegation>>(
          future: _grants,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TgcgEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Delegations could not be loaded',
                message: failureMessage(snapshot.error!),
                action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
              );
            }
            final page = snapshot.data;
            if (page == null) return const LinearProgressIndicator();
            if (page.items.isEmpty) {
              return const TgcgEmptyState(
                icon: Icons.call_split_rounded,
                title: 'No delegated authority',
                message: 'Grants you make or receive, and those in your areas, appear here.',
              );
            }
            return Column(
              children: [
                for (final grant in page.items) _DelegationTile(grant: grant, onChanged: _reload),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _DelegationTile extends StatelessWidget {
  const _DelegationTile({required this.grant, required this.onChanged});

  final Delegation grant;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final powers = grant.permissions.where(adminPowers.contains).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: TgcgColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: TgcgColors.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () async {
            final changed = await showDialog<bool>(
              context: context,
              builder: (_) => DelegationDialog(grant: grant),
            );
            if (changed == true) onChanged();
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${grant.grantorName} → ${grant.recipientName}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$powers power${powers == 1 ? '' : 's'} · '
                        '${grant.areas.map(areaLabel).join('; ')}'
                        '${grant.canRedelegate ? ' · may delegate ${grant.depth} more level(s)' : ''}',
                        style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                TgcgStatusPill(
                  label: grant.state[0].toUpperCase() + grant.state.substring(1),
                  compact: true,
                  color: switch (grant.state) {
                    'active' => TgcgColors.success,
                    'scheduled' => TgcgColors.info,
                    'revoked' => TgcgColors.danger,
                    _ => TgcgColors.muted,
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A grant's details and history; revoke it where allowed. Pops true when
/// it changed.
class DelegationDialog extends StatefulWidget {
  const DelegationDialog({super.key, required this.grant});

  final Delegation grant;

  @override
  State<DelegationDialog> createState() => _DelegationDialogState();
}

class _DelegationDialogState extends State<DelegationDialog> {
  late Delegation grant = widget.grant;
  late Future<List<AuditEntry>> history;
  bool changed = false;
  bool busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    history = TgcgBackend.of(context)!.access.delegationHistory(grant.id);
  }

  Future<void> _revoke() async {
    final reason = await promptText(
      context,
      title: 'Revoke this delegation?',
      message:
          'The recipient loses these powers at once. Grants and appointments they made '
          'from it stay valid until they are revoked or expire themselves.',
      label: 'Why it is revoked',
      action: 'Revoke',
      required: true,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    final access = TgcgBackend.of(context)!.access;
    setState(() => busy = true);
    try {
      final updated = await access.revokeDelegation(grant.id, reason);
      if (!mounted) return;
      setState(() {
        grant = updated;
        changed = true;
        history = access.delegationHistory(updated.id);
      });
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Delegation to ${grant.recipientName}'),
    content: SizedBox(
      width: 560,
      child: FutureBuilder<Map<String, PermissionInfo>>(
        future: PermissionRegistry.of(context),
        builder: (context, snapshot) {
          final registry = snapshot.data ?? const {};
          final powers = grant.permissions.where(adminPowers.contains).toList()..sort();
          final ceiling = grant.permissions.where((p) => !adminPowers.contains(p)).toList()..sort();
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'From ${grant.grantorName} (${grant.grantor}) to ${grant.recipientName} '
                  '(${grant.recipient}).',
                ),
                const SizedBox(height: 10),
                AreaChips(grant.areas),
                const SizedBox(height: 10),
                _Fact('Powers', powers.map((p) => permissionLabel(p, registry)).join(', ')),
                _Fact(
                  'Ceiling',
                  ceiling.isEmpty
                      ? 'Administrative powers only'
                      : ceiling.map((p) => permissionLabel(p, registry)).join(', '),
                ),
                _Fact('Role categories', grant.categories.map(roleCategoryLabel).join(', ')),
                _Fact('Levels', grant.levels.map(geographyLevelLabel).join(', ')),
                _Fact(
                  'Further delegation',
                  grant.canRedelegate ? '${grant.depth} more level(s)' : 'Not allowed',
                ),
                _Fact('Starts', formatMoment(grant.startsAt)),
                _Fact('Ends', grant.endsAt == null ? 'No end date' : formatMoment(grant.endsAt!)),
                if (grant.reason.isNotEmpty) _Fact('Why', grant.reason),
                if (grant.isRevoked) _Fact('Revoked because', grant.revokeReason),
                const SizedBox(height: 14),
                const Text('History', style: TextStyle(fontWeight: FontWeight.w800)),
                FutureBuilder<List<AuditEntry>>(
                  future: history,
                  builder: (context, events) {
                    if (events.hasError) return Text(failureMessage(events.error!));
                    final items = events.data;
                    if (items == null) return const LinearProgressIndicator();
                    return Column(children: [for (final event in items) AuditLine(event)]);
                  },
                ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      if (!grant.isRevoked)
        TextButton(
          onPressed: busy ? null : _revoke,
          style: TextButton.styleFrom(foregroundColor: TgcgColors.danger),
          child: const Text('Revoke'),
        ),
      FilledButton(onPressed: () => Navigator.pop(context, changed), child: const Text('Close')),
    ],
  );
}

class _Fact extends StatelessWidget {
  const _Fact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 140,
          child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

/// Pass on administrative powers within the caller's own authority. Pops the
/// new grant; the server refuses anything beyond that authority.
class DelegateDialog extends StatefulWidget {
  const DelegateDialog({super.key});

  @override
  State<DelegateDialog> createState() => _DelegateDialogState();
}

class _DelegateDialogState extends State<DelegateDialog> {
  final _recipient = TextEditingController();
  String? _recipientName;
  final _reason = TextEditingController();
  final _permissions = <String>{'assignRoles'};
  final _categories = <RoleCategory>{};
  final _levels = <GeographyLevel>{};
  final _areas = <GeographicScope>[];
  int _depth = 0;
  DateTime? _endsAt;
  bool _saving = false;
  Map<String, List<String>> _errors = const {};

  bool get _redelegates => _permissions.contains('delegateAuthority');

  @override
  void dispose() {
    _recipient.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _find() async {
    final found = await showDialog<StaffMember>(
      context: context,
      builder: (_) => const MemberSearchDialog(verifiedOnly: true),
    );
    if (found != null) {
      setState(() {
        _recipient.text = found.membershipNumber;
        _recipientName = found.fullName;
      });
    }
  }

  Future<void> _addArea() async {
    final area = await pickArea(context, levels: GeographyLevel.values);
    if (area != null && !_areas.any((item) => areaLabel(item) == areaLabel(area))) {
      setState(() => _areas.add(area));
    }
  }

  Future<void> _submit() async {
    final local = <String, List<String>>{
      if (_recipient.text.trim().isEmpty) 'recipient': ['Enter the membership number.'],
      if (!_permissions.any(adminPowers.contains))
        'permissions': ['Choose at least one power to pass on.'],
      if (_categories.isEmpty) 'categories': ['Choose the role categories it covers.'],
      if (_levels.isEmpty) 'levels': ['Choose the levels it covers.'],
      if (_areas.isEmpty) 'areas': ['Add at least one area.'],
      if (_redelegates && _depth < 1) 'depth': ['Allow at least one more level.'],
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      return;
    }
    final draft = DelegationDraft(
      recipient: _recipient.text,
      permissions: _permissions,
      categories: _categories,
      levels: _levels,
      areas: _areas,
      canRedelegate: _redelegates,
      depth: _redelegates ? _depth : 0,
      endsAt: _endsAt,
      reason: _reason.text,
    );
    final who = _recipientName ?? draft.recipient.toUpperCase();
    final confirmed = await confirmAction(
      context,
      title: 'Delegate to $who?',
      message:
          '$who may use these powers in ${_areas.map(areaLabel).join('; ')}'
          '${_endsAt == null ? '' : ' until ${formatDay(_endsAt!)}'}. You or anyone above you '
          'can revoke it; what they make from it stays until revoked itself.',
      action: 'Delegate',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final made = await TgcgBackend.of(context)!.access.delegate(draft);
      if (mounted) Navigator.pop(context, made);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors = error is ApiException ? error.fieldErrors : const {});
      showFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _error(String field) => _errors[field] == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _errors[field]!.first,
            style: const TextStyle(color: TgcgColors.danger, fontSize: 12),
          ),
        );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Delegate authority'),
    content: SizedBox(
      width: 640,
      child: FutureBuilder<Map<String, PermissionInfo>>(
        future: PermissionRegistry.of(context),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(failureMessage(snapshot.error!));
          final registry = snapshot.data;
          if (registry == null) return const LinearProgressIndicator();
          final powers = [
            for (final code in adminPowers)
              if (registry[code] case final PermissionInfo info) info,
          ]..sort((a, b) => a.label.compareTo(b.label));
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _recipient,
                        textCapitalization: TextCapitalization.characters,
                        onChanged: (_) => setState(() => _recipientName = null),
                        decoration: InputDecoration(
                          labelText: 'Recipient\'s membership number',
                          helperText: _recipientName,
                          border: const OutlineInputBorder(),
                          errorText: _errors['recipient']?.first,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: OutlinedButton.icon(
                        onPressed: _find,
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('Find'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Powers to pass on', style: TextStyle(fontWeight: FontWeight.w800)),
                _error('permissions'),
                for (final info in powers)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _permissions.contains(info.code),
                    title: Text(info.label),
                    onChanged: (on) => setState(
                      () =>
                          on == true ? _permissions.add(info.code) : _permissions.remove(info.code),
                    ),
                  ),
                if (_redelegates)
                  Row(
                    children: [
                      const Expanded(child: Text('Further levels of delegation allowed')),
                      IconButton(
                        onPressed: _depth > 1 ? () => setState(() => _depth--) : null,
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$_depth', style: const TextStyle(fontWeight: FontWeight.w800)),
                      IconButton(
                        onPressed: _depth < 10 ? () => setState(() => _depth++) : null,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                    ],
                  ),
                _error('depth'),
                _error('can_redelegate'),
                const SizedBox(height: 10),
                const Text(
                  'Ceiling: the permissions the roles they create or appoint to may hold',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                PermissionPicker(
                  registry: {
                    for (final entry in registry.entries)
                      if (!adminPowers.contains(entry.key)) entry.key: entry.value,
                  },
                  selected: _permissions,
                  onChanged: () => setState(() {}),
                ),
                const SizedBox(height: 12),
                const Text('Role categories', style: TextStyle(fontWeight: FontWeight.w800)),
                _error('categories'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final category in RoleCategory.values)
                      FilterChip(
                        label: Text(roleCategoryLabel(category)),
                        selected: _categories.contains(category),
                        onSelected: (on) => setState(
                          () => on ? _categories.add(category) : _categories.remove(category),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Levels', style: TextStyle(fontWeight: FontWeight.w800)),
                _error('levels'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final level in GeographyLevel.values)
                      FilterChip(
                        label: Text(geographyLevelLabel(level)),
                        selected: _levels.contains(level),
                        onSelected: (on) =>
                            setState(() => on ? _levels.add(level) : _levels.remove(level)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Areas', style: TextStyle(fontWeight: FontWeight.w800)),
                    ),
                    TextButton.icon(
                      onPressed: _addArea,
                      icon: const Icon(Icons.add_location_alt_outlined),
                      label: const Text('Add area'),
                    ),
                  ],
                ),
                _error('areas'),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final area in _areas)
                      InputChip(
                        label: Text(areaLabel(area)),
                        onDeleted: () => setState(() => _areas.remove(area)),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: now,
                          lastDate: DateTime(now.year + 5),
                          initialDate: _endsAt ?? now.add(const Duration(days: 90)),
                        );
                        if (picked != null) setState(() => _endsAt = picked);
                      },
                      icon: const Icon(Icons.event_busy_outlined),
                      label: Text(_endsAt == null ? 'No end date' : 'Ends ${formatDay(_endsAt!)}'),
                    ),
                    if (_endsAt != null)
                      TextButton(
                        onPressed: () => setState(() => _endsAt = null),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                _error('ends_at'),
                const SizedBox(height: 12),
                TextField(
                  controller: _reason,
                  decoration: const InputDecoration(
                    labelText: 'Why (for the record)',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _saving ? null : _submit, child: const Text('Review and delegate')),
    ],
  );
}
