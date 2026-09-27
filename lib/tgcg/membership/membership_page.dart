import 'package:flutter/material.dart';

import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'membership_store.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  String memberQuery = '';
  String agentQuery = '';
  AccreditationStatus? statusFilter;
  String? selectedAgentId;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final store = MembershipOperations.of(context);
    final role = session.role!;
    final canCreateMember = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.manageMembership,
    );
    final canAccredit = TgcgPermissionPolicy.allows(
      role,
      TgcgCapability.accreditAgents,
    );

    final memberNeedle = memberQuery.trim().toLowerCase();
    final members = store.members
        .where(
          (member) =>
              memberNeedle.isEmpty ||
              member.fullName.toLowerCase().contains(memberNeedle) ||
              member.phoneNumber.toLowerCase().contains(memberNeedle) ||
              (member.membershipNumber ?? '')
                  .toLowerCase()
                  .contains(memberNeedle),
        )
        .toList(growable: false);

    final agentNeedle = agentQuery.trim().toLowerCase();
    final agents = store.agents.where((agent) {
      if (statusFilter != null && agent.status != statusFilter) return false;
      if (agentNeedle.isEmpty) return true;
      final member = store.memberById(agent.memberId);
      return agent.agentId.toLowerCase().contains(agentNeedle) ||
          roleLabel(agent.role).toLowerCase().contains(agentNeedle) ||
          agent.scope.label.toLowerCase().contains(agentNeedle) ||
          (member?.fullName.toLowerCase().contains(agentNeedle) ?? false) ||
          (member?.membershipNumber?.toLowerCase().contains(agentNeedle) ??
              false);
    }).toList(growable: false);

    if (agents.isNotEmpty &&
        !agents.any((agent) => agent.id == selectedAgentId)) {
      selectedAgentId = agents.first.id;
    }
    final selectedAgent = selectedAgentId == null
        ? null
        : store.agents.where((agent) => agent.id == selectedAgentId).firstOrNull;

    final approved = store.agents
        .where((agent) => agent.status == AccreditationStatus.approved)
        .length;
    final pending = store.agents
        .where((agent) => agent.status == AccreditationStatus.pending)
        .length;
    final trained = store.agents.where((agent) => agent.trainingCompleted).length;
    final biometrics =
        store.agents.where((agent) => agent.biometricEnrolled).length;
    final deviceBound = store.agents.where((agent) => agent.deviceId != null).length;
    final simBound =
        store.agents.where((agent) => agent.simFingerprint != null).length;
    final ready = store.agents.where(_isOperationallyReady).length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'IDENTITY & FIELD READINESS',
          title: 'Membership & Accreditation',
          subtitle:
              'Register members, issue traceable agent identities, assign canonical geography and verify election-day readiness.',
          trailing: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canCreateMember)
                OutlinedButton.icon(
                  onPressed: () => _showMemberDialog(context, store),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: const Text('New member'),
                ),
              if (canAccredit)
                FilledButton.icon(
                  onPressed: () => _showAccreditationDialog(context, store),
                  icon: const Icon(Icons.badge_outlined),
                  label: const Text('Accredit agent'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _Metrics(
          members: store.members.length,
          agents: store.agents.length,
          approved: approved,
          pending: pending,
          ready: ready,
          biometrics: biometrics,
          deviceAndSimBound: store.agents
              .where(
                (agent) =>
                    agent.deviceId != null && agent.simFingerprint != null,
              )
              .length,
        ),
        const SizedBox(height: 16),
        _ReadinessRail(
          total: store.agents.length,
          approved: approved,
          trained: trained,
          biometrics: biometrics,
          deviceBound: deviceBound,
          simBound: simBound,
          ready: ready,
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final network = _AgentNetworkPanel(
              agents: agents,
              query: agentQuery,
              statusFilter: statusFilter,
              selectedAgentId: selectedAgentId,
              onQueryChanged: (value) => setState(() => agentQuery = value),
              onStatusChanged: (value) =>
                  setState(() => statusFilter = value),
              onSelect: (id) => setState(() => selectedAgentId = id),
            );
            final inspector = _AgentInspector(
              agent: selectedAgent,
              canManage: canAccredit,
              onEditReadiness: selectedAgent == null
                  ? null
                  : () => _showReadinessDialog(
                        context,
                        store,
                        selectedAgent,
                      ),
            );

            if (constraints.maxWidth < 1040) {
              return Column(
                children: [
                  network,
                  const SizedBox(height: 14),
                  inspector,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: network),
                const SizedBox(width: 14),
                Expanded(flex: 5, child: inspector),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _MemberRegistry(
          members: members,
          query: memberQuery,
          onQueryChanged: (value) => setState(() => memberQuery = value),
        ),
        const SizedBox(height: 16),
        const _PrivacyPanel(),
      ],
    );
  }

  Future<void> _showMemberDialog(
    BuildContext context,
    MembershipOperationsController store,
  ) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Register member'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Create the identity record first. Operational accreditation and geographic assignment follow as a separate controlled step.',
                style: TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Full name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                decoration: const InputDecoration(labelText: 'Phone number'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: email,
                decoration: const InputDecoration(labelText: 'Email (optional)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () {
              if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
              store.createMember(
                fullName: name.text,
                phoneNumber: phone.text,
                email: email.text,
              );
              Navigator.pop(dialogContext, true);
            },
            icon: const Icon(Icons.person_add_alt_1_rounded),
            label: const Text('Register member'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    email.dispose();
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Member registered in the local prototype store.'),
        ),
      );
    }
  }

  Future<void> _showAccreditationDialog(
    BuildContext context,
    MembershipOperationsController store,
  ) async {
    if (store.members.isEmpty) return;
    var memberId = store.members.first.id;
    var role = TgcgRole.pollingUnitAgent;
    final scopes = _assignmentScopes(store.geography);
    var scope = scopes.first;
    final phone = TextEditingController();
    final device = TextEditingController();
    final sim = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create agent accreditation'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const _DialogStageRail(),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: memberId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Member identity'),
                    items: store.members
                        .map(
                          (member) => DropdownMenuItem(
                            value: member.id,
                            child: Text(
                              '${member.fullName} • ${member.membershipNumber ?? member.id}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => memberId = value ?? memberId),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<TgcgRole>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Operational role'),
                    items: _assignableRoles
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(roleLabel(value)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => role = value ?? role),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<GeographicScope>(
                    initialValue: scope,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Canonical geographic assignment',
                    ),
                    items: scopes
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(
                              value.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setDialogState(() => scope = value ?? scope),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phone,
                    decoration: const InputDecoration(
                      labelText: 'Registered phone number',
                    ),
                  ),
                  const SizedBox(height: 10),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final deviceField = TextField(
                        controller: device,
                        decoration: const InputDecoration(
                          labelText: 'Device binding ID (optional)',
                        ),
                      );
                      final simField = TextField(
                        controller: sim,
                        decoration: const InputDecoration(
                          labelText: 'SIM binding ID (optional)',
                        ),
                      );
                      if (constraints.maxWidth < 520) {
                        return Column(
                          children: [
                            deviceField,
                            const SizedBox(height: 10),
                            simField,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: deviceField),
                          const SizedBox(width: 10),
                          Expanded(child: simField),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  const _PrivacyNotice(),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                final agent = store.accredit(
                  memberId: memberId,
                  role: role,
                  scope: scope,
                  phoneNumber: phone.text,
                  deviceId: device.text,
                  simFingerprint: sim.text,
                );
                setState(() => selectedAgentId = agent.id);
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.badge_outlined),
              label: const Text('Create pending accreditation'),
            ),
          ],
        ),
      ),
    );
    phone.dispose();
    device.dispose();
    sim.dispose();
    if (created == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Accreditation created as pending review.'),
        ),
      );
    }
  }

  Future<void> _showReadinessDialog(
    BuildContext context,
    MembershipOperationsController store,
    AccreditedAgent agent,
  ) async {
    var training = agent.trainingCompleted;
    var biometric = agent.biometricEnrolled;
    final device = TextEditingController(text: agent.deviceId ?? '');
    final sim = TextEditingController(text: agent.simFingerprint ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Readiness • ${agent.agentId}'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Readiness records describe operational enrollment state only. Raw biometric templates are not shown or stored in this Flutter prototype.',
                  style: TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Training completed'),
                  subtitle: const Text('Required operational training has been recorded.'),
                  value: training,
                  onChanged: (value) => setDialogState(() => training = value),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Biometric enrollment recorded'),
                  subtitle: const Text(
                    'Enrollment readiness only; liveness/anti-spoof outcome is not represented by the current domain model.',
                  ),
                  value: biometric,
                  onChanged: (value) => setDialogState(() => biometric = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: device,
                  decoration: const InputDecoration(labelText: 'Bound device ID'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: sim,
                  decoration: const InputDecoration(labelText: 'Bound SIM ID'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                store.updateReadiness(
                  agent.id,
                  trainingCompleted: training,
                  biometricEnrolled: biometric,
                  deviceId:
                      device.text.trim().isEmpty ? null : device.text.trim(),
                  simFingerprint: sim.text.trim().isEmpty ? null : sim.text.trim(),
                );
                Navigator.pop(dialogContext, true);
              },
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save readiness'),
            ),
          ],
        ),
      ),
    );
    device.dispose();
    sim.dispose();
    if (saved == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Agent readiness updated.')),
      );
    }
  }
}

