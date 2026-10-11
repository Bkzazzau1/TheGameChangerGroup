import 'dart:async';

import 'package:flutter/material.dart';

import '../api/access_repository.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'access_widgets.dart';
import 'roles_tab.dart';

const _statuses = ['active', 'suspended', 'declined', 'resigned', 'revoked'];

/// Appointments in the caller's areas, and those they supervise.
class AppointmentsTab extends StatefulWidget {
  const AppointmentsTab({super.key});

  @override
  State<AppointmentsTab> createState() => _AppointmentsTabState();
}

class _AppointmentsTabState extends State<AppointmentsTab> {
  final _search = TextEditingController();
  String? _status = 'active';
  Future<ApiPage<Appointment>>? _appointments;
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _appointments ??= _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<ApiPage<Appointment>> _load() =>
      TgcgBackend.of(context)!.access.appointments(search: _search.text, status: _status);

  void _reload() => setState(() {
    _appointments = _load();
  });

  Future<void> _appoint() async {
    final made = await showDialog<Appointment>(
      context: context,
      builder: (_) => const AppointDialog(),
    );
    if (made != null && mounted) {
      showDone(context, '${made.memberName} appointed ${made.roleName}.');
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
                  labelText: 'Member, number or role',
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
              width: 200,
              child: DropdownButtonFormField<String?>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Status',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Any status')),
                  for (final status in _statuses)
                    DropdownMenuItem(
                      value: status,
                      child: Text(appointmentStateLabel(AppointmentState.values.byName(status))),
                    ),
                ],
                onChanged: (value) {
                  _status = value;
                  _reload();
                },
              ),
            ),
            if (session.can(TgcgCapability.assignRoles))
              FilledButton.icon(
                onPressed: _appoint,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Appoint a member'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        FutureBuilder<ApiPage<Appointment>>(
          future: _appointments,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TgcgEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Appointments could not be loaded',
                message: failureMessage(snapshot.error!),
                action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
              );
            }
            final page = snapshot.data;
            if (page == null) return const LinearProgressIndicator();
            if (page.items.isEmpty) {
              return const TgcgEmptyState(
                icon: Icons.assignment_ind_outlined,
                title: 'No appointments here',
                message: 'Appointments in your areas, and those you supervise, appear here.',
              );
            }
            return Column(
              children: [
                for (final appointment in page.items)
                  AppointmentTile(appointment: appointment, onChanged: _reload),
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

class AppointmentTile extends StatelessWidget {
  const AppointmentTile({super.key, required this.appointment, required this.onChanged});

  final Appointment appointment;
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
            builder: (_) => AppointmentDialog(appointment: appointment),
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
                      '${appointment.memberName} · ${appointment.roleName}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${appointment.member} · '
                      '${appointment.areas.map(areaLabel).join('; ')}',
                      style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
                    ),
                    if (appointment.endsAt != null)
                      Text(
                        'Until ${formatDay(appointment.endsAt!)}',
                        style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              appointmentStatePill(appointment.state),
            ],
          ),
        ),
      ),
    ),
  );
}

/// An appointment's details, history and the actions open to the caller.
/// Pops true when it changed.
class AppointmentDialog extends StatefulWidget {
  const AppointmentDialog({super.key, required this.appointment});

  final Appointment appointment;

  @override
  State<AppointmentDialog> createState() => _AppointmentDialogState();
}

