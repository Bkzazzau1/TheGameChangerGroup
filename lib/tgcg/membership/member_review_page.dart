import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart';
import '../access/appointments_tab.dart' show AuditLine;
import '../api/access_repository.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

/// Identity review, polling unit changes and membership standing, for the
/// coordinators the server allows in each member's area.
class MemberReviewPage extends StatelessWidget {
  const MemberReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (TgcgBackend.of(context) == null) {
      return const ConnectToServerNotice(
        message:
            'Identity reviews and membership decisions are made on the server. Sign in '
            'with a server account to make them.',
      );
    }
    final session = TgcgSession.of(context);
    final tabs = <(String, IconData, Widget)>[
      if (session.can(TgcgCapability.verifyMemberIdentity))
        ('Identity review', Icons.verified_user_outlined, const _IdentityReviewTab()),
      if (session.can(TgcgCapability.reviewPollingUnitChanges))
        ('Polling unit changes', Icons.move_down_rounded, const _PollingUnitChangesTab()),
      if (session.can(TgcgCapability.suspendMembers))
        ('Member standing', Icons.person_off_outlined, const _StandingTab()),
    ];
    if (tabs.isEmpty) {
      return const Center(
        child: TgcgEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'No member reviews here',
          message: 'Your appointments do not include reviewing members.',
        ),
      );
    }
    return DefaultTabController(
      length: tabs.length,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: TgcgPageHeader(
              eyebrow: 'MEMBERSHIP',
              title: 'Member Review',
              subtitle:
                  'Confirm identities the system could not, move members to the polling '
                  'unit on their new voter card, and suspend or restore memberships in your areas.',
            ),
          ),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              for (final (label, icon, _) in tabs) Tab(icon: Icon(icon, size: 20), text: label),
            ],
          ),
          const Divider(height: 1),
          Expanded(child: TabBarView(children: [for (final (_, _, page) in tabs) page])),
        ],
      ),
    );
  }
}

TgcgStatusPill verificationPill(String status) => TgcgStatusPill(
  label: verificationLabel(status),
  compact: true,
  color: switch (status) {
    'verified' => TgcgColors.success,
    'pendingReview' => TgcgColors.warning,
    'rejected' => TgcgColors.danger,
    _ => TgcgColors.muted,
  },
);

TgcgStatusPill standingPill(String state) => TgcgStatusPill(
  label: membershipStateLabel(state),
  compact: true,
  color: switch (state) {
    'suspended' => TgcgColors.warning,
    'deactivated' => TgcgColors.danger,
    _ => TgcgColors.success,
  },
);

/// A searchable list of members in the caller's areas.
class _MemberList extends StatefulWidget {
  const _MemberList({
    required this.filters,
    required this.initialFilter,
    required this.onOpen,
    required this.emptyTitle,
  });

  /// (verification status, membership state, label).
  final List<(String?, String?, String)> filters;
  final int initialFilter;
  final Future<bool?> Function(StaffMember member) onOpen;
  final String emptyTitle;

  @override
  State<_MemberList> createState() => _MemberListState();
}

class _MemberListState extends State<_MemberList> {
  final _search = TextEditingController();
  late int _filter = widget.initialFilter;
  Future<ApiPage<StaffMember>>? _members;
  Timer? _debounce;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _members ??= _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<ApiPage<StaffMember>> _load() {
    final (verification, state, _) = widget.filters[_filter];
    return TgcgBackend.of(context)!.members.members(
      search: _search.text,
      verificationStatus: verification,
      membershipState: state,
    );
  }

