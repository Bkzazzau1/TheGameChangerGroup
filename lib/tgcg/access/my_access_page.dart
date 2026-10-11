import 'package:flutter/material.dart';

import '../api/access_repository.dart';
import '../api/backend.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'access_widgets.dart';

/// Where the signed-in user's access comes from, and their own appointments:
/// accept, decline or resign each one on its own.
class MyAccessPage extends StatefulWidget {
  const MyAccessPage({super.key, this.showHeader = true});

  final bool showHeader;

  @override
  State<MyAccessPage> createState() => _MyAccessPageState();
}

class _MyAccessPageState extends State<MyAccessPage> {
  Future<List<Appointment>>? _appointments;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final services = TgcgBackend.of(context);
    final session = TgcgSession.of(context, listen: false);
    if (_appointments == null && services != null && session.membershipNumber != null) {
      _appointments = services.access.myAppointments();
    }
  }

  void _reload() => setState(() {
    _appointments = TgcgBackend.of(context)!.access.myAppointments();
  });

  Future<void> _act(
    Future<Appointment> Function(AccessRepository access) action,
    String done,
  ) async {
    final access = TgcgBackend.of(context)!.access;
    setState(() => _busy = true);
    try {
      await action(access);
      if (!mounted) return;
      showDone(context, done);
      _reload();
      await refreshOwnAccess(context);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline(Appointment item) async {
    final reason = await promptText(
      context,
      title: 'Decline ${item.roleName}?',
      message: 'You will not hold this role. Your other appointments are not affected.',
      label: 'Reason',
      action: 'Decline',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _act(
      (access) => access.declineAppointment(item.id, reason: reason),
      'You declined ${item.roleName}.',
    );
  }

  Future<void> _resign(Appointment item) async {
    final reason = await promptText(
      context,
      title: 'Resign as ${item.roleName}?',
      message:
          'Your access through this appointment stops at once. Your other appointments '
          'are not affected. A resignation cannot be undone; you would need to be appointed '
          'again.',
      label: 'Reason',
      action: 'Resign',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    await _act(
      (access) => access.resignAppointment(item.id, reason: reason),
      'You resigned as ${item.roleName}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final grants = session.grants;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (widget.showHeader) ...[
          TgcgPageHeader(
            eyebrow: 'MY ACCESS',
            title: session.operatorName.isEmpty ? 'My access' : session.operatorName,
            subtitle:
                'What you can do, and where, comes from each appointment you hold. Each '
                'keeps its own areas: a power in one area never carries into another.',
          ),
          const SizedBox(height: 16),
        ],
        if (session.isServerSession && session.isOperator)
          TgcgSectionCard(
            title: 'Where your access comes from',
            child: grants.isEmpty
                ? const Text(
                    'No active appointments or roles.',
                    style: TextStyle(color: TgcgColors.muted),
                  )
                : Column(children: [for (final grant in grants) _GrantTile(grant)]),
          ),
        if (_appointments != null) ...[
          const SizedBox(height: 16),
          TgcgSectionCard(
            title: 'My appointments',
            child: FutureBuilder<List<Appointment>>(
              future: _appointments,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(failureMessage(snapshot.error!));
                final items = snapshot.data;
                if (items == null) return const LinearProgressIndicator();
                if (items.isEmpty) {
                  return const Text(
                    'You have not been appointed to any role.',
                    style: TextStyle(color: TgcgColors.muted),
                  );
                }
                return Column(
                  children: [
                    for (final item in items)
                      _AppointmentCard(
                        item: item,
                        busy: _busy,
                        onAccept: () => _act(
                          (access) => access.acceptAppointment(item.id),
                          'You accepted ${item.roleName}.',
                        ),
                        onDecline: () => _decline(item),
                        onResign: () => _resign(item),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _GrantTile extends StatelessWidget {
  const _GrantTile(this.grant);

  final AccessGrant grant;

  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    leading: Icon(
      grant.protected
          ? Icons.admin_panel_settings_rounded
          : grant.source == 'delegation'
          ? Icons.call_split_rounded
          : Icons.badge_outlined,
      color: TgcgColors.primary,
    ),
    title: Text(grant.roleName, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(
      '${switch (grant.source) {
        'legacy' => 'Former fixed role',
        'delegation' => 'Delegated authority',
        _ => 'Appointment',
      }} · ${grant.areas.map(areaLabel).join('; ')}',
    ),
    children: [
      FutureBuilder<Map<String, PermissionInfo>>(
        future: PermissionRegistry.of(context),
        builder: (context, snapshot) {
          final registry = snapshot.data ?? const {};
          return Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final code in grant.permissions.toList()..sort())
                  Chip(
                    label: Text(
                      permissionLabel(code, registry),
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          );
        },
      ),
      const SizedBox(height: 10),
    ],
  );
}

class _AppointmentCard extends StatelessWidget {
  const _AppointmentCard({
    required this.item,
    required this.busy,
    required this.onAccept,
    required this.onDecline,
    required this.onResign,
  });

  final Appointment item;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onResign;

  @override
  Widget build(BuildContext context) {
    final open =
        item.state == AppointmentState.active ||
        item.state == AppointmentState.scheduled ||
        item.state == AppointmentState.suspended;
    final undecided =
        item.acceptedAt == null &&
        (item.state == AppointmentState.active || item.state == AppointmentState.scheduled);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.roleName,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              appointmentStatePill(item.state),
            ],
          ),
          const SizedBox(height: 8),
          AreaChips(item.areas),
          const SizedBox(height: 8),
          Text(
            [
              'From ${formatDay(item.startsAt)}',
              if (item.endsAt != null) 'until ${formatDay(item.endsAt!)}',
              if (item.supervisingRole != null) 'reports to ${item.supervisingRole}',
              if (item.restrictedPermissions != null) 'restricted',
            ].join(' · '),
            style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
          ),
          if (item.statusReason.isNotEmpty)
            Text(
              item.statusReason,
              style: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
            ),
          if (open) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (undecided) ...[
                  FilledButton(onPressed: busy ? null : onAccept, child: const Text('Accept')),
                  TextButton(onPressed: busy ? null : onDecline, child: const Text('Decline')),
                ] else
                  TextButton(
                    onPressed: busy ? null : onResign,
                    style: TextButton.styleFrom(foregroundColor: TgcgColors.danger),
                    child: const Text('Resign'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
