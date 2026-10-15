import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api/backend.dart';
import '../api/member_admin_repository.dart';
import '../field/incident_report.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';
import 'geography_registry.dart';
import 'lga_wards.dart';
import 'nigeria_map.dart';
import 'ward_polling_units_page.dart';

/// Opens an LGA's ward map with the number of polling units in each ward.
/// Given [incidents], it also maps the LGA's open incidents by ward, and
/// opens on them when [showIncidents] is true.
Future<void> showLgaWardMap(
  BuildContext context, {
  required CanonicalLga lga,
  List<FieldIncident>? incidents,
  bool showIncidents = true,
}) =>
    showDialog<void>(
      context: context,
      builder: (_) => LgaWardMapDialog(
        lga: lga,
        incidents: incidents,
        initialShowIncidents: showIncidents,
      ),
    );

/// Navy shading by polling-unit count; [max] is the LGA's largest ward.
Color pollingUnitDensityColor(int count, int max) {
  if (count <= 0 || max <= 0) return const Color(0xFFEDF1F7);
  final t = math.sqrt(count / max).clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFFD3DCF0), TgcgColors.primaryMid, t)!;
}

class LgaWardMapDialog extends StatefulWidget {
  const LgaWardMapDialog({
    super.key,
    required this.lga,
    this.incidents,
    this.initialShowIncidents = true,
  });

  final CanonicalLga lga;

  /// Incidents to map by ward (only this LGA's open ones show); null leaves
  /// incidents out.
  final List<FieldIncident>? incidents;
  final bool initialShowIncidents;

  @override
  State<LgaWardMapDialog> createState() => _LgaWardMapDialogState();
}

class _LgaWardMapDialogState extends State<LgaWardMapDialog> {
  late final Future<LgaWards> _wards = LgaWards.load(widget.lga.id);
  String? _selected;

  /// This LGA's open incidents, most severe first.
  late final List<FieldIncident>? _incidents = _openHere(widget.incidents);

  List<FieldIncident>? _openHere(List<FieldIncident>? incidents) {
    if (incidents == null) return null;
    return [
      for (final incident in incidents)
        if (incident.scope.lgaId == widget.lga.id && isOpenIncident(incident)) incident,
    ]..sort(
        (a, b) => incidentSeverityRank(b.severity).compareTo(incidentSeverityRank(a.severity)),
      );
  }

  late final Map<String, List<FieldIncident>> _openByWard = () {
    final result = <String, List<FieldIncident>>{};
    for (final incident in _incidents ?? const <FieldIncident>[]) {
      final ward = incident.scope.wardId;
      if (ward != null) result.putIfAbsent(ward, () => []).add(incident);
    }
    return result;
  }();

  late bool _showIncidents = _incidents != null && widget.initialShowIncidents;