  void _reload() => setState(() {
    _members = _load();
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _search,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                labelText: 'Name or membership number',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), _reload);
              },
            ),
          ),
          for (var i = 0; i < widget.filters.length; i++)
            ChoiceChip(
              label: Text(widget.filters[i].$3),
              selected: _filter == i,
              onSelected: (_) {
                _filter = i;
                _reload();
              },
            ),
        ],
      ),
      const SizedBox(height: 16),
      FutureBuilder<ApiPage<StaffMember>>(
        future: _members,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TgcgEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Members could not be loaded',
              message: failureMessage(snapshot.error!),
              action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
            );
          }
          final page = snapshot.data;
          if (page == null) return const LinearProgressIndicator();
          if (page.items.isEmpty) {
            return TgcgEmptyState(
              icon: Icons.groups_2_outlined,
              title: widget.emptyTitle,
              message: 'Members registered in your areas appear here.',
            );
          }
          return Column(
            children: [
              for (final member in page.items)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: TgcgColors.border),
                  ),
                  child: ListTile(
                    title: Text(
                      member.fullName,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${member.membershipNumber} · ${areaLabel(member.scope)}'
                      '${member.roles.isEmpty ? '' : ' · ${member.roles.join(', ')}'}',
                    ),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        verificationPill(member.verificationStatus),
                        if (member.membershipState != 'active')
                          standingPill(member.membershipState),
                      ],
                    ),
                    onTap: () async {
                      final changed = await widget.onOpen(member);
                      if (changed == true) _reload();
                    },
                  ),
                ),
              if (page.hasMore)
                Text(
                  'Showing ${page.items.length} of ${page.count}. Search to narrow the list.',
                  style: const TextStyle(color: TgcgColors.muted),
                ),
            ],
          );
        },
      ),
    ],
  );
}

// --- identity review -----------------------------------------------------------------

class _IdentityReviewTab extends StatelessWidget {
  const _IdentityReviewTab();

  @override
  Widget build(BuildContext context) => _MemberList(
    filters: const [
      ('pendingReview', 'active', 'Awaiting review'),
      ('rejected', null, 'Rejected'),
      ('verified', null, 'Verified'),
      (null, null, 'Everyone'),
    ],
    initialFilter: 0,
    emptyTitle: 'No identities to review',
    onOpen: (member) => showDialog<bool>(
      context: context,
      builder: (_) => IdentityReviewDialog(member: member),
    ),
  );
}

/// What the system could and could not check, and the reviewer's decision.
class IdentityReviewDialog extends StatefulWidget {
  const IdentityReviewDialog({super.key, required this.member});

  final StaffMember member;

  @override
  State<IdentityReviewDialog> createState() => _IdentityReviewDialogState();
}

