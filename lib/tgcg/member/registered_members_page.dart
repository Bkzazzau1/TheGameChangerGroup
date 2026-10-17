import 'package:flutter/material.dart';

import '../access/access_widgets.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_repository.dart';
import '../session.dart' show GeographicScope, GeographyLevel;
import '../ui/tgcg_design.dart';
import 'member_shell.dart' show RegisteredMemberPage;

/// Opens [RegisteredMembersPage]; for app bars. Anyone signed in registers
/// members.
class RegisterMembersButton extends StatelessWidget {
  const RegisterMembersButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Register members',
    onPressed: () => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RegisteredMembersPage()),
    ),
    icon: Icon(Icons.person_add_alt_1_rounded, color: color),
  );
}

/// Registering members with a name and a phone number, as many as one
/// wishes, and the members one registered: their registration to complete
/// until their identity is checked.
class RegisteredMembersPage extends StatefulWidget {
  const RegisteredMembersPage({super.key});

  @override
  State<RegisteredMembersPage> createState() => _RegisteredMembersPageState();
}

enum _Next { complete, another }

class _RegisteredMembersPageState extends State<RegisteredMembersPage> {
  final _search = TextEditingController();
  late MemberRepository _repository;
  List<RegisteredMember> _shown = const [];
  int _count = 0;
  bool _more = false;
  bool _loading = true;
  bool _started = false;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _repository = TgcgBackend.of(context)!.member;
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _repository.registeredMembers(
        search: _search.text,
        offset: more ? _shown.length : 0,
      );
      if (!mounted) return;
      setState(() {
        _shown = [if (more) ..._shown, ...page.members];
        _count = page.count;
        _more = page.more;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    final member = await showDialog<RegisteredMember>(
      context: context,
      builder: (_) => const _RegisterDialog(),
    );
    if (member == null || !mounted) return;
    _load();
    final next = await showDialog<_Next>(
      context: context,
      builder: (_) => _RegisteredDialog(member: member),
    );
    if (!mounted) return;
    switch (next) {
      case _Next.complete:
        await _open(member);
      case _Next.another:
        await _register();
      case null:
        break;
    }
  }

  Future<void> _open(RegisteredMember member) async {
    if (!member.canComplete) {
      showDone(context, 'Their identity has been checked, so only they or a coordinator change it.');
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RegisteredMemberPage(membershipNumber: member.membershipNumber),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(
      title: const Text('Register members'),
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _loading ? null : _load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _register,
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Register a member'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _load(),
            decoration: InputDecoration(
              labelText: 'Search the people you registered',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      onPressed: () {
                        _search.clear();
                        _load();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          if (_error case final error?)
            TgcgEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Could not load the people you registered',
              message: failureMessage(error),
              action: OutlinedButton(onPressed: _load, child: const Text('Try again')),
            )
          else if (_loading && _shown.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_shown.isEmpty)
            TgcgEmptyState(
              icon: Icons.group_add_outlined,
              title: _search.text.isEmpty ? 'No one registered yet' : 'No one found',
              message: _search.text.isEmpty
                  ? 'People you register appear here.'
                  : 'Search by name, phone number or membership number.',
            )
          else ...[
            Text(
              _count == 1 ? '1 person' : '$_count people',
              style: const TextStyle(color: TgcgColors.muted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            for (final member in _shown)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(member.fullName, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    [
                      member.membershipNumber,
                      localPhone(member.phoneNumber),
                      if (member.place.level != GeographyLevel.country) areaLabel(member.place),
                    ].join(' · '),
                  ),
                  trailing: _statusPill(member),
                  onTap: () => _open(member),
                ),
              ),
            if (_more)
              Center(
                child: TextButton(
                  onPressed: _loading ? null : () => _load(more: true),
                  child: const Text('Show more'),
                ),
              ),
          ],
        ],
      ),
    ),
  );
}

TgcgStatusPill _statusPill(RegisteredMember member) {
  final (label, color) = switch (member) {
    RegisteredMember(verificationStatus: 'verified') => ('ID checked', TgcgColors.success),
    RegisteredMember(verificationStatus: 'rejected') => ('ID not accepted', TgcgColors.danger),
    RegisteredMember(membershipState: != 'active') => ('Not active', TgcgColors.muted),
    RegisteredMember(missing: []) => ('Complete', TgcgColors.info),
    _ => ('Needs details', TgcgColors.warning),
  };
  return TgcgStatusPill(label: label, color: color, compact: true);
}

/// A name, a phone number and the person's agreement; the place if known.
class _RegisterDialog extends StatefulWidget {
  const _RegisterDialog();

