import 'dart:async';

import 'package:flutter/material.dart';

import '../access/access_widgets.dart'
    show areaLabel, confirmAction, formatMoment, pickArea, promptText, showDone;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/meetings_repository.dart';
import '../domain/permissions.dart';
import '../session.dart';
import '../ui/server_feed.dart';
import '../ui/app_on_screen.dart';
import '../ui/tgcg_design.dart';
import 'meeting_call_page.dart';

/// Opens a meeting's call; returns what to tell the user when it ended.
typedef OpenCall = Future<String?> Function(
  BuildContext context,
  ServerMeeting meeting,
  JoinPass pass,
);

Future<String?> _openCallPage(BuildContext context, ServerMeeting meeting, JoinPass pass) =>
    Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => MeetingCallPage(meeting: meeting, pass: pass)),
    );

/// Meetings on the server: those open now, coming up, and from the last day.
/// The server decides who sees and joins each one; calls run on LiveKit.
class ServerMeetingsView extends StatefulWidget {
  const ServerMeetingsView({super.key, this.openCall = _openCallPage});

  final OpenCall openCall;

  @override
  State<ServerMeetingsView> createState() => _ServerMeetingsViewState();
}

class _ServerMeetingsViewState extends State<ServerMeetingsView> {
  late MeetingsRepository _meetings;
  bool _started = false;
  Timer? _timer;
  List<ServerMeeting>? _list;
  String? _error;
  bool _loading = false;
  String? _joining;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _meetings = TgcgBackend.of(context)!.meetings;
    if (!_started) {
      _started = true;
      unawaited(_load());
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (appOnScreen) _load(quiet: true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool quiet = false}) async {
    if (_loading || !mounted) return;
    setState(() {
      _loading = true;
      if (!quiet) _error = null;
    });
    try {
      final list = await _meetings.list();
      if (mounted) {
        setState(() {
          _list = list;
          _error = null;
        });
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _failed(Object error) {
    if (!mounted) return;
    final message = switch (error) {
      ApiException(isOffline: true) => 'The server cannot be reached. Meetings need a connection.',
      ApiException(:final message) => message,
      _ => 'Something went wrong: $error',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: TgcgColors.danger),
    );
  }

  Future<void> _join(ServerMeeting meeting) async {
    setState(() => _joining = meeting.reference);
    try {
      final pass = await _meetings.join(meeting.reference);
      if (!mounted) return;
      final ended = await widget.openCall(context, meeting, pass);
      if (mounted && ended != null) showDone(context, ended);
      unawaited(_load(quiet: true));
    } catch (error) {
      _failed(error);
    } finally {
      if (mounted) setState(() => _joining = null);
    }
  }

  Future<void> _end(ServerMeeting meeting) async {
    final confirmed = await confirmAction(
      context,
      title: 'End ${meeting.title}?',
      message: 'Everyone in the call is disconnected and nobody can join again.',
      action: 'End for everyone',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await _meetings.end(meeting.reference);
      if (mounted) showDone(context, '${meeting.title} has ended.');
      await _load(quiet: true);
    } catch (error) {
      _failed(error);
    }
  }

  Future<void> _cancel(ServerMeeting meeting) async {
    final reason = await promptText(
      context,
      title: 'Cancel ${meeting.title}?',
      label: 'Reason',
      message: 'The people invited see that it is cancelled, and why.',
      action: 'Cancel meeting',
      required: true,
      destructive: true,
    );
    if (reason == null || !mounted) return;
    try {
      await _meetings.cancel(meeting.reference, reason: reason);
      if (mounted) showDone(context, '${meeting.title} is cancelled.');
      await _load(quiet: true);
    } catch (error) {
      _failed(error);
    }
  }

  Future<void> _newMeeting() async {
    final made = await showDialog<ServerMeeting>(
      context: context,
      builder: (_) => _NewMeetingDialog(meetings: _meetings),
    );
    if (made == null || !mounted) return;
    showDone(context, '${made.title} is set up (${made.reference}).');
    await _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final list = _list;
    final live = [...?list?.where((m) => m.status == MeetingStatus.live)];
    final coming = [...?list?.where((m) => m.status == MeetingStatus.scheduled)];
    final earlier = [
      ...?list?.where((m) => m.status == MeetingStatus.ended || m.status == MeetingStatus.cancelled),
    ]..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    final callsOff = list != null && list.isNotEmpty && !list.first.callsAvailable;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
      children: [
        TgcgPageHeader(
          eyebrow: 'MEETINGS',
          title: 'Meeting Room',
          subtitle: '${areaLabel(session.scope)}: calls for your area, and those you are invited to. '
              'Calls start with sound only; turn on video in video meetings.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (session.can(TgcgCapability.startMeeting))
                FilledButton.icon(
                  onPressed: _newMeeting,
                  icon: const Icon(Icons.add_call),
                  label: const Text('New meeting'),
                ),
              IconButton(
                tooltip: 'Load again',
                onPressed: _loading ? null : () => _load(),
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        if (callsOff)
          const Padding(
            padding: EdgeInsets.only(top: 14),
            child: ServerNote(
              icon: Icons.phone_disabled_rounded,
              text: 'Calls are not set up on the server yet. Meetings can be planned; '
                  'joining opens once LiveKit is set up.',
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: ServerNote(
              icon: Icons.cloud_off_rounded,
              text: 'Meetings could not be loaded from the server: $_error',
            ),
          ),
        const SizedBox(height: 16),
        if (list == null && _error == null)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (list != null) ...[
          _Section(
            title: 'Open now',
            empty: 'No meeting is open to join right now.',
            meetings: live,
            builder: _tile,
          ),
          const SizedBox(height: 14),
          _Section(
            title: 'Coming up',
            empty: 'Nothing planned.',
            meetings: coming,
            builder: _tile,
          ),
          if (earlier.isNotEmpty) ...[
            const SizedBox(height: 14),
            _Section(title: 'Earlier', empty: '', meetings: earlier, builder: _tile),
          ],
        ],
      ],
    );
  }

  Widget _tile(ServerMeeting meeting) => _MeetingTile(
        meeting: meeting,
        joining: _joining == meeting.reference,
        onJoin: _joining == null ? () => _join(meeting) : null,
        onEnd: () => _end(meeting),
        onCancel: () => _cancel(meeting),
      );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.empty,
    required this.meetings,
    required this.builder,
  });

  final String title;
  final String empty;
  final List<ServerMeeting> meetings;
  final Widget Function(ServerMeeting) builder;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: title,
        child: meetings.isEmpty
            ? Text(empty, style: const TextStyle(color: TgcgColors.muted))
            : Column(children: [for (final meeting in meetings) builder(meeting)]),
      );
}

String _time(DateTime value) {
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
}

class _MeetingTile extends StatelessWidget {
  const _MeetingTile({
    required this.meeting,
    required this.joining,
    required this.onJoin,
    required this.onEnd,
    required this.onCancel,
  });

