import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/models.dart';
import '../ui/tgcg_design.dart';
import 'geography_registry.dart';
import 'nigeria_map.dart';

/// Opens a state's LGA map in a large dialog.
///
/// [incidents] may include incidents from other states; only those whose
/// scope belongs to [state] are shown. When [memberCounts] (registered
/// members per canonical LGA id) is given, the dialog offers a members view
/// and opens on it when [showMembers] is true.
Future<void> showStateLgaMap(
  BuildContext context, {
  required CanonicalState state,
  required List<CanonicalLga> lgas,
  required List<FieldIncident> incidents,
  Map<String, int>? memberCounts,
  int? stateMemberCount,
  bool showMembers = false,
}) =>
    showDialog<void>(
      context: context,
      builder: (context) => StateLgaMapDialog(
        state: state,
        lgas: lgas,
        incidents: [
          for (final incident in incidents)
            if (incident.scope.stateId == state.id) incident,
        ],
        memberCounts: memberCounts,
        stateMemberCount: stateMemberCount,
        initialShowMembers: showMembers && memberCounts != null,
      ),
    );

/// Sequential green scale for member density; [max] is the busiest area.
Color memberDensityColor(int count, int max) {
  if (count <= 0) return const Color(0xFFEDEEF1);
  final t = max <= 0 ? 1.0 : math.sqrt(count / max).clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFFBFC9E0), TgcgColors.primary, t)!;
}

class StateLgaMapDialog extends StatefulWidget {
  const StateLgaMapDialog({
    super.key,
    required this.state,
    required this.lgas,
    required this.incidents,
    this.memberCounts,
    this.stateMemberCount,
    this.initialShowMembers = false,
  });

  final CanonicalState state;
  final List<CanonicalLga> lgas;
  final List<FieldIncident> incidents;
  final Map<String, int>? memberCounts;
  final int? stateMemberCount;
  final bool initialShowMembers;

  @override
  State<StateLgaMapDialog> createState() => _StateLgaMapDialogState();
}

class _StateLgaMapDialogState extends State<StateLgaMapDialog> {
  String? selectedLgaId;
  late bool showMembers = widget.initialShowMembers;

  // Soft tints that tell senatorial districts apart when there is no incident.
  static const _districtTints = [
    Color(0xFFD3DCF0), // navy tint
    Color(0xFFF3E5BD), // gold tint
    Color(0xFFDDE9D6), // sage tint
  ];

  late final Map<String, CanonicalLga> _lgaById = {
    for (final lga in widget.lgas) lga.id: lga,
  };

  late final List<String> _districtIds = <String>{
    for (final lga in widget.lgas) lga.senatorialDistrictId,
  }.toList(growable: false);

  late final Map<String, List<FieldIncident>> _openByLga = () {
    final result = <String, List<FieldIncident>>{};
    for (final incident in widget.incidents) {
      final id = incident.scope.lgaId;
      if (id == null || !_isOpen(incident)) continue;
      result.putIfAbsent(id, () => []).add(incident);
    }
    for (final items in result.values) {
      items.sort((a, b) =>
          _severityRank(b.severity).compareTo(_severityRank(a.severity)));
    }
    return result;
  }();

  late final int _maxLgaMembers = (widget.memberCounts?.values ?? const [0])
      .fold<int>(0, math.max);

  late final int _lgaMemberTotal =
      (widget.memberCounts?.values ?? const <int>[]).fold<int>(0, (a, b) => a + b);

  late final Future<GeoShapeSet> _shapes = GeoShapeSet.lgasOf(widget.state.id);

  int _members(String lgaId) => widget.memberCounts?[lgaId] ?? 0;

  Color? _fillFor(String id) {
    if (showMembers) return memberDensityColor(_members(id), _maxLgaMembers);
    final open = _openByLga[id];
    if (open != null && open.isNotEmpty) {
      return Color.alphaBlend(
        _severityColor(open.first.severity).withValues(alpha: .78),
        Colors.white,
      );
    }
    final lga = _lgaById[id];
    if (lga == null) return null;
    final index = _districtIds.indexOf(lga.senatorialDistrictId);
    return _districtTints[index % _districtTints.length];
  }

  String? _labelFor(String id) {
    final name = _lgaById[id]?.name;
    if (name == null || !showMembers) return name;
    final count = _members(id);
    return count > 0 ? '$name\n$count' : name;
  }

