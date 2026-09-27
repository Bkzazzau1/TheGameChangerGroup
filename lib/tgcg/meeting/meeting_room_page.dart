import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../media/local_camera_view.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

enum _MeetingKind { audio, video, conference }
enum _MeetingStatus { live, scheduled, completed }

class _Participant {
  const _Participant({
    required this.name,
    required this.role,
    this.muted = false,
  }) : cameraOn = true;

  final String name;
  final String role;
  final bool muted;
  final bool cameraOn;
}

class _Meeting {
  _Meeting({
    required this.id,
    required this.title,
    required this.host,
    required this.time,
    required this.kind,
    required this.status,
    required this.participants,
  });

  final String id;
  final String title;
  final String host;
  final String time;
  final _MeetingKind kind;
  _MeetingStatus status;
  final List<_Participant> participants;
}

class MeetingRoomPage extends StatefulWidget {
  const MeetingRoomPage({super.key});

  @override
  State<MeetingRoomPage> createState() => _MeetingRoomPageState();
}

class _MeetingRoomPageState extends State<MeetingRoomPage> {
  bool micOn = true;
  bool cameraOn = true;
  bool speakerOn = true;
  bool presenting = false;
  _Meeting? activeMeeting;

  late final List<_Meeting> meetings = [
    _Meeting(
      id: 'MTG-1001',
      title: 'National Operations Conference',
      host: 'Situation Room Director',
      time: 'Live now',
      kind: _MeetingKind.conference,
      status: _MeetingStatus.live,
      participants: const [
        _Participant(name: 'National Operations', role: 'Host'),
        _Participant(name: 'North West Desk', role: 'Zonal Coordinator'),
        _Participant(name: 'Field Support', role: 'Technical Support', muted: true),
        _Participant(name: 'Legal Desk', role: 'Legal Officer'),
      ],
    ),
    _Meeting(
      id: 'MTG-1002',
      title: 'State Coordinators Check-in',
      host: 'National Operations Desk',
      time: '13:30',
      kind: _MeetingKind.video,
      status: _MeetingStatus.scheduled,
      participants: const [
        _Participant(name: 'National Operations', role: 'Host'),
        _Participant(name: 'Kaduna Desk', role: 'State Coordinator'),
        _Participant(name: 'Lagos Desk', role: 'State Coordinator'),
      ],
    ),
    _Meeting(
      id: 'MTG-1003',
      title: 'Evidence Review Call',
      host: 'Legal & Evidence Desk',
      time: '15:00',
      kind: _MeetingKind.audio,
      status: _MeetingStatus.scheduled,
      participants: const [
        _Participant(name: 'Legal Desk', role: 'Host'),
        _Participant(name: 'Evidence Desk', role: 'Reviewer'),
      ],
    ),
    _Meeting(
      id: 'MTG-0998',
      title: 'Morning Technical Briefing',
      host: 'Technical Support',
      time: '07:30',
      kind: _MeetingKind.video,
      status: _MeetingStatus.completed,
      participants: const [
        _Participant(name: 'Technical Support', role: 'Host'),
        _Participant(name: 'Field Support', role: 'Support Desk'),
      ],
    ),
  ];

