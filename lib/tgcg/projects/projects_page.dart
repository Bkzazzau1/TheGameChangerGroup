import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart';
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/projects_repository.dart';
import '../api/reference_repository.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/app_on_screen.dart';
import '../ui/tgcg_design.dart';
import 'project_mode.dart';

const _watching = [TgcgCapability.viewLiveOperations, TgcgCapability.assignProjectParticipants];

TgcgStatusPill projectStatusPill(String status) => TgcgStatusPill(
  compact: true,
  label: switch (status) {
    'scheduled' => 'Scheduled',
    'active' => 'On now',
    'ended' => 'Ended',
    'cancelled' => 'Cancelled',
    _ => status,
  },
  color: switch (status) {
    'active' => TgcgColors.success,
    'scheduled' => TgcgColors.info,
    'cancelled' => TgcgColors.danger,
    _ => TgcgColors.muted,
  },
);

String personStateLabel(String state) => switch (state) {
  'atPlace' => 'At their place',
  'away' => 'Away from their place',
  'unverified' => 'Place not checked',
  'suspect' => 'Location may be faked',
  'noGps' => 'No GPS',
  'notSharing' => 'Not sharing location',
  'notStarted' => 'Not started',
  'waiting' => 'Waiting for the start',
  'invited' => 'Not answered',
  'declined' => 'Declined',
  'withdrawn' => 'Withdrew',
  'removed' => 'Removed',
  _ => state,
};

TgcgStatusPill personStatePill(String state) => TgcgStatusPill(
  compact: true,
  label: personStateLabel(state),
  color: switch (state) {
    'atPlace' => TgcgColors.success,
    'away' || 'suspect' => TgcgColors.danger,
    'notSharing' || 'noGps' => TgcgColors.warning,
    'unverified' => TgcgColors.info,
    _ => TgcgColors.muted,
  },
);

