import 'package:flutter/material.dart';

import '../communications/communications_store.dart';
import '../governance/governance_store.dart';
import '../membership/membership_store.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'field_operations_store.dart';

class FieldAgentHomePage extends StatelessWidget {
  const FieldAgentHomePage({
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
    final governance = GovernanceOperations.of(context);

    final agent = _resolveAgent(membership, session);
    if (agent == null) return _UnresolvedAssignment(session: session);

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

    final rooms = communications.roomsForScope(agent.scope);
    final messageCount = rooms.fold<int>(
      0,
      (total, room) => total + communications.messagesForRoom(room.id).length,
    );

    final ownedEntityIds = <String>{agent.agentId};
    for (final incident in incidents) {
      ownedEntityIds.add(incident.id);
      ownedEntityIds.addAll(incident.evidence.map((item) => item.id));
    }
    for (final report in reports) {
      ownedEntityIds.add(report.id);
      ownedEntityIds.addAll(report.evidence.map((item) => item.id));
    }
    for (final submission in submissions) {
      ownedEntityIds.add(submission.id);
      final form = submission.resultForm;
      if (form != null) ownedEntityIds.add(form.id);
    }
    final ownPendingSync = governance.pendingOutbox
        .where((item) => ownedEntityIds.contains(item.entityId))
        .length;

    final approved = agent.status == AccreditationStatus.approved;
    final deviceBound = (agent.deviceId ?? '').trim().isNotEmpty;
    final simBound = (agent.simFingerprint ?? '').trim().isNotEmpty;
    final identityReady = approved &&
        agent.trainingCompleted &&
        agent.biometricEnrolled &&
        deviceBound &&
        simBound;
    final checkedIn = reports.any((item) => item.category == 'Agent check-in');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _DutyHeader(
          agent: agent,
          operatorName: member?.fullName ?? session.operatorName,
          identityReady: identityReady,
          checkedIn: checkedIn,
        ),
        const SizedBox(height: 14),
        _ReadinessCard(
          approved: approved,
          training: agent.trainingCompleted,
          biometric: agent.biometricEnrolled,
          device: deviceBound,
          sim: simBound,
          checkedIn: checkedIn,
        ),
        const SizedBox(height: 14),
        _PollingUnitCard(agent: agent),
        const SizedBox(height: 16),
        const Text(
          'ELECTION DAY ACTIONS',
          style: TextStyle(
            color: TgcgColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.05,
          ),
        ),
        const SizedBox(height: 9),
        _ActionGrid(
          checkedIn: checkedIn,
          messageCount: messageCount,
          pendingSync: ownPendingSync,
          onCheckIn: checkedIn ? null : () => _checkIn(context, agent, field),
          onIncident: () => onOpenModule(TgcgModule.fieldMonitoring),
          onFieldUpdate: () => onOpenModule(TgcgModule.fieldMonitoring),
          onResult: () => onOpenModule(TgcgModule.resultCapture),
          onMessages: () => onOpenModule(TgcgModule.communications),
          onSync: () => _showSyncState(context, ownPendingSync),
        ),
        const SizedBox(height: 16),
        _ActivityCard(
          incidents: incidents,
          reports: reports,
          submissions: submissions,
        ),
        const SizedBox(height: 14),
        _SyncBanner(pending: ownPendingSync),
      ],
    );
  }

  void _checkIn(
    BuildContext context,
    AccreditedAgent agent,
    FieldOperationsController field,
  ) {
    final report = field.submitFieldReport(
      category: 'Agent check-in',
      summary:
          'Agent checked in from the assigned application session. GPS capture is not yet connected to the native location service.',
      scope: agent.scope,
      reporterId: agent.agentId,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${report.id} saved locally. GPS/geofence verification remains pending integration.',
        ),
      ),
    );
  }

  void _showSyncState(BuildContext context, int pending) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'My Sync Status',
                style: TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                pending == 0
                    ? 'No pending prototype outbox item can currently be linked to this agent.'
                    : '$pending local mutation${pending == 1 ? '' : 's'} linked to your records still require server acknowledgement.',
                style: const TextStyle(color: TgcgColors.muted, height: 1.45),
              ),
              const SizedBox(height: 12),
              const Text(
                'Queued does not mean synced. Durable encrypted SQLite and the device sync worker are the next data-layer integration.',
                style: TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DutyHeader extends StatelessWidget {
  const _DutyHeader({
    required this.agent,
    required this.operatorName,
    required this.identityReady,
    required this.checkedIn,
  });

  final AccreditedAgent agent;
  final String operatorName;
  final bool identityReady;
  final bool checkedIn;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [TgcgColors.primaryDark, TgcgColors.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const TgcgLogo(size: 42),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        operatorName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        agent.agentId,
                        style: const TextStyle(
                          color: Color(0xFFBDD0CA),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                TgcgStatusPill(
                  label: checkedIn
                      ? 'CHECKED IN'
                      : identityReady
                          ? 'READY'
                          : 'ACTION NEEDED',
                  color: checkedIn
                      ? TgcgColors.success
                      : identityReady
                          ? TgcgColors.accent
                          : TgcgColors.warning,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              checkedIn
                  ? 'You are checked in for field duty.'
                  : identityReady
                      ? 'Identity and device readiness checks are complete.'
                      : 'Complete the outstanding readiness items before field duty.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                height: 1.2,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            const Text(
              'Location/geofence confirmation is separate and will activate when the native GPS service is connected.',
              style: TextStyle(
                color: Color(0xFFB8CAC4),
                fontSize: 10.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      );
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard({
    required this.approved,
    required this.training,
    required this.biometric,
    required this.device,
    required this.sim,
    required this.checkedIn,
  });

  final bool approved;
  final bool training;
  final bool biometric;
  final bool device;
  final bool sim;
  final bool checkedIn;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Duty readiness',
        subtitle: 'Operational readiness is separate from live location verification.',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ReadinessChip('Accreditation', approved),
            _ReadinessChip('Training', training),
            _ReadinessChip('Identity', biometric),
            _ReadinessChip('Device', device),
            _ReadinessChip('SIM', sim),
            _ReadinessChip('Check-in', checkedIn),
            const _ReadinessChip('Location', false, pending: true),
          ],
        ),
      );
}

class _ReadinessChip extends StatelessWidget {
  const _ReadinessChip(this.label, this.ready, {this.pending = false});

  final String label;
  final bool ready;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final color = pending
        ? TgcgColors.warning
        : ready
            ? TgcgColors.success
            : TgcgColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .075),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            pending
                ? Icons.schedule_rounded
                : ready
                    ? Icons.check_circle_rounded
                    : Icons.cancel_outlined,
            color: color,
            size: 15,
          ),
          const SizedBox(width: 5),
          Text(
            pending ? '$label pending' : label,
            style: TextStyle(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _PollingUnitCard extends StatelessWidget {
  const _PollingUnitCard({required this.agent});

  final AccreditedAgent agent;

  @override
  Widget build(BuildContext context) {
    final scope = agent.scope;
    return TgcgSectionCard(
      title: 'My Polling Unit',
      subtitle: 'Authenticated geographic assignment for field operations.',
      trailing: TgcgStatusPill(
        label: scope.pollingUnitId ?? 'ASSIGNMENT',
        color: TgcgColors.primary,
        icon: Icons.location_on_outlined,
        compact: true,
      ),
      child: Column(
        children: [
          _Detail('Polling unit', scope.pollingUnitName ?? scope.label),
          _Detail('Ward', scope.wardName ?? '—'),
          _Detail('LGA', scope.lgaName ?? '—'),
          _Detail('State', scope.stateName ?? '—'),
          const _Detail('GPS / geofence', 'Pending native integration'),
        ],
      ),
    );
  }
}

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.checkedIn,
    required this.messageCount,
    required this.pendingSync,
    required this.onCheckIn,
    required this.onIncident,
    required this.onFieldUpdate,
    required this.onResult,
    required this.onMessages,
    required this.onSync,
  });

  final bool checkedIn;
  final int messageCount;
  final int pendingSync;
  final VoidCallback? onCheckIn;
  final VoidCallback onIncident;
  final VoidCallback onFieldUpdate;
  final VoidCallback onResult;
  final VoidCallback onMessages;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionCard(
                width: width,
                label: checkedIn ? 'CHECKED IN' : 'CHECK IN',
                detail: checkedIn ? 'Duty check-in saved' : 'Start field duty',
                icon: Icons.how_to_reg_rounded,
                color: TgcgColors.success,
                onTap: onCheckIn,
              ),
              _ActionCard(
                width: width,
                label: 'REPORT INCIDENT',
                detail: 'Safety, process or technical issue',
                icon: Icons.report_problem_outlined,
                color: TgcgColors.danger,
                onTap: onIncident,
              ),
              _ActionCard(
                width: width,
                label: 'FIELD UPDATE',
                detail: 'Submit structured operational report',
                icon: Icons.post_add_rounded,
                color: TgcgColors.info,
                onTap: onFieldUpdate,
              ),
              _ActionCard(
                width: width,
                label: 'CAPTURE RESULT',
                detail: 'Evidence, figures and validation',
                icon: Icons.document_scanner_outlined,
                color: TgcgColors.primary,
                onTap: onResult,
              ),
              _ActionCard(
                width: width,
                label: 'MESSAGES',
                detail: '$messageCount scoped messages',
                icon: Icons.forum_outlined,
                color: TgcgColors.ai,
                onTap: onMessages,
              ),
              _ActionCard(
                width: width,
                label: 'SYNC STATUS',
                detail: pendingSync == 0
                    ? 'No linked pending item'
                    : '$pendingSync awaiting acknowledgement',
                icon: pendingSync == 0
                    ? Icons.cloud_done_outlined
                    : Icons.cloud_upload_outlined,
                color: pendingSync == 0
                    ? TgcgColors.success
                    : TgcgColors.warning,
                onTap: onSync,
              ),
            ],
          );
        },
      );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.width,
    required this.label,
    required this.detail,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final double width;
  final String label;
  final String detail;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: 132,
        child: Material(
          color: TgcgColors.surface,
          borderRadius: BorderRadius.circular(17),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(17),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: TgcgColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .09),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    label,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard({
    required this.incidents,
    required this.reports,
    required this.submissions,
  });

  final List<FieldIncident> incidents;
  final List<FieldReport> reports;
  final List<ElectionResultSubmission> submissions;

  @override
  Widget build(BuildContext context) {
    final items = <_ActivityItem>[
      ...incidents.map(
        (item) => _ActivityItem(
          title: item.title,
          detail: 'Incident • ${_label(item.status.name)}',
          at: item.reportedAt,
          icon: Icons.warning_amber_rounded,
          color: TgcgColors.danger,
        ),
      ),
      ...reports.map(
        (item) => _ActivityItem(
          title: item.category,
          detail: 'Field report • ${_label(item.status.name)}',
          at: item.reportedAt,
          icon: Icons.feed_outlined,
          color: TgcgColors.info,
        ),
      ),
      ...submissions.map(
        (item) => _ActivityItem(
          title: item.id,
          detail: 'Result submission • ${_label(item.status.name)}',
          at: item.submittedAt,
          icon: Icons.ballot_outlined,
          color: TgcgColors.primary,
        ),
      ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return TgcgSectionCard(
      title: 'My recent activity',
      subtitle: 'Only records submitted by this signed-in field agent are shown.',
      child: items.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.timeline_rounded,
              title: 'No field activity yet',
              message:
                  'Your check-ins, reports, incidents and result submissions will appear here.',
            )
          : Column(
              children: items.take(5).map((item) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: item.color.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(item.icon, color: item.color, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.ink,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              item.detail,
                              style: const TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 9.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _time(item.at),
                        style: const TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 9,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }
}

class _ActivityItem {
  const _ActivityItem({
    required this.title,
    required this.detail,
    required this.at,
    required this.icon,
    required this.color,
  });

  final String title;
  final String detail;
  final DateTime at;
  final IconData icon;
  final Color color;
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    final color = pending == 0 ? TgcgColors.success : TgcgColors.warning;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .16)),
      ),
      child: Row(
        children: [
          Icon(
            pending == 0
                ? Icons.offline_bolt_outlined
                : Icons.cloud_upload_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              pending == 0
                  ? 'Offline-ready architecture: no linked pending prototype mutation is currently visible.'
                  : 'Offline-safe: $pending linked record${pending == 1 ? '' : 's'} still awaiting server acknowledgement.',
              style: const TextStyle(
                color: TgcgColors.ink,
                fontSize: 10.5,
                height: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UnresolvedAssignment extends StatelessWidget {
  const _UnresolvedAssignment({required this.session});

  final TgcgSessionController session;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: TgcgSectionCard(
              child: Column(
                children: [
                  const TgcgLogo(size: 72),
                  const SizedBox(height: 16),
                  const Text(
                    'Polling-unit assignment not resolved',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The current Access ID (${session.accessId.isEmpty ? 'empty' : session.accessId}) is not linked to an accredited polling-unit agent record.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Field operations remain locked because a polling-unit agent must not inherit national scope when assignment data is missing.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: TgcgColors.danger,
                      fontSize: 11,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: session.signOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Return to sign in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 108,
              child: Text(
                label,
                style: const TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10.5,
                ),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      );
}

AccreditedAgent? _resolveAgent(
  MembershipOperationsController membership,
  TgcgSessionController session,
) {
  final accessId = session.accessId.trim().toLowerCase();
  for (final agent in membership.agents) {
    final idMatch = accessId.isNotEmpty && agent.agentId.toLowerCase() == accessId;
    final phoneMatch = accessId.isNotEmpty &&
        (agent.registeredPhoneNumber ?? '').trim().toLowerCase() == accessId;
    if (idMatch || phoneMatch) return agent;
  }
  final pollingUnitId = session.scope.pollingUnitId;
  if (pollingUnitId != null) {
    for (final agent in membership.agents) {
      if (agent.scope.pollingUnitId == pollingUnitId &&
          agent.role == TgcgRole.pollingUnitAgent) {
        return agent;
      }
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

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
