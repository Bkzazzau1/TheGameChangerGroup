import 'package:flutter/material.dart';

import '../communications/communications_store.dart';
import '../domain/models.dart';
import '../membership/membership_store.dart';
import '../offline/offline_persistence.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';

class FieldAgentDashboardPage extends StatelessWidget {
  const FieldAgentDashboardPage({
    super.key,
    required this.onOpenModule,
  });

  final ValueChanged<TgcgModule> onOpenModule;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final communications = Communications.of(context);
    final offline = OfflinePersistence.of(context);

    final agent = _resolveAgent(membership, session.accessId);
    if (agent == null) return const SizedBox.shrink();

    final member = membership.memberById(agent.memberId);
    final incidents = field
        .incidentsForScope(agent.scope)
        .where((item) => item.reporterId == agent.agentId)
        .toList(growable: false)
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final reports = field
        .reportsForScope(agent.scope)
        .where((item) => item.reporterId == agent.agentId)
        .toList(growable: false)
      ..sort((a, b) => b.reportedAt.compareTo(a.reportedAt));
    final submissions = results
        .submissionsForScope(agent.scope)
        .where((item) => item.submittedBy == agent.agentId)
        .toList(growable: false)
      ..sort((a, b) => b.submittedAt.compareTo(a.submittedAt));

    final linkedIds = <String>{agent.agentId};
    linkedIds.addAll(incidents.map((item) => item.id));
    linkedIds.addAll(reports.map((item) => item.id));
    linkedIds.addAll(submissions.map((item) => item.id));
    final pendingSync = offline.pendingOutbox
        .where((item) => linkedIds.contains(item.entityId))
        .length;

    final localRooms = communications.localRoomsForFieldAgent(agent.scope);
    final localMessages = localRooms.fold<int>(
      0,
      (count, room) => count + communications.messagesForRoom(room.id).length,
    );

    final checkedIn = reports.any((item) => item.category == 'Agent check-in');
    final ready = agent.status == AccreditationStatus.approved &&
        agent.trainingCompleted &&
        agent.biometricEnrolled &&
        (agent.deviceId ?? '').isNotEmpty &&
        (agent.simFingerprint ?? '').isNotEmpty;

    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              _Hero(
                name: member?.fullName ?? session.operatorName,
                agent: agent,
                ready: ready,
                checkedIn: checkedIn,
                pendingSync: pendingSync,
              ),
              const SizedBox(height: 14),
              _AssignmentStrip(agent: agent),
              const SizedBox(height: 16),
              _SectionTitle(
                title: 'Quick Actions',
                subtitle: 'Everything needed for polling-unit duty.',
              ),
              const SizedBox(height: 10),
              _ActionGrid(
                checkedIn: checkedIn,
                onCheckIn: checkedIn
                    ? null
                    : () => _checkIn(context, field, agent),
                onIncident: () => onOpenModule(TgcgModule.fieldMonitoring),
                onEvidence: () => onOpenModule(TgcgModule.evidenceCapture),
                onResult: () => onOpenModule(TgcgModule.resultCapture),
                onMessages: () => onOpenModule(TgcgModule.communications),
                onMeeting: () => onOpenModule(TgcgModule.meetingRoom),
              ),
              const SizedBox(height: 18),
              _SectionTitle(
                title: 'Today at a glance',
                subtitle: 'Your activity from this polling-unit assignment.',
              ),
              const SizedBox(height: 10),
              _Metrics(
                incidents: incidents.length,
                reports: reports.length,
                results: submissions.length,
                messages: localMessages,
                pendingSync: pendingSync,
              ),
              const SizedBox(height: 18),
              _LocalCoordinationCard(
                agent: agent,
                rooms: localRooms.length,
                messages: localMessages,
                onMessages: () => onOpenModule(TgcgModule.communications),
                onMeeting: () => onOpenModule(TgcgModule.meetingRoom),
              ),
              const SizedBox(height: 18),
              _RecentActivity(
                incidents: incidents,
                reports: reports,
                submissions: submissions,
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Future<void> _checkIn(
    BuildContext context,
    FieldOperationsController field,
    AccreditedAgent agent,
  ) async {
    try {
      await field.submitFieldReport(
        category: 'Agent check-in',
        summary: 'Agent checked in for field duty.',
        scope: agent.scope,
        reporterId: agent.agentId,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Check-in completed.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to complete check-in.')),
      );
    }
  }
}

class _Hero extends StatelessWidget {
  const _Hero({
    required this.name,
    required this.agent,
    required this.ready,
    required this.checkedIn,
    required this.pendingSync,
  });

