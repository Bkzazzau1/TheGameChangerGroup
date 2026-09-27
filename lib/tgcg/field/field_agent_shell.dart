import 'package:flutter/material.dart';

import '../communications/communications_page.dart';
import '../discussion/discussion_room_page.dart';
import '../evidence/evidence_capture_page.dart';
import '../meeting/meeting_room_page.dart';
import '../membership/membership_store.dart';
import '../results/result_capture_page.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'field_agent_home_page.dart';
import 'field_monitoring_page.dart';

class FieldAgentShell extends StatefulWidget {
  const FieldAgentShell({super.key});

  @override
  State<FieldAgentShell> createState() => _FieldAgentShellState();
}

class _FieldAgentShellState extends State<FieldAgentShell> {
  TgcgModule selectedModule = TgcgModule.overview;
  String? scopedAgentId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = TgcgSession.of(context, listen: false);
    final membership = MembershipOperations.of(context, listen: false);
    final agent = _resolveAgent(membership, session.accessId);
    if (agent == null || scopedAgentId == agent.agentId) return;
    scopedAgentId = agent.agentId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      TgcgSession.of(context, listen: false).updateScope(agent.scope);
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final agent = _resolveAgent(membership, session.accessId);

    if (agent == null) {
      return Scaffold(
        backgroundColor: TgcgColors.canvas,
        appBar: _appBar(session, allowHome: false),
        body: _FieldAssignmentRequired(
          session: session,
          membership: membership,
        ),
      );
    }

    final allowed = <TgcgModule>{
      TgcgModule.overview,
      TgcgModule.fieldMonitoring,
      TgcgModule.evidenceCapture,
      TgcgModule.resultCapture,
      TgcgModule.communications,
      TgcgModule.discussionRoom,
      TgcgModule.meetingRoom,
    };
    if (!allowed.contains(selectedModule)) {
      selectedModule = TgcgModule.overview;
    }

    final focused = selectedModule == TgcgModule.meetingRoom ||
        selectedModule == TgcgModule.evidenceCapture;

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: _appBar(session, allowHome: true),
      body: _pageFor(selectedModule),
      bottomNavigationBar: focused
          ? null
          : NavigationBar(
              selectedIndex: _indexFor(selectedModule),
              onDestinationSelected: (index) => setState(() {
                selectedModule = _moduleFor(index);
              }),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.sensors_outlined),
                  selectedIcon: Icon(Icons.sensors_rounded),
                  label: 'Field',
                ),
                NavigationDestination(
                  icon: Icon(Icons.ballot_outlined),
                  selectedIcon: Icon(Icons.ballot_rounded),
                  label: 'Result',
                ),
                NavigationDestination(
                  icon: Icon(Icons.chat_outlined),
                  selectedIcon: Icon(Icons.chat_rounded),
                  label: 'Messages',
                ),
                NavigationDestination(
                  icon: Icon(Icons.dynamic_feed_outlined),
                  selectedIcon: Icon(Icons.dynamic_feed_rounded),
                  label: 'Forum',
                ),
              ],
            ),
    );
  }

  PreferredSizeWidget _appBar(
    TgcgSessionController session, {
    required bool allowHome,
  }) => AppBar(
        elevation: 0,
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          children: [
            const TgcgLogo(size: 34),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedModule == TgcgModule.meetingRoom
                        ? 'TGCG MEETING'
                        : selectedModule == TgcgModule.evidenceCapture
                            ? 'TGCG EVIDENCE'
                            : 'TGCG FIELD',
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    session.scope.pollingUnitName ?? 'Polling-unit operations',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (allowHome &&
              selectedModule != TgcgModule.evidenceCapture &&
              selectedModule != TgcgModule.meetingRoom)
            IconButton(
              tooltip: 'Capture evidence',
              onPressed: () =>
                  setState(() => selectedModule = TgcgModule.evidenceCapture),
              icon: const Icon(Icons.photo_camera_outlined),
            ),
          if (allowHome && selectedModule != TgcgModule.meetingRoom)
            IconButton(
              tooltip: 'Meeting room',
              onPressed: () =>
                  setState(() => selectedModule = TgcgModule.meetingRoom),
              icon: const Icon(Icons.video_call_outlined),
            ),
          if (allowHome && selectedModule != TgcgModule.overview)
            IconButton(
              tooltip: 'Field home',
              onPressed: () =>
                  setState(() => selectedModule = TgcgModule.overview),
              icon: const Icon(Icons.home_outlined),
            ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: session.signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 6),
        ],
      );

  Widget _pageFor(TgcgModule module) => switch (module) {
        TgcgModule.overview => FieldAgentHomePage(
            onOpenModule: (next) => setState(() {
              selectedModule = switch (next) {
                TgcgModule.fieldMonitoring => TgcgModule.fieldMonitoring,
                TgcgModule.evidenceCapture => TgcgModule.evidenceCapture,
                TgcgModule.resultCapture => TgcgModule.resultCapture,
                TgcgModule.communications => TgcgModule.communications,
                TgcgModule.discussionRoom => TgcgModule.discussionRoom,
                TgcgModule.meetingRoom => TgcgModule.meetingRoom,
                _ => TgcgModule.overview,
              };
            }),
          ),
        TgcgModule.fieldMonitoring => const FieldMonitoringPage(),
        TgcgModule.evidenceCapture => const EvidenceCapturePage(),
        TgcgModule.resultCapture => const ResultCapturePage(),
        TgcgModule.communications => const CommunicationsPage(),
        TgcgModule.discussionRoom => const DiscussionRoomPage(),
        TgcgModule.meetingRoom => const MeetingRoomPage(),
        _ => FieldAgentHomePage(
            onOpenModule: (next) => setState(() => selectedModule = next),
          ),
      };

  int _indexFor(TgcgModule module) => switch (module) {
        TgcgModule.overview => 0,
        TgcgModule.fieldMonitoring => 1,
        TgcgModule.resultCapture => 2,
        TgcgModule.communications => 3,
        TgcgModule.discussionRoom => 4,
        _ => 0,
      };

  TgcgModule _moduleFor(int index) => switch (index) {
        1 => TgcgModule.fieldMonitoring,
        2 => TgcgModule.resultCapture,
        3 => TgcgModule.communications,
        4 => TgcgModule.discussionRoom,
        _ => TgcgModule.overview,
      };
}

