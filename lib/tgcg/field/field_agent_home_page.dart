import 'package:flutter/material.dart';

import '../communications/communications_store.dart';
import '../location/gps_prompt.dart';
import '../location/gps_service.dart';
import '../membership/membership_store.dart';
import '../offline/offline_persistence.dart';
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
    final offline = OfflinePersistence.of(context);

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

    final ownedIds = <String>{agent.agentId};
    for (final incident in incidents) {
      ownedIds.add(incident.id);
      ownedIds.addAll(incident.evidence.map((item) => item.id));
    }
    for (final report in reports) {
      ownedIds.add(report.id);
      ownedIds.addAll(report.evidence.map((item) => item.id));
    }
    for (final submission in submissions) {
      ownedIds.add(submission.id);
      if (submission.resultForm != null) {
        ownedIds.add(submission.resultForm!.id);
      }
    }

    final pending = offline.pendingOutbox
        .where((item) => ownedIds.contains(item.entityId))
        .toList(growable: false);

    final approved = agent.status == AccreditationStatus.approved;
    final training = agent.trainingCompleted;
    final identity = agent.biometricEnrolled;
    final device = (agent.deviceId ?? '').trim().isNotEmpty;
    final sim = (agent.simFingerprint ?? '').trim().isNotEmpty;
    final ready = approved && training && identity && device && sim;
    final checkedIn = reports.any((item) => item.category == 'Agent check-in');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _DutyHeader(
          agent: agent,
          operatorName: member?.fullName ?? session.operatorName,
          ready: ready,
          checkedIn: checkedIn,
        ),
        const SizedBox(height: 14),
        _OnDutyCard(ownerId: agent.agentId),
        const SizedBox(height: 14),
        _ReadinessCard(
          approved: approved,
          training: training,
          identity: identity,
          device: device,
          sim: sim,
          checkedIn: checkedIn,
        ),
        const SizedBox(height: 14),
        _PollingUnitCard(agent: agent),
        const SizedBox(height: 18),
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
          pendingSync: pending.length,
          onCheckIn: checkedIn ? null : () => _checkIn(context, agent, field),
          onIncident: () => onOpenModule(TgcgModule.fieldMonitoring),
          onFieldUpdate: () => onOpenModule(TgcgModule.fieldMonitoring),
          onResult: () => onOpenModule(TgcgModule.resultCapture),
          onMessages: () => onOpenModule(TgcgModule.communications),
          onSync: () => _showSyncState(context, pending),
        ),
        const SizedBox(height: 16),
        _ActivityCard(
          incidents: incidents,
          reports: reports,
          submissions: submissions,
        ),
        const SizedBox(height: 14),
        _SyncBanner(pending: pending.length),
      ],
    );
  }

  Future<void> _checkIn(
    BuildContext context,
    AccreditedAgent agent,
    FieldOperationsController field,
  ) async {
    final gps = await captureGps(context, required: true, action: 'check in');
    if (gps == null) return;
    try {
      final report = await field.submitFieldReport(
        category: 'Agent check-in',
        summary: 'Agent checked in for field duty.',
        scope: agent.scope,
        reporterId: agent.agentId,
        gps: gps,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${report.id} check-in saved with GPS ${gps.label}.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to save check-in. Please try again.')),
      );
    }
  }

  void _showSyncState(
    BuildContext context,
    List<SyncOutboxItem> pending,
  ) {
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
                'Sync Status',
                style: TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              if (pending.isEmpty)
                const _SyncSummary(
                  icon: Icons.cloud_done_outlined,
                  color: TgcgColors.success,
                  title: 'All records synced',
                  subtitle: 'Your field records are up to date.',
                )
              else ...[
                _SyncSummary(
                  icon: Icons.cloud_upload_outlined,
                  color: TgcgColors.warning,
                  title: '${pending.length} record${pending.length == 1 ? '' : 's'} awaiting sync',
                  subtitle: 'Records remain available on this device.',
                ),
                const SizedBox(height: 14),
                ...pending.take(6).map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Icon(
                          _syncIcon(item.state),
                          color: _syncColor(item.state),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${_entityLabel(item.entityType)} • ${item.entityId}',
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        Text(
                          _label(item.state.name),
                          style: TextStyle(
                            color: _syncColor(item.state),
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
    required this.ready,
    required this.checkedIn,
  });

  final AccreditedAgent agent;
  final String operatorName;
  final bool ready;
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
                          color: Color(0xFFBDC3D0),
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
                      : ready
                          ? 'READY'
                          : 'ACTION NEEDED',
                  color: checkedIn
                      ? TgcgColors.success
                      : ready
                          ? TgcgColors.accent
                          : TgcgColors.warning,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              checkedIn
                  ? 'Field duty is active.'
                  : ready
                      ? 'Ready for election-day operations.'
                      : 'Complete the outstanding readiness items.',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                height: 1.2,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              agent.scope.label,
              style: const TextStyle(
                color: Color(0xFFBCC2D0),
                fontSize: 11,
                fontWeight: FontWeight.w700,
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
    required this.identity,
    required this.device,
    required this.sim,
    required this.checkedIn,
  });

  final bool approved;
  final bool training;
  final bool identity;
  final bool device;
  final bool sim;
  final bool checkedIn;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Duty Readiness',
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _ReadinessChip('Accreditation', approved),
            _ReadinessChip('Training', training),
            _ReadinessChip('Identity', identity),
            _ReadinessChip('Device', device),
            _ReadinessChip('SIM', sim),
            _ReadinessChip('Check-in', checkedIn),
          ],
        ),
      );
}

