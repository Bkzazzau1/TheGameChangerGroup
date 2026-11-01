import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../geography/ward_polling_units_page.dart';
import '../ui/tgcg_design.dart';
import 'member_profile.dart';

/// The members registered at one polling unit. The server lists only those
/// within the account's areas.
class PollingUnitMembersPage extends StatefulWidget {
  const PollingUnitMembersPage({super.key, required this.code, required this.name});

  /// INEC polling unit code, e.g. 18-23-05-001.
  final String code;
  final String name;

  @override
  State<PollingUnitMembersPage> createState() => _PollingUnitMembersPageState();
}

class _PollingUnitMembersPageState extends State<PollingUnitMembersPage> {
  final _members = <StaffMember>[];
  int? _count;
  bool _hasMore = false;
  bool _loading = false;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_count == null && !_loading && _error == null) _load();
  }

  /// The list from the top, after a decision on someone on it.
  void _reload() {
    _members.clear();
    _load();
  }

  Future<void> _load() async {
    final backend = TgcgBackend.of(context);
    if (backend == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await backend.members.members(
        pollingUnit: widget.code,
        offset: _members.length,
      );
      if (!mounted) return;
      setState(() {
        _members.addAll(page.items);
        _count = page.count;
        _hasMore = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = _count;
    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(title: Text(titleCaseName(widget.name))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          Text(
            count == null
                ? widget.code
                : '${widget.code} • $count member${count == 1 ? '' : 's'}',
            style: const TextStyle(color: TgcgColors.muted, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          if (_members.isNotEmpty)
            Material(
              color: TgcgColors.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: TgcgColors.border),
              ),
              child: Column(
                children: [
                  for (final (index, member) in _members.indexed) ...[
                    if (index > 0) const Divider(height: 1, color: TgcgColors.border),
                    _MemberTile(member: member, onChanged: _reload),
                  ],
                ],
              ),
            )
          else if (count == 0)
            const TgcgEmptyState(
              icon: Icons.groups_2_outlined,
              title: 'No members yet',
              message: 'Nobody is registered at this polling unit.',
            ),
          if (_error != null)
            TgcgEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load members',
              message: _error is ApiException ? (_error as ApiException).message : '$_error',
              action: TextButton(onPressed: _load, child: const Text('Try again')),
            ),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_hasMore && _error == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: OutlinedButton(onPressed: _load, child: const Text('Show more')),
            ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member, required this.onChanged});

  final StaffMember member;

  /// After a decision on this member from their profile.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: _Initials(name: member.displayName),
    title: Text(member.displayName, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(
      [
        member.membershipNumber,
        verificationLabel(member.verificationStatus),
        if (member.membershipState != 'active') membershipStateLabel(member.membershipState),
        ...member.roles,
      ].join(' • '),
      style: const TextStyle(fontSize: 11.5, color: TgcgColors.muted),
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => showMemberDetails(context, member.membershipNumber, onChanged: onChanged),
  );
}

class _Initials extends StatelessWidget {
  const _Initials({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final letters = name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      backgroundColor: TgcgColors.primarySoft,
      foregroundColor: TgcgColors.primary,
      child: Text(letters, style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }
}
