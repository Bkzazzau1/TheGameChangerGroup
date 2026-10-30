import 'package:flutter/material.dart';

import 'access/access_page.dart';
import 'access/my_access_page.dart';
import 'account/change_pin_dialog.dart';
import 'ai/ai_verification_page.dart';
import 'alerts/alert_center_page.dart';
import 'analytics/ai_data_analytics_page.dart';
import 'collation/collation_page.dart';
import 'communications/bulk_communications_page.dart';
import 'communications/communications_page.dart';
import 'dashboard_page.dart';
import 'askme/ask_me_hub_page.dart';
import 'discussion/discussion_room_page.dart';
import 'evidence/evidence_capture_page.dart';
import 'field/field_monitoring_page.dart';
import 'field/situation_room_page.dart';
import 'geography/geography_page.dart';
import 'governance/governance_page.dart';
import 'media/media_intelligence_page.dart';
import 'meeting/meeting_room_page.dart';
import 'member/member_shell.dart';
import 'membership/member_review_page.dart';
import 'membership/member_search.dart';
import 'membership/members_exco_page.dart';
import 'membership/pvc_enrollment_page.dart';
import 'monitoring/system_monitoring_page.dart';
import 'offline/offline_persistence.dart';
import 'operations/live_operations_page.dart';
import 'reports/reports_page.dart';
import 'results/result_capture_page.dart';
import 'security/security_officer_page.dart';
import 'session.dart';
import 'mapping/unit_mapping_page.dart';
import 'member/registered_members_page.dart';
import 'messaging/inbox_page.dart';
import 'messaging/messages_page.dart';
import 'tracking/agents_on_ground_page.dart';
import 'ui/demo_data_notice.dart';
import 'projects/project_mode.dart';
import 'projects/projects_page.dart';
import 'ui/tgcg_design.dart';
import 'wallets/wallet_payments_page.dart';

class TgcgShell extends StatefulWidget {
  const TgcgShell({super.key});

  @override
  State<TgcgShell> createState() => _TgcgShellState();
}

class _TgcgShellState extends State<TgcgShell> {
  TgcgModule selectedModule = TgcgModule.overview;

  /// Whether the person has opened a page themselves.
  bool _chosen = false;