  String _tooltipFor(String id) {
    final lga = _lgaById[id];
    if (lga == null) return id;
    final open = _openByLga[id]?.length ?? 0;
    final parts = [
      lga.name,
      lga.senatorialDistrictName,
      if (widget.memberCounts != null) _plural(_members(id), 'member'),
      if (open > 0) _plural(open, 'open incident'),
    ];
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final totalOpen =
        _openByLga.values.fold<int>(0, (total, items) => total + items.length);
    final title = state.isFederalCapitalTerritory
        ? state.name
        : '${state.name} State';
    final hasMembers = widget.memberCounts != null;
    final stateLevelMembers = math.max(
      0,
      (widget.stateMemberCount ?? _lgaMemberTotal) - _lgaMemberTotal,
    );

    final map = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TgcgColors.border),
      ),
      child: GeoShapeMapView(
        source: _shapes,
        padding: 12,
        selectedId: selectedLgaId,
        onTap: (id) => setState(
          () => selectedLgaId = selectedLgaId == id ? null : id,
        ),
        fillFor: _fillFor,
        labelFor: _labelFor,
        fitLabels: true,
        labelFontSize: 9,
        tooltipFor: _tooltipFor,
        overlayBuilder: showMembers
            ? null
            : (shapes, projection) => [
                  for (final incident in widget.incidents)
                    if (_isOpen(incident) &&
                        incident.latitude != null &&
                        incident.longitude != null)
                      _incidentDot(incident, projection),
                ],
      ),
    );

    final panel = selectedLgaId != null && _lgaById[selectedLgaId] != null
        ? _LgaDetail(
            lga: _lgaById[selectedLgaId]!,
            incidents: _openByLga[selectedLgaId] ?? const [],
            members: hasMembers ? _members(selectedLgaId!) : null,
            onBack: () => setState(() => selectedLgaId = null),
          )
        : _LgaList(
            lgas: widget.lgas,
            openByLga: _openByLga,
            memberCounts: widget.memberCounts,
            showMembers: showMembers,
            stateLevelMembers: stateLevelMembers,
            onSelect: (id) => setState(() => selectedLgaId = id),
          );

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      backgroundColor: TgcgColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1500, maxHeight: 980),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 14, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                runSpacing: 10,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map_outlined, color: TgcgColors.primary),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: const TextStyle(
                              color: TgcgColors.ink,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            '${state.zoneName} • ${widget.lgas.length} local government areas • '
                            '${_plural(_districtIds.length, 'senatorial district')}',
                            style: const TextStyle(
                              color: TgcgColors.muted,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasMembers) ...[
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(
                            visualDensity: VisualDensity.compact,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: false,
                              icon: Icon(Icons.warning_amber_rounded, size: 16),
                              label: Text('Incidents'),
                            ),
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.groups_outlined, size: 16),
                              label: Text('Members'),
                            ),
                          ],
                          selected: {showMembers},
                          onSelectionChanged: (value) =>
                              setState(() => showMembers = value.first),
                        ),
                        const SizedBox(width: 10),
                        TgcgStatusPill(
                          label:
                              '${widget.stateMemberCount ?? _lgaMemberTotal} MEMBERS',
                          color: TgcgColors.primary,
                          icon: Icons.groups_outlined,
                          compact: true,
                        ),
                        const SizedBox(width: 8),
                      ],
                      TgcgStatusPill(
                        label: '$totalOpen OPEN',
                        color: totalOpen == 0
                            ? TgcgColors.success
                            : TgcgColors.danger,
                        icon: Icons.warning_amber_rounded,
                        compact: true,
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 860) {
                        return Column(
                          children: [
                            Expanded(flex: 3, child: map),
                            const SizedBox(height: 12),
                            Expanded(flex: 2, child: panel),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: map),
                          const SizedBox(width: 14),
                          SizedBox(width: 340, child: panel),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
              showMembers
                  ? _MembersLegend(max: _maxLgaMembers)
                  : _Legend(districtCount: _districtIds.length),
            ],
          ),
        ),
      ),
    );
  }

  Widget _incidentDot(FieldIncident incident, GeoProjection projection) {
    final point = projection.project(incident.latitude!, incident.longitude!);
    return Positioned(
      left: point.dx - 6,
      top: point.dy - 6,
      child: Tooltip(
        message: incident.title,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: _severityColor(incident.severity),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
      ),
    );
  }
}

class _LgaList extends StatelessWidget {
  const _LgaList({
    required this.lgas,
    required this.openByLga,
    required this.memberCounts,
    required this.showMembers,
    required this.stateLevelMembers,
    required this.onSelect,
  });

  final List<CanonicalLga> lgas;
  final Map<String, List<FieldIncident>> openByLga;
  final Map<String, int>? memberCounts;
  final bool showMembers;
  final int stateLevelMembers;
  final ValueChanged<String> onSelect;

  int _members(String id) => memberCounts?[id] ?? 0;

