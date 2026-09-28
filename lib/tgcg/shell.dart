import 'package:flutter/material.dart';

import 'ai/ai_verification_page.dart';
import 'alerts/alert_center_page.dart';
import 'analytics/ai_data_analytics_page.dart';
import 'collation/collation_page.dart';
import 'communications/bulk_communications_page.dart';
import 'communications/communications_page.dart';
import 'dashboard_page.dart';
import 'discussion/discussion_room_page.dart';
import 'evidence/evidence_capture_page.dart';
import 'field/field_monitoring_page.dart';
import 'field/situation_room_page.dart';
import 'geography/geography_page.dart';
import 'governance/governance_page.dart';
import 'governance/role_assignment_page.dart';
import 'media/media_intelligence_page.dart';
import 'meeting/meeting_room_page.dart';
import 'membership/national_membership_page.dart';
import 'membership/pvc_enrollment_page.dart';
import 'monitoring/system_monitoring_page.dart';
import 'offline/offline_persistence.dart';
import 'operations/live_operations_page.dart';
import 'presentation/presentation_tour_sheet.dart';
import 'reports/reports_page.dart';
import 'results/result_capture_page.dart';
import 'security/security_response_portal_page.dart';
import 'session.dart';
import 'ui/tgcg_design.dart';

class TgcgShell extends StatefulWidget {
  const TgcgShell({super.key});

  @override
  State<TgcgShell> createState() => _TgcgShellState();
}

class _TgcgShellState extends State<TgcgShell> {
  TgcgModule selectedModule = TgcgModule.overview;

  void _select(TgcgModule module) => setState(() => selectedModule = module);

  void _openTour(Set<TgcgModule> allowed) {
    showPresentationTour(
      context,
      allowedModules: allowed,
      onOpenModule: _select,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final allowed = allowedModules(session.role!);
    if (!allowed.contains(selectedModule)) {
      selectedModule = TgcgModule.overview;
    }

    final destinations = _destinations
        .where((item) => allowed.contains(item.module))
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1100;
        return Scaffold(
          backgroundColor: TgcgColors.canvas,
          appBar: desktop
              ? null
              : AppBar(
                  elevation: 0,
                  backgroundColor: TgcgColors.surface,
                  surfaceTintColor: Colors.transparent,
                  title: const _CompactBrand(),
                  actions: [
                    const _CompactSync(),
                    const SizedBox(width: 2),
                    IconButton(
                      tooltip: 'Presentation Tour',
                      onPressed: () => _openTour(allowed),
                      icon: const Icon(Icons.slideshow_rounded),
                    ),
                    if (allowed.contains(TgcgModule.alertCenter))
                      IconButton(
                        tooltip: 'Alert Centre',
                        onPressed: () => _select(TgcgModule.alertCenter),
                        icon: const Badge(
                          smallSize: 7,
                          child: Icon(Icons.notifications_none_rounded),
                        ),
                      ),
                    const SizedBox(width: 6),
                  ],
                ),
          drawer: desktop
              ? null
              : Drawer(
                  backgroundColor: TgcgColors.primaryDark,
                  child: _Navigation(
                    destinations: destinations,
                    selectedModule: selectedModule,
                    onSelect: (module) {
                      _select(module);
                      Navigator.pop(context);
                    },
                  ),
                ),
          body: desktop
              ? Row(
                  children: [
                    SizedBox(
                      width: 272,
                      child: _Navigation(
                        destinations: destinations,
                        selectedModule: selectedModule,
                        onSelect: _select,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          _CommandBar(
                            selectedModule: selectedModule,
                            showAlerts: allowed.contains(TgcgModule.alertCenter),
                            onAlerts: () => _select(TgcgModule.alertCenter),
                            onTour: () => _openTour(allowed),
                          ),
                          Expanded(child: _pageFor(selectedModule)),
                        ],
                      ),
                    ),
                  ],
                )
              : _pageFor(selectedModule),
        );
      },
    );
  }

  Widget _pageFor(TgcgModule module) => switch (module) {
        TgcgModule.overview => TgcgDashboardPage(onOpenModule: _select),
        TgcgModule.accreditation => const PvcEnrollmentPage(),
        TgcgModule.membershipNetwork => const NationalMembershipPage(),
        TgcgModule.roleAssignment => const RoleAssignmentPage(),
        TgcgModule.geography => const GeographyPage(),
        TgcgModule.liveOperations => const LiveOperationsPage(),
        TgcgModule.aiVerification => const AiVerificationPage(),
        TgcgModule.aiAnalytics => const AiDataAnalyticsPage(),
        TgcgModule.alertCenter => const AlertCenterPage(),
        TgcgModule.fieldMonitoring => const FieldMonitoringPage(),
        TgcgModule.evidenceCapture => const EvidenceCapturePage(),
        TgcgModule.situationRoom => const SituationRoomPage(),
        TgcgModule.securityResponse => const SecurityResponsePortalPage(),
        TgcgModule.resultCapture => const ResultCapturePage(),
        TgcgModule.collation => const CollationPage(),
        TgcgModule.mediaIntelligence => const MediaIntelligencePage(),
        TgcgModule.communications => const CommunicationsPage(),
        TgcgModule.bulkCommunications => const BulkCommunicationsPage(),
        TgcgModule.discussionRoom => const DiscussionRoomPage(),
        TgcgModule.meetingRoom => const MeetingRoomPage(),
        TgcgModule.systemMonitoring => const SystemMonitoringPage(),
        TgcgModule.reports => const ReportsPage(),
        TgcgModule.governance => const GovernancePage(),
      };
}

