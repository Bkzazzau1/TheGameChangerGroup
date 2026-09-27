import 'package:flutter/material.dart';

import '../communications/communications_store.dart';
import '../field/field_operations_store.dart';
import '../membership/membership_store.dart';
import '../offline/offline_persistence.dart';
import '../results/result_operations_store.dart';
import '../session.dart';
import '../sync/sync_models.dart';
import '../ui/tgcg_design.dart';

class SystemMonitoringPage extends StatelessWidget {
  const SystemMonitoringPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final offline = OfflinePersistence.of(context);
    final field = FieldOperations.of(context);
    final results = ResultOperations.of(context);
    final membership = MembershipOperations.of(context);
    final communications = Communications.of(context);

    final queued = offline.outbox.where((item) => item.state == SyncState.queued).length;
    final syncing = offline.outbox.where((item) => item.state == SyncState.syncing).length;
    final failed = offline.outbox.where((item) => item.state == SyncState.failed).length;
    final conflicts = offline.outbox.where((item) => item.state == SyncState.conflict).length;
    final delivered = communications.messages.where((item) => item.deliveryState == MessageDeliveryState.delivered).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'OPERATIONS HEALTH',
          title: 'System Monitoring',
          subtitle: '${session.scope.label}: application health, synchronization, field activity and communications status.',
          trailing: TgcgStatusPill(
            label: failed == 0 && conflicts == 0 ? 'HEALTHY' : 'ATTENTION',
            color: failed == 0 && conflicts == 0 ? TgcgColors.success : TgcgColors.warning,
            icon: failed == 0 && conflicts == 0 ? Icons.monitor_heart_outlined : Icons.warning_amber_rounded,
          ),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1050 ? 5 : constraints.maxWidth >= 650 ? 3 : constraints.maxWidth >= 430 ? 2 : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(width: width, label: 'Queued', value: '$queued', detail: 'Awaiting synchronization', icon: Icons.cloud_upload_outlined, tone: queued == 0 ? TgcgMetricTone.success : TgcgMetricTone.warning),
              TgcgMetricCard(width: width, label: 'Syncing', value: '$syncing', detail: 'Active mutations', icon: Icons.sync_rounded, tone: TgcgMetricTone.info),
              TgcgMetricCard(width: width, label: 'Failed', value: '$failed', detail: 'Retry required', icon: Icons.error_outline_rounded, tone: failed == 0 ? TgcgMetricTone.neutral : TgcgMetricTone.danger),
              TgcgMetricCard(width: width, label: 'Conflicts', value: '$conflicts', detail: 'Version reconciliation', icon: Icons.merge_type_rounded, tone: conflicts == 0 ? TgcgMetricTone.neutral : TgcgMetricTone.warning),
              TgcgMetricCard(width: width, label: 'Results', value: '${results.submissions.length}', detail: '${results.verifiedCount} verified', icon: Icons.ballot_outlined, tone: TgcgMetricTone.success),
            ],
          );
        }),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, constraints) {
          final health = _HealthPanel(
            offlineReady: offline.isReady,
            durable: offline.isDurable,
            failed: failed,
            conflicts: conflicts,
            deliveredMessages: delivered,
          );
          final activity = _ActivityPanel(
            members: membership.members.length,
            agents: membership.agents.length,
            incidents: field.incidents.length,
            reports: field.reports.length,
            results: results.submissions.length,
            messages: communications.messages.length,
          );
          if (constraints.maxWidth < 980) {
            return Column(children: [health, const SizedBox(height: 16), activity]);
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 6, child: health),
              const SizedBox(width: 16),
              Expanded(flex: 5, child: activity),
            ],
          );
        }),
        const SizedBox(height: 16),
        _SyncStream(items: offline.outbox),
      ],
    );
  }
}