class _Metrics extends StatelessWidget {
  const _Metrics({
    required this.members,
    required this.agents,
    required this.approved,
    required this.pending,
    required this.ready,
    required this.biometrics,
    required this.deviceAndSimBound,
  });

  final int members;
  final int agents;
  final int approved;
  final int pending;
  final int ready;
  final int biometrics;
  final int deviceAndSimBound;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 1180
              ? 7
              : constraints.maxWidth >= 820
                  ? 4
                  : constraints.maxWidth >= 520
                      ? 2
                      : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Members',
                value: '$members',
                detail: 'Identity records',
                icon: Icons.groups_2_outlined,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Agents',
                value: '$agents',
                detail: 'Operational identities',
                icon: Icons.badge_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Approved',
                value: '$approved',
                detail: 'Accreditation approved',
                icon: Icons.verified_user_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Pending',
                value: '$pending',
                detail: 'Awaiting decision',
                icon: Icons.hourglass_top_rounded,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Ready',
                value: '$ready',
                detail: 'Approved + training + identity + bindings',
                icon: Icons.task_alt_rounded,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Biometric',
                value: '$biometrics',
                detail: 'Enrollment recorded',
                icon: Icons.face_retouching_natural_outlined,
                tone: TgcgMetricTone.ai,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Device + SIM',
                value: '$deviceAndSimBound',
                detail: 'Both bindings present',
                icon: Icons.phonelink_lock_outlined,
              ),
            ],
          );
        },
      );
}