class _AppointmentDialogState extends State<AppointmentDialog> {
  late Appointment appointment = widget.appointment;
  late Future<List<AuditEntry>> history;
  bool changed = false;
  bool busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    history = TgcgBackend.of(context)!.access.appointmentHistory(appointment.id);
  }

  Future<void> _run(Future<Appointment> Function(AccessRepository access) action) async {
    final access = TgcgBackend.of(context)!.access;
    setState(() => busy = true);
    try {
      final updated = await action(access);
      if (!mounted) return;
      setState(() {
        appointment = updated;
        changed = true;
        history = access.appointmentHistory(updated.id);
      });
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _suspend() async {
    final reason = await promptText(
      context,
      title: 'Suspend this appointment?',
      message: 'Its access stops at once. The member\'s other appointments are not affected.',
      label: 'Why it is suspended',
      action: 'Suspend',
      required: true,
      destructive: true,
    );
    if (reason != null) await _run((access) => access.suspendAppointment(appointment.id, reason));
  }

  Future<void> _reactivate() async {
    final reason = await promptText(
      context,
      title: 'Reactivate this appointment?',
      label: 'Note',
      action: 'Reactivate',
    );
    if (reason != null) {
      await _run((access) => access.reactivateAppointment(appointment.id, reason: reason));
    }
  }

  Future<void> _revoke() async {
    final reason = await promptText(
      context,
      title: 'Revoke this appointment?',
      message: 'This ends it for good. It stays on record.',
      label: 'Why it is revoked',
      action: 'Revoke',
      required: true,
      destructive: true,
    );
    if (reason != null) await _run((access) => access.revokeAppointment(appointment.id, reason));
  }

  Future<void> _restrict() async {
    final access = TgcgBackend.of(context)!.access;
    final RoleDefinition role;
    try {
      role = await access.role(appointment.role);
    } catch (error) {
      if (mounted) showFailure(context, error);
      return;
    }
    if (!mounted) return;
    final choice = await showDialog<_Restriction>(
      context: context,
      builder: (_) => _RestrictDialog(role: role, current: appointment.restrictedPermissions),
    );
    if (choice != null) {
      await _run((access) => access.restrictAppointment(appointment.id, choice.permissions));
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final own = appointment.member == session.membershipNumber;
    final canManage = session.can(TgcgCapability.manageAssignments);
    final live =
        appointment.state != AppointmentState.declined &&
        appointment.state != AppointmentState.resigned &&
        appointment.state != AppointmentState.revoked;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text('${appointment.memberName} · ${appointment.roleName}')),
          appointmentStatePill(appointment.state),
        ],
      ),
      content: SizedBox(
        width: 560,
        child: FutureBuilder<Map<String, PermissionInfo>>(
          future: PermissionRegistry.of(context),
          builder: (context, registrySnapshot) {
            final registry = registrySnapshot.data ?? const {};
            return SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(appointment.member, style: const TextStyle(color: TgcgColors.muted)),
                  const SizedBox(height: 12),
                  AreaChips(appointment.areas),
                  const SizedBox(height: 12),
                  _Line('Starts', formatMoment(appointment.startsAt)),
                  _Line(
                    'Ends',
                    appointment.endsAt == null ? 'No end date' : formatMoment(appointment.endsAt!),
                  ),
                  if (appointment.grantedBy != null) _Line('Appointed by', appointment.grantedBy!),
                  _Line('Reports to', appointment.supervisingRole ?? 'No one'),
                  _Line(
                    'Accepted',
                    appointment.acceptedAt == null
                        ? 'Not yet'
                        : formatMoment(appointment.acceptedAt!),
                  ),
                  if (appointment.statusReason.isNotEmpty)
                    _Line('Last change', appointment.statusReason),
                  const SizedBox(height: 12),
                  Text(
                    appointment.restrictedPermissions == null
                        ? 'Permissions (all of the role\'s)'
                        : 'Permissions (restricted)',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final code in appointment.permissions.toList()..sort())
                        Chip(
                          label: Text(
                            permissionLabel(code, registry),
                            style: const TextStyle(fontSize: 12),
                          ),
                          visualDensity: VisualDensity.compact,
                        ),
                      if (appointment.permissions.isEmpty)
                        const Text(
                          'None: the restriction leaves nothing.',
                          style: TextStyle(color: TgcgColors.muted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('History', style: TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  FutureBuilder<List<AuditEntry>>(
                    future: history,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) return Text(failureMessage(snapshot.error!));
                      final events = snapshot.data;
                      if (events == null) return const LinearProgressIndicator();
                      return Column(children: [for (final event in events) AuditLine(event)]);
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
      actions: [
        if (!own && appointment.state == AppointmentState.active)
          TextButton(onPressed: busy ? null : _suspend, child: const Text('Suspend')),
        if (!own && appointment.state == AppointmentState.suspended)
          TextButton(onPressed: busy ? null : _reactivate, child: const Text('Reactivate')),
        if (!own && canManage && live)
          TextButton(onPressed: busy ? null : _restrict, child: const Text('Restrict')),
        if (!own && canManage && live)
          TextButton(
            onPressed: busy ? null : _revoke,
            style: TextButton.styleFrom(foregroundColor: TgcgColors.danger),
            child: const Text('Revoke'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context, changed), child: const Text('Close')),
      ],
    );
  }
}

class _Restriction {
  const _Restriction(this.permissions);

  /// Null lifts the restriction.
  final List<String>? permissions;
}

class _RestrictDialog extends StatefulWidget {
  const _RestrictDialog({required this.role, required this.current});

  final RoleDefinition role;
  final List<String>? current;

  @override
  State<_RestrictDialog> createState() => _RestrictDialogState();
}

class _RestrictDialogState extends State<_RestrictDialog> {
  late final Set<String> selected = {...(widget.current ?? widget.role.permissions)};

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Restrict this appointment'),
    content: SizedBox(
      width: 520,
      child: FutureBuilder<Map<String, PermissionInfo>>(
        future: PermissionRegistry.of(context),
        builder: (context, snapshot) {
          final registry = snapshot.data;
          if (registry == null) return const LinearProgressIndicator();
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Keep only some of the role\'s permissions for this one member. A '
                  'restriction can only take permissions away; giving them back needs '
                  'authority to appoint.',
                  style: TextStyle(color: TgcgColors.muted, height: 1.4),
                ),
                const SizedBox(height: 8),
                PermissionPicker(
                  registry: registry,
                  selected: selected,
                  only: widget.role.permissions,
                  onChanged: () => setState(() {}),
                ),
              ],
            ),
          );
        },
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      if (widget.current != null)
        TextButton(
          onPressed: () => Navigator.pop(context, const _Restriction(null)),
          child: const Text('Lift restriction'),
        ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _Restriction(selected.toList()..sort())),
        child: const Text('Save'),
      ),
    ],
  );
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5)),
        ),
        Expanded(
          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      ],
    ),
  );
}

