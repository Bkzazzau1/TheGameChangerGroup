import 'dart:async';

import 'package:flutter/material.dart';

import '../api/api_client.dart';
import '../api/backend.dart';
import '../api/tracking_repository.dart';
import '../geography/geography_registry.dart';
import '../geography/lga_ward_map_dialog.dart';
import '../geography/lga_wards.dart';
import '../geography/nigeria_map.dart';
import '../geography/ward_polling_units_page.dart';
import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

/// Where on-duty agents are, and who has checked in at their polling unit today.
class AgentsOnGroundPage extends StatefulWidget {
  const AgentsOnGroundPage({super.key, this.refreshEvery = const Duration(minutes: 1)});

  final Duration refreshEvery;

  @override
  State<AgentsOnGroundPage> createState() => _AgentsOnGroundPageState();
}

/// An area the user has opened from the breakdown; the first is their own scope.
class _Area {
  const _Area(this.level, this.code, this.name);
  final GeographyLevel? level;
  final String? code;
  final String name;
}

class _AgentsOnGroundPageState extends State<AgentsOnGroundPage> {
  final _trail = <_Area>[const _Area(null, null, 'My area')];
  Future<(LiveAgents, Coverage)>? _data;
  DateTime? _updatedAt;
  Timer? _timer;

  // The map's geometry, kept per area so refreshes do not reload it.
  String? _geometryKey;
  Future<(GeoShapeSet, List<String>)>? _geometry;
  Future<GeoShapeSet>? _shapes;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_data == null && TgcgBackend.of(context) != null) {
      _load();
      _timer = Timer.periodic(widget.refreshEvery, (_) {
        if (mounted) setState(_load);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _load() {
    final tracking = TgcgBackend.of(context)!.tracking;
    final area = _trail.last;
    _data = Future.wait([
      tracking.live(level: area.level, code: area.code),
      tracking.coverage(level: area.level, code: area.code),
    ]).then((results) {
      if (mounted) setState(() => _updatedAt = DateTime.now());
      return (results[0] as LiveAgents, results[1] as Coverage);
    });
  }

  void _open(_Area area) => setState(() {
        _trail.add(area);
        _load();
      });

  void _backTo(int index) => setState(() {
        _trail.removeRange(index + 1, _trail.length);
        _load();
      });

  void _ensureGeometry(GeographicScope scope, GeographyRegistry registry) {
    final key = '${scope.level.name}:${scope.lgaId}:${scope.wardId}:${scope.stateId}:'
        '${scope.senatorialDistrictId}:${scope.zoneId}';
    if (key == _geometryKey) return;
    _geometryKey = key;
    _geometry = agentMapGeometry(scope, registry);
    _shapes = _geometry!.then((value) => value.$1);
  }

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (TgcgBackend.of(context) == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: TgcgEmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Connect to the TGCG server',
            message: 'Agents send their positions to the server. Sign in with a server account '
                'to see them.',
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TgcgPageHeader(
          eyebrow: 'ELECTION DAY',
          title: 'Agents on the Ground',
          subtitle: '${session.scope.label}: where on-duty agents are, and who has checked in '
              'at their polling unit today.',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_updatedAt != null)
                Text(
                  'Updated ${_clock(_updatedAt!)}',
                  style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: () => setState(_load),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),
        if (_trail.length > 1) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (var i = 0; i < _trail.length; i++) ...[
                if (i > 0) const Icon(Icons.chevron_right_rounded, size: 18, color: TgcgColors.muted),
                ActionChip(
                  label: Text(_trail[i].name),
                  onPressed: i == _trail.length - 1 ? null : () => _backTo(i),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 16),
        FutureBuilder<(LiveAgents, Coverage)>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final error = snapshot.error;
              return TgcgEmptyState(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load agents',
                message: error is ApiException ? error.message : '$error',
                action: TextButton(onPressed: () => setState(_load), child: const Text('Try again')),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final (live, coverage) = snapshot.data!;
            _ensureGeometry(coverage.scope, MembershipOperations.of(context).geography);
            return _Body(
              live: live,
              coverage: coverage,
              geometry: _geometry!,
              shapes: _shapes!,
              onOpen: (area) => _open(_Area(area.level, area.code, area.name)),
            );
          },
        ),
      ],
    );
  }
}