class _ReadinessRail extends StatelessWidget {
  const _ReadinessRail({
    required this.total,
    required this.approved,
    required this.trained,
    required this.biometrics,
    required this.deviceBound,
    required this.simBound,
    required this.ready,
  });

  final int total;
  final int approved;
  final int trained;
  final int biometrics;
  final int deviceBound;
  final int simBound;
  final int ready;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Election-day readiness pipeline',
        subtitle:
            'Each readiness stage remains independently visible so approval never hides missing training, identity enrollment or device/SIM binding.',
        trailing: TgcgStatusPill(
          label: total == 0
              ? '0% READY'
              : '${((ready / total) * 100).round()}% READY',
          color: ready == total && total > 0
              ? TgcgColors.success
              : TgcgColors.warning,
          icon: Icons.monitor_heart_outlined,
          compact: true,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final values = <({String label, int value, IconData icon, Color color})>[
              (
                label: 'Accredited',
                value: approved,
                icon: Icons.verified_user_outlined,
                color: TgcgColors.success,
              ),
              (
                label: 'Training',
                value: trained,
                icon: Icons.school_outlined,
                color: TgcgColors.info,
              ),
              (
                label: 'Biometric',
                value: biometrics,
                icon: Icons.face_retouching_natural_outlined,
                color: TgcgColors.ai,
              ),
              (
                label: 'Device',
                value: deviceBound,
                icon: Icons.phone_android_rounded,
                color: TgcgColors.primary,
              ),
              (
                label: 'SIM',
                value: simBound,
                icon: Icons.sim_card_outlined,
                color: TgcgColors.accent,
              ),
              (
                label: 'Fully ready',
                value: ready,
                icon: Icons.task_alt_rounded,
                color: TgcgColors.success,
              ),
            ];
            final width = constraints.maxWidth >= 900
                ? (constraints.maxWidth - 50) / 6
                : constraints.maxWidth >= 520
                    ? (constraints.maxWidth - 10) / 2
                    : constraints.maxWidth;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: values
                  .map(
                    (item) => _ReadinessStage(
                      width: width,
                      label: item.label,
                      value: item.value,
                      total: total,
                      icon: item.icon,
                      color: item.color,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      );
}

class _ReadinessStage extends StatelessWidget {
  const _ReadinessStage({
    required this.width,
    required this.label,
    required this.value,
    required this.total,
    required this.icon,
    required this.color,
  });

  final double width;
  final String label;
  final int value;
  final int total;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : value / total;
    return Container(
      width: width,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: color),
              const Spacer(),
              Text(
                '$value/$total',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 10.5,
            ),
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress.clamp(0, 1).toDouble(),
            minHeight: 6,
            borderRadius: BorderRadius.circular(999),
            backgroundColor: TgcgColors.border,
            color: color,
          ),
        ],
      ),
    );
  }
}