String _actionLabel(String action) => switch (action) {
  'assignment.created' => 'Appointed',
  'assignment.accepted' => 'Accepted',
  'assignment.declined' => 'Declined',
  'assignment.resigned' => 'Resigned',
  'assignment.suspended' => 'Suspended',
  'assignment.reactivated' => 'Reactivated',
  'assignment.revoked' => 'Revoked',
  'assignment.restricted' => 'Restriction changed',
  'delegation.created' => 'Delegated',
  'delegation.revoked' => 'Revoked',
  'administrator.recovered' => 'Appointed by the recovery procedure',
  _ => action,
};

/// One event of a history.
class AuditLine extends StatelessWidget {
  const AuditLine(this.event, {super.key});

  final AuditEntry event;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 3),
          child: Icon(Icons.circle, size: 8, color: TgcgColors.primaryMid),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_actionLabel(event.action)} by ${event.actor}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                formatMoment(event.createdAt) + (event.reason.isEmpty ? '' : ' · ${event.reason}'),
                style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// Appoint a verified member to a role over one or more areas. Pops the new
/// appointment. Everything is checked again by the server.
class AppointDialog extends StatefulWidget {
  const AppointDialog({super.key, this.member, this.memberName});

  /// Preselected membership number.
  final String? member;
  final String? memberName;

  @override
  State<AppointDialog> createState() => _AppointDialogState();
}