/// The map to draw for an area, and the shapes to zoom to.
///
/// Country and zone show states; a state or senatorial district shows LGAs;
/// an LGA, ward or unit shows wards where GRID3 publishes them (else the LGA).
Future<(GeoShapeSet, List<String>)> agentMapGeometry(
  GeographicScope scope,
  GeographyRegistry registry,
) async {
  final stateId = scope.stateId;
  switch (scope.level) {
    case GeographyLevel.country:
      return (await GeoShapeSet.nigeriaStates(), const <String>[]);
    case GeographyLevel.geopoliticalZone:
      return (
        await GeoShapeSet.nigeriaStates(),
        [for (final state in registry.states) if (state.zoneId == scope.zoneId) state.id],
      );
    case GeographyLevel.state:
      return (await GeoShapeSet.lgasOf(stateId!), const <String>[]);
    case GeographyLevel.senatorialDistrict:
      return (
        await GeoShapeSet.lgasOf(stateId!),
        [for (final lga in registry.lgasForDistrict(scope.senatorialDistrictId!)) lga.id],
      );
    case GeographyLevel.lga:
    case GeographyLevel.ward:
    case GeographyLevel.pollingUnit:
      GeoShapeSet? wards;
      try {
        wards = (await LgaWards.load(scope.lgaId!)).shapes;
      } catch (_) {
        wards = null;
      }
      if (wards != null) {
        final ward = scope.wardId;
        return (
          wards,
          scope.level == GeographyLevel.lga || ward == null || !wards.shapes.containsKey(ward)
              ? const <String>[]
              : [ward],
        );
      }
      return (await GeoShapeSet.lgasOf(stateId!), [scope.lgaId!]);
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.live,
    required this.coverage,
    required this.geometry,
    required this.shapes,
    required this.onOpen,
  });

  final LiveAgents live;
  final Coverage coverage;
  final Future<(GeoShapeSet, List<String>)> geometry;
  final Future<GeoShapeSet> shapes;
  final ValueChanged<CoverageArea> onOpen;

  @override
  Widget build(BuildContext context) {
    final agents = [...live.agents]..sort((a, b) => _urgency(a).compareTo(_urgency(b)));
    final map = _AgentMap(agents: agents, geometry: geometry, shapes: shapes, scope: coverage.scope);
    final list = _AgentList(agents: agents);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CoverageSummary(tally: coverage.total),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 900) {
              return Column(children: [map, const SizedBox(height: 16), list]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: map),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: list),
              ],
            );
          },
        ),
        if (coverage.children.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Breakdown(areas: coverage.children, onOpen: onOpen),
        ],
      ],
    );
  }
}

class _CoverageSummary extends StatelessWidget {
  const _CoverageSummary({required this.tally});
  final CoverageTally tally;