class _AgentNetworkPanel extends StatelessWidget {
  const _AgentNetworkPanel({
    required this.agents,
    required this.query,
    required this.statusFilter,
    required this.selectedAgentId,
    required this.onQueryChanged,
    required this.onStatusChanged,
    required this.onSelect,
  });

  final List<AccreditedAgent> agents;
  final String query;
  final AccreditationStatus? statusFilter;
  final String? selectedAgentId;
  final ValueChanged<String> onQueryChanged;
  final ValueChanged<AccreditationStatus?> onStatusChanged;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final store = MembershipOperations.of(context, listen: false);
    return TgcgSectionCard(
      title: 'Accredited field network',
      subtitle:
          'Search by agent, member, role or geography. Select a record for readiness and accreditation details.',
      trailing: TgcgStatusPill(
        label: '${agents.length} SHOWN',
        color: TgcgColors.info,
        compact: true,
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final search = TextField(
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  labelText: 'Search agents',
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Name, agent ID, role or location',
                ),
              );
              final filter = DropdownButtonFormField<AccreditationStatus?>(
                initialValue: statusFilter,
                decoration: const InputDecoration(labelText: 'Status'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('All statuses')),
                  ...AccreditationStatus.values.map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text(_label(value.name)),
                    ),
                  ),
                ],
                onChanged: onStatusChanged,
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  children: [
                    search,
                    const SizedBox(height: 10),
                    filter,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: search),
                  const SizedBox(width: 10),
                  SizedBox(width: 180, child: filter),
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          if (agents.isEmpty)
            const TgcgEmptyState(
              icon: Icons.badge_outlined,
              title: 'No matching agents',
              message: 'Change the search or accreditation-status filter.',
            )
          else
            ...agents.map((agent) {
              final member = store.memberById(agent.memberId);
              final selected = agent.id == selectedAgentId;
              final ready = _isOperationallyReady(agent);
              return InkWell(
                onTap: () => onSelect(agent.id),
                borderRadius: BorderRadius.circular(15),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.only(bottom: 9),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: selected
                        ? TgcgColors.primarySoft
                        : TgcgColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                      color: selected
                          ? TgcgColors.primary.withValues(alpha: .32)
                          : TgcgColors.border,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _AgentAvatar(
                        name: member?.fullName ?? agent.memberId,
                        approved:
                            agent.status == AccreditationStatus.approved,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    member?.fullName ?? agent.memberId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: TgcgColors.ink,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                TgcgStatusPill(
                                  label: _label(agent.status.name).toUpperCase(),
                                  color: _statusColor(agent.status),
                                  compact: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${agent.agentId} • ${roleLabel(agent.role)}',
                              style: const TextStyle(
                                color: TgcgColors.muted,
                                fontSize: 10.5,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              agent.scope.label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: TgcgColors.primaryMid,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                _MiniState(
                                  label: 'Training',
                                  ok: agent.trainingCompleted,
                                ),
                                _MiniState(
                                  label: 'Identity',
                                  ok: agent.biometricEnrolled,
                                ),
                                _MiniState(
                                  label: 'Device',
                                  ok: agent.deviceId != null,
                                ),
                                _MiniState(
                                  label: 'SIM',
                                  ok: agent.simFingerprint != null,
                                ),
                                TgcgStatusPill(
                                  label: ready ? 'READY' : 'NOT READY',
                                  color: ready
                                      ? TgcgColors.success
                                      : TgcgColors.warning,
                                  icon: ready
                                      ? Icons.task_alt_rounded
                                      : Icons.pending_actions_rounded,
                                  compact: true,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: selected
                            ? TgcgColors.primary
                            : TgcgColors.muted,
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _AgentInspector extends StatelessWidget {
  const _AgentInspector({
    required this.agent,
    required this.canManage,
    required this.onEditReadiness,
  });

  final AccreditedAgent? agent;
  final bool canManage;
  final VoidCallback? onEditReadiness;

  @override
  Widget build(BuildContext context) {
    if (agent == null) {
      return const TgcgSectionCard(
        child: TgcgEmptyState(
          icon: Icons.contact_page_outlined,
          title: 'Select an agent',
          message:
              'Choose an accreditation record to inspect identity, assignment and readiness.',
        ),
      );
    }

    final store = MembershipOperations.of(context, listen: false);
    final member = store.memberById(agent!.memberId);
    final ready = _isOperationallyReady(agent!);

    return TgcgSectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: TgcgColors.primaryDark,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                _LargeAgentAvatar(
                  name: member?.fullName ?? agent!.memberId,
                  approved: agent!.status == AccreditationStatus.approved,
                ),
                const SizedBox(height: 12),
                Text(
                  member?.fullName ?? agent!.memberId,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${agent!.agentId} • ${roleLabel(agent!.role)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB8CEC6),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 11),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    TgcgStatusPill(
                      label: _label(agent!.status.name).toUpperCase(),
                      color: _statusColor(agent!.status),
                      compact: true,
                    ),
                    TgcgStatusPill(
                      label: ready ? 'OPERATIONALLY READY' : 'READINESS INCOMPLETE',
                      color: ready ? TgcgColors.success : TgcgColors.warning,
                      icon: ready
                          ? Icons.task_alt_rounded
                          : Icons.pending_actions_rounded,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _InspectorHeading('Identity'),
                _DetailRow(
                  icon: Icons.confirmation_number_outlined,
                  label: 'Membership number',
                  value: member?.membershipNumber ?? member?.id ?? '—',
                ),
                _DetailRow(
                  icon: Icons.phone_outlined,
                  label: 'Registered phone',
                  value: agent!.registeredPhoneNumber ?? member?.phoneNumber ?? '—',
                ),
                const SizedBox(height: 13),
                const _InspectorHeading('Assignment'),
                _DetailRow(
                  icon: roleIcon(agent!.role),
                  label: 'Operational role',
                  value: roleLabel(agent!.role),
                ),
                _DetailRow(
                  icon: Icons.location_on_outlined,
                  label: 'Geographic scope',
                  value: agent!.scope.label,
                ),
                const SizedBox(height: 13),
                const _InspectorHeading('Readiness checklist'),
                _ReadinessCheck(
                  icon: Icons.school_outlined,
                  title: 'Training completed',
                  done: agent!.trainingCompleted,
                ),
                _ReadinessCheck(
                  icon: Icons.face_retouching_natural_outlined,
                  title: 'Biometric enrollment recorded',
                  done: agent!.biometricEnrolled,
                  note: 'Raw template not exposed',
                ),
                _ReadinessCheck(
                  icon: Icons.phone_android_rounded,
                  title: 'Device bound',
                  done: agent!.deviceId != null,
                  note: agent!.deviceId,
                ),
                _ReadinessCheck(
                  icon: Icons.sim_card_outlined,
                  title: 'SIM bound',
                  done: agent!.simFingerprint != null,
                  note: agent!.simFingerprint,
                ),
                _ReadinessCheck(
                  icon: Icons.shield_outlined,
                  title: 'Liveness / anti-spoof result',
                  done: false,
                  note: 'Not represented in prototype domain yet',
                  integrationPending: true,
                ),
                if (canManage) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: onEditReadiness,
                        icon: const Icon(Icons.tune_rounded),
                        label: const Text('Update readiness'),
                      ),
                      PopupMenuButton<AccreditationStatus>(
                        tooltip: 'Change accreditation status',
                        onSelected: (value) => store.updateAccreditationStatus(
                          agent!.id,
                          value,
                        ),
                        itemBuilder: (_) => AccreditationStatus.values
                            .map(
                              (status) => PopupMenuItem(
                                value: status,
                                child: Text(_label(status.name)),
                              ),
                            )
                            .toList(),
                        child: const OutlinedButtonContent(
                          icon: Icons.verified_user_outlined,
                          label: 'Accreditation status',
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OutlinedButtonContent extends StatelessWidget {
  const OutlinedButtonContent({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: TgcgColors.primary),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                color: TgcgColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(width: 5),
            const Icon(
              Icons.arrow_drop_down_rounded,
              color: TgcgColors.primary,
            ),
          ],
        ),
      );
}

class _MemberRegistry extends StatelessWidget {
  const _MemberRegistry({
    required this.members,
    required this.query,
    required this.onQueryChanged,
  });

  final List<TgcgMember> members;
  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Member identity registry',
        subtitle:
            'Upstream member records eligible for operational accreditation. Membership does not automatically grant field access.',
        child: Column(
          children: [
            TextField(
              onChanged: onQueryChanged,
              decoration: const InputDecoration(
                labelText: 'Search member identities',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            if (members.isEmpty)
              const TgcgEmptyState(
                icon: Icons.person_search_outlined,
                title: 'No matching members',
                message: 'Try a different name, membership number or phone.',
              )
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth >= 960
                      ? (constraints.maxWidth - 24) / 3
                      : constraints.maxWidth >= 580
                          ? (constraints.maxWidth - 12) / 2
                          : constraints.maxWidth;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: members
                        .map(
                          (member) => _MemberCard(
                            width: width,
                            member: member,
                          ),
                        )
                        .toList(),
                  );
                },
              ),
          ],
        ),
      );
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.width, required this.member});

  final double width;
  final TgcgMember member;

  @override
  Widget build(BuildContext context) {
    final store = MembershipOperations.of(context, listen: false);
    final agentCount =
        store.agents.where((agent) => agent.memberId == member.id).length;
    return Container(
      width: width,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: TgcgColors.primarySoft,
            foregroundColor: TgcgColors.primary,
            child: Text(
              member.fullName.isEmpty ? '?' : member.fullName[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${member.membershipNumber ?? member.id} • ${member.phoneNumber}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 10,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    TgcgStatusPill(
                      label: _label(member.status.name).toUpperCase(),
                      color: _recordStatusColor(member.status),
                      compact: true,
                    ),
                    TgcgStatusPill(
                      label: '$agentCount AGENT ${agentCount == 1 ? 'ID' : 'IDS'}',
                      color: TgcgColors.info,
                      compact: true,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogStageRail extends StatelessWidget {
  const _DialogStageRail();

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: const [
          TgcgStatusPill(
            label: '1 IDENTITY',
            color: TgcgColors.info,
            compact: true,
          ),
          TgcgStatusPill(
            label: '2 ROLE',
            color: TgcgColors.primary,
            compact: true,
          ),
          TgcgStatusPill(
            label: '3 GEOGRAPHY',
            color: TgcgColors.primary,
            compact: true,
          ),
          TgcgStatusPill(
            label: '4 BINDINGS',
            color: TgcgColors.warning,
            compact: true,
          ),
          TgcgStatusPill(
            label: '5 REVIEW',
            color: TgcgColors.ai,
            compact: true,
          ),
        ],
      );
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: TgcgColors.ai.withValues(alpha: .05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TgcgColors.ai.withValues(alpha: .14)),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.privacy_tip_outlined, size: 18, color: TgcgColors.ai),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Biometric enrollment, consent, liveness and anti-spoof processing belong to the secured identity service. This UI stores readiness/status references only.',
                style: TextStyle(
                  color: TgcgColors.muted,
                  fontSize: 10.5,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      );
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel();

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        backgroundColor: TgcgColors.primaryDark,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.privacy_tip_outlined,
                color: TgcgColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Identity & biometric boundary',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'The Flutter prototype stores biometric-enrollment readiness only—not raw face templates. Production consent records, facial templates, liveness/anti-spoof checks, encryption and retention policies remain inside the secured backend and identity-service boundary.',
                    style: TextStyle(
                      color: Color(0xFFB8CEC6),
                      height: 1.5,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _InspectorHeading extends StatelessWidget {
  const _InspectorHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: TgcgColors.muted,
            fontSize: 9.5,
            fontWeight: FontWeight.w900,
            letterSpacing: .7,
          ),
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 17, color: TgcgColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: TgcgColors.ink,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}

class _ReadinessCheck extends StatelessWidget {
  const _ReadinessCheck({
    required this.icon,
    required this.title,
    required this.done,
    this.note,
    this.integrationPending = false,
  });

  final IconData icon;
  final String title;
  final bool done;
  final String? note;
  final bool integrationPending;

  @override
  Widget build(BuildContext context) {
    final color = integrationPending
        ? TgcgColors.info
        : done
            ? TgcgColors.success
            : TgcgColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: TgcgColors.ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 10.5,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note!,
                    style: const TextStyle(
                      color: TgcgColors.muted,
                      fontSize: 9.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          TgcgStatusPill(
            label: integrationPending
                ? 'PENDING INTEGRATION'
                : done
                    ? 'READY'
                    : 'PENDING',
            color: color,
            compact: true,
          ),
        ],
      ),
    );
  }
}

class _AgentAvatar extends StatelessWidget {
  const _AgentAvatar({required this.name, required this.approved});

  final String name;
  final bool approved;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: TgcgColors.primary.withValues(alpha: .09),
            foregroundColor: TgcgColors.primary,
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (approved)
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: TgcgColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(Icons.check, size: 9, color: Colors.white),
              ),
            ),
        ],
      );
}

class _LargeAgentAvatar extends StatelessWidget {
  const _LargeAgentAvatar({required this.name, required this.approved});

  final String name;
  final bool approved;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: .10),
              border: Border.all(
                color: Colors.white.withValues(alpha: .16),
                width: 2,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 27,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (approved)
            Positioned(
              right: 1,
              bottom: 1,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: TgcgColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(color: TgcgColors.primaryDark, width: 3),
                ),
                child: const Icon(Icons.check, size: 11, color: Colors.white),
              ),
            ),
        ],
      );
}

