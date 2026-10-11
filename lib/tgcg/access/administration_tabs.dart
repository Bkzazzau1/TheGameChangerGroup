import 'package:flutter/material.dart';

import '../api/access_repository.dart';
import '../api/backend.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'access_widgets.dart';

/// National Administrators: who they are, and the two-administrator
/// approval for suspending or removing one.
class AdministratorsTab extends StatefulWidget {
  const AdministratorsTab({super.key});

  @override
  State<AdministratorsTab> createState() => _AdministratorsTabState();
}

class _AdministratorsTabState extends State<AdministratorsTab> {
  Future<(List<AdministratorAccount>, List<AdminAction>)>? _data;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<AdministratorAccount>, List<AdminAction>)> _load() async {
    final access = TgcgBackend.of(context)!.access;
    final results = await Future.wait([
      access.administrators(),
      access.adminActions(status: 'pending'),
    ]);
    return (results[0] as List<AdministratorAccount>, (results[1] as ApiPage<AdminAction>).items);
  }

  void _reload() => setState(() {
    _data = _load();
  });

  Future<void> _run(Future<Object?> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      showDone(context, done);
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request(AdministratorAccount target, String kind) async {
    final verb = kind == 'suspend' ? 'suspend' : 'remove';
    final reason = await promptText(
      context,
      title: '${verb[0].toUpperCase()}${verb.substring(1)} ${target.fullName}?',
      message:
          'This needs a second National Administrator\'s approval; your request counts '
          'as yours. ${target.fullName} cannot approve it.',
      label: 'Why',
      action: 'Request',
      required: true,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    final access = TgcgBackend.of(context)!.access;
    await _run(
      () => access.requestAdminAction(target: target.accessId, kind: kind, reason: reason),
      'Request recorded. A second administrator must approve it.',
    );
  }

  Future<void> _approve(AdminAction action) async {
    final confirmed = await confirmAction(
      context,
      title: 'Approve: ${action.kind} ${action.targetName}?',
      message:
          '${action.requestedBy} asked: "${action.reason}". With your approval it is '
          'carried out at once.',
      action: 'Approve',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    final access = TgcgBackend.of(context)!.access;
    await _run(() => access.approveAdminAction(action.id), 'Approved.');
  }

  Future<void> _cancel(AdminAction action) async {
    final reason = await promptText(
      context,
      title: 'Cancel this request?',
      label: 'Why',
      action: 'Cancel request',
    );
    if (reason == null || !mounted) return;
    final access = TgcgBackend.of(context)!.access;
    await _run(() => access.cancelAdminAction(action.id, reason: reason), 'Request cancelled.');
  }

  Future<void> _reinstate(AdministratorAccount target) async {
    final reason = await promptText(
      context,
      title: 'Reinstate ${target.fullName}?',
      label: 'Why',
      action: 'Reinstate',
      required: true,
    );
    if (reason == null || !mounted) return;
    final access = TgcgBackend.of(context)!.access;
    await _run(
      () => access.reinstateAdministrator(target.accessId, reason),
      '${target.fullName} reinstated.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = TgcgSession.of(context).accessId;
    return FutureBuilder<(List<AdministratorAccount>, List<AdminAction>)>(
      future: _data,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return TgcgEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Administrators could not be loaded',
            message: failureMessage(snapshot.error!),
            action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Padding(padding: EdgeInsets.all(20), child: LinearProgressIndicator());
        }
        final (administrators, pending) = data;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const TgcgSectionCard(
              title: 'The two-administrator rule',
              child: Text(
                'Suspending or removing a National Administrator takes a request and the approval '
                'of a second administrator; neither can be the one concerned, and the last '
                'active administrator is never removed. To appoint an administrator, appoint a '
                'verified member to the National Administrator role from Appointments.',
                style: TextStyle(height: 1.45),
              ),
            ),
            const SizedBox(height: 16),
            if (pending.isNotEmpty) ...[
              TgcgSectionCard(
                title: 'Awaiting approval',
                child: Column(
                  children: [
                    for (final action in pending)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.how_to_vote_outlined, color: TgcgColors.warning),
                        title: Text(
                          '${action.kind == 'suspend' ? 'Suspend' : 'Remove'} '
                          '${action.targetName} (${action.target})',
                        ),
                        subtitle: Text(
                          'Asked by ${action.requestedBy} on ${formatMoment(action.createdAt)}: '
                          '${action.reason}',
                        ),
                        trailing: Wrap(
                          spacing: 6,
                          children: [
                            if (action.requestedBy == me)
                              TextButton(
                                onPressed: _busy ? null : () => _cancel(action),
                                child: const Text('Cancel'),
                              )
                            else if (action.target != me && !action.approvals.contains(me))
                              FilledButton(
                                onPressed: _busy ? null : () => _approve(action),
                                child: const Text('Approve'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            TgcgSectionCard(
              title: 'National Administrators',
              child: Column(
                children: [
                  for (final admin in administrators)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.admin_panel_settings_rounded,
                        color: admin.state == 'active' ? TgcgColors.success : TgcgColors.muted,
                      ),
                      title: Text('${admin.fullName} (${admin.accessId})'),
                      subtitle: Text(
                        '${admin.state[0].toUpperCase()}${admin.state.substring(1)}'
                        '${admin.legacy ? ' · former fixed role' : ''}'
                        '${admin.appointments.isNotEmpty ? ' · appointed' : ''}'
                        '${admin.pendingRequest != null ? ' · request pending' : ''}',
                      ),
                      trailing: admin.accessId == me || admin.pendingRequest != null
                          ? null
                          : PopupMenuButton<String>(
                              enabled: !_busy,
                              onSelected: (choice) => switch (choice) {
                                'reinstate' => _reinstate(admin),
                                _ => _request(admin, choice),
                              },
                              itemBuilder: (_) => [
                                if (admin.state == 'active')
                                  const PopupMenuItem(
                                    value: 'suspend',
                                    child: Text('Request suspension'),
                                  ),
                                if (admin.state == 'suspended')
                                  const PopupMenuItem(value: 'reinstate', child: Text('Reinstate')),
                                const PopupMenuItem(
                                  value: 'remove',
                                  child: Text('Request removal'),
                                ),
                              ],
                            ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

const _auditFilters = [
  (null, 'Everything'),
  ('role.', 'Roles'),
  ('assignment.', 'Appointments'),
  ('delegation.', 'Delegation'),
  ('administrator.', 'Administrators'),
  ('member.', 'Members'),
];

/// The tamper-evident audit log (nationwide viewers only).
class AuditTab extends StatefulWidget {
  const AuditTab({super.key});

  @override
  State<AuditTab> createState() => _AuditTabState();
}

class _AuditTabState extends State<AuditTab> {
  String? _action;
  final _entries = <AuditEntry>[];
  int _page = 0;
  bool _more = true;
  bool _loading = false;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_page == 0 && !_loading) _next();
  }

  Future<void> _next() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await TgcgBackend.of(context)!.access.audit(action: _action, page: _page + 1);
      if (!mounted) return;
      setState(() {
        _entries.addAll(page.items);
        _page += 1;
        _more = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter(String? action) {
    setState(() {
      _action = action;
      _entries.clear();
      _page = 0;
      _more = true;
    });
    _next();
  }

  Future<void> _verify() async {
    try {
      final broken = await TgcgBackend.of(context)!.access.verifyAudit();
      if (!mounted) return;
      await confirmAction(
        context,
        title: broken == null ? 'The audit log is intact' : 'The audit log was altered',
        message: broken == null
            ? 'Every event still matches the chain of fingerprints written when it happened.'
            : 'Event $broken or the link to it no longer matches what was written. Report this '
                  'to the technical team at once.',
        action: 'Close',
      );
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final (value, label) in _auditFilters)
              ChoiceChip(
                label: Text(label),
                selected: _action == value,
                onSelected: (_) => _filter(value),
              ),
            if (session.can(TgcgCapability.appointNationalAdministrator))
              OutlinedButton.icon(
                onPressed: _verify,
                icon: const Icon(Icons.verified_user_outlined),
                label: const Text('Check integrity'),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          TgcgEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'The audit log could not be loaded',
            message: failureMessage(_error!),
          )
        else if (_entries.isEmpty && !_loading)
          const TgcgEmptyState(
            icon: Icons.fact_check_outlined,
            title: 'Nothing recorded',
            message: 'The audit log is readable only with nationwide audit access.',
          ),
        for (final entry in _entries)
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: TgcgColors.border),
            ),
            child: ListTile(
              title: Text(
                '${entry.action} · ${entry.targetLabel.isEmpty ? entry.targetId : entry.targetLabel}',
              ),
              subtitle: Text(
                '${entry.actor} · ${formatMoment(entry.createdAt)}'
                '${entry.reason.isEmpty ? '' : '\n${entry.reason}'}',
              ),
              isThreeLine: entry.reason.isNotEmpty,
            ),
          ),
        if (_loading) const LinearProgressIndicator(),
        if (_more && !_loading && _error == null && _entries.isNotEmpty)
          Center(
            child: TextButton(onPressed: _next, child: const Text('Load more')),
          ),
      ],
    );
  }
}
