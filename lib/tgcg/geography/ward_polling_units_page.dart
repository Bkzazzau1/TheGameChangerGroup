import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../api/reference_repository.dart';
import '../domain/permissions.dart';
import '../field/incident_report.dart';
import '../membership/polling_unit_members_page.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

/// Who may find members in their areas, as on the server (`MEMBER_READERS`).
const memberReaders = [
  TgcgCapability.manageMembership,
  TgcgCapability.registerMembers,
  TgcgCapability.accreditAgents,
  TgcgCapability.manageAgentAssignments,
  TgcgCapability.verifyMemberIdentity,
  TgcgCapability.suspendMembers,
  TgcgCapability.viewMemberSensitiveData,
];

bool canFindMembers(TgcgSessionController session) => session.canAny(memberReaders);

/// INEC names are upper case; show them in title case.
String titleCaseName(String name) => name
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

/// Opens a ward's polling units, with the members registered at each for
/// those who may find members there, and the open [incidents] reported at
/// each when given.
Future<void> openWardPollingUnits(
  BuildContext context, {
  required String code,
  required String name,
  List<FieldIncident>? incidents,
}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => WardPollingUnitsPage(code: code, name: name, incidents: incidents),
      ),
    );

class WardPollingUnitsPage extends StatefulWidget {
  const WardPollingUnitsPage({
    super.key,
    required this.code,
    required this.name,
    this.incidents,
  });

  /// INEC ward code, e.g. 18-23-05.
  final String code;
  final String name;

  /// Incidents to show at the ward's polling units; only this ward's open
  /// ones show.
  final List<FieldIncident>? incidents;

  @override
  State<WardPollingUnitsPage> createState() => _WardPollingUnitsPageState();
}

class _WardPollingUnitsPageState extends State<WardPollingUnitsPage> {
  Future<(List<ServerPollingUnit>, MemberCounts?)>? _data;

  /// The ward's open incidents, most severe first.
  late final List<FieldIncident> _open = [
    for (final incident in widget.incidents ?? const <FieldIncident>[])
      if (incident.scope.wardId == widget.code && isOpenIncident(incident)) incident,
  ]..sort((a, b) => incidentSeverityRank(b.severity).compareTo(incidentSeverityRank(a.severity)));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _data ??= _load();
  }

  Future<(List<ServerPollingUnit>, MemberCounts?)> _load() async {
    final backend = TgcgBackend.of(context);
    if (backend == null) return (const <ServerPollingUnit>[], null);
    final counts = canFindMembers(TgcgSession.of(context, listen: false))
        ? backend.members
              .counts(level: GeographyLevel.ward, code: widget.code, by: GeographyLevel.pollingUnit)
              // A ward outside the account's area has no numbers to show.
              .then<MemberCounts?>((value) => value, onError: (Object _) => null)
        : Future<MemberCounts?>.value();
    final units = await backend.reference.pollingUnitsWithin(
      GeographicScope(level: GeographyLevel.ward, country: 'Nigeria', wardId: widget.code),
    );
    return (units, await counts);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: TgcgColors.canvas,
    appBar: AppBar(title: Text('${titleCaseName(widget.name)} ward')),
    body: FutureBuilder<(List<ServerPollingUnit>, MemberCounts?)>(
      future: _data,
      builder: (context, snapshot) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          // Reports come first: they are known before the polling units load.
          if (_open.isNotEmpty) ..._incidents(),
          ..._pollingUnits(snapshot),
        ],
      ),
    ),
  );

  /// The open incidents, by polling unit; those for the ward as a whole first.
  List<Widget> _incidents() {
    final byUnit = <String?, List<FieldIncident>>{};
    for (final incident in _open) {
      byUnit.putIfAbsent(incident.scope.pollingUnitId, () => []).add(incident);
    }
    final units = byUnit.keys.toList()
      ..sort((a, b) => a == null ? -1 : (b == null ? 1 : a.compareTo(b)));
    return [
      Text(
        'OPEN INCIDENTS (${_open.length})',
        style: const TextStyle(
          color: TgcgColors.muted,
          fontSize: 10.5,
          fontWeight: FontWeight.w900,
          letterSpacing: .6,
        ),
      ),
      const SizedBox(height: 8),
      for (final unit in units) ...[
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            unit == null
                ? 'Whole ward'
                : '${titleCaseName(byUnit[unit]!.first.scope.pollingUnitName ?? unit)} • $unit',
            style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900),
          ),
        ),
        for (final incident in byUnit[unit]!) IncidentReportLine(incident: incident),
      ],
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _pollingUnits(
    AsyncSnapshot<(List<ServerPollingUnit>, MemberCounts?)> snapshot,
  ) {
    if (snapshot.hasError) {
      final error = snapshot.error;
      return [
        Padding(
          padding: const EdgeInsets.all(8),
          child: TgcgEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load polling units',
            message: error is ApiException ? error.message : '$error',
            action: TextButton(
              onPressed: () => setState(() => _data = _load()),
              child: const Text('Try again'),
            ),
          ),
        ),
      ];
    }
    if (!snapshot.hasData) {
      return const [
        Padding(
          padding: EdgeInsets.all(32),
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final (units, counts) = snapshot.data!;
    return [
      Text(
        '${widget.code} • ${units.length} polling unit${units.length == 1 ? '' : 's'}'
        '${counts == null ? '' : ' • ${_members(counts.total)}'}',
        style: const TextStyle(color: TgcgColors.muted, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      Material(
        color: TgcgColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: TgcgColors.border),
        ),
        child: Column(
          children: [
            for (final (index, unit) in units.indexed) ...[
              if (index > 0) const Divider(height: 1, color: TgcgColors.border),
              ListTile(
                title: Text(
                  titleCaseName(unit.name),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(
                  '${unit.code}'
                  '${unit.registeredVoters == null ? '' : ' • ${unit.registeredVoters} voters'}',
                  style: const TextStyle(fontSize: 11.5, color: TgcgColors.muted),
                ),
                trailing: _trailing(unit, counts),
                onTap: counts == null
                    ? null
                    : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              PollingUnitMembersPage(code: unit.code, name: unit.name),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    ];
  }

  Widget? _trailing(ServerPollingUnit unit, MemberCounts? counts) {
    final open = _open.where((incident) => incident.scope.pollingUnitId == unit.code).toList();
    final members = counts == null
        ? null
        : Text(
            _members(counts[unit.code]),
            style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.primary),
          );
    if (open.isEmpty) return members;
    final pill = TgcgStatusPill(
      label: '${open.length} OPEN',
      color: incidentSeverityColor(open.first.severity),
      compact: true,
    );
    if (members == null) return pill;
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [pill, const SizedBox(height: 4), members],
    );
  }
}

String _members(int count) => '$count member${count == 1 ? '' : 's'}';