  static const contacts = [
    _Participant(name: 'National Operations Desk', role: 'Situation Room'),
    _Participant(name: 'Technical Support', role: 'Support Desk'),
    _Participant(name: 'Legal & Evidence Desk', role: 'Legal Officer'),
    _Participant(name: 'Field Coordination', role: 'Coordinator'),
  ];

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final canStart = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.startMeeting,
    );
    final canJoin = TgcgPermissionPolicy.allows(
      session.role!,
      TgcgCapability.joinMeeting,
    );

    if (activeMeeting != null) {
      return _LiveMeetingStage(
        meeting: activeMeeting!,
        operatorName: session.operatorName,
        micOn: micOn,
        cameraOn: cameraOn,
        speakerOn: speakerOn,
        presenting: presenting,
        onToggleMic: () => setState(() => micOn = !micOn),
        onToggleCamera: () => setState(() => cameraOn = !cameraOn),
        onToggleSpeaker: () => setState(() => speakerOn = !speakerOn),
        onTogglePresent: () => setState(() => presenting = !presenting),
        onEnd: _endMeeting,
      );
    }

    final live = meetings.where((item) => item.status == _MeetingStatus.live).toList();
    final scheduled = meetings
        .where((item) => item.status == _MeetingStatus.scheduled)
        .toList(growable: false);
    final completed = meetings
        .where((item) => item.status == _MeetingStatus.completed)
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'LIVE COLLABORATION',
          title: 'Meeting Room',
          subtitle:
              '${session.scope.label}: audio calls, video meetings and multi-participant conferences.',
          trailing: canStart
              ? FilledButton.icon(
                  onPressed: () => _scheduleMeeting(context, session),
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: const Text('Schedule meeting'),
                )
              : TgcgStatusPill(
                  label: 'JOIN ACCESS',
                  color: TgcgColors.info,
                  icon: Icons.video_call_outlined,
                ),
        ),
        const SizedBox(height: 18),
        _MeetingMetrics(
          live: live.length,
          scheduled: scheduled.length,
          completed: completed.length,
          participants: meetings.fold<int>(
            0,
            (sum, item) => sum + item.participants.length,
          ),
        ),
        const SizedBox(height: 16),
        if (canStart) ...[
          _QuickMeetingActions(
            onVideo: () => _startInstantMeeting(session, _MeetingKind.video),
            onAudio: () => _startInstantMeeting(session, _MeetingKind.audio),
            onConference: () => _startInstantMeeting(session, _MeetingKind.conference),
          ),
          const SizedBox(height: 16),
        ],
        if (live.isNotEmpty) ...[
          TgcgSectionCard(
            title: 'Live now',
            subtitle: 'Meetings currently open for your team.',
            trailing: TgcgStatusPill(
              label: '${live.length} LIVE',
              color: TgcgColors.danger,
              icon: Icons.fiber_manual_record_rounded,
              compact: true,
            ),
            child: Column(
              children: live
                  .map(
                    (meeting) => _MeetingRow(
                      meeting: meeting,
                      actionLabel: 'Join now',
                      onTap: canJoin ? () => _joinMeeting(meeting) : null,
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],
        LayoutBuilder(
          builder: (context, constraints) {
            final schedule = TgcgSectionCard(
              title: 'Upcoming meetings',
              subtitle: 'Your scheduled calls and conferences.',
              child: scheduled.isEmpty
                  ? const TgcgEmptyState(
                      icon: Icons.event_available_outlined,
                      title: 'No upcoming meeting',
                      message: 'Scheduled meetings will appear here.',
                    )
                  : Column(
                      children: scheduled
                          .map(
                            (meeting) => _MeetingRow(
                              meeting: meeting,
                              actionLabel: 'Join',
                              onTap: canJoin ? () => _joinMeeting(meeting) : null,
                            ),
                          )
                          .toList(),
                    ),
            );
            final people = _PeoplePanel(
              contacts: contacts,
              canStart: canStart,
              onAudioCall: (person) => _startDirectCall(session, person, false),
              onVideoCall: (person) => _startDirectCall(session, person, true),
            );

            if (constraints.maxWidth < 950) {
              return Column(
                children: [
                  schedule,
                  const SizedBox(height: 16),
                  people,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: schedule),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: people),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        TgcgSectionCard(
          title: 'Recent meetings',
          subtitle: 'Completed team sessions.',
          child: Column(
            children: completed
                .map(
                  (meeting) => _MeetingRow(
                    meeting: meeting,
                    actionLabel: 'View',
                    onTap: () {},
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  void _startInstantMeeting(TgcgSessionController session, _MeetingKind kind) {
    final meeting = _Meeting(
      id: 'MTG-${1000 + meetings.length + 1}',
      title: switch (kind) {
        _MeetingKind.audio => 'Instant Audio Call',
        _MeetingKind.video => 'Instant Video Meeting',
        _MeetingKind.conference => 'Instant Conference Room',
      },
      host: session.operatorName,
      time: 'Live now',
      kind: kind,
      status: _MeetingStatus.live,
      participants: [
        _Participant(name: session.operatorName, role: roleLabel(session.role!)),
        const _Participant(name: 'National Operations Desk', role: 'Operations'),
        if (kind == _MeetingKind.conference)
          const _Participant(name: 'Technical Support', role: 'Support Desk'),
      ],
    );
    setState(() {
      meetings.insert(0, meeting);
      activeMeeting = meeting;
      cameraOn = kind != _MeetingKind.audio;
      micOn = true;
      speakerOn = true;
      presenting = false;
    });
  }

  void _startDirectCall(
    TgcgSessionController session,
    _Participant person,
    bool video,
  ) {
    final meeting = _Meeting(
      id: 'CALL-${DateTime.now().millisecondsSinceEpoch}',
      title: video ? 'Video call' : 'Audio call',
      host: session.operatorName,
      time: 'Live now',
      kind: video ? _MeetingKind.video : _MeetingKind.audio,
      status: _MeetingStatus.live,
      participants: [
        _Participant(name: session.operatorName, role: roleLabel(session.role!)),
        person,
      ],
    );
    setState(() {
      activeMeeting = meeting;
      cameraOn = video;
      micOn = true;
      speakerOn = true;
      presenting = false;
    });
  }

  void _joinMeeting(_Meeting meeting) {
    setState(() {
      meeting.status = _MeetingStatus.live;
      activeMeeting = meeting;
      cameraOn = meeting.kind != _MeetingKind.audio;
      micOn = true;
      speakerOn = true;
      presenting = false;
    });
  }

  void _endMeeting() {
    setState(() {
      if (activeMeeting != null) {
        activeMeeting!.status = _MeetingStatus.completed;
      }
      activeMeeting = null;
      micOn = true;
      cameraOn = true;
      speakerOn = true;
      presenting = false;
    });
  }

  Future<void> _scheduleMeeting(
    BuildContext context,
    TgcgSessionController session,
  ) async {
    final titleController = TextEditingController();
    final timeController = TextEditingController(text: '16:00');
    var kind = _MeetingKind.video;
    final create = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Schedule meeting'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Meeting title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: timeController,
                  decoration: const InputDecoration(
                    labelText: 'Time',
                    prefixIcon: Icon(Icons.schedule_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<_MeetingKind>(
                  initialValue: kind,
                  decoration: const InputDecoration(labelText: 'Meeting type'),
                  items: const [
                    DropdownMenuItem(
                      value: _MeetingKind.audio,
                      child: Text('Audio call'),
                    ),
                    DropdownMenuItem(
                      value: _MeetingKind.video,
                      child: Text('Video meeting'),
                    ),
                    DropdownMenuItem(
                      value: _MeetingKind.conference,
                      child: Text('Conference meeting'),
                    ),
                  ],
                  onChanged: (value) => setDialogState(
                    () => kind = value ?? kind,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (titleController.text.trim().isEmpty) return;
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.event_available_rounded),
              label: const Text('Schedule'),
            ),
          ],
        ),
      ),
    );

    if (create == true) {
      setState(() {
        meetings.insert(
          0,
          _Meeting(
            id: 'MTG-${1000 + meetings.length + 1}',
            title: titleController.text.trim(),
            host: session.operatorName,
            time: timeController.text.trim(),
            kind: kind,
            status: _MeetingStatus.scheduled,
            participants: [
              _Participant(
                name: session.operatorName,
                role: roleLabel(session.role!),
              ),
            ],
          ),
        );
      });
    }
    titleController.dispose();
    timeController.dispose();
  }
}

class _MeetingMetrics extends StatelessWidget {
  const _MeetingMetrics({
    required this.live,
    required this.scheduled,
    required this.completed,
    required this.participants,
  });

  final int live;
  final int scheduled;
  final int completed;
  final int participants;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900
              ? 4
              : constraints.maxWidth >= 520
                  ? 2
                  : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Live rooms',
                value: '$live',
                detail: 'Active calls and conferences',
                icon: Icons.fiber_manual_record_rounded,
                tone: live > 0 ? TgcgMetricTone.warning : TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Scheduled',
                value: '$scheduled',
                detail: 'Upcoming team meetings',
                icon: Icons.calendar_month_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Completed',
                value: '$completed',
                detail: 'Recent meeting sessions',
                icon: Icons.task_alt_rounded,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Participants',
                value: '$participants',
                detail: 'People across meeting rooms',
                icon: Icons.groups_rounded,
                tone: TgcgMetricTone.neutral,
              ),
            ],
          );
        },
      );
}

class _QuickMeetingActions extends StatelessWidget {
  const _QuickMeetingActions({
    required this.onVideo,
    required this.onAudio,
    required this.onConference,
  });

  final VoidCallback onVideo;
  final VoidCallback onAudio;
  final VoidCallback onConference;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Start a meeting',
        subtitle: 'Connect immediately with your team.',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < 620
                ? constraints.maxWidth
                : (constraints.maxWidth - 24) / 3;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _QuickAction(
                  width: width,
                  icon: Icons.videocam_rounded,
                  title: 'Video meeting',
                  detail: 'Start with camera and audio',
                  onTap: onVideo,
                ),
                _QuickAction(
                  width: width,
                  icon: Icons.call_rounded,
                  title: 'Audio call',
                  detail: 'Start a voice-only room',
                  onTap: onAudio,
                ),
                _QuickAction(
                  width: width,
                  icon: Icons.groups_rounded,
                  title: 'Conference',
                  detail: 'Open a multi-person room',
                  onTap: onConference,
                ),
              ],
            );
          },
        ),
      );
}

