import 'package:flutter/material.dart';

import '../access/access_widgets.dart';
import '../api/backend.dart';
import '../api/messaging_repository.dart';
import '../api/projects_repository.dart';
import '../session.dart' show GeographicScope, GeographyLevel;
import '../ui/tgcg_design.dart';

/// SMS pages a message takes, as the server counts them.
int smsPages(String text) {
  final plain = text.codeUnits.every((unit) => unit < 128);
  final (single, part) = plain ? (160, 153) : (70, 67);
  if (text.length <= single) return 1;
  return (text.length + part - 1) ~/ part;
}

String groupSummary(MessageGroup group) {
  switch (group.type) {
    case 'project':
      return 'Team: ${group.name}';
    case 'list':
      return 'List: ${group.name}';
  }
  final who = switch (group.people) {
    'withRole' => 'People with a role',
    'noRole' => 'Members with no role',
    'roles' => group.roles.map((role) => role.$2).join(', '),
    _ => 'Everyone',
  };
  final where = group.areas.isEmpty ? 'all your area' : group.areas.map(areaLabel).join(', ');
  return [
    '$who in $where',
    if (group.gender == 'female') 'women',
    if (group.gender == 'male') 'men',
    if (group.verifiedOnly) 'identity checked',
  ].join(' · ');
}

/// Bulk messages: SMS, WhatsApp and app notifications to groups of members,
/// what was sent, and saved lists. Each channel needs its own power, and
/// reaches only members in the sender's areas.
class MessagesPage extends StatelessWidget {
  const MessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (TgcgBackend.of(context) == null) {
      return const ConnectToServerNotice(
        message: 'Messages are sent from the server. Sign in with a server account to send them.',
      );
    }
    return const DefaultTabController(
      length: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.edit_outlined, size: 20), text: 'New message'),
              Tab(icon: Icon(Icons.outbox_outlined, size: 20), text: 'Sent'),
              Tab(icon: Icon(Icons.list_alt_outlined, size: 20), text: 'Lists'),
            ],
          ),
          Divider(height: 1),
          Expanded(child: TabBarView(children: [_ComposeTab(), _SentTab(), _ListsTab()])),
        ],
      ),
    );
  }
}

class _ComposeTab extends StatefulWidget {
  const _ComposeTab();

  @override
  State<_ComposeTab> createState() => _ComposeTabState();
}

class _ComposeTabState extends State<_ComposeTab> {
  Future<MessagingOptions>? _options;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _channels = <String>{};
  final _groups = <MessageGroup>[];
  MessagePreview? _preview;
  bool _busy = false;

  MessagingRepository get _repository => TgcgBackend.of(context)!.messaging;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _options ??= _repository.options();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _changed() => setState(() => _preview = null);

  bool get _ready =>
      !_busy && _channels.isNotEmpty && _groups.isNotEmpty && _body.text.trim().isNotEmpty;

  Future<void> _addFilter(List<(String, String)> roles) async {
    final group = await showDialog<MessageGroup>(
      context: context,
      builder: (_) => _FilterDialog(roles: roles),
    );
    if (group != null) setState(() => _groups.add(group));
    _changed();
  }

  Future<void> _addProject() async {
    final List<TgcgProject> projects;
    try {
      projects = await TgcgBackend.of(context)!.projects.projects();
    } catch (error) {
      if (mounted) showFailure(context, error);
      return;
    }
    if (!mounted) return;
    final picked = await showDialog<TgcgProject>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('A project team'),
        children: [
          if (projects.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No projects in your areas.')),
          for (final project in projects)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, project),
              child: Text(project.name),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _groups.add(MessageGroup.project(picked.id, picked.name)));
    _changed();
  }

