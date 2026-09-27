import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/models.dart';
import '../domain/permissions.dart';
import '../geography/geography_registry.dart';
import '../session.dart';
import 'membership_store.dart';

class MembershipPage extends StatefulWidget {
  const MembershipPage({super.key});

  @override
  State<MembershipPage> createState() => _MembershipPageState();
}

class _MembershipPageState extends State<MembershipPage> {
  String query = '';
  AccreditationStatus? statusFilter;

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

    final members = store.members
        .where((member) =>
            query.trim().isEmpty ||
            member.fullName.toLowerCase().contains(query.trim().toLowerCase()) ||
            member.phoneNumber.contains(query.trim()) ||
            (member.membershipNumber ?? '').toLowerCase().contains(query.trim().toLowerCase()))
        .toList(growable: false);
    final agents = store.agents
        .where((agent) => statusFilter == null || agent.status == statusFilter)
        .toList(growable: false);
    final approved = store.agents.where((a) => a.status == AccreditationStatus.approved).length;
    final trained = store.agents.where((a) => a.trainingCompleted).length;
    final biometrics = store.agents.where((a) => a.biometricEnrolled).length;
    final boundDevices = store.agents.where((a) => a.deviceId != null).length;

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Membership & Accreditation',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: TgcgApp.ink,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Register members, issue agent identities, assign canonical geography and track election-day readiness.',
                    style: TextStyle(color: TgcgApp.muted, height: 1.5),
                  ),
                ],
              ),
            ),
            if (canCreateMember || canAccredit)
              Wrap(
                spacing: 8,
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
          ],
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric('Members', '${store.members.length}', Icons.groups_2_outlined),
            _Metric('Approved agents', '$approved', Icons.verified_user_outlined),
            _Metric('Training complete', '$trained', Icons.school_outlined),
            _Metric('Biometric enrolled', '$biometrics', Icons.face_retouching_natural_outlined),
            _Metric('Device bound', '$boundDevices', Icons.phonelink_lock_outlined),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final memberPanel = _MemberPanel(
              members: members,
              query: query,
              onQueryChanged: (value) => setState(() => query = value),
            );
            final agentPanel = _AgentPanel(
              agents: agents,
              statusFilter: statusFilter,
              canManage: canAccredit,
              onStatusFilterChanged: (value) => setState(() => statusFilter = value),
            );
            if (constraints.maxWidth < 980) {
              return Column(
                children: [
                  memberPanel,
                  const SizedBox(height: 14),
                  agentPanel,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 4, child: memberPanel),
                const SizedBox(width: 14),
                Expanded(flex: 6, child: agentPanel),
              ],
            );
          },
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
      builder: (context) => AlertDialog(
        title: const Text('Register member'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Full name')),
              const SizedBox(height: 10),
              TextField(controller: phone, decoration: const InputDecoration(labelText: 'Phone number')),
              const SizedBox(height: 10),
              TextField(controller: email, decoration: const InputDecoration(labelText: 'Email (optional)')),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (name.text.trim().isEmpty || phone.text.trim().isEmpty) return;
              store.createMember(
                fullName: name.text,
                phoneNumber: phone.text,
                email: email.text,
              );
              Navigator.pop(context, true);
            },
            child: const Text('Register'),
          ),
        ],
      ),
    );
    name.dispose();
    phone.dispose();
    email.dispose();
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member registered in the local prototype store.')),
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
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Accredit agent'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: memberId,
                    decoration: const InputDecoration(labelText: 'Member'),
                    items: store.members
                        .map((member) => DropdownMenuItem(
                              value: member.id,
                              child: Text('${member.fullName} • ${member.membershipNumber ?? member.id}'),
                            ))
                        .toList(),
                    onChanged: (value) => setDialogState(() => memberId = value ?? memberId),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<TgcgRole>(
                    initialValue: role,
                    decoration: const InputDecoration(labelText: 'Operational role'),
                    items: _assignableRoles
                        .map((value) => DropdownMenuItem(value: value, child: Text(roleLabel(value))))
                        .toList(),
                    onChanged: (value) => setDialogState(() => role = value ?? role),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<GeographicScope>(
                    initialValue: scope,
                    decoration: const InputDecoration(labelText: 'Canonical geographic assignment'),
                    items: scopes
                        .map((value) => DropdownMenuItem(value: value, child: Text(value.label)))
                        .toList(),
                    onChanged: (value) => setDialogState(() => scope = value ?? scope),
                  ),
                  const SizedBox(height: 10),
                  TextField(controller: phone, decoration: const InputDecoration(labelText: 'Registered phone')),
                  const SizedBox(height: 10),
                  TextField(controller: device, decoration: const InputDecoration(labelText: 'Device ID (optional)')),
                  const SizedBox(height: 10),
                  TextField(controller: sim, decoration: const InputDecoration(labelText: 'SIM binding ID (optional)')),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                store.accredit(
                  memberId: memberId,
                  role: role,
                  scope: scope,
                  phoneNumber: phone.text,
                  deviceId: device.text,
                  simFingerprint: sim.text,
                );
                Navigator.pop(context, true);
              },
              child: const Text('Create accreditation'),
            ),
          ],
        ),
      ),
    );
    phone.dispose();
    device.dispose();
    sim.dispose();
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Accreditation created as pending review.')),
      );
    }
  }
}

class _MemberPanel extends StatelessWidget {
  const _MemberPanel({
    required this.members,
    required this.query,
    required this.onQueryChanged,
  });