  final ServerMeeting meeting;
  final bool joining;
  final VoidCallback? onJoin;
  final VoidCallback onEnd;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final m = meeting;
    final live = m.status == MeetingStatus.live;
    final over = m.status == MeetingStatus.ended || m.status == MeetingStatus.cancelled;
    final when = live
        ? 'Open now · planned until ${_time(m.endsAt)}'
        : '${formatMoment(m.startsAt.toLocal())} · ${m.durationMinutes} min';
    final who = m.audience == MeetingAudience.area
        ? 'Everyone in ${areaLabel(m.scope)}'
            '${m.invitees.isEmpty ? '' : ', and ${m.invitees.length} invited'}'
        : 'Invited only: ${m.invitees.length} ${m.invitees.length == 1 ? 'person' : 'people'}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: live ? TgcgColors.success.withValues(alpha: .06) : TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: live ? TgcgColors.success.withValues(alpha: .3) : TgcgColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                m.kind == MeetingKind.video ? Icons.videocam_outlined : Icons.mic_none_rounded,
                color: live ? TgcgColors.success : TgcgColors.primaryMid,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  m.title,
                  style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900),
                ),
              ),
              if (m.status == MeetingStatus.cancelled)
                const TgcgStatusPill(label: 'CANCELLED', color: TgcgColors.danger, compact: true)
              else if (m.status == MeetingStatus.ended)
                const TgcgStatusPill(label: 'ENDED', color: TgcgColors.muted, compact: true),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$when · called by ${m.hostName.isEmpty ? m.host : m.hostName}',
            style: const TextStyle(color: TgcgColors.muted, fontSize: 11),
          ),
          Text(who, style: const TextStyle(color: TgcgColors.muted, fontSize: 11)),
          if (m.agenda.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(m.agenda, style: const TextStyle(color: TgcgColors.ink, height: 1.4)),
          ],
          if (m.status == MeetingStatus.cancelled && m.cancelReason.isNotEmpty)
            Text(
              'Cancelled: ${m.cancelReason}',
              style: const TextStyle(color: TgcgColors.danger, fontSize: 11),
            ),
          if (!over) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (live && m.canJoin)
                  FilledButton.icon(
                    onPressed: m.callsAvailable ? onJoin : null,
                    icon: joining
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.call_rounded, size: 18),
                    label: const Text('Join'),
                  ),
                if (live && m.canManage)
                  OutlinedButton.icon(
                    onPressed: onEnd,
                    icon: const Icon(Icons.stop_circle_outlined, size: 18),
                    label: const Text('End'),
                  ),
                if (m.canManage)
                  TextButton(onPressed: onCancel, child: const Text('Cancel meeting')),
                if (live && m.admitted > 0)
                  Text(
                    '${m.admitted} joined',
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 11),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Calls a meeting: what it is about, sound or video, when, and for whom.
class _NewMeetingDialog extends StatefulWidget {
  const _NewMeetingDialog({required this.meetings});

