
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../access/access_widgets.dart' show failureMessage, showFailure;
import '../api/access_repository.dart' show ApiPage;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/support_groups_repository.dart';
import '../member/referral.dart' show ShareText, shareTextWithDevice;
import '../ui/tgcg_design.dart';
import 'my_support_groups_page.dart' show groupStatus;

typedef ListFile = ({Uint8List bytes, String name});
typedef PickListFile = Future<ListFile?> Function();

/// A list from the device's files: Excel, CSV, Word, PDF or a photo.
Future<ListFile?> pickListFileWithDevice() async {
  const lists = XTypeGroup(
    label: 'Lists',
    extensions: ['xlsx', 'csv', 'docx', 'pdf', 'jpg', 'jpeg', 'png'],
    mimeTypes: [
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'text/csv',
      'text/comma-separated-values',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'application/pdf',
      'image/jpeg',
      'image/png',
    ],
    uniformTypeIdentifiers: [
      'org.openxmlformats.spreadsheetml.sheet',
      'public.comma-separated-values-text',
      'org.openxmlformats.wordprocessingml.document',
      'com.adobe.pdf',
      'public.jpeg',
      'public.png',
    ],
  );
  final file = await openFile(acceptedTypeGroups: const [lists]);
  if (file == null) return null;
  return (bytes: await file.readAsBytes(), name: file.name);
}

/// What happened to someone sent to be added, in a few words.
String addOutcomeLabel(String outcome) => switch (outcome) {
  'registered' => 'Registered with TGCG and added',
  'asked' => 'Already a TGCG member: asked in the app to say yes',
  'already' => 'Already in the group, or already asked',
  'declined' => 'Said no to this group before',
  'left' => 'Left this group',
  _ => 'Not added',
};

/// The group a member leads: its code and link once approved, who is in it,
/// adding people one by one or from a list, and messages to them in the app.
class LedGroupPage extends StatefulWidget {
  const LedGroupPage({
    super.key,
    required this.groupId,
    this.pickFile = pickListFileWithDevice,
    this.share = shareTextWithDevice,
  });

  final String groupId;
  final PickListFile pickFile;
  final ShareText share;

  @override
  State<LedGroupPage> createState() => _LedGroupPageState();
}

class _LedGroupPageState extends State<LedGroupPage> {
  Future<SupportGroup>? _group;
  final _people = <GroupPerson>[];
  bool _loadingPeople = false;
  bool _morePeople = false;
  Object? _peopleError;
  bool _reading = false;

