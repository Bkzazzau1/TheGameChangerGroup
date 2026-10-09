import 'package:flutter/material.dart';

import '../media/local_camera_view.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

class FieldAgentMeetingPage extends StatefulWidget {
  const FieldAgentMeetingPage({super.key});

  @override
  State<FieldAgentMeetingPage> createState() => _FieldAgentMeetingPageState();
}

class _FieldAgentMeetingPageState extends State<FieldAgentMeetingPage> {
  bool inCall = false;
  bool micOn = true;
  bool cameraOn = true;
  bool speakerOn = true;
  bool groupCall = false;
  String activeTitle = '';
  List<_LocalContact> activeParticipants = const [];

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (inCall) {
      return _CallStage(
        title: activeTitle,
        operatorName: session.operatorName,
        participants: activeParticipants,
        micOn: micOn,
        cameraOn: cameraOn,
        speakerOn: speakerOn,
        onMic: () => setState(() => micOn = !micOn),
        onCamera: () => setState(() => cameraOn = !cameraOn),
        onSpeaker: () => setState(() => speakerOn = !speakerOn),
        onEnd: _endCall,
      );
    }

    final ward = session.scope.wardName ?? 'Assigned Ward';
    final lga = session.scope.lgaName ?? 'Assigned LGA';
    final contacts = <_LocalContact>[
      _LocalContact(
        name: '$ward Coordinator',
        role: 'Ward Coordinator',
        initials: 'WC',
      ),
      _LocalContact(
        name: '$lga Field Desk',
        role: 'LGA Coordination',
        initials: 'LD',
      ),
      const _LocalContact(
        name: 'Nearby Polling Unit Team',
        role: 'Field Agents',
        initials: 'PU',
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 26),
      children: [
        _MeetingHero(
          ward: ward,
          lga: lga,
          onStartGroup: () => _startGroupCall(contacts),
        ),
        const SizedBox(height: 14),
        _QuickCalls(
          onAudio: () => _startDirectCall(contacts.first, video: false),
          onVideo: () => _startDirectCall(contacts.first, video: true),
          onGroup: () => _startGroupCall(contacts),
        ),
        const SizedBox(height: 16),
        TgcgSectionCard(
          title: 'Your Local Team',
          subtitle: '$ward • $lga',
          child: Column(
            children: contacts
                .map(
                  (contact) => _ContactRow(
                    contact: contact,
                    onAudio: () => _startDirectCall(contact, video: false),
                    onVideo: () => _startDirectCall(contact, video: true),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 16),
        TgcgSectionCard(
          title: 'Local Meetings',
          subtitle: 'Ward and LGA coordination for your assignment.',
          child: Column(
            children: [
              _MeetingRow(
                title: '$ward Field Briefing',
                subtitle: 'Ward Coordinator • Live now',
                live: true,
                onJoin: () => _startGroupCall(contacts),
              ),
              _MeetingRow(
                title: '$lga Agent Check-in',
                subtitle: 'LGA Field Desk • 16:00',
                onJoin: () => _startGroupCall(contacts),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _startDirectCall(_LocalContact contact, {required bool video}) {
    setState(() {
      inCall = true;
      groupCall = false;
      activeTitle = video ? 'Video Call' : 'Audio Call';
      activeParticipants = [contact];
      cameraOn = video;
      micOn = true;
      speakerOn = true;
    });
  }

  void _startGroupCall(List<_LocalContact> contacts) {
    setState(() {
      inCall = true;
      groupCall = true;
      activeTitle = 'Local Team Conference';
      activeParticipants = contacts;
      cameraOn = true;
      micOn = true;
      speakerOn = true;
    });
  }

  void _endCall() {
    setState(() {
      inCall = false;
      groupCall = false;
      activeParticipants = const [];
      activeTitle = '';
      cameraOn = true;
      micOn = true;
      speakerOn = true;
    });
  }
}

class _LocalContact {
  const _LocalContact({
    required this.name,
    required this.role,
    required this.initials,
  });

  final String name;
  final String role;
  final String initials;
}

class _MeetingHero extends StatelessWidget {
  const _MeetingHero({
    required this.ward,
    required this.lga,
    required this.onStartGroup,
  });

  final String ward;
  final String lga;
  final VoidCallback onStartGroup;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF04102C), Color(0xFF061A49)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.video_call_rounded,
                      color: Colors.white, size: 27),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Meeting Room',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Local voice and video coordination',
                        style: TextStyle(
                          color: Color(0xFFC6CBD7),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              '$ward • $lga',
              style: const TextStyle(
                color: Color(0xFFD7DBE3),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onStartGroup,
                style: FilledButton.styleFrom(
                  backgroundColor: TgcgColors.accent,
                  foregroundColor: TgcgColors.primaryDark,
                ),
                icon: const Icon(Icons.groups_2_rounded),
                label: const Text('Start Local Conference'),
              ),
            ),
          ],
        ),
      );
}

class _QuickCalls extends StatelessWidget {
  const _QuickCalls({
    required this.onAudio,
    required this.onVideo,
    required this.onGroup,
  });

  final VoidCallback onAudio;
  final VoidCallback onVideo;
  final VoidCallback onGroup;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: _QuickCallButton(
              icon: Icons.call_outlined,
              label: 'Audio',
              onTap: onAudio,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _QuickCallButton(
              icon: Icons.videocam_outlined,
              label: 'Video',
              onTap: onVideo,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: _QuickCallButton(
              icon: Icons.groups_2_outlined,
              label: 'Group',
              onTap: onGroup,
            ),
          ),
        ],
      );
}

class _QuickCallButton extends StatelessWidget {
  const _QuickCallButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: TgcgColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: TgcgColors.border),
            ),
            child: Column(
              children: [
                Icon(icon, color: TgcgColors.primary, size: 22),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.onAudio,
    required this.onVideo,
  });

  final _LocalContact contact;
  final VoidCallback onAudio;
  final VoidCallback onVideo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: TgcgColors.primarySoft,
              child: Text(
                contact.initials,
                style: const TextStyle(
                  color: TgcgColors.primary,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    contact.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contact.role,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Audio call',
              onPressed: onAudio,
              icon: const Icon(Icons.call_outlined, size: 19),
            ),
            IconButton.filledTonal(
              tooltip: 'Video call',
              onPressed: onVideo,
              icon: const Icon(Icons.videocam_outlined, size: 19),
            ),
          ],
        ),
      );
}