class _IdentityReviewDialogState extends State<IdentityReviewDialog> {
  late Future<MemberVerification> _verification;
  Future<Uint8List>? _photo;
  bool _changed = false;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final members = TgcgBackend.of(context)!.members;
    _verification = members.verification(widget.member.membershipNumber);
    if (widget.member.sensitiveVisible && widget.member.photoUrl != null) {
      _photo ??= members.photo(widget.member.membershipNumber);
    }
  }

  Future<void> _run(
    Future<MemberVerification> Function(MemberAdminRepository members) action,
    String done,
  ) async {
    final members = TgcgBackend.of(context)!.members;
    setState(() => _busy = true);
    try {
      final result = action(members);
      await result;
      if (!mounted) return;
      setState(() {
        _verification = result;
        _changed = true;
      });
      showDone(context, done);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final notes = await promptText(
      context,
      title: 'Confirm ${widget.member.fullName}\'s identity?',
      message:
          'Record what you checked yourself, for example that you compared the PVC with '
          'the person in front of you. Do not write the VIN or phone number here.',
      label: 'What you checked and how',
      action: 'Confirm identity',
      required: true,
    );
    if (notes == null) return;
    await _run(
      (members) => members.approveIdentity(widget.member.membershipNumber, notes),
      'Identity confirmed.',
    );
  }

  Future<void> _reject() async {
    final reason = await promptText(
      context,
      title: 'Reject ${widget.member.fullName}\'s identity?',
      message:
          'Any appointments they hold stop at once, and they cannot be appointed until '
          'their identity is confirmed.',
      label: 'Why it could not be confirmed',
      action: 'Reject',
      required: true,
      destructive: true,
    );
    if (reason == null) return;
    await _run(
      (members) => members.rejectIdentity(widget.member.membershipNumber, reason),
      'Identity rejected.',
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.member.fullName),
    content: SizedBox(
      width: 560,
      child: FutureBuilder<MemberVerification>(
        future: _verification,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(failureMessage(snapshot.error!));
          final verification = snapshot.data;
          if (verification == null) return const LinearProgressIndicator();
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_photo != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: FutureBuilder<Uint8List>(
                            future: _photo,
                            builder: (context, photo) => photo.hasData
                                ? Image.memory(
                                    photo.data!,
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover,
                                  )
                                : const SizedBox(width: 96, height: 96),
                          ),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.member.membershipNumber),
                          Text(
                            areaLabel(widget.member.scope),
                            style: const TextStyle(color: TgcgColors.muted),
                          ),
                          const SizedBox(height: 6),
                          verificationPill(verification.status),
                          if (verification.reviewedBy != null)
                            Text(
                              'Last decision by ${verification.reviewedBy}',
                              style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Checks', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                for (final check in verification.checks)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      switch (check.result) {
                        'passed' => Icons.check_circle_rounded,
                        'failed' => Icons.cancel_rounded,
                        'pending' => Icons.hourglass_top_rounded,
                        _ => Icons.help_outline_rounded,
                      },
                      color: switch (check.result) {
                        'passed' => TgcgColors.success,
                        'failed' => TgcgColors.danger,
                        'pending' => TgcgColors.warning,
                        _ => TgcgColors.muted,
                      },
                    ),
                    title: Text(checkLabel(check.kind)),
                    subtitle: Text(check.detail),
                  ),
                const SizedBox(height: 8),
                const Text(
                  'Checks marked as not available were not performed: no authoritative INEC '
                  'source, liveness detection or trusted reference photo is connected. '
                  'Confirm those in person.',
                  style: TextStyle(color: TgcgColors.muted, fontSize: 12.5, height: 1.4),
                ),
                if (verification.hasFailedCheck)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'A failed check must be resolved (for example by adding the PVC) '
                      'before the identity can be confirmed.',
                      style: TextStyle(color: TgcgColors.danger, fontSize: 12.5),
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
        onPressed: _busy
            ? null
            : () => _run(
                (members) => members.runChecks(widget.member.membershipNumber),
                'Checks run again.',
              ),
        child: const Text('Run checks again'),
      ),
      TextButton(
        onPressed: _busy ? null : _reject,
        style: TextButton.styleFrom(foregroundColor: TgcgColors.danger),
        child: const Text('Reject'),
      ),
      FilledButton(onPressed: _busy ? null : _approve, child: const Text('Confirm identity')),
      TextButton(onPressed: () => Navigator.pop(context, _changed), child: const Text('Close')),
    ],
  );
}

// --- polling unit changes --------------------------------------------------------------

class _PollingUnitChangesTab extends StatefulWidget {
  const _PollingUnitChangesTab();

  @override
  State<_PollingUnitChangesTab> createState() => _PollingUnitChangesTabState();
}

