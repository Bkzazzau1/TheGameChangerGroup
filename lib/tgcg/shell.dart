import 'package:flutter/material.dart';

import 'collation/collation_page.dart';
import 'communications/communications_page.dart';
import 'dashboard_page.dart';
import 'field/field_monitoring_page.dart';
import 'field/situation_room_page.dart';
import 'geography/geography_page.dart';
import 'governance/governance_page.dart';
import 'governance/governance_store.dart';
import 'membership/membership_page.dart';
import 'reports/reports_page.dart';
import 'results/result_capture_page.dart';
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

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final role = session.role!;
    final allowed = allowedModules(role);

    if (!allowed.contains(selectedModule)) {
      selectedModule = TgcgModule.overview;
    }

    final destinations = _allDestinations
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
                  titleSpacing: 6,
                  title: const _CompactBrand(),
                  actions: [
                    _CompactSync(),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Notifications',
                      onPressed: () {},
                      icon: const Icon(Icons.notifications_none_rounded),
                    ),
                    const SizedBox(width: 6),
                  ],
                ),
          drawer: desktop
              ? null
              : Drawer(
                  backgroundColor: TgcgColors.primaryDark,
                  child: SafeArea(
                    child: _Navigation(
                      destinations: destinations,
                      selectedModule: selectedModule,
                      onSelect: (module) {
                        _select(module);
                        Navigator.pop(context);
                      },
                    ),
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
                          _CommandBar(selectedModule: selectedModule),
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
        TgcgModule.accreditation => const MembershipPage(),
        TgcgModule.geography => const GeographyPage(),
        TgcgModule.fieldMonitoring => const FieldMonitoringPage(),
        TgcgModule.situationRoom => const SituationRoomPage(),
        TgcgModule.resultCapture => const ResultCapturePage(),
        TgcgModule.collation => const CollationPage(),
        TgcgModule.communications => const CommunicationsPage(),
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

const _allDestinations = <_Destination>[
  _Destination(
    TgcgModule.overview,
    'Command Overview',
    Icons.space_dashboard_outlined,
    _NavGroup.command,
  ),
  _Destination(
    TgcgModule.situationRoom,
    'Situation Room',
    Icons.radar_rounded,
    _NavGroup.command,
  ),
  _Destination(
    TgcgModule.geography,
    'Geographic Operations',
    Icons.public_rounded,
    _NavGroup.command,
  ),
  _Destination(
    TgcgModule.accreditation,
    'Accreditation',
    Icons.badge_outlined,
    _NavGroup.fieldOperations,
  ),
  _Destination(
    TgcgModule.fieldMonitoring,
    'Field Monitoring',
    Icons.sensors_outlined,
    _NavGroup.fieldOperations,
  ),
  _Destination(
    TgcgModule.resultCapture,
    'Result Capture',
    Icons.ballot_outlined,
    _NavGroup.fieldOperations,
  ),
  _Destination(
    TgcgModule.collation,
    'Collation',
    Icons.account_tree_outlined,
    _NavGroup.fieldOperations,
  ),
  _Destination(
    TgcgModule.communications,
    'Communications',
    Icons.forum_outlined,
    _NavGroup.coordination,
  ),
  _Destination(
    TgcgModule.reports,
    'Reports & Exports',
    Icons.description_outlined,
    _NavGroup.control,
  ),
  _Destination(
    TgcgModule.governance,
    'Data & Governance',
    Icons.shield_outlined,
    _NavGroup.control,
  ),
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
                    ? const Border(
                        left: BorderSide(color: TgcgColors.accent, width: 3),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    size: 19,
                    color: active ? Colors.white : const Color(0xFFA9BBB5),
                  ),
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
                  child: const Icon(
                    Icons.person_outline_rounded,
                    color: TgcgColors.accent,
                    size: 19,
                  ),
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
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        roleLabel(session.role!),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFA5B8B1),
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Sign out',
                  onPressed: session.signOut,
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.logout_rounded,
                    color: Color(0xFFA5B8B1),
                    size: 18,
                  ),
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
  const _CommandBar({required this.selectedModule});

  final TgcgModule selectedModule;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final governance = GovernanceOperations.of(context);
    final pending = governance.pendingOutbox.length;

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
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TextField(
                readOnly: true,
                decoration: const InputDecoration(
                  hintText: 'Search agents, polling units, incidents or results',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                ),
                onTap: () {},
              ),
            ),
          ),
          const Spacer(),
          const TgcgStatusPill(
            label: 'DEMO ENVIRONMENT',
            color: TgcgColors.warning,
            icon: Icons.science_outlined,
            compact: true,
          ),
          const SizedBox(width: 8),
          TgcgStatusPill(
            label: pending == 0 ? 'SYNCED' : '$pending TO SYNC',
            color: pending == 0 ? TgcgColors.success : TgcgColors.warning,
            icon: pending == 0 ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
            compact: true,
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {},
            icon: const Badge(
              smallSize: 7,
              child: Icon(Icons.notifications_none_rounded),
            ),
          ),
          const SizedBox(width: 4),
          Tooltip(
            message: '${roleLabel(session.role!)} • ${session.scope.label}',
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: TgcgColors.primarySoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Icon(Icons.person_outline_rounded, color: TgcgColors.primary, size: 19),
            ),
          ),
        ],
      ),
    );
  }
}

class _CompactSync extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final pending = GovernanceOperations.of(context).pendingOutbox.length;
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
  Widget build(BuildContext context) => Row(
        children: [
          const _BrandMark(),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'TGCG-EMCOP',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'National Operations',
                  style: TextStyle(color: Color(0xFF8EA49D), fontSize: 9.5),
                ),
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
          _BrandMark(size: 36),
          SizedBox(width: 8),
          Text(
            'TGCG-EMCOP',
            style: TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.ink),
          ),
        ],
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 39});

  final double size;

  @override
  Widget build(BuildContext context) => TgcgLogo(size: size);
}

String _groupLabel(_NavGroup group) => switch (group) {
      _NavGroup.command => 'COMMAND',
      _NavGroup.fieldOperations => 'FIELD OPERATIONS',
      _NavGroup.coordination => 'COORDINATION',
      _NavGroup.control => 'CONTROL',
    };

String _moduleLabel(TgcgModule module) => switch (module) {
      TgcgModule.overview => 'Command Overview',
      TgcgModule.accreditation => 'Accreditation',
      TgcgModule.geography => 'Geographic Operations',
      TgcgModule.fieldMonitoring => 'Field Monitoring',
      TgcgModule.situationRoom => 'Situation Room',
      TgcgModule.resultCapture => 'Result Capture',
      TgcgModule.collation => 'Collation',
      TgcgModule.communications => 'Communications',
      TgcgModule.reports => 'Reports & Exports',
      TgcgModule.governance => 'Data & Governance',
    };