  Future<void> _addList() async {
    final List<SavedList> lists;
    try {
      lists = await _repository.lists();
    } catch (error) {
      if (mounted) showFailure(context, error);
      return;
    }
    if (!mounted) return;
    final picked = await showDialog<SavedList>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('A saved list'),
        children: [
          if (lists.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No saved lists yet.')),
          for (final list in lists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, list),
              child: Text('${list.name} (${list.people})'),
            ),
        ],
      ),
    );
    if (picked != null) setState(() => _groups.add(MessageGroup.list(picked.id, picked.name)));
    _changed();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    try {
      final preview = await _repository.preview(
        channels: _channels.toList(),
        groups: _groups,
        body: _body.text,
      );
      if (mounted) setState(() => _preview = preview);
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final preview = await _repository.preview(
        channels: _channels.toList(),
        groups: _groups,
        body: _body.text,
      );
      if (!mounted) return;
      setState(() => _preview = preview);
      final sure = await confirmAction(
        context,
        title: 'Send to ${preview.people} people?',
        message: [
          for (final channel in _channels)
            '${channelLabel(channel)}: ${preview.channels[channel]?.$1 ?? 0}',
          if (_channels.contains('sms')) 'Each SMS takes ${preview.smsPages} page(s).',
        ].join('\n'),
        action: 'Send',
      );
      if (!sure || !mounted) return;
      final sent = await _repository.send(
        channels: _channels.toList(),
        groups: _groups,
        body: _body.text,
        title: _title.text,
      );
      if (!mounted) return;
      showDone(context, 'Sending to ${sent.people} people.');
      setState(() {
        _body.clear();
        _title.clear();
        _groups.clear();
        _preview = null;
      });
    } catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MessagingOptions>(
    future: _options,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TgcgEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Messages could not be loaded',
            message: failureMessage(snapshot.error!),
          ),
        );
      }
      final options = snapshot.data;
      if (options == null) return const Center(child: CircularProgressIndicator());
      final preview = _preview;
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Send by', style: TextStyle(fontWeight: FontWeight.w800)),
          Wrap(
            spacing: 8,
            children: [
              for (final (channel, label) in messageChannels)
                if (options.channels.contains(channel))
                  FilterChip(
                    label: Text(label),
                    selected: _channels.contains(channel),
                    onSelected: (on) {
                      setState(() => on ? _channels.add(channel) : _channels.remove(channel));
                      _changed();
                    },
                  ),
            ],
          ),
          if (_channels.contains('push'))
            TextField(
              controller: _title,
              maxLength: 120,
              decoration: const InputDecoration(labelText: 'Notification title'),
            ),
          TextField(
            controller: _body,
            minLines: 3,
            maxLines: 8,
            maxLength: 1000,
            decoration: InputDecoration(
              labelText: 'Message',
              helperText: _channels.contains('sms') && _body.text.isNotEmpty
                  ? '${smsPages(_body.text)} SMS page(s)'
                  : null,
            ),
            onChanged: (_) => _changed(),
          ),
          const SizedBox(height: 10),
          const Text('To', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final group in _groups)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(switch (group.type) {
                'project' => Icons.flag_outlined,
                'list' => Icons.list_alt_outlined,
                _ => Icons.groups_2_outlined,
              }),
              title: Text(groupSummary(group)),
              trailing: IconButton(
                tooltip: 'Remove',
                onPressed: () {
                  setState(() => _groups.remove(group));
                  _changed();
                },
                icon: const Icon(Icons.close_rounded),
              ),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              ActionChip(
                avatar: const Icon(Icons.groups_2_outlined, size: 18),
                label: const Text('People'),
                onPressed: () => _addFilter(options.roles),
              ),
              ActionChip(
                avatar: const Icon(Icons.flag_outlined, size: 18),
                label: const Text('Project team'),
                onPressed: _addProject,
              ),
              ActionChip(
                avatar: const Icon(Icons.list_alt_outlined, size: 18),
                label: const Text('Saved list'),
                onPressed: _addList,
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (preview != null)
            TgcgSectionCard(
              title: 'Reaches ${preview.people} people',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final MapEntry(key: channel, value: (reachable, unreachable))
                      in preview.channels.entries)
                    Text(
                      '${channelLabel(channel)}: $reachable'
                      '${unreachable > 0 ? ' ($unreachable with no ${channel == 'push' ? 'app' : 'number'})' : ''}',
                    ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              OutlinedButton(onPressed: _ready ? _check : null, child: const Text('Who it reaches')),
              FilledButton.icon(
                onPressed: _ready ? _send : null,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Send'),
              ),
            ],
          ),
        ],
      );
    },
  );
}

/// People in some areas, narrowed by role, gender or a checked identity.
class _FilterDialog extends StatefulWidget {
  const _FilterDialog({required this.roles});

  final List<(String, String)> roles;

