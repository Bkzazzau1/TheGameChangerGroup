import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart' show failureMessage, showFailure;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/support_groups_repository.dart';
import '../ui/tgcg_design.dart';
import 'led_group_page.dart';
import 'organization_form.dart';

/// How a group's vetting stands, in words and a colour.
(String, Color) groupStatus(SupportGroup group) => switch (group.status) {
  'approved' => ('Approved', TgcgColors.success),
  'pending' => (
    group.leaderConfirmed ? 'Waiting for vetting' : 'Waiting for the leader',
    TgcgColors.warning,
  ),
  'suspended' => ('Suspended', TgcgColors.danger),
  _ => ('Not approved', TgcgColors.danger),
};

/// The member's support groups: groups asking them to confirm, the groups
/// they are in and lead, joining one with its code, and registering one.
/// Nobody else sees which groups a member is in, apart from the group's
/// leader and those who vet groups.
class MySupportGroupsPage extends StatefulWidget {
  const MySupportGroupsPage({super.key});

  @override
  State<MySupportGroupsPage> createState() => _MySupportGroupsPageState();
}

class _MySupportGroupsPageState extends State<MySupportGroupsPage> {
  Future<MySupportGroups>? _mine;
  final _busy = <String>{};

  SupportGroupsRepository get _groups => TgcgBackend.of(context)!.supportGroups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mine ??= _groups.mine();
  }

  void _reload() => setState(() => _mine = _groups.mine());

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _answer(MyGroupPlace place, bool yes) async {
    setState(() => _busy.add(place.id));
    try {
      await _groups.answer(place.id, yes: yes);
      if (!mounted) return;
      _say(yes ? 'You are now in ${place.groupName}.' : 'You told ${place.groupName} no.');
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(place.id));
    }
  }

  Future<void> _leave(MyGroupPlace place) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leave ${place.groupName}?'),
        content: const Text('You stay a member of TGCG. You can join again with its code.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave != true || !mounted) return;
    setState(() => _busy.add(place.id));
    try {
      await _groups.leave(place.id);
      if (!mounted) return;
      _say('You left ${place.groupName}.');
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy.remove(place.id));
    }
  }

  Future<void> _join() async {
    final joined = await showDialog<bool>(context: context, builder: (_) => const _JoinDialog());
    if (joined == true && mounted) {
      _say('You joined the group.');
      _reload();
    }
  }

  Future<void> _register() async {
    final group = await Navigator.of(
      context,
    ).push<SupportGroup>(MaterialPageRoute(builder: (_) => const RegisterOrganizationPage()));
    if (group == null || !mounted) return;
    _say('${group.name} is registered as ${group.serialNumber}. TGCG will vet it.');
    _reload();
  }

  Future<void> _open(SupportGroup group) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => LedGroupPage(groupId: group.id)));
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(
      title: const Text('Support groups'),
      actions: [
        IconButton(
          tooltip: 'Load again',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<MySupportGroups>(
        future: _mine,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TgcgEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'Your groups could not be loaded',
              message: failureMessage(snapshot.error!),
              action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
            );
          }
          final mine = snapshot.data;
          if (mine == null) return const LinearProgressIndicator(minHeight: 2);
          return TgcgPageList(
            children: [
              for (final place in mine.invitations) ...[
                _Invitation(
                  place: place,
                  busy: _busy.contains(place.id),
                  onAnswer: (yes) => _answer(place, yes),
                ),
                const SizedBox(height: 12),
              ],
              if (mine.leading.isNotEmpty) ...[
                const TgcgSectionHeading(title: 'Groups you lead'),
                TgcgRowGroup(
                  children: [
                    for (final group in mine.leading)
                      TgcgActionRow(
                        icon: Icons.diversity_3_outlined,
                        title: group.name,
                        detail: [
                          group.serialNumber,
                          if (group.kindName.isNotEmpty) group.kindName,
                          group.area,
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
                const SizedBox(height: 18),
              ],
              if (mine.groups.any((place) => !place.leads)) ...[
                const TgcgSectionHeading(title: 'Groups you are in'),
                TgcgRowGroup(
                  children: [
                    for (final place in mine.groups)
                      if (!place.leads)
                        TgcgActionRow(
                          icon: Icons.groups_outlined,
                          title: place.groupName,
                          detail: [
                            'Led by ${place.leaderName}',
                            if (place.kindName.isNotEmpty) place.kindName,
                            place.coverageLabel,
                          ].join(' · '),
                          trailing: TextButton(
                            onPressed: _busy.contains(place.id) ? null : () => _leave(place),
                            child: const Text('Leave'),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 18),
              ],
              if (mine.invitations.isEmpty && mine.leading.isEmpty && mine.groups.isEmpty)
                const TgcgEmptyState(
                  icon: Icons.diversity_3_outlined,
                  title: 'You are not in a support group',
                  message:
                      'Join one with the code its leader gives you, or register your own '
                      'organization.',
                ),
              const SizedBox(height: 6),
              TgcgRowGroup(
                children: [
                  TgcgActionRow(
                    icon: Icons.pin_outlined,
                    title: "Join with a group's code",
                    detail: 'The 7-digit code from its leader',
                    onTap: _join,
                  ),
                  TgcgActionRow(
                    icon: Icons.add_business_outlined,
                    title: 'Register an organization',
                    detail: 'TGCG vets it before it can add members',
                    onTap: _register,
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _Invitation extends StatelessWidget {
  const _Invitation({required this.place, required this.busy, required this.onAnswer});

  final MyGroupPlace place;
  final bool busy;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
    title: place.leads
        ? '${place.groupName} names you as its leader'
        : '${place.groupName} lists you as a member',
    subtitle: place.leads
        ? 'Registered with TGCG as ${place.serialNumber}. Say yes if you lead it; TGCG vets '
              'it after that.'
        : 'Led by ${place.leaderName}. The group sees your name and place only after you say yes.',
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: busy ? null : () => onAnswer(false),
            child: const Text('No'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: busy ? null : () => onAnswer(true),
            child: Text(place.leads ? 'Yes, I lead it' : 'Yes, I am a member'),
          ),
        ),
      ],
    ),
  );
}

class _JoinDialog extends StatefulWidget {
  const _JoinDialog();

  @override
  State<_JoinDialog> createState() => _JoinDialogState();
}

class _JoinDialogState extends State<_JoinDialog> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (_code.text.trim().length != 7) {
      setState(() => _error = 'The code has 7 digits.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TgcgBackend.of(context)!.supportGroups.join(_code.text);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.fieldError('group_code') ?? error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Join a support group'),
    content: TextField(
      controller: _code,
      autofocus: true,
      keyboardType: TextInputType.number,
      maxLength: 7,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: (_) => _join(),
      decoration: InputDecoration(labelText: "The group's code", errorText: _error),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _busy ? null : _join, child: const Text('Join')),
    ],
  );
}

/// A signed-in member registers an organization: one they lead, or one led
/// by someone they name, as when entering a paper form.
class RegisterOrganizationPage extends StatefulWidget {
  const RegisterOrganizationPage({super.key});

  @override
  State<RegisterOrganizationPage> createState() => _RegisterOrganizationPageState();
}

class _RegisterOrganizationPageState extends State<RegisterOrganizationPage> {
  final _draft = OrganizationDraft();
  final _leaderName = TextEditingController();
  final _leaderPhone = TextEditingController();
  bool _someoneElse = false;
  bool _consent = false;
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _draft.dispose();
    _leaderName.dispose();
    _leaderPhone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final errors = {
      ..._draft.check(),
      if (_someoneElse && _leaderName.text.trim().isEmpty)
        'leader_full_name': "Enter the leader's name.",
      if (_someoneElse && _leaderPhone.text.trim().isEmpty)
        'leader_phone_number': "Enter the leader's phone number.",
    };
    if (errors.isNotEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() {
      _busy = true;
      _errors = {};
    });
    try {
      final group = await TgcgBackend.of(context)!.supportGroups.register(
        _draft.details,
        leaderName: _someoneElse ? _leaderName.text : '',
        leaderPhone: _someoneElse ? _leaderPhone.text : '',
        consent: _someoneElse && _consent,
      );
      if (mounted) Navigator.pop(context, group);
    } on ApiException catch (error) {
      if (!mounted) return;
      final fields = {for (final entry in error.fieldErrors.entries) entry.key: entry.value.first};
      setState(() => _errors = fields.isEmpty ? {'general': error.message} : fields);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(title: const Text('Register an organization')),
    body: SafeArea(
      child: TgcgPageList(
        children: [
          if (_errors['general'] ?? _errors['detail'] case final message?) ...[
            TgcgNotice(
              icon: Icons.error_outline_rounded,
              color: TgcgColors.danger,
              child: Text(message),
            ),
            const SizedBox(height: 14),
          ],
          TgcgSectionCard(
            child: OrganizationFields(
              draft: _draft,
              errors: _errors,
              onChanged: () => setState(() {}),
            ),
          ),
          const SizedBox(height: 14),
          TgcgSectionCard(
            title: 'Who leads it?',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('I lead it')),
                    ButtonSegment(value: true, label: Text('Someone else')),
                  ],
                  selected: {_someoneElse},
                  onSelectionChanged: (value) => setState(() => _someoneElse = value.first),
                ),
                if (_someoneElse) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _leaderName,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: "Leader's full name",
                      errorText: _errors['leader_full_name'],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _leaderPhone,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: "Leader's phone number (WhatsApp)",
                      helperText:
                          'A TGCG member is asked in the app to say yes. Someone new '
                          'joins TGCG with this number as their first PIN.',
                      helperMaxLines: 3,
                      errorText: _errors['leader_phone_number'],
                    ),
                  ),
                  Material(
                    type: MaterialType.transparency,
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _consent,
                      onChanged: (value) => setState(() => _consent = value ?? false),
                      title: const Text(
                        'If the leader is not yet a TGCG member, they agreed to join TGCG and to '
                        'TGCG keeping their name and number.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                  if (_errors['consent'] case final error?)
                    Text(error, style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.how_to_reg_outlined),
            label: const Text('Register the organization'),
          ),
        ],
      ),
    ),
  );
}
