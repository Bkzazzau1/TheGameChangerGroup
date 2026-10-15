import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../geography/ward_polling_units_page.dart';
import '../ui/tgcg_design.dart';

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
                    _MemberTile(member: member),
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
  const _MemberTile({required this.member});

  final StaffMember member;

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
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MemberDetailsPage(member: member)),
    ),
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

/// One member's details, as far as the server shows them to this account.
class MemberDetailsPage extends StatefulWidget {
  const MemberDetailsPage({super.key, required this.member});

  final StaffMember member;

  @override
  State<MemberDetailsPage> createState() => _MemberDetailsPageState();
}

class _MemberDetailsPageState extends State<MemberDetailsPage> {
  Future<Uint8List>? _photo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final member = widget.member;
    final backend = TgcgBackend.of(context);
    if (_photo == null && backend != null && member.sensitiveVisible && member.photoUrl != null) {
      _photo = backend.members.photo(member.membershipNumber);
    }
  }

  @override
  Widget build(BuildContext context) {
    final member = widget.member;
    final birth = member.dateOfBirth;
    final joined = member.createdAt;
    final rows = <(String, String)>[
      ('Membership number', member.membershipNumber),
      ('Identity', verificationLabel(member.verificationStatus)),
      ('Standing', membershipStateLabel(member.membershipState)),
      if (member.roles.isNotEmpty) ('Roles', member.roles.join(', ')),
      ('Polling unit', member.scope.label),
      if (member.phoneNumber != null)
        ('Phone', '${member.phoneNumber}${member.phoneVerified ? '' : ' (not confirmed)'}'),
      if ((member.email ?? '').isNotEmpty) ('Email', member.email!),
      if (member.gender.isNotEmpty) ('Gender', _capitalised(member.gender)),
      if (birth != null) ('Date of birth', _day(birth)),
      if (member.occupation.isNotEmpty) ('Occupation', member.occupation),
      ('PVC', member.vin != null ? 'VIN ending ${member.vin}' : (member.hasPvc ? 'On file' : 'Not added')),
      if (member.registrationChannel.isNotEmpty)
        ('Joined through', _channel(member.registrationChannel)),
      if (joined != null) ('Joined', _day(joined)),
      ('App account', member.hasAppAccount ? 'Yes' : 'No'),
    ];
    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(title: Text(member.displayName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          Center(
            child: _photo == null
                ? SizedBox.square(
                    dimension: 96,
                    child: FittedBox(child: _Initials(name: member.displayName)),
                  )
                : FutureBuilder<Uint8List>(
                    future: _photo,
                    builder: (context, snapshot) => ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox.square(
                        dimension: 120,
                        child: snapshot.hasData
                            ? Image.memory(snapshot.data!, fit: BoxFit.cover)
                            : ColoredBox(
                                color: TgcgColors.primarySoft,
                                child: Icon(
                                  snapshot.hasError
                                      ? Icons.no_photography_outlined
                                      : Icons.person_rounded,
                                  color: TgcgColors.primary,
                                  size: 48,
                                ),
                              ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            member.displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 16),
          Material(
            color: TgcgColors.surface,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: TgcgColors.border),
            ),
            child: Column(
              children: [
                for (final (index, (label, value)) in rows.indexed) ...[
                  if (index > 0) const Divider(height: 1, color: TgcgColors.border),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 130,
                          child: Text(
                            label,
                            style: const TextStyle(
                              color: TgcgColors.muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _capitalised(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String _day(DateTime date) => '${date.day} ${_months[date.month - 1]} ${date.year}';

String _channel(String channel) => switch (channel) {
  'self' => 'The app',
  'ussd' => 'USSD',
  'import' => "A chapter's list",
  'assisted' => 'A coordinator',
  _ => _capitalised(channel),
};