enum _NavGroup { command, fieldOperations, coordination, control }

class _Destination {
  const _Destination(this.module, this.label, this.icon, this.group);
  final TgcgModule module;
  final String label;
  final IconData icon;
  final _NavGroup group;
}

const _destinations = <_Destination>[
  _Destination(TgcgModule.overview, 'Command Overview', Icons.space_dashboard_outlined, _NavGroup.command),
  _Destination(TgcgModule.liveOperations, 'Live Operations', Icons.travel_explore_rounded, _NavGroup.command),
  _Destination(TgcgModule.aiAnalytics, 'AI Data Analytics', Icons.query_stats_rounded, _NavGroup.command),
  _Destination(TgcgModule.alertCenter, 'Alert Centre', Icons.notifications_active_outlined, _NavGroup.command),
  _Destination(TgcgModule.membershipNetwork, 'Registered Members', Icons.groups_2_outlined, _NavGroup.command),
  _Destination(TgcgModule.situationRoom, 'Situation Room', Icons.radar_rounded, _NavGroup.command),
  _Destination(TgcgModule.securityResponse, 'Security Response', Icons.emergency_share_outlined, _NavGroup.command),
  _Destination(TgcgModule.mediaIntelligence, 'Media Intelligence', Icons.insights_outlined, _NavGroup.command),
  _Destination(TgcgModule.geography, 'Geographic Operations', Icons.public_rounded, _NavGroup.command),
  _Destination(TgcgModule.accreditation, 'Member Enrolment', Icons.how_to_reg_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.aiVerification, 'AI Verification', Icons.auto_awesome_rounded, _NavGroup.fieldOperations),
  _Destination(TgcgModule.fieldMonitoring, 'Field Monitoring', Icons.sensors_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.evidenceCapture, 'Evidence Capture', Icons.perm_media_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.resultCapture, 'Result Capture', Icons.ballot_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.collation, 'Collation', Icons.account_tree_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.communications, 'Communications', Icons.forum_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.bulkCommunications, 'Bulk Communications', Icons.send_to_mobile_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.discussionRoom, 'Discussion Forum', Icons.dynamic_feed_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.meetingRoom, 'Meeting Room', Icons.video_camera_front_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.roleAssignment, 'Role Assignment', Icons.manage_accounts_outlined, _NavGroup.control),
  _Destination(TgcgModule.systemMonitoring, 'System Monitoring', Icons.monitor_heart_outlined, _NavGroup.control),
  _Destination(TgcgModule.reports, 'Reports & Exports', Icons.description_outlined, _NavGroup.control),
  _Destination(TgcgModule.governance, 'Data & Governance', Icons.shield_outlined, _NavGroup.control),
];

class _Navigation extends StatelessWidget {
  const _Navigation({
    required this.destinations,
    required this.selectedModule,
    required this.onSelect,
  });