  @override
  State<_FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<_FilterDialog> {
  final _areas = <GeographicScope>[];
  String _people = 'everyone';
  final _roles = <(String, String)>{};
  String _gender = '';
  bool _verifiedOnly = false;

  Future<void> _addArea() async {
    final area = await pickArea(
      context,
      levels: const [
        GeographyLevel.state,
        GeographyLevel.lga,
        GeographyLevel.ward,
        GeographyLevel.pollingUnit,
      ],
    );
    if (area == null || _areas.any((item) => areaLabel(item) == areaLabel(area))) return;
    setState(() => _areas.add(area));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('People'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Where', style: TextStyle(fontWeight: FontWeight.w800)),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (_areas.isEmpty) const Chip(label: Text('All your area')),
                for (final area in _areas)
                  InputChip(
                    label: Text(areaLabel(area)),
                    onDeleted: () => setState(() => _areas.remove(area)),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add area'),
                  onPressed: _addArea,
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _people,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Who'),
              items: const [
                DropdownMenuItem(value: 'everyone', child: Text('Everyone')),
                DropdownMenuItem(value: 'withRole', child: Text('People with a role')),
                DropdownMenuItem(value: 'noRole', child: Text('Members with no role')),
                DropdownMenuItem(value: 'roles', child: Text('Chosen roles')),
              ],
              onChanged: (value) => setState(() => _people = value ?? 'everyone'),
            ),
            if (_people == 'roles')
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final role in widget.roles)
                    FilterChip(
                      label: Text(role.$2),
                      selected: _roles.contains(role),
                      onSelected: (on) => setState(() => on ? _roles.add(role) : _roles.remove(role)),
                    ),
                ],
              ),
            DropdownButtonFormField<String>(
              initialValue: _gender,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Gender'),
              items: const [
                DropdownMenuItem(value: '', child: Text('Women and men')),
                DropdownMenuItem(value: 'female', child: Text('Women')),
                DropdownMenuItem(value: 'male', child: Text('Men')),
              ],
              onChanged: (value) => setState(() => _gender = value ?? ''),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only checked identities'),
              value: _verifiedOnly,
              onChanged: (value) => setState(() => _verifiedOnly = value),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      FilledButton(
        onPressed: _people == 'roles' && _roles.isEmpty
            ? null
            : () => Navigator.pop(
                context,
                MessageGroup.filter(
                  areas: List.of(_areas),
                  people: _people,
                  roles: _roles.toList(),
                  gender: _gender,
                  verifiedOnly: _verifiedOnly,
                ),
              ),
        child: const Text('Add'),
      ),
    ],
  );
}

class _SentTab extends StatefulWidget {
  const _SentTab();

  @override
  State<_SentTab> createState() => _SentTabState();
}

class _SentTabState extends State<_SentTab> {
  Future<List<SentMessage>>? _sent;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sent ??= TgcgBackend.of(context)!.messaging.sent();
  }

  void _reload() => setState(() {
    _sent = TgcgBackend.of(context)!.messaging.sent();
  });

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SentMessage>>(
    future: _sent,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TgcgEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Sent messages could not be loaded',
            message: failureMessage(snapshot.error!),
            action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
          ),
        );
      }
      final sent = snapshot.data;
      if (sent == null) return const Center(child: CircularProgressIndicator());
      if (sent.isEmpty) {
        return const Center(
          child: TgcgEmptyState(
            icon: Icons.outbox_outlined,
            title: 'Nothing sent yet',
            message: 'Messages you send appear here.',
          ),
        );
      }
      return RefreshIndicator(
        onRefresh: () async => _reload(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final message in sent)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (message.title.isNotEmpty)
                        Text(message.title, style: const TextStyle(fontWeight: FontWeight.w800)),
                      Text(message.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Text(
                        [
                          if (message.createdAt != null) formatMoment(message.createdAt!),
                          '${message.people} people',
                          message.status == 'done' ? 'sent' : 'sending',
                        ].join(' · '),
                        style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                      ),
                      for (final channel in message.channels)
                        Text(
                          '${channelLabel(channel)}: ${message.count(channel, 'sent')} sent'
                          '${message.count(channel, 'failed') > 0 ? ', ${message.count(channel, 'failed')} not sent' : ''}'
                          '${message.count(channel, 'queued') + message.count(channel, 'sending') > 0 ? ', ${message.count(channel, 'queued') + message.count(channel, 'sending')} waiting' : ''}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}

List<String> _numbers(String text) => [
  for (final part in text.split(RegExp(r'[\s,;]+')))
    if (part.trim().isNotEmpty) part.trim().toUpperCase(),
];

class _ListsTab extends StatefulWidget {
  const _ListsTab();

  @override
  State<_ListsTab> createState() => _ListsTabState();
}

class _ListsTabState extends State<_ListsTab> {
  Future<List<SavedList>>? _lists;

  MessagingRepository get _repository => TgcgBackend.of(context)!.messaging;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lists ??= _repository.lists();
  }

  void _reload() => setState(() {
    _lists = _repository.lists();
  });

  Future<void> _create() async {
    final made = await showDialog<(String, List<String>)>(
      context: context,
      builder: (_) => const _ListDialog(),
    );
    if (made == null) return;
    try {
      await _repository.createList(made.$1, members: made.$2);
      if (!mounted) return;
      showDone(context, 'List saved.');
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _open(SavedList summary) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ListDetailDialog(listId: summary.id),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<SavedList>>(
    future: _lists,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Center(
          child: TgcgEmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Lists could not be loaded',
            message: failureMessage(snapshot.error!),
            action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
          ),
        );
      }
      final lists = snapshot.data;
      if (lists == null) return const Center(child: CircularProgressIndicator());
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New list'),
            ),
          ),
          const SizedBox(height: 10),
          if (lists.isEmpty)
            const TgcgEmptyState(
              icon: Icons.list_alt_outlined,
              title: 'No saved lists',
              message: 'Lists you save appear here.',
            ),
          for (final list in lists)
            Card(
              child: ListTile(
                title: Text(list.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${list.people} people'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _open(list),
              ),
            ),
        ],
      );
    },
  );
}

