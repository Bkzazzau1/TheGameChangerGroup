import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart';

import '../access/access_widgets.dart' show confirmAction;
import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/meetings_repository.dart';
import '../ui/tgcg_design.dart';

Room _createRoom() =>
    Room(roomOptions: const RoomOptions(adaptiveStream: true, dynacast: true));

/// One meeting's call, on LiveKit. Audio first: the microphone starts on and
/// the camera off; in a video meeting the camera can be turned on.
///
/// Pops with a message to show when the call ended other than by leaving.
class MeetingCallPage extends StatefulWidget {
  const MeetingCallPage({
    super.key,
    required this.meeting,
    required this.pass,
    this.createRoom = _createRoom,
  });

  final ServerMeeting meeting;
  final JoinPass pass;
  final Room Function() createRoom;

  @override
  State<MeetingCallPage> createState() => _MeetingCallPageState();
}

class _MeetingCallPageState extends State<MeetingCallPage> {
  late final _room = widget.createRoom();
  late final EventsListener<RoomEvent> _events = _room.createListener();
  bool _connecting = true;
  bool _busy = false;
  bool _exiting = false;
  bool _confirmingEnd = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _room.addListener(_changed);
    _events.on<RoomDisconnectedEvent>(_disconnected);
    unawaited(_connect());
  }

  Future<void> _connect() async {
    try {
      await _room.connect(widget.pass.url, widget.pass.token);
      if (!mounted || _exiting) return;
      await _room.localParticipant?.setMicrophoneEnabled(true);
    } catch (error) {
      if (mounted) setState(() => _error = 'The call could not start: $error');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  void _changed() {
    if (mounted && !_exiting) setState(() {});
  }

  void _leave([String? message]) {
    // LiveKit can disconnect before or after the end API response, while
    // this page remains mounted for the navigation transition.
    if (!mounted || _exiting) return;
    _exiting = true;
    final navigator = Navigator.of(context);
    // A disconnect can also arrive while the confirmation dialog is open.
    // Close that boolean-result dialog before returning the call's message.
    if (_confirmingEnd && ModalRoute.of(context)?.isCurrent == false) {
      navigator.pop(false);
    }
    navigator.pop(message);
  }

  void _disconnected(RoomDisconnectedEvent event) {
    if (!mounted) return;
    final message = switch (event.reason) {
      DisconnectReason.clientInitiated => null,
      DisconnectReason.roomDeleted => 'The meeting has ended.',
      DisconnectReason.duplicateIdentity => 'You joined this meeting from another device.',
      DisconnectReason.participantRemoved => 'You were removed from the meeting.',
      _ => 'The call was cut off. Join again from the meeting list.',
    };
    _leave(message);
  }

  Future<void> _toggleMicrophone() async {
    final me = _room.localParticipant;
    if (me == null) return;
    await _guard(() => me.setMicrophoneEnabled(!me.isMicrophoneEnabled()));
  }

  Future<void> _toggleCamera() async {
    final me = _room.localParticipant;
    if (me == null) return;
    await _guard(() => me.setCameraEnabled(!me.isCameraEnabled()));
  }

  Future<void> _endForEveryone() async {
    final services = TgcgBackend.of(context);
    if (services == null) return;
    _confirmingEnd = true;
    final bool confirmed;
    try {
      confirmed = await confirmAction(
        context,
        title: 'End ${widget.meeting.title}?',
        message: 'Everyone in the call is disconnected and nobody can join again.',
        action: 'End for everyone',
        destructive: true,
      );
    } finally {
      _confirmingEnd = false;
    }
    if (!confirmed || !mounted || _exiting) return;
    await _guard(() async {
      await services.meetings.end(widget.meeting.reference);
      _leave('The meeting has ended.');
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException ? error.message : '$error';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: TgcgColors.danger),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _exiting = true;
    _room.removeListener(_changed);
    unawaited(_events.dispose());
    unawaited(_room.disconnect().whenComplete(_room.dispose));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = _room.localParticipant;
    final people = <Participant>[
      ?me,
      ..._room.remoteParticipants.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name)),
    ];
    final video = widget.meeting.kind == MeetingKind.video;
    final call = Scaffold(
      backgroundColor: TgcgColors.primaryDark,
      appBar: AppBar(
        backgroundColor: TgcgColors.primaryDark,
        foregroundColor: Colors.white,
        title: Text(widget.meeting.title, overflow: TextOverflow.ellipsis),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${people.length} in the call',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: _error != null
          ? _Message(text: _error!, onBack: () => _leave())
          : _connecting
              ? const Center(child: CircularProgressIndicator(color: Colors.white))
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1000
                        ? 4
                        : constraints.maxWidth >= 640
                            ? 3
                            : 2;
                    return GridView.count(
                      padding: const EdgeInsets.all(12),
                      crossAxisCount: columns,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: video ? 4 / 3 : 1.3,
                      children: [
                        for (final person in people)
                          _PersonTile(participant: person, isMe: identical(person, me)),
                      ],
                    );
                  },
                ),
      bottomNavigationBar: _error != null || _connecting || me == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _Control(
                      icon: me.isMicrophoneEnabled() ? Icons.mic_rounded : Icons.mic_off_rounded,
                      label: me.isMicrophoneEnabled() ? 'Mute' : 'Unmute',
                      onPressed: _busy ? null : _toggleMicrophone,
                    ),
                    if (video)
                      _Control(
                        icon: me.isCameraEnabled()
                            ? Icons.videocam_rounded
                            : Icons.videocam_off_rounded,
                        label: me.isCameraEnabled() ? 'Camera off' : 'Camera on',
                        onPressed: _busy ? null : _toggleCamera,
                      ),
                    _Control(
                      icon: Icons.call_end_rounded,
                      label: 'Leave',
                      color: TgcgColors.danger,
                      onPressed: () => _leave(),
                    ),
                    if (widget.meeting.canManage)
                      _Control(
                        icon: Icons.stop_circle_outlined,
                        label: 'End for everyone',
                        color: TgcgColors.danger,
                        onPressed: _busy ? null : _endForEveryone,
                      ),
                  ],
                ),
              ),
            ),
    );
    return PopScope<String>(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _exiting = true;
      },
      child: call,
    );
  }
}

