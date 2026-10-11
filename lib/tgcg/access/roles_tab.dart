import 'dart:async';

import 'package:flutter/material.dart';

import '../api/access_repository.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'access_widgets.dart';

/// Every role the caller can see: search, filter, inspect, create, edit,
/// archive and restore. The server decides who may change which role.
class RolesTab extends StatefulWidget {
  const RolesTab({super.key});

  @override
  State<RolesTab> createState() => _RolesTabState();
}

class _RolesTabState extends State<RolesTab> {
  final _search = TextEditingController();
  RoleCategory? _category;
  bool _archived = false;
  Future<ApiPage<RoleDefinition>>? _roles;
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _roles ??= _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<ApiPage<RoleDefinition>> _load() => TgcgBackend.of(
    context,
  )!.access.roles(search: _search.text, category: _category, archived: _archived);

  void _reload() => setState(() {
    _roles = _load();
  });

  Future<void> _create() async {
    final created = await showDialog<RoleDefinition>(
      context: context,
      builder: (_) => const RoleEditorDialog(),
    );
    if (created != null && mounted) {
      showDone(context, '${created.name} created.');
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 280,
              child: TextField(
                controller: _search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Search roles',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), _reload);
                },
              ),
            ),
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<RoleCategory?>(
                initialValue: _category,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All categories')),
                  for (final category in RoleCategory.values)
                    DropdownMenuItem(value: category, child: Text(roleCategoryLabel(category))),
                ],
                onChanged: (value) {
                  _category = value;
                  _reload();
                },
              ),
            ),
            FilterChip(
              label: const Text('Archived'),
              selected: _archived,
              onSelected: (value) {
                _archived = value;
                _reload();
              },
            ),
            if (session.can(TgcgCapability.manageRoles))
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New role'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<ApiPage<RoleDefinition>>(
          future: _roles,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TgcgEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Roles could not be loaded',
                message: failureMessage(snapshot.error!),
                action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
              );
            }
            final page = snapshot.data;
            if (page == null) return const LinearProgressIndicator();
            if (page.items.isEmpty) {
              return TgcgEmptyState(
                icon: Icons.badge_outlined,
                title: _archived ? 'No archived roles' : 'No roles found',
                message: 'Change the search or the filters.',
              );
            }
            return Column(
              children: [
                for (final role in page.items) _RoleCard(role: role, onChanged: _reload),
                if (page.hasMore)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'Showing ${page.items.length} of ${page.count}. Search to narrow the list.',
                      style: const TextStyle(color: TgcgColors.muted),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.role, required this.onChanged});

  final RoleDefinition role;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => Padding(
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
            builder: (_) => RoleDetailDialog(role: role),
          );
          if (changed != false) onChanged();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: TgcgColors.primarySoft,
                child: Icon(
                  role.isProtected
                      ? Icons.admin_panel_settings_rounded
                      : role.grantsAdminPowers
                      ? Icons.manage_accounts_rounded
                      : Icons.badge_outlined,
                  color: TgcgColors.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      role.name,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${roleCategoryLabel(role.category)} · '
                      '${role.permittedLevels.map(geographyLevelLabel).join(', ')} · '
                      '${role.permissions.length} permissions',
                      style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    // Under the text, so a phone keeps the name readable.
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (role.archived)
                          const TgcgStatusPill(
                            label: 'Archived',
                            color: TgcgColors.muted,
                            compact: true,
                          ),
                        if (role.isSystem)
                          const TgcgStatusPill(
                            label: 'System',
                            color: TgcgColors.primaryMid,
                            compact: true,
                          ),
                        TgcgStatusPill(
                          label: '${role.activeAssignments} active',
                          color: TgcgColors.success,
                          compact: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// A role's details and the actions open to the caller. Pops true when the
/// role changed.
class RoleDetailDialog extends StatefulWidget {
  const RoleDetailDialog({super.key, required this.role});

  final RoleDefinition role;

  @override
  State<RoleDetailDialog> createState() => _RoleDetailDialogState();
}

class _RoleDetailDialogState extends State<RoleDetailDialog> {
  late RoleDefinition role = widget.role;
  bool changed = false;
  bool busy = false;

  Future<void> _run(Future<RoleDefinition> Function() action, String done) async {
    setState(() => busy = true);
    try {
      final updated = await action();
      if (!mounted) return;
      setState(() {
        role = updated;
        changed = true;
      });
      showDone(context, done);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _edit() async {
    final updated = await showDialog<RoleDefinition>(
      context: context,
      builder: (_) => RoleEditorDialog(role: role),
    );
    if (updated != null && mounted) {
      setState(() {
        role = updated;
        changed = true;
      });
    }
  }

  Future<void> _archive() async {
    final reason = await promptText(
      context,
      title: 'Archive ${role.name}?',
      message:
          'Its ${role.activeAssignments} active appointments stop granting access at once. '
          'They stay on record, and the role can be restored.',
      label: 'Why it is archived',
      action: 'Archive',
      required: true,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    final access = TgcgBackend.of(context)!.access;
    await _run(() => access.archiveRole(role.code, reason), '${role.name} archived.');
  }

  Future<void> _restore() async {
    final access = TgcgBackend.of(context)!.access;
    await _run(() => access.restoreRole(role.code), '${role.name} restored.');
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final canManage = session.can(TgcgCapability.manageRoles);
    return AlertDialog(
      title: Text(role.name),
      content: SizedBox(
        width: 560,
        child: FutureBuilder<Map<String, PermissionInfo>>(
          future: PermissionRegistry.of(context),
          builder: (context, snapshot) {
            final registry = snapshot.data ?? const {};
            final byModule = <String, List<String>>{};
            for (final code in role.permissions) {
              byModule.putIfAbsent(registry[code]?.module ?? 'other', () => []).add(code);
            }
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (role.description.isNotEmpty) ...[
                    Text(role.description, style: const TextStyle(height: 1.4)),
                    const SizedBox(height: 12),
                  ],
                  _Fact('Category', roleCategoryLabel(role.category)),
                  _Fact('Assigned at', role.permittedLevels.map(geographyLevelLabel).join(', ')),
                  _Fact('Reports to', role.supervisingRole ?? 'No one'),
                  _Fact('Active appointments', '${role.activeAssignments}'),
                  if (role.createdBy != null) _Fact('Created by', role.createdBy!),
                  if (role.archived) _Fact('Archived because', role.archiveReason),
                  if (role.isProtected)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'National Administrators are appointed only by another, and '
                        'suspended or removed only with two administrators\' approval.',
                        style: TextStyle(color: TgcgColors.muted, height: 1.4),
                      ),
                    ),
                  const SizedBox(height: 16),
                  const Text('Permissions', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  for (final entry in byModule.entries) ...[
                    Text(
                      _moduleLabel(entry.key),
                      style: const TextStyle(
                        color: TgcgColors.primaryMid,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final code in entry.value..sort())
                          Chip(
                            label: Text(
                              permissionLabel(code, registry),
                              style: const TextStyle(fontSize: 12),
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        if (canManage && !role.isProtected && !role.archived)
          TextButton.icon(
            onPressed: busy ? null : _edit,
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit'),
          ),
        if (canManage && !role.isSystem && !role.archived)
          TextButton.icon(
            onPressed: busy ? null : _archive,
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Archive'),
          ),
        if (canManage && role.archived)
          TextButton.icon(
            onPressed: busy ? null : _restore,
            icon: const Icon(Icons.unarchive_outlined),
            label: const Text('Restore'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context, changed), child: const Text('Close')),
      ],
    );
  }
}

String _moduleLabel(String module) {
  final spaced = module.replaceAllMapped(RegExp('([A-Z])'), (m) => ' ${m[1]!.toLowerCase()}');
  return spaced.isEmpty ? module : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
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
          width: 160,
          child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

/// Create a role (no [role]) or edit one. Pops the saved role. Permissions
/// beyond the caller's authority are refused by the server.
class RoleEditorDialog extends StatefulWidget {
  const RoleEditorDialog({super.key, this.role});

  final RoleDefinition? role;

  @override
  State<RoleEditorDialog> createState() => _RoleEditorDialogState();
}

class _RoleEditorDialogState extends State<RoleEditorDialog> {
  late final _name = TextEditingController(text: widget.role?.name ?? '');
  late final _description = TextEditingController(text: widget.role?.description ?? '');
  late RoleCategory _category = widget.role?.category ?? RoleCategory.other;
  late final Set<GeographyLevel> _levels = {...?widget.role?.permittedLevels};
  late final Set<String> _permissions = {...?widget.role?.permissions};
  late String? _supervisor = widget.role?.supervisingRole;
  Future<List<RoleDefinition>>? _supervisors;
  bool _saving = false;
  Map<String, List<String>> _errors = const {};

  bool get _isSystem => widget.role?.isSystem ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _supervisors ??= TgcgBackend.of(context)!.access
        .roles(archived: false)
        .then((page) => page.items.where((item) => item.code != widget.role?.code).toList());
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final local = <String, List<String>>{
      if (_name.text.trim().isEmpty && !_isSystem) 'name': ['Give the role a name.'],
      if (_levels.isEmpty && !_isSystem) 'permitted_levels': ['Choose at least one level.'],
      if (_permissions.isEmpty && !_isSystem) 'permissions': ['Choose at least one permission.'],
    };
    if (local.isNotEmpty) {
      setState(() => _errors = local);
      return;
    }
    final draft = RoleDraft(
      name: _name.text,
      description: _description.text,
      category: _category,
      permittedLevels: [
        for (final level in GeographyLevel.values)
          if (_levels.contains(level)) level,
      ],
      permissions: _permissions,
      supervisingRole: _supervisor,
    );
    final confirmed = await confirmAction(
      context,
      title: widget.role == null ? 'Create ${draft.name.trim()}?' : 'Save ${draft.name.trim()}?',
      message: widget.role == null
          ? 'The role will hold ${draft.permissions.length} permissions. Nobody holds it until '
                'someone is appointed to it.'
          : 'Everyone appointed to this role gets the changed permissions at once.',
      action: widget.role == null ? 'Create' : 'Save',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    final access = TgcgBackend.of(context)!.access;
    try {
      final role = widget.role;
      final saved = role == null
          ? await access.createRole(draft)
          : await access.updateRole(
              role.code,
              _isSystem
                  ? {'description': draft.description, 'supervising_role': draft.supervisingRole}
                  : draft.toJson(),
            );
      if (mounted) Navigator.pop(context, saved);
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() => _errors = error is ApiException ? error.fieldErrors : const {});
      showFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.role == null ? 'New role' : 'Edit ${widget.role!.name}'),
    content: SizedBox(
      width: 620,
      child: FutureBuilder<Map<String, PermissionInfo>>(
        future: PermissionRegistry.of(context),
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(failureMessage(snapshot.error!));
          final registry = snapshot.data;
          if (registry == null) return const LinearProgressIndicator();
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isSystem)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'System roles keep their name, levels and permissions. You can change '
                      'the description and who it reports to.',
                      style: TextStyle(color: TgcgColors.muted, height: 1.4),
                    ),
                  ),
                TextField(
                  controller: _name,
                  enabled: !_isSystem,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    border: const OutlineInputBorder(),
                    errorText: _errors['name']?.first,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _description,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'What the role does',
                    border: const OutlineInputBorder(),
                    errorText: _errors['description']?.first,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<RoleCategory>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in RoleCategory.values)
                      DropdownMenuItem(value: category, child: Text(roleCategoryLabel(category))),
                  ],
                  onChanged: _isSystem
                      ? null
                      : (value) => setState(() => _category = value ?? _category),
                ),
                const SizedBox(height: 12),
                FutureBuilder<List<RoleDefinition>>(
                  future: _supervisors,
                  builder: (context, roles) {
                    final items = roles.data ?? const <RoleDefinition>[];
                    return DropdownButtonFormField<String?>(
                      initialValue: items.any((item) => item.code == _supervisor)
                          ? _supervisor
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Reports to',
                        helperText:
                            'Holders of that role can suspend and lift their own '
                            'suspensions of this role\'s appointments in their areas.',
                        helperMaxLines: 2,
                        border: const OutlineInputBorder(),
                        errorText: _errors['supervising_role']?.first,
                      ),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('No one')),
                        for (final item in items)
                          DropdownMenuItem(value: item.code, child: Text(item.name)),
                      ],
                      onChanged: (value) => setState(() => _supervisor = value),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _Label('Assigned at', error: _errors['permitted_levels']?.first),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final level in GeographyLevel.values)
                      FilterChip(
                        label: Text(geographyLevelLabel(level)),
                        selected: _levels.contains(level),
                        onSelected: _isSystem
                            ? null
                            : (on) =>
                                  setState(() => on ? _levels.add(level) : _levels.remove(level)),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _Label('Permissions', error: _errors['permissions']?.first),
                PermissionPicker(
                  registry: registry,
                  selected: _permissions,
                  enabled: !_isSystem,
                  onChanged: () => setState(() {}),
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
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(widget.role == null ? 'Create role' : 'Save'),
      ),
    ],
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text, {this.error});

  final String text;
  final String? error;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (error != null)
          Text(error!, style: const TextStyle(color: TgcgColors.danger, fontSize: 12)),
      ],
    ),
  );
}

/// Choose permissions, grouped by module. Protected permissions never
/// appear; administrative powers are marked, because passing them on is
/// delegation.
class PermissionPicker extends StatelessWidget {
  const PermissionPicker({
    super.key,
    required this.registry,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.only,
  });

  final Map<String, PermissionInfo> registry;
  final Set<String> selected;
  final VoidCallback onChanged;
  final bool enabled;

  /// Offer only these codes (e.g. a role's own permissions for a restriction).
  final Set<String>? only;

  @override
  Widget build(BuildContext context) {
    final byModule = <String, List<PermissionInfo>>{};
    for (final info in registry.values) {
      if (info.protected) continue;
      if (only != null && !only!.contains(info.code)) continue;
      byModule.putIfAbsent(info.module, () => []).add(info);
    }
    final modules = byModule.keys.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final module in modules) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Text(
              _moduleLabel(module),
              style: const TextStyle(
                color: TgcgColors.primaryMid,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          for (final info in byModule[module]!..sort((a, b) => a.label.compareTo(b.label)))
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: selected.contains(info.code),
              title: Text(info.label),
              subtitle: adminPowers.contains(info.code)
                  ? const Text('Administrative power: passing it on is delegation.')
                  : info.sensitive
                  ? const Text('Gives access to members\' personal details.')
                  : null,
              onChanged: enabled
                  ? (on) {
                      on == true ? selected.add(info.code) : selected.remove(info.code);
                      onChanged();
                    }
                  : null,
            ),
        ],
      ],
    );
  }
}
