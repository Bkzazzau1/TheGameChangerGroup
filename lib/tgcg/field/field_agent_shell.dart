import 'package:flutter/material.dart';

import '../results/result_capture_page.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'agent_home_page.dart';
import 'field_agent_meeting_page.dart';
import 'field_monitoring_page.dart';

/// The polling-unit agent's phone app. Everything in it works on the
/// agent's own server account: their identity, polling unit and records.
class FieldAgentShell extends StatefulWidget {
  const FieldAgentShell({super.key});

  @override
  State<FieldAgentShell> createState() => _FieldAgentShellState();
}

class _FieldAgentShellState extends State<FieldAgentShell> {
  static const _tabs = [
    TgcgModule.overview,
    TgcgModule.fieldMonitoring,
    TgcgModule.resultCapture,
    TgcgModule.meetingRoom,
  ];

  TgcgModule selectedModule = TgcgModule.overview;

  void _open(TgcgModule module) => setState(() => selectedModule = module);

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final tabs = [
      for (final module in _tabs)
        if (module == TgcgModule.overview || session.modules.contains(module)) module,
    ];
    if (!tabs.contains(selectedModule)) selectedModule = TgcgModule.overview;

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 14,
        title: Row(
          children: [
            const TgcgLogo(size: 34),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _titleFor(selectedModule),
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    session.scope.pollingUnitName ?? session.scope.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: session.signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: switch (selectedModule) {
        TgcgModule.fieldMonitoring => const FieldMonitoringPage(),
        TgcgModule.resultCapture => const ResultCapturePage(),
        TgcgModule.meetingRoom => const FieldAgentMeetingPage(),
        _ => AgentHomePage(onOpenModule: _open),
      },
      bottomNavigationBar: tabs.length < 2
          ? null
          : NavigationBar(
              height: 68,
              selectedIndex: tabs.indexOf(selectedModule),
              onDestinationSelected: (index) => _open(tabs[index]),
              destinations: [
                for (final module in tabs)
                  switch (module) {
                    TgcgModule.fieldMonitoring => const NavigationDestination(
                        icon: Icon(Icons.warning_amber_outlined),
                        selectedIcon: Icon(Icons.warning_amber_rounded),
                        label: 'Report',
                      ),
                    TgcgModule.resultCapture => const NavigationDestination(
                        icon: Icon(Icons.ballot_outlined),
                        selectedIcon: Icon(Icons.ballot_rounded),
                        label: 'Result',
                      ),
                    TgcgModule.meetingRoom => const NavigationDestination(
                        icon: Icon(Icons.call_outlined),
                        selectedIcon: Icon(Icons.call_rounded),
                        label: 'Meetings',
                      ),
                    _ => const NavigationDestination(
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Home',
                      ),
                  },
              ],
            ),
    );
  }

  String _titleFor(TgcgModule module) => switch (module) {
        TgcgModule.fieldMonitoring => 'FIELD REPORTING',
        TgcgModule.resultCapture => 'RESULT SUBMISSION',
        TgcgModule.meetingRoom => 'MEETINGS',
        _ => 'POLLING AGENT',
      };
}
