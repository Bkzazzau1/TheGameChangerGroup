import 'package:flutter/material.dart';

import '../communications/communications_page.dart';
import '../discussion/discussion_room_page.dart';
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
        body: FieldAgentHomePage(onOpenModule: (_) {}),
      );
    }

    final allowed = <TgcgModule>{
      TgcgModule.overview,
      TgcgModule.fieldMonitoring,
      TgcgModule.resultCapture,
      TgcgModule.communications,
      TgcgModule.discussionRoom,
      TgcgModule.meetingRoom,
    };
    if (!allowed.contains(selectedModule)) {
      selectedModule = TgcgModule.overview;
    }

    final inMeeting = selectedModule == TgcgModule.meetingRoom;

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: _appBar(session, allowHome: true),
      body: _pageFor(selectedModule),
      bottomNavigationBar: inMeeting
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
          if (allowHome && selectedModule != TgcgModule.meetingRoom)
            IconButton(
              tooltip: 'Meeting room',
              onPressed: () => setState(() => selectedModule = TgcgModule.meetingRoom),
              icon: const Icon(Icons.video_call_outlined),
            ),
          if (allowHome && selectedModule != TgcgModule.overview)
            IconButton(
              tooltip: 'Field home',
              onPressed: () => setState(() => selectedModule = TgcgModule.overview),
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
                TgcgModule.resultCapture => TgcgModule.resultCapture,
                TgcgModule.communications => TgcgModule.communications,
                TgcgModule.discussionRoom => TgcgModule.discussionRoom,
                TgcgModule.meetingRoom => TgcgModule.meetingRoom,
                _ => TgcgModule.overview,
              };
            }),
          ),
        TgcgModule.fieldMonitoring => const FieldMonitoringPage(),
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
