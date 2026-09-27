import 'package:flutter/material.dart';

import 'app.dart';
import 'collation/collation_page.dart';
import 'communications/communications_page.dart';
import 'dashboard_page.dart';
import 'domain/models.dart';
import 'field/field_monitoring_page.dart';
import 'field/situation_room_page.dart';
import 'geography/geography_page.dart';
import 'governance/governance_page.dart';
import 'membership/membership_page.dart';
import 'reports/reports_page.dart';
import 'results/result_capture_page.dart';
import 'session.dart';

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
        final wide = constraints.maxWidth >= 1040;
        return Scaffold(
          appBar: wide
              ? null
              : AppBar(
                  backgroundColor: Colors.white,
                  surfaceTintColor: Colors.white,
                  title: const _CompactBrand(),
                  actions: [
                    _RoleChip(role: role),
                    const SizedBox(width: 8),
                  ],
                ),
          drawer: wide
              ? null
              : Drawer(
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
          body: wide
              ? Row(
                  children: [
                    SizedBox(
                      width: 292,
                      child: _Navigation(
                        destinations: destinations,
                        selectedModule: selectedModule,
                        onSelect: _select,
                      ),
                    ),
                    Expanded(child: _pageFor(selectedModule)),
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

class _Destination {
  const _Destination(this.module, this.label, this.icon);
  final TgcgModule module;
  final String label;
  final IconData icon;
}

const _allDestinations = <_Destination>[
  _Destination(TgcgModule.overview, 'Command Overview', Icons.dashboard_rounded),
  _Destination(TgcgModule.accreditation, 'Accreditation', Icons.badge_outlined),
  _Destination(TgcgModule.geography, 'Geographic Operations', Icons.map_outlined),
  _Destination(TgcgModule.fieldMonitoring, 'Field Monitoring', Icons.radar_rounded),
  _Destination(
    TgcgModule.situationRoom,
    'Situation Room',
    Icons.dashboard_customize_outlined,
  ),
  _Destination(TgcgModule.resultCapture, 'Result Capture', Icons.ballot_outlined),
  _Destination(TgcgModule.collation, 'Collation', Icons.account_tree_outlined),
  _Destination(
    TgcgModule.communications,
    'Communications',
    Icons.chat_bubble_outline_rounded,
  ),
  _Destination(TgcgModule.reports, 'Reports', Icons.description_outlined),
  _Destination(
    TgcgModule.governance,
    'Data & Governance',
    Icons.admin_panel_settings_outlined,
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
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE1E7E4))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(18, 20, 18, 16),
              child: _Brand(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F8F6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE1E9E5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.operatorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TgcgApp.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      roleLabel(session.role!),
                      style: const TextStyle(
                        color: TgcgApp.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      session.scope.label,
                      style: const TextStyle(
                        color: TgcgApp.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                itemCount: destinations.length,
                itemBuilder: (context, index) {
                  final item = destinations[index];
                  final active = item.module == selectedModule;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ListTile(
                      dense: true,
                      selected: active,
                      selectedTileColor: const Color(0xFFE8F1EE),
                      selectedColor: TgcgApp.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(item.icon, size: 21),
                      title: Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              active ? FontWeight.w900 : FontWeight.w700,
                        ),
                      ),
                      onTap: () => onSelect(item.module),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: session.signOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) => const Row(
        children: [
          _BrandMark(),
          SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TGCG-EMCOP',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: TgcgApp.ink,
                    letterSpacing: .4,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'National Operations',
                  style: TextStyle(fontSize: 11, color: TgcgApp.muted),
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
        children: [
          _BrandMark(size: 34),
          SizedBox(width: 9),
          Text(
            'TGCG-EMCOP',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: TgcgApp.ink,
            ),
          ),
        ],
      );
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({this.size = 42});
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: TgcgApp.primary,
          borderRadius: BorderRadius.circular(size * .3),
        ),
        child: Icon(
          Icons.hub_rounded,
          color: Colors.white,
          size: size * .52,
        ),
      );
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final TgcgRole role;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(maxWidth: 175),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F1EE),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          roleLabel(role),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: TgcgApp.primary,
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}