  @override
  Widget build(BuildContext context) {
    final share = (tally.checkedInShare * 100).round();
    return TgcgSectionCard(
      title: 'Check-ins today',
      subtitle: '${tally.checkedIn} of ${tally.agents} polling-unit agents have checked in ($share%).',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: tally.checkedInShare, minHeight: 10),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TgcgStatusPill(label: '${tally.onSite} AT THEIR UNIT', color: TgcgColors.success, compact: true),
              TgcgStatusPill(label: '${tally.away} AWAY', color: TgcgColors.warning, compact: true),
              TgcgStatusPill(label: '${tally.suspect} SUSPECT GPS', color: TgcgColors.danger, compact: true),
              TgcgStatusPill(label: '${tally.unverified} NOT CHECKABLE', color: TgcgColors.info, compact: true),
              TgcgStatusPill(label: '${tally.notCheckedIn} NOT CHECKED IN', color: TgcgColors.muted, compact: true),
              TgcgStatusPill(label: '${tally.onDutyNow} ON DUTY NOW', color: TgcgColors.primary, compact: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentMap extends StatelessWidget {
  const _AgentMap({
    required this.agents,
    required this.geometry,
    required this.shapes,
    required this.scope,
  });

  final List<LiveAgent> agents;
  final Future<(GeoShapeSet, List<String>)> geometry;
  final Future<GeoShapeSet> shapes;
  final GeographicScope scope;

  /// A tapped LGA opens its wards; a tapped ward, its polling units.
  Future<void> _open(BuildContext context, String id) async {
    switch (scope.level) {
      case GeographyLevel.state:
      case GeographyLevel.senatorialDistrict:
        final lga = MembershipOperations.of(context, listen: false).geography.lga(id);
        if (lga != null) await showLgaWardMap(context, lga: lga);
      case GeographyLevel.lga:
      case GeographyLevel.ward:
      case GeographyLevel.pollingUnit:
        // Without published ward boundaries the map shows the LGA itself.
        if (id == scope.lgaId) return;
        final wards = await LgaWards.load(scope.lgaId!);
        final ward = wards.wards.where((ward) => ward.code == id).firstOrNull;
        if (ward == null || !context.mounted) return;
        await openWardPollingUnits(context, code: ward.code, name: ward.name);
      default:
        return;
    }
  }

  /// One dot per agent with a position; the most urgent are painted on top.
  List<Widget> _markers(GeoShapeSet _, GeoProjection projection) {
    final markers = <Widget>[];
    for (final agent in agents.reversed) {
      final position = agent.position;
      if (position == null) continue;
      final point = projection.project(position.latitude, position.longitude);
      markers.add(
        Positioned(
          key: ValueKey('agent-${agent.agentId}'),
          left: point.dx - 8,
          top: point.dy - 8,
          child: _AgentDot(agent: agent),
        ),
      );
    }
    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final placed = agents.where((agent) => agent.position != null).length;
    return TgcgSectionCard(
      title: 'Live map',
      subtitle: '$placed of ${agents.length} on-duty agent${agents.length == 1 ? '' : 's'} '
          'have sent a position.',
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 420,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: TgcgColors.primaryDark,
              borderRadius: BorderRadius.circular(16),
            ),
            child: FutureBuilder<(GeoShapeSet, List<String>)>(
              future: geometry,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data == null) {
                  return Center(
                    child: snapshot.hasError
                        ? const Text('Map unavailable', style: TextStyle(color: Colors.white70))
                        : const CircularProgressIndicator(),
                  );
                }
                return Stack(
                  children: [
                    Positioned.fill(
                      child: GeoShapeMapView(
                        source: shapes,
                        style: GeoMapStyle.dark,
                        padding: 28,
                        focusIds: data.$2,
                        onTap: (id) => _open(context, id),
                        fillFor: (_) => null,
                        overlayBuilder: _markers,
                      ),
                    ),
                    if (agents.isEmpty)
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 24,
                        child: IgnorePointer(
                          child: Center(
                            child: Text(
                              'No agents on duty in this area right now',
                              style: TextStyle(color: Color(0xFFB8BFCE), fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          const Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              _Legend('At their unit', TgcgColors.success),
              _Legend('Away', TgcgColors.warning),
              _Legend('Suspect GPS', TgcgColors.danger),
              _Legend('Not checkable', TgcgColors.info),
              _Legend('No recent signal', TgcgColors.muted),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 11.5, color: TgcgColors.muted)),
        ],
      );
}

class _AgentDot extends StatelessWidget {
  const _AgentDot({required this.agent});
  final LiveAgent agent;

  @override
  Widget build(BuildContext context) {
    final (label, color) = agentStatus(agent);
    return Tooltip(
      message: '${agent.name} (${agent.agentId})\n$label'
          '${agent.pollingUnit == null ? '' : '\nUnit ${agent.pollingUnit}'}'
          '${_distance(agent)}${_lastSeen(agent)}',
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
      ),
    );
  }
}

class _AgentList extends StatelessWidget {
  const _AgentList({required this.agents});
  final List<LiveAgent> agents;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'On duty now',
        subtitle: agents.isEmpty
            ? 'No agents are on duty in this area.'
            : 'Agents who need attention are listed first.',
        child: Column(
          children: [
            for (final agent in agents)
              Builder(builder: (context) {
                final (label, color) = agentStatus(agent);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: CircleAvatar(
                    radius: 7,
                    backgroundColor: color,
                  ),
                  title: Text(agent.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(
                    '${agent.agentId}${agent.pollingUnit == null ? '' : ' · ${agent.pollingUnit}'}'
                    '${_distance(agent)}${_lastSeen(agent)}'.replaceAll('\n', ' · '),
                    style: const TextStyle(fontSize: 11.5, color: TgcgColors.muted),
                  ),
                  trailing: TgcgStatusPill(label: label, color: color, compact: true),
                );
              }),
          ],
        ),
      );
}

class _Breakdown extends StatelessWidget {
  const _Breakdown({required this.areas, required this.onOpen});
  final List<CoverageArea> areas;
  final ValueChanged<CoverageArea> onOpen;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'By ${_levelName(areas.first.level)}',
        subtitle: 'Tap an area to open it.',
        child: Column(
          children: [
            for (final area in areas)
              InkWell(
                onTap: () => onOpen(area),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(area.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: area.tally.checkedInShare,
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${area.tally.checkedIn} of ${area.tally.agents} checked in',
                              style: const TextStyle(fontSize: 11, color: TgcgColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 3,
                        child: Text(
                          '${area.tally.onSite} at unit · ${area.tally.away} away'
                          '${area.tally.suspect > 0 ? ' · ${area.tally.suspect} suspect' : ''}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                      const Icon(Icons.chevron_right_rounded, color: TgcgColors.muted),
                    ],
                  ),
                ),
              ),
          ],
        ),
      );
}

/// What to call an agent's situation, and its colour.
(String, Color) agentStatus(LiveAgent agent) {
  final position = agent.position;
  if (position == null || agent.stale) return ('NO RECENT SIGNAL', TgcgColors.muted);
  return switch (position.status) {
    AgentLocationStatus.onSite => ('AT THEIR UNIT', TgcgColors.success),
    AgentLocationStatus.away => ('AWAY', TgcgColors.warning),
    AgentLocationStatus.suspect => ('SUSPECT GPS', TgcgColors.danger),
    AgentLocationStatus.unverified => ('NOT CHECKABLE', TgcgColors.info),
    AgentLocationStatus.noGps => ('NO GPS', TgcgColors.muted),
  };
}

/// Lower comes first: problems before agents who are where they should be.
int _urgency(LiveAgent agent) {
  final position = agent.position;
  if (position == null || agent.stale) return 2;
  return switch (position.status) {
    AgentLocationStatus.suspect => 0,
    AgentLocationStatus.away => 1,
    AgentLocationStatus.noGps => 2,
    AgentLocationStatus.unverified => 3,
    AgentLocationStatus.onSite => 4,
  };
}

String _distance(LiveAgent agent) {
  final metres = agent.position?.distanceToUnitMeters;
  if (metres == null) return '';
  return metres >= 1000
      ? '\n${(metres / 1000).toStringAsFixed(1)} km from unit'
      : '\n$metres m from unit';
}

String _lastSeen(LiveAgent agent) {
  final at = agent.position?.capturedAt;
  if (at == null) return '';
  final minutes = DateTime.now().difference(at).inMinutes;
  return minutes < 1 ? '\nseen just now' : '\nseen $minutes min ago';
}

String _clock(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

String _levelName(GeographyLevel level) => switch (level) {
      GeographyLevel.country => 'country',
      GeographyLevel.geopoliticalZone => 'zone',
      GeographyLevel.state => 'state',
      GeographyLevel.senatorialDistrict => 'senatorial district',
      GeographyLevel.lga => 'LGA',
      GeographyLevel.ward => 'ward',
      GeographyLevel.pollingUnit => 'polling unit',
    };
