import 'package:flutter/material.dart';

import '../app.dart';
import '../domain/models.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import 'geography_registry.dart';

class GeographyPage extends StatefulWidget {
  const GeographyPage({super.key});

  @override
  State<GeographyPage> createState() => _GeographyPageState();
}

class _GeographyPageState extends State<GeographyPage> {
  final List<GeographicScope> path = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (path.isEmpty) {
      path.add(TgcgSession.of(context, listen: false).scope);
    }
  }

  @override
  Widget build(BuildContext context) {
    final membership = MembershipOperations.of(context);
    final registry = membership.geography;
    final scope = path.last;
    final children = registry.childScopes(scope);
    final units = registry.pollingUnitsWithin(scope);
    final agents = membership.agentsForScope(scope);
    final approvedAgents = agents.where((a) => a.status == AccreditationStatus.approved).toList();
    final assignedUnits = membership.assignedPollingUnitsWithin(scope);
    final coverage = units.isEmpty ? 0.0 : assignedUnits / units.length;

    return ListView(
      padding: const EdgeInsets.all(28),
      children: [
        const Text(
          'Geographic Operations',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: TgcgApp.ink),
        ),
        const SizedBox(height: 7),
        Text(
          '${scope.label}: canonical operational hierarchy, polling-unit registry and agent assignment coverage.',
          style: const TextStyle(color: TgcgApp.muted, height: 1.5),
        ),
        const SizedBox(height: 14),
        _Breadcrumbs(
          path: path,
          onSelect: (index) => setState(() => path.removeRange(index + 1, path.length)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric('Polling units', '${units.length}', Icons.location_on_outlined),
            _Metric('Assigned PUs', '$assignedUnits', Icons.assignment_ind_outlined),
            _Metric('Approved agents', '${approvedAgents.length}', Icons.verified_user_outlined),
            _Metric('Assignment coverage', '${(coverage * 100).toStringAsFixed(1)}%', Icons.donut_large_rounded),
          ],
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Polling-unit assignment coverage',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: coverage.clamp(0, 1),
                  minHeight: 9,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: const Color(0xFFE4EAE7),
                ),
                const SizedBox(height: 8),
                Text(
                  '$assignedUnits of ${units.length} polling units in this prototype scope currently have at least one approved polling-unit agent.',
                  style: const TextStyle(color: TgcgApp.muted, height: 1.45),
                ),
              ],
            ),
          ),
        ),
        if (children.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Panel(
            title: 'Geographic drill-down',
            subtitle: 'Navigate the canonical hierarchy without free-text geography.',
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: children.map((child) {
                final childUnits = registry.pollingUnitsWithin(child);
                final childAssigned = membership.assignedPollingUnitsWithin(child);
                return _ScopeCard(
                  scope: child,
                  pollingUnitCount: childUnits.length,
                  assignedCount: childAssigned,
                  onOpen: () => setState(() => path.add(child)),
                );
              }).toList(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final puPanel = _PollingUnitPanel(
              registry: registry,
              units: units,
              membership: membership,
            );
            final agentPanel = _ScopeAgentPanel(agents: agents);
            if (constraints.maxWidth < 940) {
              return Column(children: [puPanel, const SizedBox(height: 14), agentPanel]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: puPanel),
                const SizedBox(width: 14),
                Expanded(flex: 4, child: agentPanel),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _Breadcrumbs extends StatelessWidget {
  const _Breadcrumbs({required this.path, required this.onSelect});
  final List<GeographicScope> path;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (var index = 0; index < path.length; index++) ...[
            TextButton(
              onPressed: index == path.length - 1 ? null : () => onSelect(index),
              child: Text(path[index].label),
            ),
            if (index != path.length - 1)
              const Icon(Icons.chevron_right_rounded, size: 18, color: TgcgApp.muted),
          ],
        ],
      );
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({
    required this.scope,
    required this.pollingUnitCount,
    required this.assignedCount,
    required this.onOpen,
  });

  final GeographicScope scope;
  final int pollingUnitCount;
  final int assignedCount;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 280,
        child: InkWell(
          onTap: onOpen,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAF9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE1E8E5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(scope.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: TgcgApp.muted),
                  ],
                ),
                const SizedBox(height: 8),
                Text('$pollingUnitCount PUs • $assignedCount assigned',
                    style: const TextStyle(fontSize: 11, color: TgcgApp.muted)),
              ],
            ),
          ),
        ),
      );
}

class _PollingUnitPanel extends StatelessWidget {
  const _PollingUnitPanel({
    required this.registry,
    required this.units,
    required this.membership,
  });

  final GeographyRegistry registry;
  final List<CanonicalPollingUnit> units;
  final MembershipOperationsController membership;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Canonical polling units',
        subtitle: 'Operational records must reference these identifiers rather than free-text locations.',
        child: units.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 22),
                child: Center(child: Text('No polling units are available in this scope.')),
              )
            : Column(
                children: units.map((unit) {
                  final assigned = membership.agentsForScope(unit.scope)
                      .where((agent) =>
                          agent.role == TgcgRole.pollingUnitAgent &&
                          agent.status == AccreditationStatus.approved &&
                          agent.scope.pollingUnitId == unit.scope.pollingUnitId)
                      .toList(growable: false);
                  return Container(
                    margin: const EdgeInsets.only(bottom: 9),
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAF9),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: const Color(0xFFE2E8E5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.location_on_outlined, color: TgcgApp.primary),
                        const SizedBox(width: 11),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(unit.scope.label,
                                  style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgApp.ink)),
                              const SizedBox(height: 3),
                              Text(
                                '${unit.code}${unit.registeredVoters == null ? '' : ' • ${unit.registeredVoters} registered voters'}',
                                style: const TextStyle(fontSize: 10.5, color: TgcgApp.muted),
                              ),
                            ],
                          ),
                        ),
                        _Pill(
                          assigned.isEmpty ? 'Unassigned' : '${assigned.length} approved agent${assigned.length == 1 ? '' : 's'}',
                          assigned.isEmpty ? const Color(0xFF9A6700) : TgcgApp.primary,
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      );
}

class _ScopeAgentPanel extends StatelessWidget {
  const _ScopeAgentPanel({required this.agents});
  final List<AccreditedAgent> agents;

  @override
  Widget build(BuildContext context) {
    final store = MembershipOperations.of(context, listen: false);
    return _Panel(
      title: 'Agents in scope',
      subtitle: 'Accredited operational personnel assigned within this geography.',
      child: agents.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 22),
              child: Center(child: Text('No accredited agents in this scope.')),
            )
          : Column(
              children: agents.map((agent) {
                final member = store.memberById(agent.memberId);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(roleIcon(agent.role), color: TgcgApp.primary),
                  title: Text(member?.fullName ?? agent.memberId,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text('${roleLabel(agent.role)} • ${agent.scope.label}'),
                  trailing: _Pill(_label(agent.status.name), _statusColor(agent.status)),
                );
              }).toList(),
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
        width: 215,
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

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.subtitle, required this.child});
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: TgcgApp.ink)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: TgcgApp.muted)),
              const SizedBox(height: 14),
              child,
            ],
          ),
        ),
      );
}

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
