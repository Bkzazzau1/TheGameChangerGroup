import 'package:flutter/material.dart';

import '../session.dart';
import 'tgcg_design.dart';

/// Identifies local demonstration views when signed in to the live server.
/// API-backed pages have no notice; mixed views describe their live actions.
class TgcgDemoDataPage extends StatelessWidget {
  const TgcgDemoDataPage({
    super.key,
    required this.module,
    required this.child,
    this.message,
  });

  final TgcgModule module;
  final Widget child;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final notice = message ?? _messageFor(module);
    if (!TgcgSession.of(context).isServerSession || notice == null) {
      return child;
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            color: TgcgColors.accentSoft,
            border: Border(bottom: BorderSide(color: TgcgColors.accent)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: TgcgColors.accentDeep,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: 'Demo data. ',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      TextSpan(text: notice),
                    ],
                  ),
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  static String? _messageFor(TgcgModule module) => switch (module) {
    TgcgModule.membershipNetwork =>
      'Members, agent profiles and totals on this page are sample or local records, not the server member register.',
    TgcgModule.accreditation =>
      'Enrollment and agent profiles on this page use sample or local records. Polling-unit lookup uses the live API.',
    TgcgModule.geography =>
      'Membership and agent counts include sample records; incident and result counts come from the server. Geographic boundaries are shown for navigation.',
    TgcgModule.liveOperations =>
      'Agent and response activity on this page include sample records. Incidents, field reports and results come from the server.',
    TgcgModule.evidenceCapture =>
      'Evidence lists and linked incidents include sample records. This view is not the server evidence register.',
    TgcgModule.aiVerification =>
      'The review examples and verification activity are demonstrations, not server verification decisions.',
    TgcgModule.aiAnalytics =>
      'Charts, forecasts and analysis on this page include sample data. Incident, report and result figures come from the server.',
    TgcgModule.alertCenter =>
      'Alerts and activity shown here include sample records, not live server alerts.',
    TgcgModule.securityResponse =>
      'Agency contacts, dispatches and response activity include sample or local records, not live emergency services.',
    TgcgModule.mediaIntelligence =>
      'Media reports and intelligence shown here use sample or local records, not a live media feed.',
    TgcgModule.communications =>
      'Contacts, messages and delivery activity are sample or local records. Messages here are not delivered through the live server.',
    TgcgModule.bulkCommunications =>
      'Recipients and campaign activity use sample or local records. Campaigns here do not send live messages.',
    TgcgModule.systemMonitoring =>
      'Activity counts include sample records. Sync status reflects this device, not overall server health.',
    TgcgModule.reports =>
      'Report totals and previews include sample records, not live server reports.',
    TgcgModule.governance =>
      'Governance activity and profiles use sample or local records. Use Role Management for live server appointments.',
    // Live from the server.
    TgcgModule.overview ||
    TgcgModule.roleAssignment ||
    TgcgModule.memberReview ||
    TgcgModule.unitMapping ||
    TgcgModule.agentTracking ||
    TgcgModule.situationRoom ||
    TgcgModule.fieldMonitoring ||
    TgcgModule.resultCapture ||
    TgcgModule.collation ||
    TgcgModule.discussionRoom ||
    TgcgModule.meetingRoom => null,
  };
}