class _MiniState extends StatelessWidget {
  const _MiniState({required this.label, required this.ok});

  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) => TgcgStatusPill(
        label: label.toUpperCase(),
        color: ok ? TgcgColors.success : TgcgColors.warning,
        icon: ok ? Icons.check_circle_outline_rounded : Icons.pending_outlined,
        compact: true,
      );
}

bool _isOperationallyReady(AccreditedAgent agent) =>
    agent.status == AccreditationStatus.approved &&
    agent.trainingCompleted &&
    agent.biometricEnrolled &&
    agent.deviceId != null &&
    agent.simFingerprint != null;

List<GeographicScope> _assignmentScopes(GeographyRegistry registry) {
  final values = <String, GeographicScope>{'country': GeographicScope.nigeria};
  for (final unit in registry.pollingUnits) {
    final pu = unit.scope;
    final candidates = <GeographicScope>[
      GeographicScope(
        level: GeographyLevel.geopoliticalZone,
        country: pu.country,
        zoneId: pu.zoneId,
        zoneName: pu.zoneName,
      ),
      GeographicScope(
        level: GeographyLevel.state,
        country: pu.country,
        zoneId: pu.zoneId,
        zoneName: pu.zoneName,
        stateId: pu.stateId,
        stateName: pu.stateName,
      ),
      GeographicScope(
        level: GeographyLevel.senatorialDistrict,
        country: pu.country,
        zoneId: pu.zoneId,
        zoneName: pu.zoneName,
        stateId: pu.stateId,
        stateName: pu.stateName,
        senatorialDistrictId: pu.senatorialDistrictId,
        senatorialDistrictName: pu.senatorialDistrictName,
      ),
      GeographicScope(
        level: GeographyLevel.lga,
        country: pu.country,
        zoneId: pu.zoneId,
        zoneName: pu.zoneName,
        stateId: pu.stateId,
        stateName: pu.stateName,
        senatorialDistrictId: pu.senatorialDistrictId,
        senatorialDistrictName: pu.senatorialDistrictName,
        lgaId: pu.lgaId,
        lgaName: pu.lgaName,
      ),
      GeographicScope(
        level: GeographyLevel.ward,
        country: pu.country,
        zoneId: pu.zoneId,
        zoneName: pu.zoneName,
        stateId: pu.stateId,
        stateName: pu.stateName,
        senatorialDistrictId: pu.senatorialDistrictId,
        senatorialDistrictName: pu.senatorialDistrictName,
        lgaId: pu.lgaId,
        lgaName: pu.lgaName,
        wardId: pu.wardId,
        wardName: pu.wardName,
      ),
      pu,
    ];
    for (final scope in candidates) {
      values[_scopeKey(scope)] = scope;
    }
  }
  final result = values.values.toList()
    ..sort((a, b) {
      final levelCompare = a.level.index.compareTo(b.level.index);
      return levelCompare != 0 ? levelCompare : a.label.compareTo(b.label);
    });
  return result;
}