class _FieldAssignmentRequired extends StatelessWidget {
  const _FieldAssignmentRequired({
    required this.session,
    required this.membership,
  });

  final TgcgSessionController session;
  final MembershipOperationsController membership;

  @override
  Widget build(BuildContext context) {
    final agents = membership.agents
        .where((agent) =>
            agent.role == TgcgRole.pollingUnitAgent &&
            agent.status == AccreditationStatus.approved)
        .toList(growable: false);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: TgcgColors.primarySoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.how_to_vote_rounded,
                          color: TgcgColors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Field Assignment Required',
                              style: TextStyle(
                                color: TgcgColors.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Select an approved polling-unit profile to continue.',
                              style: TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  ...agents.map((agent) {
                    final member = membership.memberById(agent.memberId);
                    final ready = agent.trainingCompleted &&
                        agent.biometricEnrolled &&
                        (agent.deviceId ?? '').trim().isNotEmpty &&
                        (agent.simFingerprint ?? '').trim().isNotEmpty;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => session.signIn(
                          role: TgcgRole.pollingUnitAgent,
                          operatorName: member?.fullName ?? agent.agentId,
                          accessId: agent.agentId,
                          scope: agent.scope,
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: TgcgColors.surfaceSoft,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: TgcgColors.border),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: TgcgColors.primarySoft,
                                foregroundColor: TgcgColors.primary,
                                child: Text(
                                  (member?.fullName ?? agent.agentId)
                                      .trim()
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      member?.fullName ?? agent.agentId,
                                      style: const TextStyle(
                                        color: TgcgColors.ink,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${agent.agentId} • ${agent.scope.lgaName ?? agent.scope.stateName ?? ''}',
                                      style: const TextStyle(
                                        color: TgcgColors.muted,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      agent.scope.pollingUnitName ?? agent.scope.label,
                                      style: const TextStyle(
                                        color: TgcgColors.muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              TgcgStatusPill(
                                label: ready ? 'READY' : 'APPROVED',
                                color: ready
                                    ? TgcgColors.success
                                    : TgcgColors.primary,
                                compact: true,
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: TgcgColors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                  if (agents.isEmpty)
                    const TgcgEmptyState(
                      icon: Icons.badge_outlined,
                      title: 'No approved field profiles',
                      message: 'Sign in again with an assigned polling-unit account.',
                    ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: session.signOut,
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Sign in again'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

AccreditedAgent? _resolveAgent(
  MembershipOperationsController membership,
  String accessId,
) {
  final normalized = accessId.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final agent in membership.agents) {
    if (agent.role != TgcgRole.pollingUnitAgent) continue;
    final idMatch = agent.agentId.toLowerCase() == normalized;
    final phoneMatch =
        (agent.registeredPhoneNumber ?? '').trim().toLowerCase() == normalized;
    if (idMatch || phoneMatch) return agent;
  }
  return null;
}
