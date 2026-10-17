import 'dart:async';

import 'package:flutter/material.dart';

import '../account/change_pin_dialog.dart';
import '../discussion/discussion_room_page.dart';
import '../evidence/evidence_upload.dart';
import '../location/gps_service.dart';
import '../messaging/inbox_page.dart';
import '../projects/project_mode.dart';
import '../results/result_capture_page.dart';
import '../session.dart';
import '../sound/sound_alert_overlay.dart';
import '../sound/sound_alerts.dart';
import '../ui/tgcg_design.dart';
import 'agent_home_page.dart';
import 'field_agent_meeting_page.dart';
import 'field_monitoring_page.dart';
import 'field_operations_store.dart';

/// The polling-unit agent's phone app. Everything in it works on the
/// agent's own server account: their identity, polling unit and records.
class FieldAgentShell extends StatefulWidget {
  const FieldAgentShell({super.key, this.soundAlerts});

  final SoundAlerts? soundAlerts;

  @override
  State<FieldAgentShell> createState() => _FieldAgentShellState();
}

class _FieldAgentShellState extends State<FieldAgentShell> {
  static const _tabs = [
    TgcgModule.overview,
    TgcgModule.fieldMonitoring,
    TgcgModule.resultCapture,
    TgcgModule.meetingRoom,
    TgcgModule.discussionRoom,
  ];

  TgcgModule selectedModule = TgcgModule.overview;
  late final SoundAlerts _alerts = widget.soundAlerts ?? SoundAlerts.instance;

  @override
  void initState() {
    super.initState();
    _alerts.attach(_sendAlert);
    DutyTracker.instance.addListener(_dutyChanged);
  }

  @override
  void dispose() {
    DutyTracker.instance.removeListener(_dutyChanged);
    _alerts.detach(_sendAlert);
    // Signing out stops the listening too.
    unawaited(_alerts.switchOff());
    super.dispose();
  }

  void _dutyChanged() {
    if (!DutyTracker.instance.onDuty) unawaited(_alerts.switchOff());
  }

  /// A sound alert becomes an incident at the agent's polling unit, with
  /// the recording, like any report from the phone.
  Future<void> _sendAlert(SoundAlert alert) async {
    final session = TgcgSession.of(context, listen: false);
    final field = FieldOperations.of(context, listen: false);
    final kind = alert.danger.kind;
    final recording = await evidenceFromBytes(
      type: EvidenceType.audio,
      name: 'sound-alert.wav',
      bytes: alert.clip,
      mimeType: 'audio/wav',
      takenAt: alert.danger.at,
    );
    await field.createIncident(
      title: 'Sound alert: ${kind.label}',
      category: kind.category,
      severity: kind.severity,
      scope: session.scope,
      reporterId: session.accessId,
      summary: alert.summary,
      gps: alert.gps,
      photos: [recording],
      origin: RecordOrigin.systemDerived,
    );
  }

  void _open(TgcgModule module) => setState(() => selectedModule = module);

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final tabs = [
      for (final module in _tabs)
        if (module == TgcgModule.overview || session.modules.contains(module)) module,
    ];
    if (!tabs.contains(selectedModule)) selectedModule = TgcgModule.overview;

    return SoundAlertOverlay(
      alerts: _alerts,
      child: Scaffold(
        backgroundColor: TgcgColors.canvas,
        appBar: AppBar(
          elevation: 0,
          backgroundColor: TgcgColors.surface,
          // The theme's white icons are for dark bars: this one is light.
          foregroundColor: TgcgColors.ink,
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
            const InboxButton(),
            IconButton(
              tooltip: 'Change PIN',
              onPressed: () => showChangePin(context),
              icon: const Icon(Icons.password_rounded),
            ),
            IconButton(
              tooltip: 'Sign out',
              onPressed: session.signOut,
              icon: const Icon(Icons.logout_rounded),
            ),
            const SizedBox(width: 4),
          ],
        ),
        body: Column(
          children: [
            const ProjectStrip(),
            Expanded(
              child: ProjectGpsGate(
                child: switch (selectedModule) {
                  TgcgModule.fieldMonitoring => const FieldMonitoringPage(),
                  TgcgModule.resultCapture => const ResultCapturePage(),
                  TgcgModule.meetingRoom => const FieldAgentMeetingPage(),
                  TgcgModule.discussionRoom => const DiscussionRoomPage(),
                  _ => AgentHomePage(onOpenModule: _open, soundAlerts: _alerts),
                },
              ),
            ),
          ],
        ),
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
                      TgcgModule.discussionRoom => const NavigationDestination(
                          icon: Icon(Icons.forum_outlined),
                          selectedIcon: Icon(Icons.forum_rounded),
                          label: 'Forum',
                        ),
                      _ => const NavigationDestination(
                          icon: Icon(Icons.home_outlined),
                          selectedIcon: Icon(Icons.home_rounded),
                          label: 'Home',
                        ),
                    },
                ],
              ),
      ),
    );
  }

  String _titleFor(TgcgModule module) => switch (module) {
        TgcgModule.fieldMonitoring => 'FIELD REPORTING',
        TgcgModule.resultCapture => 'RESULT SUBMISSION',
        TgcgModule.meetingRoom => 'MEETINGS',
        TgcgModule.discussionRoom => 'FORUM',
        _ => 'POLLING AGENT',
      };
}