class _MeetingRow extends StatelessWidget {
  const _MeetingRow({
    required this.title,
    required this.subtitle,
    required this.onJoin,
    this.live = false,
  });

  final String title;
  final String subtitle;
  final VoidCallback onJoin;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: TgcgColors.surfaceSoft,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: (live ? TgcgColors.danger : TgcgColors.primary)
                    .withValues(alpha: .09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                live ? Icons.fiber_manual_record_rounded : Icons.event_outlined,
                color: live ? TgcgColors.danger : TgcgColors.primary,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 10.8,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.tonal(
              onPressed: onJoin,
              child: Text(live ? 'Join' : 'Open'),
            ),
          ],
        ),
      );
}

class _CallStage extends StatelessWidget {
  const _CallStage({
    required this.title,
    required this.operatorName,
    required this.participants,
    required this.micOn,
    required this.cameraOn,
    required this.speakerOn,
    required this.onMic,
    required this.onCamera,
    required this.onSpeaker,
    required this.onEnd,
  });

  final String title;
  final String operatorName;
  final List<_LocalContact> participants;
  final bool micOn;
  final bool cameraOn;
  final bool speakerOn;
  final VoidCallback onMic;
  final VoidCallback onCamera;
  final VoidCallback onSpeaker;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFF030918),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: TgcgColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${participants.length + 1} participants',
                            style: const TextStyle(
                              color: Color(0xFF9BA2B3),
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.lock_outline_rounded,
                        color: Color(0xFF9BA2B3), size: 18),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tiles = <Widget>[
                        _VideoTile(
                          label: operatorName,
                          subtitle: 'You',
                          cameraOn: cameraOn,
                          child: cameraOn ? const LocalCameraView() : null,
                        ),
                        ...participants.map(
                          (person) => _VideoTile(
                            label: person.name,
                            subtitle: person.role,
                            cameraOn: true,
                          ),
                        ),
                      ];
                      final columns = constraints.maxWidth >= 760 ? 2 : 1;
                      final width = columns == 1
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 10) / 2;
                      return SingleChildScrollView(
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: tiles
                              .map((tile) => SizedBox(
                                    width: width,
                                    height: columns == 1 ? 210 : 230,
                                    child: tile,
                                  ))
                              .toList(),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _CallControl(
                      icon: micOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      active: micOn,
                      onTap: onMic,
                    ),
                    const SizedBox(width: 10),
                    _CallControl(
                      icon: cameraOn
                          ? Icons.videocam_rounded
                          : Icons.videocam_off_rounded,
                      active: cameraOn,
                      onTap: onCamera,
                    ),
                    const SizedBox(width: 10),
                    _CallControl(
                      icon: speakerOn
                          ? Icons.volume_up_rounded
                          : Icons.volume_off_rounded,
                      active: speakerOn,
                      onTap: onSpeaker,
                    ),
                    const SizedBox(width: 14),
                    _CallControl(
                      icon: Icons.call_end_rounded,
                      active: true,
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

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.label,
    required this.subtitle,
    required this.cameraOn,
    this.child,
  });

  final String label;
  final String subtitle;
  final bool cameraOn;
  final Widget? child;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: const Color(0xFF09142E),
              child: child ??
                  Center(
                    child: CircleAvatar(
                      radius: 31,
                      backgroundColor: const Color(0xFF1D2C4F),
                      child: Text(
                        _initials(label),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
            ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: const TextStyle(
                              color: Color(0xFFC2C6D0),
                              fontSize: 8,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      cameraOn ? Icons.mic_rounded : Icons.mic_off_rounded,
                      size: 15,
                      color: Colors.white70,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _CallControl extends StatelessWidget {
  const _CallControl({
    required this.icon,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: danger
                ? TgcgColors.danger
                : active
                    ? const Color(0xFF172952)
                    : const Color(0xFF3A2525),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white, size: 21),
        ),
      );
}

String _initials(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return 'TG';
  if (parts.length == 1) {
    return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