class _PersonTile extends StatelessWidget {
  const _PersonTile({required this.participant, required this.isMe});

  final Participant participant;
  final bool isMe;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: participant,
        builder: (context, _) {
          final camera = participant.videoTrackPublications
              .where((item) => !item.isScreenShare && !item.muted && item.track != null)
              .firstOrNull
              ?.track;
          final name = participant.name.isNotEmpty ? participant.name : participant.identity;
          final speaking = participant.isSpeaking;
          return Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: TgcgColors.primary,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: speaking ? TgcgColors.accentBright : Colors.white12,
                width: speaking ? 3 : 1,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (camera is VideoTrack)
                  VideoTrackRenderer(camera, fit: VideoViewFit.cover)
                else
                  Center(
                    child: CircleAvatar(
                      radius: 30,
                      backgroundColor: TgcgColors.primaryMid,
                      child: Text(
                        _initials(name),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Row(
                    children: [
                      Icon(
                        participant.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        size: 16,
                        color: participant.isMuted ? TgcgColors.danger : Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          isMe ? '$name (you)' : name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  return parts.take(2).map((part) => part[0].toUpperCase()).join();
}

class _Control extends StatelessWidget {
  const _Control({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: color ?? Colors.white,
          foregroundColor: color == null ? TgcgColors.primaryDark : Colors.white,
        ),
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(label),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, required this.onBack});

  final String text;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.call_end_rounded, color: Colors.white70, size: 40),
              const SizedBox(height: 12),
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 12),
              FilledButton(onPressed: onBack, child: const Text('Back')),
            ],
          ),
        ),
      );
}