/// Projects: scheduled periods of field work, such as an election. A
/// National Administrator schedules them; coordinators assign people and
/// watch where they are.
class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  Future<List<TgcgProject>>? _projects;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TgcgBackend.of(context) != null) _projects ??= _load();
  }

  Future<List<TgcgProject>> _load() => TgcgBackend.of(context)!.projects.projects();

  void _reload() => setState(() {
    _projects = _load();
  });

  Future<void> _create() async {
    final mode = ProjectMode.of(context);
    final made = await showDialog<TgcgProject>(
      context: context,
      builder: (_) => const ProjectFormDialog(),
    );
    if (made == null || !mounted) return;
    showDone(context, '${made.name} is scheduled.');
    _reload();
    unawaited(mode?.refresh());
  }

  Future<void> _open(TgcgProject project) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => ProjectDetailPage(projectId: project.id)),
    );
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (TgcgBackend.of(context) == null) {
      return const ConnectToServerNotice(
        message: 'Projects are scheduled on the server. Sign in with a server account to see them.',
      );
    }
    final session = TgcgSession.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Projects', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ),
            if (session.can(TgcgCapability.manageProjects))
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New project'),
              ),
          ],
        ),
        const SizedBox(height: 14),
        FutureBuilder<List<TgcgProject>>(
          future: _projects,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TgcgEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Projects could not be loaded',
                message: failureMessage(snapshot.error!),
                action: OutlinedButton(onPressed: _reload, child: const Text('Try again')),
              );
            }
            final projects = snapshot.data;
            if (projects == null) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (projects.isEmpty) {
              return const TgcgEmptyState(
                icon: Icons.flag_outlined,
                title: 'No projects',
                message: 'Projects in your areas appear here.',
              );
            }
            return Column(
              children: [
                for (final project in projects)
                  Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () => _open(project),
                      title: Text(
                        project.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        [
                          '${formatMoment(project.startsAt)} to ${formatMoment(project.endsAt)}',
                          project.areas.map(areaLabel).join(', '),
                          ?project.electionName,
                        ].join('\n'),
                      ),
                      isThreeLine: true,
                      trailing: projectStatusPill(statusNow(project)),
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

/// One project: when and where it runs, the account's own place in it, and
/// for coordinators, who is where.
class ProjectDetailPage extends StatefulWidget {
  const ProjectDetailPage({super.key, required this.projectId});

  final String projectId;

  @override
  State<ProjectDetailPage> createState() => _ProjectDetailPageState();
}

class _ProjectDetailPageState extends State<ProjectDetailPage> {
  Future<TgcgProject>? _project;
  Future<ProjectMonitor>? _monitor;
  Timer? _timer;

  ProjectsRepository get _repository => TgcgBackend.of(context)!.projects;

  bool get _watches => TgcgSession.of(context, listen: false).canAny(_watching);

  @override
  void initState() {
    super.initState();
    // Who is where changes all the time while a project runs.
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted && _watches && appOnScreen) {
        setState(() {
          _monitor = _repository.monitor(widget.projectId);
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_project == null) _load();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _load() {
    _project = _repository.project(widget.projectId);
    _monitor = _watches ? _repository.monitor(widget.projectId) : null;
  }

  void _reload() {
    setState(_load);
    unawaited(ProjectMode.of(context)?.refresh());
  }

  Future<void> _run(Future<Object?> Function() action, String done) async {
    try {
      await action();
      if (!mounted) return;
      showDone(context, done);
      _reload();
    } catch (error) {
      if (mounted) showFailure(context, error);
    }
  }

  Future<void> _edit(TgcgProject project) async {
    final saved = await showDialog<TgcgProject>(
      context: context,
      builder: (_) => ProjectFormDialog(project: project),
    );
    if (saved != null && mounted) _reload();
  }

  Future<void> _cancel(TgcgProject project) async {
    final reason = await promptText(
      context,
      title: 'Cancel ${project.name}?',
      label: 'Reason',
      action: 'Cancel project',
      required: true,
      destructive: true,
    );
    if (reason == null) return;
    await _run(() => _repository.cancel(project.id, reason), 'The project is cancelled.');
  }

  Future<void> _assign(TgcgProject project) async {
    final picked = await showDialog<(String, GeographicScope?)>(
      context: context,
      builder: (_) => const _AssignDialog(),
    );
    if (picked == null) return;
    final (member, place) = picked;
    await _run(
      () => _repository.assign(project.id, member, place: place),
      'Assigned. They answer in their app.',
    );
  }

  Future<void> _remove(ProjectPerson person) async {
    final reason = await promptText(
      context,
      title: 'Take ${person.name} out of the project?',
      label: 'Reason',
      action: 'Take out',
      required: true,
      destructive: true,
    );
    if (reason == null) return;
    await _run(() => _repository.remove(person.participation, reason), 'Taken out.');
  }

  Future<void> _withdraw(ProjectParticipation participation) async {
    final sure = await confirmAction(
      context,
      title: 'Stop taking part?',
      message: 'Your location stops being shared for this project.',
      action: 'Stop taking part',
      destructive: true,
    );
    if (!sure) return;
    await _run(
      () => _repository.answer(participation.id, 'withdraw'),
      'You no longer take part in this project.',
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(title: const Text('Project')),
    body: FutureBuilder<TgcgProject>(
      future: _project,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TgcgEmptyState(
              icon: Icons.error_outline_rounded,
              title: 'The project could not be loaded',
              message: failureMessage(snapshot.error!),
            ),
          );
        }
        final project = snapshot.data;
        if (project == null) return const Center(child: CircularProgressIndicator());
        final status = statusNow(project);
        final open = status == 'scheduled' || status == 'active';
        final mine = project.myParticipation;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TgcgSectionCard(
              title: project.name,
              trailing: projectStatusPill(status),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Line('From', formatMoment(project.startsAt)),
                  _Line('To', formatMoment(project.endsAt)),
                  _Line('Areas', project.areas.map(areaLabel).join(', ')),
                  if (project.electionName != null) _Line('Election', project.electionName!),
                  _Line('Place', project.checkPlace ? 'Compared with their polling unit' : 'Not compared'),
                  if (project.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(project.description),
                  ],
                  if (project.cancelReason.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Cancelled: ${project.cancelReason}',
                      style: const TextStyle(color: TgcgColors.danger),
                    ),
                  ],
                  if (project.canManage && open) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(onPressed: () => _edit(project), child: const Text('Change')),
                        TextButton(
                          onPressed: () => _cancel(project),
                          child: const Text('Cancel project'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (mine != null) ...[
              const SizedBox(height: 12),
              TgcgSectionCard(
                title: 'Your place',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Line('At', areaLabel(mine.place)),
                    _Line('Answer', personStateLabel(mine.status)),
                    if (open && mine.invited)
                      FilledButton(
                        onPressed: () => answerInvitation(context, project).then((_) => _reload()),
                        child: const Text('Answer'),
                      ),
                    if (open && mine.accepted)
                      TextButton(
                        onPressed: () => _withdraw(mine),
                        child: const Text('Stop taking part'),
                      ),
                  ],
                ),
              ),
            ],
            if (_monitor != null) ...[
              const SizedBox(height: 12),
              TgcgSectionCard(
                title: 'Who is where',
                trailing: project.canAssign && open
                    ? FilledButton.icon(
                        onPressed: () => _assign(project),
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        label: const Text('Assign'),
                      )
                    : null,
                child: _MonitorView(
                  monitor: _monitor!,
                  onRemove: project.canAssign && open ? _remove : null,
                ),
              ),
            ],
          ],
        );
      },
    ),
  );
}