String _scopeKey(GeographicScope scope) => switch (scope.level) {
      GeographyLevel.country => scope.country,
      GeographyLevel.geopoliticalZone => 'z:${scope.zoneId}',
      GeographyLevel.state => 's:${scope.stateId}',
      GeographyLevel.senatorialDistrict => 'sd:${scope.senatorialDistrictId}',
      GeographyLevel.lga => 'l:${scope.lgaId}',
      GeographyLevel.ward => 'w:${scope.wardId}',
      GeographyLevel.pollingUnit => 'p:${scope.pollingUnitId}',
    };

const _assignableRoles = <TgcgRole>[
  TgcgRole.zonalCoordinator,
  TgcgRole.stateCoordinator,
  TgcgRole.lgaCoordinator,
  TgcgRole.wardCoordinator,
  TgcgRole.pollingUnitAgent,
  TgcgRole.observer,
  TgcgRole.legalOfficer,
  TgcgRole.technicalSupport,
];

Color _statusColor(AccreditationStatus status) => switch (status) {
      AccreditationStatus.approved => TgcgColors.success,
      AccreditationStatus.pending => TgcgColors.warning,
      AccreditationStatus.suspended => const Color(0xFFB54708),
      AccreditationStatus.revoked => TgcgColors.danger,
    };

Color _recordStatusColor(RecordStatus status) => switch (status) {
      RecordStatus.verified => TgcgColors.success,
      RecordStatus.submitted => TgcgColors.info,
      RecordStatus.underReview => TgcgColors.ai,
      RecordStatus.disputed || RecordStatus.rejected => TgcgColors.danger,
      _ => TgcgColors.muted,
    };

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty
      ? spaced
      : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