  void _select(TgcgModule module) => setState(() {
        selectedModule = module;
        _chosen = true;
      });

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final allowed = session.modules;
    // While a project runs, the app opens on it.
    final mode = ProjectMode.of(context);
    if (!_chosen &&
        mode != null &&
        mode.running.isNotEmpty &&
        allowed.contains(TgcgModule.projects)) {
      selectedModule = TgcgModule.projects;
    }
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
              : TgcgBrandBar(
                  // Beside these buttons a phone has room for less of the name.
                  title: constraints.maxWidth < 350
                      ? ''
                      : (constraints.maxWidth < 420 ? 'TGCG' : 'TGCG-EMCOP'),
                  actions: [
                    _CompactSync(iconOnly: constraints.maxWidth < 430),
                    // Five buttons share a narrow phone's bar with the name.
                    Theme(
                      data: Theme.of(context).copyWith(visualDensity: VisualDensity.compact),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const MemberSearchButton(),
                          const InboxButton(),
                          const RegisterMembersButton(),
                          if (allowed.contains(TgcgModule.alertCenter))
                            IconButton(
                              tooltip: 'Alert Centre',
                              onPressed: () => _select(TgcgModule.alertCenter),
                              icon: const Badge(
                                smallSize: 7,
                                child: Icon(Icons.notifications_none_rounded),
                              ),
                            ),
                        ],
                      ),
                    ),
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
                          ),
                          const ProjectStrip(),
                          Expanded(child: ProjectGpsGate(child: _pageFor(selectedModule))),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  children: [
                    const ProjectStrip(),
                    Expanded(child: ProjectGpsGate(child: _pageFor(selectedModule))),
                  ],
                ),
        );
      },
    );
  }

  Widget _pageFor(TgcgModule module) => TgcgDemoDataPage(
        module: module,
        child: _contentFor(module),
      );

  Widget _contentFor(TgcgModule module) => switch (module) {
        TgcgModule.overview => TgcgDashboardPage(onOpenModule: _select),
        TgcgModule.accreditation => const PvcEnrollmentPage(),
        TgcgModule.membershipNetwork => const MembersExcoPage(),
        TgcgModule.roleAssignment => const AccessControlPage(),
        TgcgModule.memberReview => const MemberReviewPage(),
        TgcgModule.geography => const GeographyPage(),
        TgcgModule.liveOperations => const LiveOperationsPage(),
        TgcgModule.aiVerification => const AiVerificationPage(),
        TgcgModule.aiAnalytics => const AiDataAnalyticsPage(),
        TgcgModule.alertCenter => const AlertCenterPage(),
        TgcgModule.fieldMonitoring => const FieldMonitoringPage(),
        TgcgModule.evidenceCapture => const EvidenceCapturePage(),
        TgcgModule.situationRoom => const SituationRoomPage(),
        TgcgModule.securityResponse => const SecurityOfficerPage(),
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
        TgcgModule.unitMapping => const UnitMappingPage(),
        TgcgModule.agentTracking => const AgentsOnGroundPage(),
        TgcgModule.wallets => const WalletPaymentsPage(),
        TgcgModule.projects => const ProjectsPage(),
        TgcgModule.messages => const MessagesPage(),
        TgcgModule.askMe => const AskMeHubPage(),
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
  _Destination(TgcgModule.membershipNetwork, 'Members & Exco', Icons.groups_2_outlined, _NavGroup.command),
  _Destination(TgcgModule.projects, 'Projects', Icons.flag_outlined, _NavGroup.command),
  _Destination(TgcgModule.situationRoom, 'Situation Room', Icons.radar_rounded, _NavGroup.command),
  _Destination(TgcgModule.agentTracking, 'Agents on the Ground', Icons.share_location_rounded, _NavGroup.command),
  _Destination(TgcgModule.securityResponse, 'Security Response', Icons.emergency_share_outlined, _NavGroup.command),
  _Destination(TgcgModule.mediaIntelligence, 'Media Intelligence', Icons.insights_outlined, _NavGroup.command),
  _Destination(TgcgModule.geography, 'Geographic Operations', Icons.public_rounded, _NavGroup.command),
  _Destination(TgcgModule.accreditation, 'Member Enrolment', Icons.how_to_reg_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.unitMapping, 'Polling Unit Mapping', Icons.add_location_alt_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.aiVerification, 'AI Verification', Icons.auto_awesome_rounded, _NavGroup.fieldOperations),
  _Destination(TgcgModule.fieldMonitoring, 'Field Monitoring', Icons.sensors_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.evidenceCapture, 'Evidence Capture', Icons.perm_media_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.resultCapture, 'Result Capture', Icons.ballot_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.collation, 'Collation', Icons.account_tree_outlined, _NavGroup.fieldOperations),
  _Destination(TgcgModule.communications, 'Communications', Icons.forum_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.bulkCommunications, 'Bulk Communications', Icons.send_to_mobile_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.messages, 'Messages', Icons.campaign_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.discussionRoom, 'Social Forum', Icons.dynamic_feed_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.askMe, 'Ask Me', Icons.record_voice_over_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.meetingRoom, 'Meeting Room', Icons.video_camera_front_outlined, _NavGroup.coordination),
  _Destination(TgcgModule.roleAssignment, 'Roles & Access', Icons.manage_accounts_outlined, _NavGroup.control),
  _Destination(TgcgModule.memberReview, 'Member Review', Icons.verified_user_outlined, _NavGroup.control),
  _Destination(TgcgModule.wallets, 'Wallets', Icons.account_balance_wallet_outlined, _NavGroup.control),
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
              padding: EdgeInsets.fromLTRB(18, 18, 18, 10),
              child: _Brand(),
            ),
            Divider(height: 1, color: Colors.white.withValues(alpha: .1)),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
                children: [
                  for (final group in _NavGroup.values)
                    if (destinations.any((item) => item.group == group)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(11, 16, 11, 7),
                        child: Text(
                          _groupLabel(group),
                          style: TgcgType.eyebrow.copyWith(color: TgcgColors.onNavyMuted),
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
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: active ? Colors.white.withValues(alpha: .1) : Colors.transparent,
          borderRadius: BorderRadius.circular(TgcgRadius.sm),
          child: InkWell(
            borderRadius: BorderRadius.circular(TgcgRadius.sm),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Row(
                  children: [
                    Icon(
                      item.icon,
                      size: 20,
                      color: active ? TgcgColors.accentBright : TgcgColors.onNavyMuted,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: active ? Colors.white : TgcgColors.onNavyMuted,
                          fontSize: 13.5,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        ),
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

class _OperatorCard extends StatelessWidget {
  const _OperatorCard({required this.session});
  final TgcgSessionController session;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 4, 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const TgcgIconBadge(
                  icon: Icons.person_outline_rounded,
                  color: TgcgColors.accentBright,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.operatorName.isEmpty ? 'TGCG Operator' : session.operatorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TgcgType.label.copyWith(color: Colors.white),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        session.roleTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TgcgType.caption.copyWith(color: TgcgColors.onNavyMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, color: TgcgColors.onNavyMuted, size: 15),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    session.scope.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TgcgType.caption.copyWith(color: TgcgColors.onNavyMuted),
                  ),
                ),
                if (session.isServerSession)
                  // One menu, so the name keeps its room in a phone's drawer.
                  PopupMenuButton<VoidCallback>(
                    tooltip: 'Account',
                    icon: const Icon(
                      Icons.more_vert_rounded,
                      color: TgcgColors.onNavyMuted,
                      size: 19,
                    ),
                    onSelected: (open) => open(),
                    itemBuilder: (_) => [
                      if (session.membershipNumber != null)
                        PopupMenuItem(
                          value: () => openMyMembership(context),
                          child: const Text('My membership'),
                        ),
                      PopupMenuItem(
                        value: () => openMyAccess(context),
                        child: const Text('My access'),
                      ),
                      PopupMenuItem(
                        value: () => showChangePin(context),
                        child: Text(
                          session.isMember || session.role == null
                              ? 'Change PIN'
                              : 'Change password',
                        ),
                      ),
                    ],
                  ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: session.signOut,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.logout_rounded, color: TgcgColors.onNavyMuted, size: 19),
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
  });

  final TgcgModule selectedModule;
  final bool showAlerts;
  final VoidCallback onAlerts;

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
          Text(_moduleLabel(selectedModule), style: TgcgType.section),
          const Spacer(),
          TgcgStatusPill(
            label: pending == 0 ? 'SYNCED' : '$pending TO SYNC',
            color: pending == 0 ? TgcgColors.success : TgcgColors.warning,
            icon: pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
            compact: true,
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
          if (session.isServerSession)
            ...const [MemberSearchButton(wide: true), InboxButton(), RegisterMembersButton()],
          const SizedBox(width: 4),
          Tooltip(
            message: '${session.roleTitle} • ${session.scope.label}',
            child: InkWell(
              borderRadius: BorderRadius.circular(TgcgRadius.sm),
              onTap: session.isServerSession ? () => openMyAccess(context) : null,
              child: const TgcgIconBadge(icon: Icons.person_outline_rounded, size: 36),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSync extends StatelessWidget {
  const _CompactSync({this.iconOnly = false});

  final bool iconOnly;

  @override
  Widget build(BuildContext context) {
    final pending = OfflinePersistence.of(context).pendingOutbox.length;
    final label = pending == 0 ? 'SYNCED' : '$pending QUEUED';
    final color = pending == 0 ? TgcgColors.success : TgcgColors.warning;
    final icon = pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined;
    if (iconOnly) {
      return Tooltip(
        message: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Badge.count(
            count: pending,
            isLabelVisible: pending > 0,
            child: Icon(icon, color: color, size: 20, semanticLabel: label),
          ),
        ),
      );
    }
    return TgcgStatusPill(label: label, color: color, icon: icon, compact: true);
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
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 1),
                Text(
                  'National Operations',
                  style: TextStyle(color: TgcgColors.onNavyMuted, fontSize: 12),
                ),
              ],
            ),
          ),
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
      TgcgModule.membershipNetwork => 'Members & Exco',
      TgcgModule.roleAssignment => 'Roles & Access',
      TgcgModule.memberReview => 'Member Review',
      TgcgModule.geography => 'Geographic Operations',
      TgcgModule.liveOperations => 'Live Operations',
      TgcgModule.aiVerification => 'AI Verification Centre',
      TgcgModule.aiAnalytics => 'AI Data Analytics Centre',
      TgcgModule.alertCenter => 'Alert Centre',
      TgcgModule.fieldMonitoring => 'Field Monitoring',
      TgcgModule.evidenceCapture => 'Evidence Capture',
      TgcgModule.situationRoom => 'Situation Room',
      TgcgModule.securityResponse => 'Security Response',
      TgcgModule.resultCapture => 'Result Capture',
      TgcgModule.collation => 'Collation',
      TgcgModule.mediaIntelligence => 'Media Intelligence',
      TgcgModule.communications => 'Communications',
      TgcgModule.bulkCommunications => 'Bulk Communications Centre',
      TgcgModule.discussionRoom => 'Social Forum',
      TgcgModule.meetingRoom => 'Meeting Room',
      TgcgModule.systemMonitoring => 'System Monitoring',
      TgcgModule.reports => 'Reports & Exports',
      TgcgModule.governance => 'Data & Governance',
      TgcgModule.unitMapping => 'Polling Unit Mapping',
      TgcgModule.agentTracking => 'Agents on the Ground',
      TgcgModule.wallets => 'Wallets',
      TgcgModule.projects => 'Projects',
      TgcgModule.messages => 'Messages',
      TgcgModule.askMe => 'Ask Me',
    };


/// Where the signed-in user's access comes from, and their own appointments.
void openMyAccess(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _WhileOperator(
          child: Scaffold(
            backgroundColor: TgcgColors.canvas,
            appBar: _MyAccessBar(),
            body: MyAccessPage(showHeader: false),
          ),
        ),
      ),
    );

/// A member who holds appointments keeps their card, polling unit, news and
/// volunteering.
void openMyMembership(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const _WhileOperator(child: MemberShell())),
    );

class _MyAccessBar extends StatelessWidget implements PreferredSizeWidget {
  const _MyAccessBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) => AppBar(title: const Text('My access'));
}

/// Closes a page opened from the operations app once the account no longer
/// uses it (for example after resigning the last appointment).
class _WhileOperator extends StatelessWidget {
  const _WhileOperator({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!TgcgSession.of(context).isOperator) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.of(context).maybePop();
      });
    }
    return child;
  }
}