class _MonitorView extends StatelessWidget {
  const _MonitorView({required this.monitor, this.onRemove});

  final Future<ProjectMonitor> monitor;
  final void Function(ProjectPerson person)? onRemove;

  @override
  Widget build(BuildContext context) => FutureBuilder<ProjectMonitor>(
    future: monitor,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return Text(failureMessage(snapshot.error!), style: const TextStyle(color: TgcgColors.danger));
      }
      final data = snapshot.data;
      if (data == null) {
        return const Padding(
          padding: EdgeInsets.all(12),
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in data.counts.entries)
                Chip(label: Text('${personStateLabel(entry.key)}: ${entry.value}')),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Incidents ${data.incidents} · Reports ${data.reports} · Results ${data.results}',
            style: const TextStyle(color: TgcgColors.muted),
          ),
          const SizedBox(height: 6),
          if (data.people.isEmpty)
            const Text('Nobody is assigned here yet.', style: TextStyle(color: TgcgColors.muted)),
          for (final person in data.people)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${person.name} (${person.member})'),
              subtitle: Text(
                [
                  areaLabel(person.place),
                  if (person.distanceMeters != null) '${person.distanceMeters} m from their place',
                  if (person.lastSeen != null) 'seen ${formatMoment(person.lastSeen!)}',
                ].join(' · '),
              ),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  personStatePill(person.state),
                  if (onRemove != null && const {'invited', 'accepted'}.contains(person.status))
                    IconButton(
                      tooltip: 'Take out',
                      onPressed: () => onRemove!(person),
                      icon: const Icon(Icons.person_remove_outlined),
                    ),
                ],
              ),
            ),
        ],
      );
    },
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
          width: 90,
          child: Text(label, style: const TextStyle(color: TgcgColors.muted)),
        ),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700))),
      ],
    ),
  );
}

/// The membership number of someone with a role, and optionally where they
/// work (by default their own polling unit).
class _AssignDialog extends StatefulWidget {
  const _AssignDialog();

  @override
  State<_AssignDialog> createState() => _AssignDialogState();
}

class _AssignDialogState extends State<_AssignDialog> {
  final _member = TextEditingController();
  GeographicScope? _place;

  @override
  void dispose() {
    _member.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Assign someone'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _member,
            decoration: const InputDecoration(labelText: 'Membership number', hintText: 'TGCG-000123'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _place == null ? 'At their own polling unit' : areaLabel(_place!),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final place = await pickArea(
                    context,
                    levels: const [GeographyLevel.pollingUnit, GeographyLevel.ward, GeographyLevel.lga],
                  );
                  if (place != null) setState(() => _place = place);
                },
                child: const Text('Choose place'),
              ),
            ],
          ),
        ],
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      FilledButton(
        onPressed: _member.text.trim().isEmpty
            ? null
            : () => Navigator.pop(context, (_member.text.trim(), _place)),
        child: const Text('Assign'),
      ),
    ],
  );
}

/// Schedules a project, or changes one. Once it runs, its start, areas and
/// election stay as they are.
class ProjectFormDialog extends StatefulWidget {
  const ProjectFormDialog({super.key, this.project});

  final TgcgProject? project;

  @override
  State<ProjectFormDialog> createState() => _ProjectFormDialogState();
}

class _ProjectFormDialogState extends State<ProjectFormDialog> {
  late final _name = TextEditingController(text: widget.project?.name ?? '');
  late final _brief = TextEditingController(text: widget.project?.description ?? '');
  late DateTime? _startsAt = widget.project?.startsAt;
  late DateTime? _endsAt = widget.project?.endsAt;
  late final List<GeographicScope> _areas = [...?widget.project?.areas];
  late String? _election = widget.project?.electionCode;
  late bool _checkPlace = widget.project?.checkPlace ?? true;
  Future<List<ServerElection>>? _elections;
  Map<String, String> _errors = const {};
  String? _error;
  bool _saving = false;