  /// Members registered in each ward, for those who may find members here.
  MemberCounts? _members;
  bool _countsAsked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_countsAsked) return;
    _countsAsked = true;
    final backend = TgcgBackend.of(context);
    if (backend == null || !canFindMembers(TgcgSession.of(context, listen: false))) return;
    backend.members
        .counts(level: GeographyLevel.lga, code: widget.lga.id, by: GeographyLevel.ward)
        .then((counts) {
          if (mounted) setState(() => _members = counts);
        }, onError: (Object _) {}); // an LGA outside the account's area: no numbers
  }

  void _open(WardInfo ward) {
    setState(() => _selected = ward.code);
    openWardPollingUnits(
      context,
      code: ward.code,
      name: ward.name,
      incidents: _incidents == null ? null : _openByWard[ward.code] ?? const [],
    );
  }

  @override
  Widget build(BuildContext context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: TgcgColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500, maxHeight: 980),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 14, 18),
            child: FutureBuilder<LgaWards>(
              future: _wards,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _frame(
                    subtitle: '',
                    body: const Center(child: Text('Ward data could not be loaded.')),
                  );
                }
                final data = snapshot.data;
                if (data == null) {
                  return _frame(
                    subtitle: '',
                    body: const Center(child: CircularProgressIndicator()),
                  );
                }
                return _frame(
                  subtitle:
                      '${widget.lga.stateName} State • ${data.wards.length} wards • '
                      '${data.pollingUnits} polling units',
                  body: _body(data),
                  footer: data.attribution,
                );
              },
            ),
          ),
        ),
      );

  Widget _frame({required String subtitle, required Widget body, String? footer}) {
    final incidents = _incidents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // On a phone the incident view's controls go below the title.
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                spacing: 10,
                runSpacing: 10,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.grid_view_rounded, color: TgcgColors.primary),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${widget.lga.name} LGA: wards',
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                            ),
                            if (subtitle.isNotEmpty)
                              Text(
                                subtitle,
                                style: const TextStyle(color: TgcgColors.muted, fontSize: 12),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (incidents != null)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          style: const ButtonStyle(visualDensity: VisualDensity.compact),
                          segments: const [
                            ButtonSegment(
                              value: true,
                              icon: Icon(Icons.warning_amber_rounded, size: 16),
                              label: Text('Incidents'),
                            ),
                            ButtonSegment(
                              value: false,
                              icon: Icon(Icons.how_to_vote_outlined, size: 16),
                              label: Text('Polling units'),
                            ),
                          ],
                          selected: {_showIncidents},
                          onSelectionChanged: (value) =>
                              setState(() => _showIncidents = value.first),
                        ),
                        TgcgStatusPill(
                          label: '${incidents.length} OPEN',
                          color: incidents.isEmpty ? TgcgColors.success : TgcgColors.danger,
                          icon: Icons.warning_amber_rounded,
                          compact: true,
                        ),
                      ],
                    ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Expanded(child: body),
        if (footer != null && footer.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(footer, style: const TextStyle(color: TgcgColors.muted, fontSize: 10)),
        ],
      ],
    );
  }

  Color _fill(String code, WardInfo? ward, int max) {
    if (!_showIncidents) return pollingUnitDensityColor(ward?.pollingUnits ?? 0, max);
    final open = _openByWard[code];
    if (open == null || open.isEmpty) return pollingUnitDensityColor(0, 0);
    return Color.alphaBlend(
      incidentSeverityColor(open.first.severity).withValues(alpha: .78),
      Colors.white,
    );
  }

  String? _labelFor(WardInfo? ward) {
    if (ward == null) return null;
    if (!_showIncidents) return '${_title(ward.name)}\n${ward.pollingUnits} PUs';
    final open = _openByWard[ward.code]?.length ?? 0;
    return open == 0 ? _title(ward.name) : '${_title(ward.name)}\n$open open';
  }

  String _tooltipFor(String code, WardInfo? ward) {
    if (ward == null) return code;
    final open = _openByWard[code]?.length ?? 0;
    return '${_title(ward.name)} ($code) • ${ward.pollingUnits} polling units'
        '${_incidents == null ? '' : ' • ${_plural(open, 'open incident')}'}';
  }

  Widget _incidentDot(FieldIncident incident, GeoProjection projection) {
    final point = projection.project(incident.latitude!, incident.longitude!);
    return Positioned(
      left: point.dx - 12,
      top: point.dy - 12,
      child: Tooltip(
        message: incident.title,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => openIncidentReport(context, incident),
          child: SizedBox.square(
            dimension: 24,
            child: Center(
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: incidentSeverityColor(incident.severity),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(LgaWards data) {
    final max = data.wards.fold<int>(0, (m, w) => math.max(m, w.pollingUnits));
    final byCode = {for (final w in data.wards) w.code: w};
    final wholeLga = _showIncidents
        ? (_incidents ?? const <FieldIncident>[]).where((i) => i.scope.wardId == null).length
        : 0;
    final list = _WardList(
      wards: data.wards,
      selected: _selected,
      members: _members,
      openByWard: _showIncidents ? _openByWard : null,
      hasShape: (code) => data.shapes?.shapes.containsKey(code) ?? false,
      onSelect: _open,
    );
    final lgaNote = wholeLga == 0
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              '${_plural(wholeLga, 'open incident')} for the whole LGA',
              style: const TextStyle(fontSize: 11.5, color: TgcgColors.muted),
            ),
          );
    final shapes = data.shapes;
    if (shapes == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TgcgColors.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Ward boundaries for ${widget.lga.stateName} State are not yet published '
              '(GRID3 currently covers 24 states). The ward list and polling unit counts '
              'below are complete.',
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(height: 12),
          ?lgaNote,
          Expanded(child: list),
        ],
      );
    }
    final incidents = _incidents;
    final map = Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: TgcgColors.surfaceSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TgcgColors.border),
      ),
      child: GeoShapeMapView(
        source: Future.value(shapes),
        padding: 12,
        selectedId: _selected,
        onTap: (code) {
          final ward = byCode[code];
          if (ward != null) _open(ward);
        },
        fillFor: (code) => _fill(code, byCode[code], max),
        labelFor: (code) => _labelFor(byCode[code]),
        fitLabels: true,
        labelFontSize: 9,
        tooltipFor: (code) => _tooltipFor(code, byCode[code]),
        overlayBuilder: _showIncidents && incidents != null
            ? (shapes, projection) => [
                  for (final incident in incidents)
                    if (incident.latitude != null && incident.longitude != null)
                      _incidentDot(incident, projection),
                ]
            : null,
      ),
    );
    final missing = data.wards.length - data.mappedWards;
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 860;
        final panel = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (missing > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '$missing ward${missing == 1 ? ' has' : 's have'} no published boundary and '
                  '${missing == 1 ? 'is' : 'are'} listed only.',
                  style: const TextStyle(fontSize: 11.5, color: TgcgColors.muted),
                ),
              ),
            ?lgaNote,
            Expanded(child: list),
          ],
        );
        if (narrow) {
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
            SizedBox(width: 320, child: panel),
          ],
        );
      },
    );
  }
}