class _AppointDialogState extends State<AppointDialog> {
  late final _member = TextEditingController(text: widget.member ?? '');
  late String? _memberName = widget.memberName;
  final _reason = TextEditingController();
  Future<List<RoleDefinition>>? _roles;
  RoleDefinition? _role;
  final _areas = <GeographicScope>[];
  bool _restricted = false;
  final _keep = <String>{};
  DateTime? _startsAt;
  DateTime? _endsAt;
  bool _saving = false;
  Map<String, List<String>> _errors = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _roles ??= TgcgBackend.of(context)!.access.roles(archived: false).then((page) => page.items);
  }

  @override
  void dispose() {
    _member.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _findMember() async {
    final found = await showDialog<StaffMember>(
      context: context,
      builder: (_) => const MemberSearchDialog(verifiedOnly: true),
    );
    if (found != null) {
      setState(() {
        _member.text = found.membershipNumber;
        _memberName = found.fullName;
      });
    }
  }

  Future<void> _addArea() async {
    final role = _role;
    if (role == null) return;
    final area = await pickArea(context, levels: role.permittedLevels);
    if (area == null) return;
    final key = areaLabel(area);
    if (_areas.any((item) => areaLabel(item) == key)) return;
    setState(() => _areas.add(area));
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      initialDate: (start ? _startsAt : _endsAt) ?? now,
    );
    if (picked != null) {
      setState(() => start ? _startsAt = picked : _endsAt = picked);
    }
  }

  Future<void> _submit() async {
    final role = _role;
    final local = <String, List<String>>{
      if (_member.text.trim().isEmpty) 'member': ['Enter the membership number.'],
      if (role == null) 'role': ['Choose a role.'],
      if (_areas.isEmpty) 'areas': ['Add at least one area.'],
    };
    if (local.isNotEmpty || role == null) {
      setState(() => _errors = local);
      return;
    }
    final who = _memberName ?? _member.text.trim().toUpperCase();
    final confirmed = await confirmAction(
      context,
      title: 'Appoint $who?',
      message:
          '$who becomes ${role.name} for ${_areas.map(areaLabel).join('; ')}'
          '${_startsAt == null ? ', starting now' : ', from ${formatDay(_startsAt!)}'}'
          '${_endsAt == null ? '' : ' until ${formatDay(_endsAt!)}'}.'
          '${_restricted ? ' Limited to ${_keep.length} of the role\'s permissions.' : ''}',
      action: 'Appoint',
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _saving = true;
      _errors = const {};
    });
    try {
      final made = await TgcgBackend.of(context)!.access.appoint(
        member: _member.text,
        role: role.code,
        areas: _areas,
        restrictedPermissions: _restricted ? (_keep.toList()..sort()) : null,
        startsAt: _startsAt,
        endsAt: _endsAt,
        reason: _reason.text,
      );
      if (mounted) Navigator.pop(context, made);
    } catch (error) {
      if (!mounted) return;
      setState(() => _errors = error is ApiException ? error.fieldErrors : const {});
      showFailure(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Appoint a member'),
    content: SizedBox(
      width: 600,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Only members with a verified identity and an active membership can be '
              'appointed, and only within your own authority.',
              style: TextStyle(color: TgcgColors.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _member,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() => _memberName = null),
                    decoration: InputDecoration(
                      labelText: 'Membership number',
                      hintText: 'TGCG-000123',
                      helperText: _memberName,
                      border: const OutlineInputBorder(),
                      errorText: _errors['member']?.first,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    onPressed: _findMember,
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('Find'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<RoleDefinition>>(
              future: _roles,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(failureMessage(snapshot.error!));
                final roles = snapshot.data;
                if (roles == null) return const LinearProgressIndicator();
                return DropdownButtonFormField<RoleDefinition>(
                  initialValue: _role,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Role',
                    border: const OutlineInputBorder(),
                    errorText: _errors['role']?.first,
                  ),
                  items: [
                    for (final role in roles) DropdownMenuItem(value: role, child: Text(role.name)),
                  ],
                  onChanged: (value) => setState(() {
                    _role = value;
                    _areas.clear();
                    _keep
                      ..clear()
                      ..addAll(value?.permissions ?? const {});
                  }),
                );
              },
            ),
            if (_role != null) ...[
              const SizedBox(height: 14),
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
              if (_errors['areas'] != null)
                Text(
                  _errors['areas']!.first,
                  style: const TextStyle(color: TgcgColors.danger, fontSize: 12),
                ),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final area in _areas)
                    InputChip(
                      label: Text(areaLabel(area)),
                      onDeleted: () => setState(() => _areas.remove(area)),
                    ),
                  if (_areas.isEmpty)
                    Text(
                      '${_role!.name} is assigned at '
                      '${_role!.permittedLevels.map(geographyLevelLabel).join(', ')} level.',
                      style: const TextStyle(color: TgcgColors.muted),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Limit to some of the role\'s permissions'),
                value: _restricted,
                onChanged: (value) => setState(() => _restricted = value),
              ),
              if (_restricted)
                FutureBuilder<Map<String, PermissionInfo>>(
                  future: PermissionRegistry.of(context),
                  builder: (context, snapshot) {
                    final registry = snapshot.data;
                    if (registry == null) return const LinearProgressIndicator();
                    return PermissionPicker(
                      registry: registry,
                      selected: _keep,
                      only: _role!.permissions,
                      onChanged: () => setState(() {}),
                    );
                  },
                ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(start: true),
                    icon: const Icon(Icons.event_outlined),
                    label: Text(
                      _startsAt == null ? 'Starts now' : 'Starts ${formatDay(_startsAt!)}',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(start: false),
                    icon: const Icon(Icons.event_busy_outlined),
                    label: Text(_endsAt == null ? 'No end date' : 'Ends ${formatDay(_endsAt!)}'),
                  ),
                  if (_endsAt != null)
                    TextButton(
                      onPressed: () => setState(() => _endsAt = null),
                      child: const Text('Clear end date'),
                    ),
                ],
              ),
              if (_errors['ends_at'] != null)
                Text(
                  _errors['ends_at']!.first,
                  style: const TextStyle(color: TgcgColors.danger, fontSize: 12),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                decoration: const InputDecoration(
                  labelText: 'Note for the record (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _saving ? null : _submit, child: const Text('Review and appoint')),
    ],
  );
}