  bool get _started => widget.project != null && statusNow(widget.project!) == 'active';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _elections ??= TgcgBackend.of(context)!.reference.elections();
  }

  @override
  void dispose() {
    _name.dispose();
    _brief.dispose();
    super.dispose();
  }

  Future<DateTime?> _pickMoment(DateTime? current) async {
    final now = DateTime.now();
    final initial = current ?? now.add(const Duration(hours: 1));
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      initialDate: initial.isBefore(now) ? now : initial,
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _addArea() async {
    final area = await pickArea(
      context,
      levels: const [
        GeographyLevel.state,
        GeographyLevel.lga,
        GeographyLevel.ward,
        GeographyLevel.country,
      ],
    );
    if (area == null) return;
    if (_areas.any((item) => areaLabel(item) == areaLabel(area))) return;
    setState(() => _areas.add(area));
  }

  bool get _ready =>
      !_saving &&
      _name.text.trim().isNotEmpty &&
      _startsAt != null &&
      _endsAt != null &&
      _areas.isNotEmpty;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _errors = const {};
      _error = null;
    });
    final repository = TgcgBackend.of(context)!.projects;
    final project = widget.project;
    try {
      final saved = project == null
          ? await repository.create(
              name: _name.text,
              description: _brief.text,
              startsAt: _startsAt!,
              endsAt: _endsAt!,
              areas: _areas,
              election: _election,
              checkPlace: _checkPlace,
            )
          : await repository.update(
              project.id,
              name: _name.text,
              description: _brief.text,
              startsAt: _started ? null : _startsAt,
              endsAt: _endsAt,
              areas: _started ? null : _areas,
              election: _started ? null : _election,
              clearElection: !_started && _election == null,
              checkPlace: _checkPlace,
            );
      if (mounted) Navigator.pop(context, saved);
    } catch (error) {
      final fields = <String, String>{
        if (error is ApiException)
          for (final field in const ['name', 'starts_at', 'ends_at', 'areas', 'election'])
            if (error.fieldError(field) case final message?) field: message,
      };
      setState(() {
        _saving = false;
        _errors = fields;
        _error = fields.isEmpty ? failureMessage(error) : null;
      });
    }
  }

  Widget _moment(String label, DateTime? value, String field, ValueChanged<DateTime> picked, bool locked) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: Text(
          _errors[field] ?? (value == null ? 'Choose a date and time' : formatMoment(value)),
          style: TextStyle(color: _errors.containsKey(field) ? TgcgColors.danger : null),
        ),
        trailing: locked
            ? null
            : TextButton(
                onPressed: () async {
                  final moment = await _pickMoment(value);
                  if (moment != null) setState(() => picked(moment));
                },
                child: const Text('Choose'),
              ),
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.project == null ? 'New project' : 'Change project'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              decoration: InputDecoration(labelText: 'Name', errorText: _errors['name']),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _brief,
              minLines: 2,
              maxLines: 4,
              maxLength: 2000,
              decoration: const InputDecoration(labelText: 'What people are to do'),
            ),
            _moment('Starts', _startsAt, 'starts_at', (value) => _startsAt = value, _started),
            _moment('Ends', _endsAt, 'ends_at', (value) => _endsAt = value, false),
            const SizedBox(height: 6),
            const Text('Areas', style: TextStyle(fontWeight: FontWeight.w800)),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final area in _areas)
                  InputChip(
                    label: Text(areaLabel(area)),
                    onDeleted: _started ? null : () => setState(() => _areas.remove(area)),
                  ),
                if (!_started)
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add area'),
                    onPressed: _addArea,
                  ),
              ],
            ),
            if (_errors['areas'] != null)
              Text(_errors['areas']!, style: const TextStyle(color: TgcgColors.danger)),
            const SizedBox(height: 10),
            FutureBuilder<List<ServerElection>>(
              future: _elections,
              builder: (context, snapshot) {
                final elections = snapshot.data ?? const <ServerElection>[];
                return DropdownButtonFormField<String?>(
                  initialValue: elections.any((e) => e.code == _election) ? _election : null,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Election', errorText: _errors['election']),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('None')),
                    for (final election in elections)
                      DropdownMenuItem<String?>(
                        value: election.code,
                        child: Text(election.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _started ? null : (value) => setState(() => _election = value),
                );
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Compare location with their polling unit'),
              value: _checkPlace,
              onChanged: (value) => setState(() => _checkPlace = value),
            ),
            if (_error != null) Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      FilledButton(
        onPressed: _ready ? _save : null,
        child: Text(widget.project == null ? 'Schedule' : 'Save'),
      ),
    ],
  );
}