  @override
  State<_RegisterDialog> createState() => _RegisterDialogState();
}

class _RegisterDialogState extends State<_RegisterDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  GeographicScope? _place;
  bool _agreed = false;
  bool _busy = false;
  Map<String, String> _errors = const {};

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  bool get _ready =>
      !_busy && _agreed && _name.text.trim().isNotEmpty && _phone.text.trim().isNotEmpty;

  Future<void> _pickPlace() async {
    final place = await pickArea(
      context,
      levels: const [
        GeographyLevel.state,
        GeographyLevel.lga,
        GeographyLevel.ward,
        GeographyLevel.pollingUnit,
      ],
    );
    if (place != null && mounted) setState(() => _place = place);
  }

  Future<void> _send() async {
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _errors = const {};
    });
    try {
      final member = await TgcgBackend.of(context)!.member.registerSomeone(
        fullName: _name.text,
        phone: _phone.text,
        place: _place,
      );
      navigator.pop(member);
    } on ApiException catch (error) {
      if (!mounted) return;
      final fields = {
        for (final entry in error.fieldErrors.entries) entry.key: entry.value.first,
      };
      setState(() {
        _errors = {
          for (final key in const ['full_name', 'phone_number', 'scope', 'consent'])
            if (fields[key] case final message?) key: message,
          if (fields.isEmpty) 'general': error.message,
        };
      });
    } catch (error) {
      if (mounted) setState(() => _errors = {'general': failureMessage(error)});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Register a member'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(labelText: 'Full name', errorText: _errors['full_name']),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'Phone number',
                errorText: _errors['phone_number'],
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _place == null ? 'Place (optional)' : areaLabel(_place!),
                    style: TextStyle(
                      color: _place == null ? TgcgColors.muted : TgcgColors.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_place != null)
                  IconButton(
                    tooltip: 'Remove place',
                    onPressed: () => setState(() => _place = null),
                    icon: const Icon(Icons.close_rounded),
                  ),
                TextButton(
                  onPressed: _busy ? null : _pickPlace,
                  child: Text(_place == null ? 'Add' : 'Change'),
                ),
              ],
            ),
            if (_errors['scope'] case final error?)
              Text(error, style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _agreed,
              onChanged: (value) => setState(() => _agreed = value ?? false),
              title: const Text(
                'They agreed to join TGCG and to TGCG keeping their name and phone number',
              ),
              subtitle: _errors['consent'] == null
                  ? null
                  : Text(_errors['consent']!, style: const TextStyle(color: TgcgColors.danger)),
            ),
            if (_errors['general'] case final error?)
              Text(error, style: const TextStyle(color: TgcgColors.danger)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _ready ? _send : null,
        child: _busy
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Text('Register'),
      ),
    ],
  );
}

/// The new member's number and how they sign in: their phone number is also
/// their first password.
class _RegisteredDialog extends StatelessWidget {
  const _RegisteredDialog({required this.member});

  final RegisteredMember member;

  @override
  Widget build(BuildContext context) {
    final number = localPhone(member.phoneNumber);
    return AlertDialog(
      title: Text('${member.fullName} is registered'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (label, value) in [
            ('Membership number', member.membershipNumber),
            ('Signs in with', number),
            ('Password', number),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: const TextStyle(color: TgcgColors.muted)),
                  ),
                  SelectableText(value, style: const TextStyle(fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _Next.another),
          child: const Text('Register another'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _Next.complete),
          child: const Text('Complete registration'),
        ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
      ],
    );
  }
}
