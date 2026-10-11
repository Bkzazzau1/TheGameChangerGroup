import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/tgcg_design.dart';
import 'geography_registry.dart';
import 'lga_wards.dart';
import 'nigeria_map.dart';

/// Opens an LGA's ward map with the number of polling units in each ward.
Future<void> showLgaWardMap(BuildContext context, {required CanonicalLga lga}) =>
    showDialog<void>(context: context, builder: (_) => LgaWardMapDialog(lga: lga));

/// Navy shading by polling-unit count; [max] is the LGA's largest ward.
Color pollingUnitDensityColor(int count, int max) {
  if (count <= 0 || max <= 0) return const Color(0xFFEDF1F7);
  final t = math.sqrt(count / max).clamp(0.0, 1.0);
  return Color.lerp(const Color(0xFFD3DCF0), TgcgColors.primaryMid, t)!;
}

class LgaWardMapDialog extends StatefulWidget {
  const LgaWardMapDialog({super.key, required this.lga});
  final CanonicalLga lga;

  @override
  State<LgaWardMapDialog> createState() => _LgaWardMapDialogState();
}

class _LgaWardMapDialogState extends State<LgaWardMapDialog> {
  late final Future<LgaWards> _wards = LgaWards.load(widget.lga.id);
  String? _selected;

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

  Widget _frame({required String subtitle, required Widget body, String? footer}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.grid_view_rounded, color: TgcgColors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.lga.name} LGA: wards',
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: const TextStyle(color: TgcgColors.muted, fontSize: 12)),
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

  Widget _body(LgaWards data) {
    final max = data.wards.fold<int>(0, (m, w) => math.max(m, w.pollingUnits));
    final byCode = {for (final w in data.wards) w.code: w};
    final list = _WardList(
      wards: data.wards,
      selected: _selected,
      hasShape: (code) => data.shapes?.shapes.containsKey(code) ?? false,
      onSelect: (code) => setState(() => _selected = _selected == code ? null : code),
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
          Expanded(child: list),
        ],
      );
    }
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
        onTap: (code) => setState(() => _selected = _selected == code ? null : code),
        fillFor: (code) => pollingUnitDensityColor(byCode[code]?.pollingUnits ?? 0, max),
        labelFor: (code) {
          final ward = byCode[code];
          return ward == null ? null : '${_title(ward.name)}\n${ward.pollingUnits} PUs';
        },
        fitLabels: true,
        labelFontSize: 9,
        tooltipFor: (code) {
          final ward = byCode[code];
          return ward == null
              ? code
              : '${_title(ward.name)} ($code) • ${ward.pollingUnits} polling units';
        },
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

class _WardList extends StatelessWidget {
  const _WardList({
    required this.wards,
    required this.selected,
    required this.hasShape,
    required this.onSelect,
  });

  final List<WardInfo> wards;
  final String? selected;
  final bool Function(String code) hasShape;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => Material(
        color: TgcgColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: TgcgColors.border),
        ),
        child: ListView.separated(
          itemCount: wards.length,
          separatorBuilder: (_, _) => const Divider(height: 1, color: TgcgColors.border),
          itemBuilder: (context, index) {
            final ward = wards[index];
            return ListTile(
              dense: true,
              selected: ward.code == selected,
              selectedTileColor: TgcgColors.primarySoft,
              onTap: () => onSelect(ward.code),
              title: Text(_title(ward.name), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: Text(
                '${ward.code}${hasShape(ward.code) ? '' : ' • no boundary'}',
                style: const TextStyle(fontSize: 11, color: TgcgColors.muted),
              ),
              trailing: Text(
                '${ward.pollingUnits} PUs',
                style: const TextStyle(fontWeight: FontWeight.w900, color: TgcgColors.primary),
              ),
            );
          },
        ),
      );
}