  final List<TgcgMember> members;
  final String query;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Member registry',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
              const SizedBox(height: 4),
              const Text('Identity records eligible for operational accreditation.',
                  style: TextStyle(fontSize: 11, color: TgcgApp.muted)),
              const SizedBox(height: 12),
              TextField(
                onChanged: onQueryChanged,
                decoration: const InputDecoration(
                  labelText: 'Search members',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const SizedBox(height: 12),
              if (members.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No matching members.')),
                )
              else
                ...members.map((member) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: TgcgApp.primary.withValues(alpha: .08),
                        child: Text(member.fullName.isEmpty ? '?' : member.fullName[0]),
                      ),
                      title: Text(member.fullName,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text('${member.membershipNumber ?? member.id} • ${member.phoneNumber}'),
                      trailing: _Pill(_label(member.status.name), TgcgApp.primary),
                    )),
            ],
          ),
        ),
      );
}

class _AgentPanel extends StatelessWidget {
  const _AgentPanel({
    required this.agents,
    required this.statusFilter,
    required this.canManage,
    required this.onStatusFilterChanged,
  });

  final List<AccreditedAgent> agents;
  final AccreditationStatus? statusFilter;
  final bool canManage;
  final ValueChanged<AccreditationStatus?> onStatusFilterChanged;

  @override
  Widget build(BuildContext context) {
    final store = MembershipOperations.of(context, listen: false);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Accredited field network',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                      SizedBox(height: 4),
                      Text('Role, scope, training and device-readiness records.',
                          style: TextStyle(fontSize: 11, color: TgcgApp.muted)),
                    ],
                  ),
                ),
                SizedBox(
                  width: 175,
                  child: DropdownButtonFormField<AccreditationStatus?>(
                    initialValue: statusFilter,
                    decoration: const InputDecoration(labelText: 'Status'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All')),
                      ...AccreditationStatus.values.map(
                        (value) => DropdownMenuItem(value: value, child: Text(_label(value.name))),
                      ),
                    ],
                    onChanged: onStatusFilterChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (agents.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No agents match this filter.')),
              )
            else
              ...agents.map((agent) {
                final member = store.memberById(agent.memberId);
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAF9),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE2E8E5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(member?.fullName ?? agent.memberId,
                                    style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                                const SizedBox(height: 3),
                                Text('${agent.agentId} • ${roleLabel(agent.role)}',
                                    style: const TextStyle(fontSize: 11, color: TgcgApp.muted)),
                              ],
                            ),
                          ),
                          _Pill(_label(agent.status.name), _statusColor(agent.status)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(agent.scope.label,
                          style: const TextStyle(fontWeight: FontWeight.w700, color: TgcgApp.primary)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 7,
                        runSpacing: 7,
                        children: [
                          _Pill(agent.trainingCompleted ? 'Training complete' : 'Training pending',
                              agent.trainingCompleted ? TgcgApp.primary : const Color(0xFF9A6700)),
                          _Pill(agent.biometricEnrolled ? 'Biometric enrolled' : 'Biometric pending',
                              agent.biometricEnrolled ? TgcgApp.primary : const Color(0xFF9A6700)),
                          _Pill(agent.deviceId == null ? 'Device unbound' : 'Device bound',
                              agent.deviceId == null ? const Color(0xFF9A6700) : TgcgApp.primary),
                          _Pill(agent.simFingerprint == null ? 'SIM unbound' : 'SIM bound',
                              agent.simFingerprint == null ? const Color(0xFF9A6700) : TgcgApp.primary),
                        ],
                      ),
                      if (canManage) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            PopupMenuButton<AccreditationStatus>(
                              tooltip: 'Change accreditation status',
                              onSelected: (value) => store.updateAccreditationStatus(agent.id, value),
                              itemBuilder: (_) => AccreditationStatus.values
                                  .map((status) => PopupMenuItem(
                                        value: status,
                                        child: Text(_label(status.name)),
                                      ))
                                  .toList(),
                              child: const Text('Update status',
                                  style: TextStyle(color: TgcgApp.primary, fontWeight: FontWeight.w800)),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 205,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(15),
            child: Row(
              children: [
                Icon(icon, color: TgcgApp.primary),
                const SizedBox(width: 11),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                    Text(label, style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
}

class _PrivacyPanel extends StatelessWidget {
  const _PrivacyPanel();

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.privacy_tip_outlined, color: TgcgApp.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Identity and biometric handling',
                        style: TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                    const SizedBox(height: 5),
                    const Text(
                      'This Flutter prototype stores only biometric-enrollment readiness, not raw face templates. Production biometric processing, consent records, encryption and retention controls belong in the secured backend and biometric service boundary.',
                      style: TextStyle(color: TgcgApp.muted, height: 1.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

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

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w900, color: color)),
      );
}

Color _statusColor(AccreditationStatus status) => switch (status) {
      AccreditationStatus.approved => TgcgApp.primary,
      AccreditationStatus.pending => const Color(0xFF9A6700),
      AccreditationStatus.suspended => const Color(0xFFB54708),
      AccreditationStatus.revoked => const Color(0xFFB42318),
    };

String _label(String value) {
  final spaced = value.replaceAllMapped(
    RegExp(r'([a-z])([A-Z])'),
    (match) => '${match.group(1)} ${match.group(2)}',
  );
  return spaced.isEmpty ? spaced : '${spaced[0].toUpperCase()}${spaced.substring(1)}';
}