class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.width,
    required this.icon,
    required this.title,
    required this.detail,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: Material(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: TgcgColors.primarySoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: TgcgColors.primary),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          detail,
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: TgcgColors.muted),
                ],
              ),
            ),
          ),
        ),
      );
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.meeting,
    required this.actionLabel,
    required this.onTap,
  });

  final _Meeting meeting;
  final String actionLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: TgcgColors.surfaceSoft,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: TgcgColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _meetingColor(meeting.kind).withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _meetingIcon(meeting.kind),
                  color: _meetingColor(meeting.kind),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meeting.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${meeting.host} • ${meeting.time} • ${meeting.participants.length} participants',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: onTap,
                child: Text(actionLabel),
              ),
            ],
          ),
        ),
      );
}

class _PeoplePanel extends StatelessWidget {
  const _PeoplePanel({
    required this.contacts,
    required this.canStart,
    required this.onAudioCall,
    required this.onVideoCall,
  });

  final List<_Participant> contacts;
  final bool canStart;
  final ValueChanged<_Participant> onAudioCall;
  final ValueChanged<_Participant> onVideoCall;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Available people',
        subtitle: 'Start a direct call with a team desk.',
        child: Column(
          children: contacts.map((person) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 11),
              child: Row(
                children: [
                  _MeetingAvatar(name: person.name, size: 38),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          person.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          person.role,
                          style: const TextStyle(color: TgcgColors.muted, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                  if (canStart) ...[
                    IconButton(
                      tooltip: 'Audio call',
                      onPressed: () => onAudioCall(person),
                      icon: const Icon(Icons.call_outlined, size: 19),
                    ),
                    IconButton(
                      tooltip: 'Video call',
                      onPressed: () => onVideoCall(person),
                      icon: const Icon(Icons.videocam_outlined, size: 20),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      );
}

class _LiveMeetingStage extends StatelessWidget {
  const _LiveMeetingStage({
    required this.meeting,
    required this.operatorName,
    required this.micOn,
    required this.cameraOn,
    required this.speakerOn,
    required this.presenting,
    required this.onToggleMic,
    required this.onToggleCamera,
    required this.onToggleSpeaker,
    required this.onTogglePresent,
    required this.onEnd,
  });

  final _Meeting meeting;
  final String operatorName;
  final bool micOn;
  final bool cameraOn;
  final bool speakerOn;
  final bool presenting;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleCamera;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onTogglePresent;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF081D19),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                child: Row(
                  children: [
                    const TgcgLogo(size: 36),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            meeting.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${meeting.participants.length} participants • ${meeting.id}',
                            style: const TextStyle(
                              color: Color(0xFF9CB3AB),
                              fontSize: 9.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const TgcgStatusPill(
                      label: 'LIVE',
                      color: TgcgColors.danger,
                      icon: Icons.fiber_manual_record_rounded,
                      compact: true,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final participants = <_Participant>[
                      if (!meeting.participants
                          .any((person) => person.name == operatorName))
                        _Participant(name: operatorName, role: 'You'),
                      ...meeting.participants,
                    ];
                    final columns = constraints.maxWidth >= 950
                        ? 3
                        : constraints.maxWidth >= 560
                            ? 2
                            : 1;
                    const gap = 12.0;
                    final width =
                        (constraints.maxWidth - 32 - gap * (columns - 1)) / columns;
                    return SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                      child: Wrap(
                        spacing: gap,
                        runSpacing: gap,
                        children: participants.map((person) {
                          final isMe = person.name == operatorName;
                          return _ParticipantTile(
                            width: width,
                            participant: person,
                            micOn: isMe ? micOn : !person.muted,
                            cameraOn: isMe ? cameraOn : person.cameraOn,
                            presenting: isMe && presenting,
                            isSelf: isMe,
                          );
                        }).toList(),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 13, 16, 16),
                decoration: const BoxDecoration(
                  color: Color(0xFF0D2923),
                  border: Border(top: BorderSide(color: Color(0xFF1E4038))),
                ),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _CallControl(
                      icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      label: micOn ? 'Mute' : 'Unmute',
                      active: micOn,
                      onTap: onToggleMic,
                    ),
                    _CallControl(
                      icon: cameraOn ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                      label: cameraOn ? 'Camera' : 'Camera off',
                      active: cameraOn,
                      onTap: onToggleCamera,
                    ),
                    _CallControl(
                      icon: speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                      label: 'Speaker',
                      active: speakerOn,
                      onTap: onToggleSpeaker,
                    ),
                    _CallControl(
                      icon: Icons.present_to_all_rounded,
                      label: presenting ? 'Presenting' : 'Present',
                      active: presenting,
                      onTap: onTogglePresent,
                    ),
                    _CallControl(
                      icon: Icons.chat_bubble_outline_rounded,
                      label: 'Chat',
                      active: false,
                      onTap: () {},
                    ),
                    _CallControl(
                      icon: Icons.call_end_rounded,
                      label: 'End',
                      active: false,
                      danger: true,
                      onTap: onEnd,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.width,
    required this.participant,
    required this.micOn,
    required this.cameraOn,
    required this.presenting,
    this.isSelf = false,
  });

  final double width;
  final _Participant participant;
  final bool micOn;
  final bool cameraOn;
  final bool presenting;
  final bool isSelf;

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: 250,
        decoration: BoxDecoration(
          color: const Color(0xFF12372F),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: presenting ? TgcgColors.accent : const Color(0xFF244A42),
            width: presenting ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Center(
              child: cameraOn && isSelf
                  ? const LocalCameraView()
                  : cameraOn
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MeetingAvatar(name: participant.name, size: 78),
                        const SizedBox(height: 12),
                        Text(
                          participant.name,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          participant.role,
                          style: const TextStyle(
                            color: Color(0xFFA7BBB5),
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    )
                  : const Icon(
                      Icons.videocam_off_rounded,
                      color: Color(0xFF708A82),
                      size: 52,
                    ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .34),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      participant.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (presenting)
              const Positioned(
                right: 12,
                top: 12,
                child: TgcgStatusPill(
                  label: 'PRESENTING',
                  color: TgcgColors.accent,
                  icon: Icons.present_to_all_rounded,
                  compact: true,
                ),
              ),
          ],
        ),
      );
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger
        ? TgcgColors.danger
        : active
            ? Colors.white
            : const Color(0xFFB2C3BE);
    final background = danger
        ? TgcgColors.danger
        : active
            ? const Color(0xFF31554C)
            : const Color(0xFF173A32);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 82,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 8.8,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeetingAvatar extends StatelessWidget {
  const _MeetingAvatar({required this.name, required this.size});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((item) => item.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? 'TG'
        : parts.take(2).map((item) => item[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: TgcgColors.primarySoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: TgcgColors.primary,
          fontSize: size * .28,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

IconData _meetingIcon(_MeetingKind kind) => switch (kind) {
      _MeetingKind.audio => Icons.call_rounded,
      _MeetingKind.video => Icons.videocam_rounded,
      _MeetingKind.conference => Icons.groups_rounded,
    };

Color _meetingColor(_MeetingKind kind) => switch (kind) {
      _MeetingKind.audio => TgcgColors.info,
      _MeetingKind.video => TgcgColors.primary,
      _MeetingKind.conference => TgcgColors.ai,
    };