  final List<_Destination> destinations;
  final TgcgModule selectedModule;
  final ValueChanged<TgcgModule> onSelect;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    return Container(
      color: TgcgColors.primaryDark,
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: _Brand(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                children: [
                  for (final group in _NavGroup.values)
                    if (destinations.any((item) => item.group == group)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(10, 15, 10, 7),
                        child: Text(
                          _groupLabel(group),
                          style: const TextStyle(
                            color: Color(0xFF8EA49D),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.1,
                          ),
                        ),
                      ),
                      ...destinations
                          .where((item) => item.group == group)
                          .map(
                            (item) => _NavTile(
                              item: item,
                              active: item.module == selectedModule,
                              onTap: () => onSelect(item.module),
                            ),
                          ),
                    ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _OperatorCard(session: session),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.active, required this.onTap});
  final _Destination item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Material(
          color: active ? const Color(0xFF173A32) : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: active
                    ? const Border(left: BorderSide(color: TgcgColors.accent, width: 3))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(item.icon, size: 19, color: active ? Colors.white : const Color(0xFFA9BBB5)),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: active ? Colors.white : const Color(0xFFB8C7C2),
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w900 : FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({required this.session});
  final TgcgSessionController session;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: .08)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: TgcgColors.accent.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.person_outline_rounded, color: TgcgColors.accent, size: 19),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.operatorName.isEmpty ? 'TGCG Operator' : session.operatorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        roleLabel(session.role!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Color(0xFFA5B8B1), fontSize: 9.5),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: session.signOut,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.logout_rounded, color: Color(0xFFA5B8B1), size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Color(0xFF80968E), size: 14),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    session.scope.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF8EA49D), fontSize: 9.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _CommandBar extends StatelessWidget {
  const _CommandBar({
    required this.selectedModule,
    required this.showAlerts,
    required this.onAlerts,
    required this.onTour,
  });

  final TgcgModule selectedModule;
  final bool showAlerts;
  final VoidCallback onAlerts;
  final VoidCallback onTour;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final pending = OfflinePersistence.of(context).pendingOutbox.length;
    return Container(
      height: 68,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: const BoxDecoration(
        color: TgcgColors.surface,
        border: Border(bottom: BorderSide(color: TgcgColors.border)),
      ),
      child: Row(
        children: [
          Text(
            _moduleLabel(selectedModule),
            style: const TextStyle(color: TgcgColors.ink, fontSize: 14, fontWeight: FontWeight.w900),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: const TextField(
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Search agents, polling units, incidents or results',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                ),
              ),
            ),
          ),
          const Spacer(),
          TgcgStatusPill(
            label: pending == 0 ? 'SYNCED' : '$pending TO SYNC',
            color: pending == 0 ? TgcgColors.success : TgcgColors.warning,
            icon: pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
            compact: true,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onTour,
            icon: const Icon(Icons.slideshow_rounded, size: 17),
            label: const Text('Tour'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (showAlerts) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Alert Centre',
              onPressed: onAlerts,
              icon: const Badge(
                smallSize: 7,
                child: Icon(Icons.notifications_none_rounded),
              ),
            ),
          ],
          const SizedBox(width: 4),
          Tooltip(
            message: '${roleLabel(session.role!)} • ${session.scope.label}',
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: TgcgColors.primarySoft, borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.person_outline_rounded, color: TgcgColors.primary, size: 19),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSync extends StatelessWidget {
  const _CompactSync();

  @override
  Widget build(BuildContext context) {
    final pending = OfflinePersistence.of(context).pendingOutbox.length;
    return TgcgStatusPill(
      label: pending == 0 ? 'SYNCED' : '$pending QUEUED',
      color: pending == 0 ? TgcgColors.success : TgcgColors.warning,
      icon: pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
      compact: true,
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
        children: [
          TgcgLogo(size: 39),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TGCG-EMCOP',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, letterSpacing: .7, fontSize: 14),
                ),
                SizedBox(height: 2),
                Text('National Operations', style: TextStyle(color: Color(0xFF8EA49D), fontSize: 9.5)),
              ],
            ),
          ),
        ],
      );
}

class _CompactBrand extends StatelessWidget {
  const _CompactBrand();

  @override
  Widget build(BuildContext context) => const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TgcgLogo(size: 36),
          SizedBox(width: 8),
          Text('TGCG-EMCOP', style: TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink)),
        ],
      );
}

String _groupLabel(_NavGroup group) => switch (group) {
      _NavGroup.command => 'COMMAND',
      _NavGroup.fieldOperations => 'FIELD OPERATIONS',
      _NavGroup.coordination => 'COORDINATION',
      _NavGroup.control => 'CONTROL',
    };

String _moduleLabel(TgcgModule module) => switch (module) {
      TgcgModule.overview => 'Command Overview',
      TgcgModule.accreditation => 'Member Enrolment',
      TgcgModule.membershipNetwork => 'Registered Members',
      TgcgModule.roleAssignment => 'Role Assignment',
      TgcgModule.geography => 'Geographic Operations',
      TgcgModule.liveOperations => 'Live Operations',
      TgcgModule.aiVerification => 'AI Verification Centre',
      TgcgModule.aiAnalytics => 'AI Data Analytics Centre',
      TgcgModule.alertCenter => 'Alert Centre',
      TgcgModule.fieldMonitoring => 'Field Monitoring',
      TgcgModule.evidenceCapture => 'Evidence Capture',
      TgcgModule.situationRoom => 'Situation Room',
      TgcgModule.securityResponse => 'Security & Emergency Response',
      TgcgModule.resultCapture => 'Result Capture',
      TgcgModule.collation => 'Collation',
      TgcgModule.mediaIntelligence => 'Media Intelligence',
      TgcgModule.communications => 'Communications',
      TgcgModule.bulkCommunications => 'Bulk Communications Centre',
      TgcgModule.discussionRoom => 'Discussion Forum',
      TgcgModule.meetingRoom => 'Meeting Room',
      TgcgModule.systemMonitoring => 'System Monitoring',
      TgcgModule.reports => 'Reports & Exports',
      TgcgModule.governance => 'Data & Governance',
    };