  final MeetingsRepository meetings;

  @override
  State<_NewMeetingDialog> createState() => _NewMeetingDialogState();
}

class _NewMeetingDialogState extends State<_NewMeetingDialog> {
  final _title = TextEditingController();
  final _agenda = TextEditingController();
  final _invitees = TextEditingController();
  var _kind = MeetingKind.audio;
  var _audience = MeetingAudience.area;
  var _duration = 60;
  DateTime? _startsAt; // null: now
  GeographicScope? _area; // null: your own area
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _agenda.dispose();
    _invitees.dispose();
    super.dispose();
  }

  List<String> get _inviteeIds => [
        for (final part in _invitees.text.split(RegExp(r'[\s,;]+')))
          if (part.trim().isNotEmpty) part.trim().toUpperCase(),
      ];

  Future<void> _pickTime() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
      initialDate: _startsAt ?? now,
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_startsAt ?? now.add(const Duration(hours: 1))),
    );
    if (time == null || !mounted) return;
    setState(() => _startsAt = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _pickArea() async {
    final area = await pickArea(
      context,
      levels: const [GeographyLevel.state, GeographyLevel.lga, GeographyLevel.ward],
    );
    if (area != null && mounted) setState(() => _area = area);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final made = await widget.meetings.create(
        title: _title.text,
        agenda: _agenda.text,
        kind: _kind,
        audience: _audience,
        startsAt: _startsAt,
        durationMinutes: _duration,
        scope: _area,
        invitees: _inviteeIds,
      );
      if (mounted) Navigator.of(context).pop(made);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = _title.text.trim().isNotEmpty &&
        (_audience == MeetingAudience.area || _inviteeIds.isNotEmpty);
    return AlertDialog(
      title: const Text('New meeting'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                autofocus: true,
                maxLength: 160,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'What is it about?'),
              ),
              TextField(
                controller: _agenda,
                maxLines: 3,
                maxLength: 4000,
                decoration: const InputDecoration(labelText: 'Agenda (optional)'),
              ),
              const SizedBox(height: 8),
              SegmentedButton<MeetingKind>(
                segments: const [
                  ButtonSegment(
                    value: MeetingKind.audio,
                    icon: Icon(Icons.mic_none_rounded),
                    label: Text('Sound only'),
                  ),
                  ButtonSegment(
                    value: MeetingKind.video,
                    icon: Icon(Icons.videocam_outlined),
                    label: Text('Video'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (value) => setState(() => _kind = value.single),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sound only works best where the network is weak.',
                style: TextStyle(color: TgcgColors.muted, fontSize: 11),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ChoiceChip(
                    label: const Text('Start now'),
                    selected: _startsAt == null,
                    onSelected: (_) => setState(() => _startsAt = null),
                  ),
                  ChoiceChip(
                    label: Text(
                      _startsAt == null ? 'Plan for later' : formatMoment(_startsAt!),
                    ),
                    selected: _startsAt != null,
                    onSelected: (_) => _pickTime(),
                  ),
                  DropdownButton<int>(
                    value: _duration,
                    items: [
                      for (final minutes in const [30, 60, 90, 120, 180])
                        DropdownMenuItem(value: minutes, child: Text('$minutes min')),
                    ],
                    onChanged: (value) => setState(() => _duration = value ?? _duration),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<MeetingAudience>(
                segments: const [
                  ButtonSegment(value: MeetingAudience.area, label: Text('Everyone in the area')),
                  ButtonSegment(value: MeetingAudience.invited, label: Text('Only people I invite')),
                ],
                selected: {_audience},
                onSelectionChanged: (value) => setState(() => _audience = value.single),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Area: ${_area == null ? 'your own area' : areaLabel(_area!)}',
                      style: const TextStyle(color: TgcgColors.ink),
                    ),
                  ),
                  TextButton(onPressed: _pickArea, child: const Text('Choose area')),
                ],
              ),
              TextField(
                controller: _invitees,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: _audience == MeetingAudience.invited
                      ? 'Invite (access IDs)'
                      : 'Also invite (access IDs, optional)',
                  helperText: 'Separate them with commas, e.g. LC-KD-01, WC-KD-07',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, style: const TextStyle(color: TgcgColors.danger)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        FilledButton(
          onPressed: ready && !_saving ? _save : null,
          child: Text(_startsAt == null ? 'Start meeting' : 'Plan meeting'),
        ),
      ],
    );
  }
}