  @override
  Widget build(BuildContext context) {
    final sorted = [...lgas]..sort((a, b) {
        final primary = showMembers
            ? _members(b.id).compareTo(_members(a.id))
            : (openByLga[b.id]?.length ?? 0)
                .compareTo(openByLga[a.id]?.length ?? 0);
        return primary != 0 ? primary : a.name.compareTo(b.name);
      });
    final showStateLevel = showMembers && stateLevelMembers > 0;
    return _PanelFrame(
      title: showMembers ? 'Members by LGA' : 'Local government areas',
      child: Column(
        children: [
          if (showStateLevel)
            Container(
              width: double.infinity,
              color: TgcgColors.accentSoft,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              child: Text(
                '${_plural(stateLevelMembers, 'member')} registered at state level '
                'without an LGA.',
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: sorted.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: TgcgColors.border),
              itemBuilder: (context, index) {
                final lga = sorted[index];
                final open = openByLga[lga.id] ?? const <FieldIncident>[];
                final members = _members(lga.id);
                return ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  onTap: () => onSelect(lga.id),
                  title: Text(
                    lga.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: TgcgColors.ink,
                    ),
                  ),
                  subtitle: Text(
                    lga.senatorialDistrictName,
                    style:
                        const TextStyle(fontSize: 11, color: TgcgColors.muted),
                  ),
                  trailing: showMembers
                      ? Text(
                          '$members',
                          style: TextStyle(
                            color: members == 0
                                ? TgcgColors.muted
                                : TgcgColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        )
                      : open.isEmpty
                          ? const Icon(Icons.chevron_right_rounded,
                              color: TgcgColors.muted)
                          : TgcgStatusPill(
                              label: '${open.length} OPEN',
                              color: _severityColor(open.first.severity),
                              compact: true,
                            ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LgaDetail extends StatelessWidget {
  const _LgaDetail({
    required this.lga,
    required this.incidents,
    required this.members,
    required this.onBack,
  });

  final CanonicalLga lga;
  final List<FieldIncident> incidents;
  final int? members;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => _PanelFrame(
        title: lga.name,
        leading: IconButton(
          tooltip: 'All LGAs',
          visualDensity: VisualDensity.compact,
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded, size: 18),
        ),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
            if (members != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: TgcgColors.primarySoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.groups_outlined, color: TgcgColors.primary),
                    const SizedBox(width: 10),
                    Text(
                      '$members',
                      style: const TextStyle(
                        color: TgcgColors.primary,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'registered members',
                      style: TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            _Fact(label: 'Senatorial district', value: lga.senatorialDistrictName),
            _Fact(label: 'State', value: lga.stateName),
            _Fact(label: 'Geopolitical zone', value: lga.zoneName),
            _Fact(label: 'LGA code', value: lga.id),
            const SizedBox(height: 12),
            Text(
              'OPEN INCIDENTS (${incidents.length})',
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .6,
              ),
            ),
            const SizedBox(height: 8),
            if (incidents.isEmpty)
              const Text(
                'No open incidents reported in this LGA.',
                style: TextStyle(color: TgcgColors.muted, fontSize: 12),
              ),
            for (final incident in incidents)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: TgcgColors.surfaceSoft,
                  borderRadius: BorderRadius.circular(10),
                  border: Border(
                    left: BorderSide(
                      color: _severityColor(incident.severity),
                      width: 3,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      incident.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: TgcgColors.ink,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${incident.severity.name.toUpperCase()} • '
                      '${incident.status.name} • ${incident.scope.label}',
                      style: const TextStyle(
                        color: TgcgColors.muted,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
}

class _PanelFrame extends StatelessWidget {
  const _PanelFrame({required this.title, required this.child, this.leading});

  final String title;
  final Widget child;
  final Widget? leading;

  @override
  Widget build(BuildContext context) => Material(
        color: TgcgColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: TgcgColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: TgcgColors.surfaceSoft,
              padding: EdgeInsets.fromLTRB(leading == null ? 14 : 4, 6, 14, 6),
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  ?leading,
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: TgcgColors.ink,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: TgcgColors.border),
            Expanded(child: child),
          ],
        ),
      );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 130,
              child: Text(
                label,
                style: const TextStyle(color: TgcgColors.muted, fontSize: 11.5),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

Widget _legendItem(Color color, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: TgcgColors.border),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: TgcgColors.muted,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );

class _Legend extends StatelessWidget {
  const _Legend({required this.districtCount});
  final int districtCount;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          _legendItem(
              _severityColor(IncidentSeverity.critical), 'Critical / high incident'),
          _legendItem(_severityColor(IncidentSeverity.medium), 'Medium incident'),
          _legendItem(_severityColor(IncidentSeverity.low), 'Low / info incident'),
          for (var i = 0; i < districtCount && i < 3; i++)
            _legendItem(
              _StateLgaMapDialogState._districtTints[i],
              'Senatorial district ${i + 1} (no open incident)',
            ),
        ],
      );
}

class _MembersLegend extends StatelessWidget {
  const _MembersLegend({required this.max});
  final int max;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 14,
        runSpacing: 6,
        children: [
          _legendItem(memberDensityColor(0, max), 'No members'),
          if (max > 0) ...[
            _legendItem(memberDensityColor(1, max), 'Few members'),
            _legendItem(memberDensityColor(max, max), 'Most members ($max)'),
          ],
        ],
      );
}

String _plural(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

bool _isOpen(FieldIncident incident) =>
    incident.status != IncidentStatus.resolved &&
    incident.status != IncidentStatus.closed;

int _severityRank(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => 5,
      IncidentSeverity.high => 4,
      IncidentSeverity.medium => 3,
      IncidentSeverity.low => 2,
      IncidentSeverity.info => 1,
    };

Color _severityColor(IncidentSeverity severity) => switch (severity) {
      IncidentSeverity.critical => TgcgColors.danger,
      IncidentSeverity.high => const Color(0xFFD92D20),
      IncidentSeverity.medium => TgcgColors.warning,
      IncidentSeverity.low => TgcgColors.info,
      IncidentSeverity.info => TgcgColors.muted,
    };