  SupportGroupsRepository get _groups => TgcgBackend.of(context)!.supportGroups;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_group == null) _reload();
  }

  void _reload() {
    setState(() {
      _group = _groups.led(widget.groupId);
      _people.clear();
      _morePeople = false;
      _peopleError = null;
    });
    _loadPeople();
  }

  Future<void> _loadPeople() async {
    setState(() => _loadingPeople = true);
    try {
      final ApiPage<GroupPerson> page = await _groups.people(
        widget.groupId,
        offset: _people.length,
      );
      if (!mounted) return;
      setState(() {
        _people.addAll(page.items);
        _morePeople = page.hasMore;
      });
    } catch (error) {
      if (mounted) setState(() => _peopleError = error);
    } finally {
      if (mounted) setState(() => _loadingPeople = false);
    }
  }

  void _say(String message) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _say('$what copied.');
  }

  Future<void> _addOne() async {
    final result = await showDialog<AddResult>(
      context: context,
      builder: (_) => _AddPersonDialog(groupId: widget.groupId),
    );
    if (result == null || !mounted) return;
    _say(result.outcome == 'problem' ? result.detail : addOutcomeLabel(result.outcome));
    _reload();
  }

  Future<void> _upload(SupportGroup group) async {
    ListFile? file;
    try {
      file = await widget.pickFile();
    } catch (error) {
      if (mounted) showFailure(context, error);
      return;
    }
    if (file == null || !mounted) return;
    setState(() => _reading = true);
    try {
      final read = await _groups.readList(widget.groupId, file);
      if (!mounted) return;
      final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ListReviewPage(group: group, fileName: file!.name, read: read),
        ),
      );
      if (added == true && mounted) _reload();
    } on ApiException catch (error) {
      if (mounted) _say(error.fieldError('file') ?? error.message);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _reading = false);
    }
  }

  Future<void> _message(SupportGroup group) async {
    final people = await showDialog<int>(
      context: context,
      builder: (_) => _MessageDialog(group: group),
    );
    if (people != null && mounted) {
      _say('Sent in the app to $people ${people == 1 ? 'person' : 'people'}.');
    }
  }

  Future<void> _remove(GroupPerson person) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${person.fullName.isEmpty ? person.phoneNumber : person.fullName}?'),
        content: const Text('They stay a member of TGCG.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    try {
      await _groups.remove(widget.groupId, person.id);
      if (mounted) _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(
      title: const Text('Your group'),
      actions: [
        IconButton(
          tooltip: 'Load again',
          onPressed: _reload,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
    ),
    body: SafeArea(
      child: FutureBuilder<SupportGroup>(
        future: _group,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TgcgEmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'The group could not be loaded',
              message: failureMessage(snapshot.error!),
              action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
            );
          }
          final group = snapshot.data;
          if (group == null) return const LinearProgressIndicator(minHeight: 2);
          final (status, color) = groupStatus(group);
          return TgcgPageList(
            children: [
              TgcgSectionCard(
                title: group.name,
                subtitle: [
                  group.serialNumber,
                  if (group.kindName.isNotEmpty) group.kindName,
                  group.area,
                ].join(' · '),
                trailing: TgcgStatusPill(label: status, color: color),
                trailingBeside: true,
                child: _GroupState(group: group),
              ),
              if (group.isApproved) ...[
                const SizedBox(height: 14),
                TgcgMetricGrid(
                  across: const [3, 3, 3],
                  cards: [
                    TgcgMetricCard(
                      label: 'In the group',
                      value: '${group.members ?? 0}',
                      icon: Icons.groups_outlined,
                    ),
                    TgcgMetricCard(
                      label: 'Approved by TGCG',
                      value: '${group.approvedMembers ?? 0}',
                      icon: Icons.verified_outlined,
                      tone: TgcgMetricTone.success,
                    ),
                    TgcgMetricCard(
                      label: 'Waiting to say yes',
                      value: '${group.waiting ?? 0}',
                      icon: Icons.hourglass_top_rounded,
                      tone: TgcgMetricTone.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TgcgSectionCard(
                  title: 'Invite people',
                  subtitle:
                      'Members join with the code. Someone new joins TGCG and the group '
                      'through the link.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectableText(group.joinCode ?? '', style: TgcgType.title),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => _copy(group.joinCode ?? '', 'Code'),
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text('Copy code'),
                          ),
                          if (group.link case final link?) ...[
                            OutlinedButton.icon(
                              onPressed: () => _copy(link, 'Link'),
                              icon: const Icon(Icons.link_rounded),
                              label: const Text('Copy link'),
                            ),
                            FilledButton.icon(
                              onPressed: () => widget.share(
                                'Join ${group.name} in TGCG: $link (group code ${group.joinCode})',
                              ),
                              icon: const Icon(Icons.share_rounded),
                              label: const Text('Share'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                TgcgRowGroup(
                  children: [
                    TgcgActionRow(
                      icon: Icons.person_add_alt_1_rounded,
                      title: 'Add a person',
                      detail: 'A name and phone number',
                      onTap: _addOne,
                    ),
                    TgcgActionRow(
                      icon: Icons.upload_file_rounded,
                      title: _reading ? 'Reading the list…' : 'Upload a list',
                      detail: 'Excel, CSV, Word, PDF or a photo of the list',
                      trailing: _reading
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                      onTap: _reading ? null : () => _upload(group),
                    ),
                    TgcgActionRow(
                      icon: Icons.mark_chat_unread_outlined,
                      title: 'Message the group',
                      detail: 'In the app, to everyone in the group',
                      onTap: () => _message(group),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              const TgcgSectionHeading(title: 'People'),
              if (_peopleError != null && _people.isEmpty)
                TgcgNotice(
                  icon: Icons.cloud_off_outlined,
                  color: TgcgColors.danger,
                  child: Text(failureMessage(_peopleError!)),
                )
              else if (_people.isEmpty && _loadingPeople)
                const LinearProgressIndicator(minHeight: 2)
              else
                TgcgRowGroup(
                  children: [
                    for (final person in _people)
                      _PersonRow(
                        person: person,
                        onRemove: group.isApproved && !person.leads ? () => _remove(person) : null,
                      ),
                  ],
                ),
              if (_morePeople) ...[
                const SizedBox(height: 10),
                Center(
                  child: OutlinedButton(
                    onPressed: _loadingPeople ? null : _loadPeople,
                    child: const Text('Show more'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
}

class _GroupState extends StatelessWidget {
  const _GroupState({required this.group});

  final SupportGroup group;

  @override
  Widget build(BuildContext context) {
    final text = switch (group.status) {
      'approved' => 'Add your members below. Each one is asked or registered as needed.',
      'pending' when !group.leaderConfirmed =>
        'Waiting for ${group.leader.fullName} to say yes in the app. TGCG vets it after that.',
      'pending' => 'TGCG is vetting the organization. You will hear in your messages.',
      'suspended' => 'TGCG suspended the group: ${group.decisionReason}',
      _ =>
        group.decisionReason.isEmpty
            ? 'TGCG did not approve the organization.'
            : 'TGCG did not approve the organization: ${group.decisionReason}',
    };
    return Text(text, style: TgcgType.support);
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({required this.person, this.onRemove});

  final GroupPerson person;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final detail = [
      person.phoneNumber,
      if (person.place.isNotEmpty) person.place,
      if (person.leads) 'Leader',
    ].join(' · ');
    final (label, color) = person.isWaiting
        ? ('Waiting to say yes', TgcgColors.warning)
        : person.approved == true
        ? ('Approved', TgcgColors.success)
        : ('Not yet approved', TgcgColors.muted);
    return TgcgActionRow(
      icon: person.isWaiting ? Icons.hourglass_top_rounded : Icons.person_outline_rounded,
      color: person.isWaiting ? TgcgColors.warning : TgcgColors.primary,
      title: person.fullName.isEmpty ? person.phoneNumber : person.fullName,
      detail: detail,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TgcgStatusPill(compact: true, label: label, color: color),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove from the group',
              onPressed: onRemove,
              icon: const Icon(Icons.person_remove_outlined, size: 20),
            ),
        ],
      ),
    );
  }
}

class _AddPersonDialog extends StatefulWidget {
  const _AddPersonDialog({required this.groupId});

  final String groupId;

  @override
  State<_AddPersonDialog> createState() => _AddPersonDialogState();
}

class _AddPersonDialogState extends State<_AddPersonDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  bool _consent = false;
  bool _busy = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final errors = {
      if (_name.text.trim().isEmpty) 'full_name': 'Enter their full name.',
      if (_phone.text.trim().isEmpty) 'phone_number': 'Enter their phone number.',
      if (!_consent) 'consent': 'Tick the box to confirm.',
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
      final results = await TgcgBackend.of(context)!.supportGroups.add(widget.groupId, [
        {'full_name': _name.text.trim(), 'phone_number': _phone.text.trim()},
      ], consent: true);
      if (!mounted) return;
      final result = results.first;
      if (result.outcome == 'problem') {
        setState(() => _errors = {'phone_number': result.detail});
        return;
      }
      Navigator.pop(context, result);
    } on ApiException catch (error) {
      if (mounted) setState(() => _errors = {'phone_number': error.message});
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a person'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Full name', errorText: _errors['full_name']),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Phone number',
              helperText: 'Someone new signs in with this number as their PIN.',
              helperMaxLines: 2,
              errorText: _errors['phone_number'],
              errorMaxLines: 3,
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _consent,
            onChanged: (value) => setState(() => _consent = value ?? false),
            title: const Text(
              'They agreed to join TGCG and to be listed in this group.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          if (_errors['consent'] case final error?)
            Text(error, style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5)),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _busy ? null : _add, child: const Text('Add')),
    ],
  );
}

class _MessageDialog extends StatefulWidget {
  const _MessageDialog({required this.group});

  final SupportGroup group;

  @override
  State<_MessageDialog> createState() => _MessageDialogState();
}

class _MessageDialogState extends State<_MessageDialog> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      setState(() => _error = 'Write a title and the message.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final people = await TgcgBackend.of(
        context,
      )!.supportGroups.message(widget.group.id, title: _title.text, body: _body.text);
      if (mounted) Navigator.pop(context, people);
    } on ApiException catch (error) {
      if (mounted) {
        setState(
          () => _error = error.fieldError('body') ?? error.fieldError('title') ?? error.message,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Message ${widget.group.name}'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _title,
            maxLength: 80,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: _body,
            maxLength: 1000,
            minLines: 3,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Message',
              helperText: 'Everyone in the group gets it in the app. No SMS is sent.',
              helperMaxLines: 2,
              errorText: _error,
              errorMaxLines: 3,
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _busy ? null : _send, child: const Text('Send')),
    ],
  );
}

/// The people read from an uploaded list, to check before adding them. Lines
/// with a problem cannot be added; the others can be unticked. Long lists go
/// to the server in batches.
class ListReviewPage extends StatefulWidget {
  const ListReviewPage({
    super.key,
    required this.group,
    required this.fileName,
    required this.read,
  });

  final SupportGroup group;
  final String fileName;
  final ReadList read;

  @override
  State<ListReviewPage> createState() => _ListReviewPageState();
}

class _ListReviewPageState extends State<ListReviewPage> {
  late final Set<int> _chosen = {
    for (final person in widget.read.people)
      if (person.canAdd) person.line,
  };
  bool _consent = false;
  String? _consentError;
  int? _sent;
  List<AddResult>? _results;
  String? _stoppedBy;

  List<ListedPerson> get _toAdd => [
    for (final person in widget.read.people)
      if (_chosen.contains(person.line)) person,
  ];

  Future<void> _add() async {
    if (!_consent) {
      setState(() => _consentError = 'Tick the box to confirm.');
      return;
    }
    final people = _toAdd;
    final groups = TgcgBackend.of(context)!.supportGroups;
    final results = <AddResult>[];
    setState(() {
      _sent = 0;
      _consentError = null;
      _stoppedBy = null;
    });
    for (var start = 0; start < people.length; start += addBatchSize) {
      final batch = people.skip(start).take(addBatchSize).toList();
      try {
        results.addAll(
          await groups.add(widget.group.id, [
            for (final person in batch) person.toJson(),
          ], consent: true),
        );
      } catch (error) {
        if (!mounted) return;
        setState(() => _stoppedBy = failureMessage(error));
        break;
      }
      if (!mounted) return;
      setState(() => _sent = start + batch.length);
    }
    if (mounted) setState(() => _results = results);
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.read.people;
    final problems = people.where((person) => !person.canAdd).length;
    final results = _results;
    final adding = _sent != null && results == null;
    return PopScope(
      canPop: !adding,
      child: Scaffold(
        backgroundColor: TgcgColors.canvas,
        appBar: AppBar(
          title: const Text('Check the list'),
          leading: results == null
              ? null
              : IconButton(
                  tooltip: 'Done',
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.close_rounded),
                ),
        ),
        body: SafeArea(
          child: TgcgPageList(
            children: [
              TgcgSectionCard(
                title: widget.fileName,
                subtitle:
                    '${people.length} ${people.length == 1 ? 'person' : 'people'} found'
                    '${problems > 0 ? ', $problems with a problem' : ''}. Check each name and '
                    'number against the list.',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final note in widget.read.notes) ...[
                      TgcgNotice(
                        icon: Icons.info_outline_rounded,
                        color: TgcgColors.warning,
                        child: Text(note),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (results == null) ...[
                      Material(
                        type: MaterialType.transparency,
                        child: CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: _consent,
                          onChanged: adding
                              ? null
                              : (value) => setState(() {
                                  _consent = value ?? false;
                                  _consentError = null;
                                }),
                          title: Text(
                            'These people agreed to join TGCG and to be listed in '
                            '${widget.group.name}.',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                      ),
                      if (_consentError case final error?)
                        Text(
                          error,
                          style: const TextStyle(color: TgcgColors.danger, fontSize: 12.5),
                        ),
                      const SizedBox(height: 8),
                      if (adding) ...[
                        LinearProgressIndicator(
                          value: _toAdd.isEmpty ? null : _sent! / _toAdd.length,
                          minHeight: 6,
                        ),
                        const SizedBox(height: 6),
                        Text('Adding $_sent of ${_toAdd.length}…', style: TgcgType.caption),
                      ] else
                        FilledButton.icon(
                          onPressed: _chosen.isEmpty ? null : _add,
                          icon: const Icon(Icons.group_add_outlined),
                          label: Text(
                            'Add ${_chosen.length} ${_chosen.length == 1 ? 'person' : 'people'}',
                          ),
                        ),
                    ] else
                      _Summary(results: results, stoppedBy: _stoppedBy),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TgcgRowGroup(
                children: [
                  for (final person in people)
                    _ListedRow(
                      person: person,
                      chosen: _chosen.contains(person.line),
                      result: results?.where((result) => result.line == person.line).firstOrNull,
                      onChanged: results != null || adding || !person.canAdd
                          ? null
                          : (value) => setState(() {
                              value ? _chosen.add(person.line) : _chosen.remove(person.line);
                            }),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.results, this.stoppedBy});

  final List<AddResult> results;
  final String? stoppedBy;

  @override
  Widget build(BuildContext context) {
    int count(String outcome) => results.where((result) => result.outcome == outcome).length;
    final lines = [
      if (count('registered') > 0) '${count('registered')} registered with TGCG and added',
      if (count('asked') > 0) '${count('asked')} already members, asked in the app to say yes',
      if (count('already') > 0) '${count('already')} already in the group',
      if (count('declined') + count('left') > 0)
        '${count('declined') + count('left')} said no or left before, not asked again',
      if (count('problem') > 0) '${count('problem')} not added: see the lines marked below',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (stoppedBy != null) ...[
          TgcgNotice(
            icon: Icons.cloud_off_outlined,
            color: TgcgColors.danger,
            child: Text('Adding stopped after ${results.length}: $stoppedBy'),
          ),
          const SizedBox(height: 8),
        ],
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(line, style: TgcgType.bodyStrong),
          ),
      ],
    );
  }
}

class _ListedRow extends StatelessWidget {
  const _ListedRow({required this.person, required this.chosen, this.result, this.onChanged});

  final ListedPerson person;
  final bool chosen;
  final AddResult? result;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final note = !person.canAdd
        ? person.problem
        : result == null
        ? (person.place.isEmpty ? 'No place given' : person.place)
        : result.outcome == 'problem'
        ? result.detail
        : addOutcomeLabel(result.outcome);
    final bad = !person.canAdd || result?.outcome == 'problem';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: person.canAdd && chosen,
            onChanged: onChanged == null ? null : (value) => onChanged!(value ?? false),
          ),
          SizedBox(width: 34, child: Text('${person.line}', style: TgcgType.caption)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.fullName.isEmpty ? 'No name' : person.fullName,
                  style: TgcgType.bodyStrong,
                ),
                Text(person.phoneNumber, style: TgcgType.caption),
                Text(note, style: TgcgType.caption.copyWith(color: bad ? TgcgColors.danger : null)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