  final String name;
  final AccreditedAgent agent;
  final bool ready;
  final bool checkedIn;
  final int pendingSync;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [TgcgColors.primaryDark, TgcgColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: TgcgColors.primary.withValues(alpha: .14),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: Colors.white.withValues(alpha: .14)),
                  ),
                  child: const Center(child: TgcgLogo(size: 42)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${agent.agentId} • Polling Unit Agent',
                        style: const TextStyle(
                          color: Color(0xFFC8D7D2),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: checkedIn
                        ? TgcgColors.success.withValues(alpha: .18)
                        : Colors.white.withValues(alpha: .11),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: .14)),
                  ),
                  child: Text(
                    checkedIn
                        ? 'ON DUTY'
                        : ready
                            ? 'READY'
                            : 'CHECK STATUS',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Election Day Workspace',
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w900,
                height: 1.08,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              '${agent.scope.pollingUnitName ?? 'Polling Unit'} • ${agent.scope.wardName ?? ''} • ${agent.scope.lgaName ?? ''}',
              style: const TextStyle(
                color: Color(0xFFC6D6D0),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    icon: Icons.verified_user_outlined,
                    label: 'Accreditation',
                    value: agent.status == AccreditationStatus.approved
                        ? 'Approved'
                        : 'Pending',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeroStat(
                    icon: Icons.cloud_sync_outlined,
                    label: 'Sync',
                    value: pendingSync == 0 ? 'Up to date' : '$pendingSync pending',
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                        color: Color(0xFFBDD0CA),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 2),
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                      )),
                ],
              ),
            ),
          ],
        ),
      );
}

class _AssignmentStrip extends StatelessWidget {
  const _AssignmentStrip({required this.agent});

  final AccreditedAgent agent;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: TgcgColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: TgcgColors.primarySoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.location_on_outlined,
                  color: TgcgColors.primary, size: 20),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.scope.pollingUnitName ?? agent.scope.label,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${agent.scope.wardName ?? 'Ward'} • ${agent.scope.lgaName ?? 'LGA'} • ${agent.scope.stateName ?? 'State'}',
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            TgcgStatusPill(
              label: agent.scope.pollingUnitId ?? 'PU',
              color: TgcgColors.primary,
              compact: true,
            ),
          ],
        ),
      );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: const TextStyle(
              color: TgcgColors.muted,
              fontSize: 10,
            ),
          ),
        ],
      );
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.checkedIn,
    required this.onCheckIn,
    required this.onIncident,
    required this.onEvidence,
    required this.onResult,
    required this.onMessages,
    required this.onMeeting,
  });

  final bool checkedIn;
  final VoidCallback? onCheckIn;
  final VoidCallback onIncident;
  final VoidCallback onEvidence;
  final VoidCallback onResult;
  final VoidCallback onMessages;
  final VoidCallback onMeeting;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 720 ? 3 : 2;
          const gap = 10.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              _ActionTile(
                width: width,
                label: checkedIn ? 'Checked In' : 'Check In',
                detail: checkedIn ? 'Duty active' : 'Start field duty',
                icon: Icons.how_to_reg_rounded,
                tone: TgcgColors.success,
                onTap: onCheckIn,
              ),
              _ActionTile(
                width: width,
                label: 'Report Incident',
                detail: 'Send an incident update',
                icon: Icons.warning_amber_rounded,
                tone: TgcgColors.danger,
                onTap: onIncident,
              ),
              _ActionTile(
                width: width,
                label: 'Capture Evidence',
                detail: 'Photo, video or audio',
                icon: Icons.photo_camera_outlined,
                tone: TgcgColors.info,
                onTap: onEvidence,
              ),
              _ActionTile(
                width: width,
                label: 'Submit Result',
                detail: 'Capture polling-unit result',
                icon: Icons.ballot_outlined,
                tone: TgcgColors.primary,
                onTap: onResult,
              ),
              _ActionTile(
                width: width,
                label: 'Local Messages',
                detail: 'Ward and LGA team only',
                icon: Icons.chat_bubble_outline_rounded,
                tone: TgcgColors.accent,
                onTap: onMessages,
              ),
              _ActionTile(
                width: width,
                label: 'Meeting Room',
                detail: 'Call your local team',
                icon: Icons.video_call_outlined,
                tone: TgcgColors.primary,
                onTap: onMeeting,
              ),
            ],
          );
        },
      );
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.width,
    required this.label,
    required this.detail,
    required this.icon,
    required this.tone,
    required this.onTap,
  });

  final double width;
  final String label;
  final String detail;
  final IconData icon;
  final Color tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: 122,
        child: Material(
          color: TgcgColors.surface,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: TgcgColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: tone, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 8.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.incidents,
    required this.reports,
    required this.results,
    required this.messages,
    required this.pendingSync,
  });

  final int incidents;
  final int reports;
  final int results;
  final int messages;
  final int pendingSync;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Incidents',
                value: '$incidents',
                detail: 'Reported by you',
                icon: Icons.warning_amber_rounded,
                tone: incidents > 0 ? TgcgMetricTone.warning : TgcgMetricTone.neutral,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Field updates',
                value: '$reports',
                detail: 'Submitted today',
                icon: Icons.fact_check_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Results',
                value: '$results',
                detail: 'Polling-unit submissions',
                icon: Icons.ballot_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Local messages',
                value: '$messages',
                detail: pendingSync == 0 ? 'Records up to date' : '$pendingSync awaiting sync',
                icon: Icons.forum_outlined,
                tone: pendingSync == 0 ? TgcgMetricTone.neutral : TgcgMetricTone.warning,
              ),
            ],
          );
        },
      );
}