class _PollingUnitChangesTabState extends State<_PollingUnitChangesTab> {
  String? _status = 'pending';
  Future<ApiPage<PollingUnitChange>>? _changes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _changes ??= _load();
  }

  Future<ApiPage<PollingUnitChange>> _load() =>
      TgcgBackend.of(context)!.members.pollingUnitChanges(status: _status);

  void _reload() => setState(() {
    _changes = _load();
  });

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      Wrap(
        spacing: 8,
        children: [
          for (final (value, label) in const [
            ('pending', 'Awaiting review'),
            ('approved', 'Approved'),
            ('rejected', 'Rejected'),
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
        ],
      ),
      const SizedBox(height: 16),
      FutureBuilder<ApiPage<PollingUnitChange>>(
        future: _changes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TgcgEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'Requests could not be loaded',
              message: failureMessage(snapshot.error!),
            );
          }
          final page = snapshot.data;
          if (page == null) return const LinearProgressIndicator();
          if (page.items.isEmpty) {
            return const TgcgEmptyState(
              icon: Icons.move_down_rounded,
              title: 'No requests',
              message: 'Members asking to move into polling units in your areas appear here.',
            );
          }
          return Column(
            children: [
              for (final change in page.items)
                Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: const BorderSide(color: TgcgColors.border),
                  ),
                  child: ListTile(
                    title: Text(
                      '${change.memberName} (${change.member})',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      '${change.fromPollingUnit ?? 'No polling unit'} → '
                      '${change.toPollingUnit} ${change.toPollingUnitName} · '
                      '${formatDay(change.createdAt)}',
                    ),
                    trailing: Text(change.status),
                    onTap: () async {
                      final changed = await showDialog<bool>(
                        context: context,
                        builder: (_) => PollingUnitChangeDialog(change: change),
                      );
                      if (changed == true) _reload();
                    },
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );
}

/// A request to move a member's registered polling unit, with the photo of
/// the updated voter card it rests on.
class PollingUnitChangeDialog extends StatefulWidget {
  const PollingUnitChangeDialog({super.key, required this.change});

  final PollingUnitChange change;

  @override
  State<PollingUnitChangeDialog> createState() => _PollingUnitChangeDialogState();
}

class _PollingUnitChangeDialogState extends State<PollingUnitChangeDialog> {
  late PollingUnitChange _change = widget.change;
  late final Future<Uint8List> _card = TgcgBackend.of(
    context,
  )!.members.pollingUnitChangeCard(widget.change.id);
  bool _busy = false;

  Future<void> _decide({required bool approve}) async {
    final reason = await promptText(
      context,
      title: approve ? 'Approve this move?' : 'Reject this request?',
      message: approve
          ? 'The member\'s registered polling unit becomes ${_change.toPollingUnit}. Their '
                'appointments do not change.'
          : 'Tell the member why, so they can ask again with the right card.',
      label: approve ? 'Note' : 'Why it is rejected',
      action: approve ? 'Approve' : 'Reject',
      required: !approve,
      destructive: !approve,
    );
    if (reason == null || !mounted) return;
    final members = TgcgBackend.of(context)!.members;
    setState(() => _busy = true);
    try {
      final updated = approve
          ? await members.approvePollingUnitChange(_change.id, reason: reason)
          : await members.rejectPollingUnitChange(_change.id, reason);
      if (!mounted) return;
      Navigator.pop(context, true);
      showDone(context, approve ? 'Polling unit changed.' : 'Request rejected.');
      _change = updated;
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${_change.memberName} wants to move'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From: ${_change.fromPollingUnit ?? 'no polling unit'}'),
            Text('To: ${_change.toPollingUnit} ${_change.toPollingUnitName}'),
            if (_change.reason.isNotEmpty) Text('Reason: ${_change.reason}'),
            Text(
              'Asked on ${formatMoment(_change.createdAt)}',
              style: const TextStyle(color: TgcgColors.muted),
            ),
            const SizedBox(height: 12),
            const Text(
              'Check that the card shows the new polling unit and belongs to this member.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            FutureBuilder<Uint8List>(
              future: _card,
              builder: (context, snapshot) {
                if (snapshot.hasError) return Text(failureMessage(snapshot.error!));
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(snapshot.data!, fit: BoxFit.contain),
                );
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (_change.isPending) ...[
        TextButton(
          onPressed: _busy ? null : () => _decide(approve: false),
          style: TextButton.styleFrom(foregroundColor: TgcgColors.danger),
          child: const Text('Reject'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _decide(approve: true),
          child: const Text('Approve'),
        ),
      ],
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
    ],
  );
}

// --- standing -------------------------------------------------------------------------

class _StandingTab extends StatelessWidget {
  const _StandingTab();

  @override
  Widget build(BuildContext context) => _MemberList(
    filters: const [
      (null, null, 'Everyone'),
      (null, 'suspended', 'Suspended'),
      (null, 'deactivated', 'Deactivated'),
    ],
    initialFilter: 0,
    emptyTitle: 'No members found',
    onOpen: (member) => showDialog<bool>(
      context: context,
      builder: (_) => StandingDialog(member: member),
    ),
  );
}

/// Suspend, deactivate or restore one membership, with its history.
class StandingDialog extends StatefulWidget {
  const StandingDialog({super.key, required this.member});

  final StaffMember member;

  @override
  State<StandingDialog> createState() => _StandingDialogState();
}

class _StandingDialogState extends State<StandingDialog> {
  late StaffMember _member = widget.member;
  late Future<List<AuditEntry>> _history = TgcgBackend.of(
    context,
  )!.members.history(widget.member.membershipNumber);
  bool _changed = false;
  bool _busy = false;

  Future<void> _change(String action) async {
    final (title, message, required) = switch (action) {
      'suspend' => (
        'Suspend ${_member.fullName}?',
        'All their operational access stops at once and they are signed out. Their '
            'appointments stay on record.',
        true,
      ),
      'deactivate' => (
        'Deactivate ${_member.fullName}\'s membership?',
        'They are signed out and cannot sign in again. Their history is kept.',
        true,
      ),
      _ => (
        'Restore ${_member.fullName}\'s membership?',
        'Only appointments that are otherwise still valid give access again.',
        false,
      ),
    };
    final reason = await promptText(
      context,
      title: title,
      message: message,
      label: 'Reason',
      action: action[0].toUpperCase() + action.substring(1),
      required: required,
      destructive: action != 'restore',
    );
    if (reason == null || !mounted) return;
    final members = TgcgBackend.of(context)!.members;
    setState(() => _busy = true);
    try {
      final number = _member.membershipNumber;
      final updated = switch (action) {
        'suspend' => await members.suspend(number, reason),
        'deactivate' => await members.deactivate(number, reason),
        _ => await members.restore(number, reason: reason),
      };
      if (!mounted) return;
      setState(() {
        _member = updated;
        _changed = true;
        _history = members.history(number);
      });
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_member.fullName),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_member.membershipNumber} · ${areaLabel(_member.scope)}'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                standingPill(_member.membershipState),
                verificationPill(_member.verificationStatus),
              ],
            ),
            if (_member.roles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Appointments: ${_member.roles.join(', ')}'),
            ],
            if (_member.sensitiveVisible && _member.phoneNumber != null) ...[
              const SizedBox(height: 8),
              Text('Phone: ${_member.phoneNumber}'),
            ],
            const SizedBox(height: 14),
            const Text('History', style: TextStyle(fontWeight: FontWeight.w800)),
            FutureBuilder<List<AuditEntry>>(
              future: _history,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  final error = snapshot.error;
                  return Text(
                    error is ApiException && error.statusCode == 403
                        ? 'History is shown to those who review or suspend members here.'
                        : failureMessage(error!),
                    style: const TextStyle(color: TgcgColors.muted),
                  );
                }
                final events = snapshot.data;
                if (events == null) return const LinearProgressIndicator();
                if (events.isEmpty) {
                  return const Text('Nothing yet.', style: TextStyle(color: TgcgColors.muted));
                }
                return Column(children: [for (final event in events) AuditLine(event)]);
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      if (_member.membershipState == 'active')
        TextButton(
          onPressed: _busy ? null : () => _change('suspend'),
          child: const Text('Suspend'),
        ),
      if (_member.membershipState != 'active')
        TextButton(
          onPressed: _busy ? null : () => _change('restore'),
          child: const Text('Restore'),
        ),
      if (_member.membershipState != 'deactivated')
        TextButton(
          onPressed: _busy ? null : () => _change('deactivate'),
          style: TextButton.styleFrom(foregroundColor: TgcgColors.danger),
          child: const Text('Deactivate'),
        ),
      FilledButton(onPressed: () => Navigator.pop(context, _changed), child: const Text('Close')),
    ],
  );
}