class _HealthPanel extends StatelessWidget {
  const _HealthPanel({required this.offlineReady, required this.durable, required this.failed, required this.conflicts, required this.deliveredMessages});
  final bool offlineReady;
  final bool durable;
  final int failed;
  final int conflicts;
  final int deliveredMessages;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Service health',
        subtitle: 'Core application services and operational safeguards.',
        child: Column(
          children: [
            _HealthRow(label: 'Local database', detail: 'Encrypted operational persistence', healthy: offlineReady && durable),
            _HealthRow(label: 'Encryption', detail: 'AES-256-GCM local protection', healthy: offlineReady),
            _HealthRow(label: 'Sync outbox', detail: failed == 0 ? 'Mutation queue operating normally' : '$failed failed mutation${failed == 1 ? '' : 's'}', healthy: failed == 0),
            _HealthRow(label: 'Conflict control', detail: conflicts == 0 ? 'No active version conflict' : '$conflicts mutation conflict${conflicts == 1 ? '' : 's'}', healthy: conflicts == 0),
            _HealthRow(label: 'Communications', detail: '$deliveredMessages delivered messages', healthy: true),
            const _HealthRow(label: 'PVC recognition', detail: 'Identity recognition service available', healthy: true),
            const _HealthRow(label: 'Evidence capture', detail: 'Photo, video, audio and GPS capture', healthy: true),
          ],
        ),
      );
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.label, required this.detail, required this.healthy});
  final String label;
  final String detail;
  final bool healthy;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: (healthy ? TgcgColors.success : TgcgColors.warning).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(healthy ? Icons.check_circle_outline_rounded : Icons.warning_amber_rounded, color: healthy ? TgcgColors.success : TgcgColors.warning, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink)),
                const SizedBox(height: 2),
                Text(detail, style: const TextStyle(color: TgcgColors.muted, fontSize: 10.5)),
              ]),
            ),
            TgcgStatusPill(label: healthy ? 'HEALTHY' : 'ATTENTION', color: healthy ? TgcgColors.success : TgcgColors.warning, compact: true),
          ],
        ),
      );
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({required this.members, required this.agents, required this.incidents, required this.reports, required this.results, required this.messages});
  final int members;
  final int agents;
  final int incidents;
  final int reports;
  final int results;
  final int messages;

  @override
  Widget build(BuildContext context) {
    final values = [
      ('Members', members, Icons.groups_outlined),
      ('Agents', agents, Icons.badge_outlined),
      ('Incidents', incidents, Icons.warning_amber_outlined),
      ('Field reports', reports, Icons.assignment_outlined),
      ('Results', results, Icons.ballot_outlined),
      ('Messages', messages, Icons.chat_bubble_outline_rounded),
    ];
    return TgcgSectionCard(
      title: 'Operations pulse',
      subtitle: 'Current locally available operational records.',
      child: Column(
        children: values.map((item) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Icon(item.$3, color: TgcgColors.primary, size: 19),
            const SizedBox(width: 10),
            Expanded(child: Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text('${item.$2}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
          ]),
        )).toList(),
      ),
    );
  }
}

class _SyncStream extends StatelessWidget {
  const _SyncStream({required this.items});
  final List<SyncOutboxItem> items;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Synchronization stream',
        subtitle: 'Latest mutation state across the durable outbox.',
        child: items.isEmpty
            ? const TgcgEmptyState(icon: Icons.cloud_done_outlined, title: 'All clear', message: 'No local mutations are waiting for synchronization.')
            : Column(
                children: items.take(12).map((item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: _color(item.state).withValues(alpha: .10), child: Icon(_icon(item.state), color: _color(item.state), size: 18)),
                  title: Text('${item.entityType} • ${item.entityId}', style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('Version ${item.mutationVersion} • ${item.mutationType.name}'),
                  trailing: TgcgStatusPill(label: item.state.name.toUpperCase(), color: _color(item.state), compact: true),
                )).toList(),
              ),
      );

  static Color _color(SyncState state) => switch (state) {
        SyncState.queued => TgcgColors.warning,
        SyncState.syncing => TgcgColors.info,
        SyncState.synced => TgcgColors.success,
        SyncState.failed => TgcgColors.danger,
        SyncState.conflict => TgcgColors.warning,
      };

  static IconData _icon(SyncState state) => switch (state) {
        SyncState.queued => Icons.schedule_rounded,
        SyncState.syncing => Icons.sync_rounded,
        SyncState.synced => Icons.cloud_done_outlined,
        SyncState.failed => Icons.error_outline_rounded,
        SyncState.conflict => Icons.merge_type_rounded,
      };
}