/// A new list's name and membership numbers.
class _ListDialog extends StatefulWidget {
  const _ListDialog();

  @override
  State<_ListDialog> createState() => _ListDialogState();
}

class _ListDialogState extends State<_ListDialog> {
  final _name = TextEditingController();
  final _members = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _members.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New list'),
    content: SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Name'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _members,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Membership numbers',
              hintText: 'TGCG-000123, TGCG-000456',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      FilledButton(
        onPressed: _name.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (_name.text.trim(), _numbers(_members.text))),
        child: const Text('Save'),
      ),
    ],
  );
}

/// A saved list's people: add or remove them, or delete the list.
class _ListDetailDialog extends StatefulWidget {
  const _ListDetailDialog({required this.listId});

  final String listId;

  @override
  State<_ListDetailDialog> createState() => _ListDetailDialogState();
}

class _ListDetailDialogState extends State<_ListDetailDialog> {
  Future<SavedList>? _list;
  final _add = TextEditingController();

  MessagingRepository get _repository => TgcgBackend.of(context)!.messaging;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _list ??= _repository.list(widget.listId);
  }

  @override
  void dispose() {
    _add.dispose();
    super.dispose();
  }

  Future<void> _change({List<String> add = const [], List<String> remove = const []}) async {
    try {
      final list = await _repository.updateList(widget.listId, add: add, remove: remove);
      if (!mounted) return;
      _add.clear();
      setState(() => _list = Future.value(list));
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _delete(SavedList list) async {
    final sure = await confirmAction(
      context,
      title: 'Delete ${list.name}?',
      message: 'The people stay members; only the list goes.',
      action: 'Delete',
      destructive: true,
    );
    if (!sure || !mounted) return;
    try {
      await _repository.deleteList(list.id);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<SavedList>(
    future: _list,
    builder: (context, snapshot) {
      final list = snapshot.data;
      return AlertDialog(
        title: Text(list?.name ?? 'List'),
        content: SizedBox(
          width: 440,
          height: 420,
          child: snapshot.hasError
              ? Text(failureMessage(snapshot.error!))
              : list == null
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _add,
                            decoration: const InputDecoration(labelText: 'Add membership numbers'),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _change(add: _numbers(_add.text)),
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    Expanded(
                      child: ListView(
                        children: [
                          for (final (number, name) in list.members)
                            ListTile(
                              dense: true,
                              title: Text(name),
                              subtitle: Text(number),
                              trailing: IconButton(
                                tooltip: 'Remove',
                                onPressed: () => _change(remove: [number]),
                                icon: const Icon(Icons.person_remove_outlined),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
        ),
        actions: [
          if (list != null)
            TextButton(onPressed: () => _delete(list), child: const Text('Delete list')),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      );
    },
  );
}