class _LocalCoordinationCard extends StatelessWidget {
  const _LocalCoordinationCard({
    required this.agent,
    required this.rooms,
    required this.messages,
    required this.onMessages,
    required this.onMeeting,
  });

  final AccreditedAgent agent;
  final int rooms;
  final int messages;
  final VoidCallback onMessages;
  final VoidCallback onMeeting;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Local Coordination',
        subtitle:
            '${agent.scope.wardName ?? 'Ward'} • ${agent.scope.lgaName ?? 'LGA'}',
        trailing: TgcgStatusPill(
          label: '$rooms ROOMS',
          color: TgcgColors.primary,
          compact: true,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _CoordinationButton(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Messages',
                    subtitle: '$messages local messages',
                    onTap: onMessages,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CoordinationButton(
                    icon: Icons.video_call_outlined,
                    title: 'Meeting',
                    subtitle: 'Call local team',
                    onTap: onMeeting,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
}

class _CoordinationButton extends StatelessWidget {
  const _CoordinationButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Icon(icon, color: TgcgColors.primary, size: 21),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                            color: TgcgColors.ink,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w900,
                          )),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TgcgColors.muted,
                            fontSize: 8.8,
                          )),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({
    required this.incidents,
    required this.reports,
    required this.submissions,
  });

  final List<FieldIncident> incidents;
  final List<FieldReport> reports;
  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (incidents.isNotEmpty) {
      rows.add(_ActivityRow(
        icon: Icons.warning_amber_rounded,
        title: incidents.first.category,
        subtitle: 'Incident • ${_time(incidents.first.reportedAt)}',
        color: TgcgColors.danger,
      ));
    }
    if (reports.isNotEmpty) {
      rows.add(_ActivityRow(
        icon: Icons.fact_check_outlined,
        title: reports.first.category,
        subtitle: 'Field update • ${_time(reports.first.reportedAt)}',
        color: TgcgColors.info,
      ));
    }
    if (submissions.isNotEmpty) {
      rows.add(_ActivityRow(
        icon: Icons.ballot_outlined,
        title: 'Polling-unit result',
        subtitle: 'Result • ${_time(submissions.first.submittedAt)}',
        color: TgcgColors.success,
      ));
    }

    return TgcgSectionCard(
      title: 'Recent Activity',
      child: rows.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.history_rounded,
              title: 'No activity yet',
              message: 'Your latest field actions will appear here.',
            )
          : Column(children: rows),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, color: color, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w900,
                      )),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 9,
                      )),
                ],
              ),
            ),
          ],
        ),
      );
}

AccreditedAgent? _resolveAgent(
  MembershipOperationsController membership,
  String accessId,
) {
  final normalized = accessId.trim().toLowerCase();
  for (final agent in membership.agents) {
    if (agent.role != TgcgRole.pollingUnitAgent) continue;
    if (agent.agentId.toLowerCase() == normalized ||
        (agent.registeredPhoneNumber ?? '').trim().toLowerCase() == normalized) {
      return agent;
    }
  }
  return null;
}

String _time(DateTime value) {
  final local = value.toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