/// Find a member in the caller's areas. Pops the chosen member.
class MemberSearchDialog extends StatefulWidget {
  const MemberSearchDialog({super.key, this.verifiedOnly = false});

  final bool verifiedOnly;

  @override
  State<MemberSearchDialog> createState() => _MemberSearchDialogState();
}

class _MemberSearchDialogState extends State<MemberSearchDialog> {
  final _query = TextEditingController();
  Future<ApiPage<StaffMember>>? _results;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search() => setState(() {
    _results = _query.text.trim().length < 2
        ? null
        : TgcgBackend.of(context)!.members.members(
            search: _query.text,
            verificationStatus: widget.verifiedOnly ? 'verified' : null,
            membershipState: 'active',
          );
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.verifiedOnly ? 'Find a verified member' : 'Find a member'),
    content: SizedBox(
      width: 480,
      height: 420,
      child: Column(
        children: [
          TextField(
            controller: _query,
            autofocus: true,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              labelText: 'Name or membership number',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              _debounce?.cancel();
              _debounce = Timer(const Duration(milliseconds: 350), _search);
            },
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _results == null
                ? const Center(
                    child: Text(
                      'Type at least two letters.',
                      style: TextStyle(color: TgcgColors.muted),
                    ),
                  )
                : FutureBuilder<ApiPage<StaffMember>>(
                    future: _results,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        final error = snapshot.error!;
                        return Center(
                          child: Text(
                            error is ApiException && error.statusCode == 403
                                ? 'You cannot search members. Enter the membership number '
                                      'instead.'
                                : failureMessage(error),
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      final page = snapshot.data;
                      if (page == null) return const LinearProgressIndicator();
                      if (page.items.isEmpty) {
                        return const Center(child: Text('No members found.'));
                      }
                      return ListView(
                        children: [
                          for (final member in page.items)
                            ListTile(
                              leading: const Icon(Icons.person_outline_rounded),
                              title: Text(member.fullName),
                              subtitle: Text(
                                '${member.membershipNumber} · ${areaLabel(member.scope)}',
                              ),
                              onTap: () => Navigator.pop(context, member),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
  );
}