class _ReadinessChip extends StatelessWidget {
  const _ReadinessChip(this.label, this.ready);

  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? TgcgColors.success : TgcgColors.warning;
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
            ready ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 15,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            label,
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
  final Future<void> Function()? onCheckIn;
  final VoidCallback onIncident;
  final VoidCallback onFieldUpdate;
  final VoidCallback onResult;
  final VoidCallback onMessages;
  final VoidCallback onSync;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth < 350
              ? constraints.maxWidth
              : (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ActionCard(
                width: width,
                label: checkedIn ? 'CHECKED IN' : 'CHECK IN',
                detail: checkedIn ? 'Duty active' : 'Start field duty',
                icon: Icons.how_to_reg_rounded,
                color: TgcgColors.success,
                onTap: checkedIn || onCheckIn == null
                    ? null
                    : () async => onCheckIn!(),
              ),
              _ActionCard(
                width: width,
                label: 'REPORT INCIDENT',
                detail: 'Report an operational issue',
                icon: Icons.report_problem_outlined,
                color: TgcgColors.danger,
                onTap: onIncident,
              ),
              _ActionCard(
                width: width,
                label: 'FIELD UPDATE',
                detail: 'Submit field status',
                icon: Icons.post_add_rounded,
                color: TgcgColors.info,
                onTap: onFieldUpdate,
              ),
              _ActionCard(
                width: width,
                label: 'CAPTURE RESULT',
                detail: 'Submit polling-unit result',
                icon: Icons.document_scanner_outlined,
                color: TgcgColors.primary,
                onTap: onResult,
              ),
              _ActionCard(
                width: width,
                label: 'MESSAGES',
                detail: '$messageCount messages',
                icon: Icons.forum_outlined,
                color: TgcgColors.ai,
                onTap: onMessages,
              ),
              _ActionCard(
                width: width,
                label: 'SYNC STATUS',
                detail: pendingSync == 0 ? 'Up to date' : '$pendingSync awaiting sync',
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
        height: 136,
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
          detail: 'Result • ${_label(item.status.name)}',
          at: item.submittedAt,
          icon: Icons.ballot_outlined,
          color: TgcgColors.primary,
        ),
      ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return TgcgSectionCard(
      title: 'Recent Activity',
      child: items.isEmpty
          ? const TgcgEmptyState(
              icon: Icons.history_rounded,
              title: 'No activity yet',
              message: 'Your field activity will appear here.',
            )
          : Column(
              children: items.take(8).map((item) => _ActivityRow(item: item)).toList(),
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

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});

  final _ActivityItem item;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(10),
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
                      fontSize: 10.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    item.detail,
                    style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5),
                  ),
                ],
              ),
            ),
            Text(
              _time(item.at),
              style: const TextStyle(color: TgcgColors.muted, fontSize: 9),
            ),
          ],
        ),
      );
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.pending});

  final int pending;

  @override
  Widget build(BuildContext context) {
    final color = pending > 0 ? TgcgColors.warning : TgcgColors.success;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Icon(
            pending > 0 ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              pending > 0
                  ? '$pending record${pending == 1 ? '' : 's'} awaiting sync'
                  : 'All field records are up to date',
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncSummary extends StatelessWidget {
  const _SyncSummary({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      );
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(
              width: 110,
              child: Text(
                label,
                style: const TextStyle(color: TgcgColors.muted, fontSize: 10),
              ),
            ),
            Expanded(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
}

class _UnresolvedAssignment extends StatelessWidget {
  const _UnresolvedAssignment({required this.session});

  final TgcgSessionController session;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: TgcgSectionCard(
              title: 'Field Assignment Required',
              child: Column(
                children: [
                  const Icon(
                    Icons.location_off_outlined,
                    size: 54,
                    color: TgcgColors.warning,
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Your access ID is not linked to a polling-unit assignment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: TgcgColors.muted, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: session.signOut,
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('Sign in again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

AccreditedAgent? _resolveAgent(
  MembershipOperationsController membership,
  TgcgSessionController session,
) {
  final normalized = session.accessId.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final agent in membership.agents) {
    if (agent.role != TgcgRole.pollingUnitAgent) continue;
    if (agent.agentId.toLowerCase() == normalized ||
        (agent.registeredPhoneNumber ?? '').trim().toLowerCase() == normalized) {
      return agent;
    }
  }
  return null;
}

Color _syncColor(SyncState state) => switch (state) {
      SyncState.queued => TgcgColors.warning,
      SyncState.syncing => TgcgColors.info,
      SyncState.synced => TgcgColors.success,
      SyncState.failed => TgcgColors.danger,
      SyncState.conflict => TgcgColors.ai,
    };

IconData _syncIcon(SyncState state) => switch (state) {
      SyncState.queued => Icons.schedule_rounded,
      SyncState.syncing => Icons.sync_rounded,
      SyncState.synced => Icons.cloud_done_outlined,
      SyncState.failed => Icons.cloud_off_outlined,
      SyncState.conflict => Icons.merge_type_rounded,
    };

String _entityLabel(String value) => switch (value) {
      'field_incident' => 'Incident',
      'field_report' => 'Field report',
      'election_result' => 'Result',
      _ => _label(value),
    };

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
  final clean = spaced.replaceAll('_', ' ');
  return clean.isEmpty
      ? clean
      : '${clean[0].toUpperCase()}${clean.substring(1)}';
}


/// Switch for sharing live location while on duty on election day.
class _OnDutyCard extends StatelessWidget {
  const _OnDutyCard({required this.ownerId});
  final String ownerId;

  @override
  Widget build(BuildContext context) {
    final tracker = DutyTracker.instance;
    return ListenableBuilder(
      listenable: tracker,
      builder: (context, _) {
        final last = tracker.lastFix;
        final since = tracker.since?.toLocal();
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
          decoration: BoxDecoration(
            color: tracker.onDuty ? TgcgColors.primary : TgcgColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: tracker.onDuty ? TgcgColors.primary : TgcgColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                tracker.onDuty ? Icons.share_location_rounded : Icons.location_disabled_outlined,
                color: tracker.onDuty ? TgcgColors.accentBright : TgcgColors.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tracker.onDuty ? 'On duty: sharing location' : 'Off duty',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: tracker.onDuty ? Colors.white : TgcgColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tracker.onDuty
                          ? 'Since ${_hhmm(since)}'
                              '${last == null ? ' · waiting for GPS' : ' · last fix ±${last.accuracyMeters.round()} m'}'
                          : 'Switch on when you start election-day duty. Your coordinator sees your position only while you are on duty.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: tracker.onDuty ? const Color(0xFFC9D4F0) : TgcgColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: tracker.onDuty,
                onChanged: (value) => _toggle(context, tracker, value),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _toggle(BuildContext context, DutyTracker tracker, bool value) async {
    if (!value) {
      await tracker.stop();
      return;
    }
    try {
      await tracker.start(
        ownerId: ownerId,
        persistence: OfflinePersistence.of(context, listen: false),
      );
    } on GpsUnavailable catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  static String _hhmm(DateTime? value) => value == null
      ? '--:--'
      : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}