/// INEC names are upper case; show them in title case.
String _title(String name) => name
    .toLowerCase()
    .split(' ')
    .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
    .join(' ');

String _plural(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

class _WardList extends StatelessWidget {
  const _WardList({
    required this.wards,
    required this.selected,
    required this.members,
    required this.openByWard,
    required this.hasShape,
    required this.onSelect,
  });

  final List<WardInfo> wards;
  final String? selected;
  final MemberCounts? members;

  /// Open incidents by ward while the incident view is on.
  final Map<String, List<FieldIncident>>? openByWard;
  final bool Function(String code) hasShape;
  final ValueChanged<WardInfo> onSelect;

  int _open(String code) => openByWard?[code]?.length ?? 0;

  @override
  Widget build(BuildContext context) {
    // In the incident view, wards with the most open incidents come first.
    final sorted = openByWard == null
        ? wards
        : ([...wards.indexed]..sort((a, b) {
                final order = _open(b.$2.code).compareTo(_open(a.$2.code));
                return order != 0 ? order : a.$1.compareTo(b.$1);
              }))
            .map((entry) => entry.$2)
            .toList();
    return Material(
      color: TgcgColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: TgcgColors.border),
      ),
      child: ListView.separated(
        itemCount: sorted.length,
        separatorBuilder: (_, _) => const Divider(height: 1, color: TgcgColors.border),
        itemBuilder: (context, index) {
          final ward = sorted[index];
          final open = openByWard?[ward.code] ?? const <FieldIncident>[];
          return ListTile(
            dense: true,
            selected: ward.code == selected,
            selectedTileColor: TgcgColors.primarySoft,
            onTap: () => onSelect(ward),
            title: Text(_title(ward.name), style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
              '${ward.code}${hasShape(ward.code) ? '' : ' • no boundary'}',
              style: const TextStyle(fontSize: 11, color: TgcgColors.muted),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (open.isNotEmpty)
                  TgcgStatusPill(
                    label: '${open.length} OPEN',
                    color: incidentSeverityColor(open.first.severity),
                    compact: true,
                  )
                else
                  Text(
                    '${ward.pollingUnits} PUs',
                    style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.primary),
                  ),
                if (members != null)
                  Text(
                    '${members![ward.code]} members',
                    style: const TextStyle(fontSize: 11, color: TgcgColors.muted),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
