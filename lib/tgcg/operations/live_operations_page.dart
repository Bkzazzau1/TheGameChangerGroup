import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/tgcg_design.dart';

class LiveOperationsPage extends StatefulWidget {
  const LiveOperationsPage({super.key});

  @override
  State<LiveOperationsPage> createState() => _LiveOperationsPageState();
}

class _LiveOperationsPageState extends State<LiveOperationsPage> {
  String selectedZone = 'North West';

  static const zones = [
    _ZoneOps('North West', 'NW', 62, 18, 11, 39),
    _ZoneOps('North Central', 'NC', 54, 14, 8, 31),
    _ZoneOps('North East', 'NE', 41, 10, 7, 22),
    _ZoneOps('South West', 'SW', 71, 16, 12, 44),
    _ZoneOps('South South', 'SS', 49, 11, 9, 28),
    _ZoneOps('South East', 'SE', 38, 7, 6, 19),
  ];

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final selected = zones.firstWhere((item) => item.name == selectedZone);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
      children: [
        TgcgPageHeader(
          eyebrow: 'ELECTION-DAY OPERATIONS',
          title: 'Live National Operations',
          subtitle:
              '${session.scope.label}: field check-ins, operational incidents, evidence activity and result-submission progress.',
          trailing: const TgcgStatusPill(
            label: 'LIVE',
            color: TgcgColors.success,
            icon: Icons.circle,
          ),
        ),
        const SizedBox(height: 18),
        const _TopMetrics(),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final map = _MapPanel(
              zones: zones,
              selected: selectedZone,
              onSelect: (value) => setState(() => selectedZone = value),
            );
            final detail = _ZoneDetail(zone: selected);
            if (constraints.maxWidth < 980) {
              return Column(children: [map, const SizedBox(height: 16), detail]);
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 7, child: map),
                const SizedBox(width: 16),
                Expanded(flex: 4, child: detail),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _ZoneStrip(
          zones: zones,
          selected: selectedZone,
          onSelect: (value) => setState(() => selectedZone = value),
        ),
        const SizedBox(height: 16),
        const _LiveActivityFeed(),
      ],
    );
  }
}

class _ZoneOps {
  const _ZoneOps(this.name, this.code, this.agents, this.results, this.incidents, this.checkIns);
  final String name;
  final String code;
  final int agents;
  final int results;
  final int incidents;
  final int checkIns;
}

class _TopMetrics extends StatelessWidget {
  const _TopMetrics();

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : constraints.maxWidth >= 520 ? 2 : 1;
          const gap = 12.0;
          final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              TgcgMetricCard(
                width: width,
                label: 'Agents active',
                value: '315',
                detail: 'Across operational zones',
                icon: Icons.badge_outlined,
                tone: TgcgMetricTone.success,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Checked in',
                value: '183',
                detail: 'Field duty active',
                icon: Icons.how_to_reg_outlined,
                tone: TgcgMetricTone.info,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Open incidents',
                value: '53',
                detail: 'Operational review queue',
                icon: Icons.warning_amber_rounded,
                tone: TgcgMetricTone.warning,
              ),
              TgcgMetricCard(
                width: width,
                label: 'Results received',
                value: '86',
                detail: 'Unofficial field submissions',
                icon: Icons.ballot_outlined,
                tone: TgcgMetricTone.ai,
              ),
            ],
          );
        },
      );
}

class _MapPanel extends StatelessWidget {
  const _MapPanel({required this.zones, required this.selected, required this.onSelect});
  final List<_ZoneOps> zones;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'National activity map',
        subtitle: 'Select a zone to inspect current operational activity.',
        trailing: const TgcgStatusPill(
          label: '6 ZONES',
          color: TgcgColors.primary,
          icon: Icons.public_rounded,
          compact: true,
        ),
        child: SizedBox(
          height: 440,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _NigeriaOpsPainter(),
                  ),
                ),
                ..._nodes(constraints.biggest).map(
                  (node) {
                    final zone = zones.firstWhere((z) => z.code == node.code);
                    final active = selected == zone.name;
                    return Positioned(
                      left: node.dx * constraints.maxWidth - 46,
                      top: node.dy * constraints.maxHeight - 30,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () => onSelect(zone.name),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          width: 92,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                          decoration: BoxDecoration(
                            color: active ? TgcgColors.primary : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: active ? TgcgColors.accent : TgcgColors.border,
                              width: active ? 2 : 1,
                            ),
                            boxShadow: const [
                              BoxShadow(color: Color(0x18000000), blurRadius: 12, offset: Offset(0, 5)),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.circle, size: 8, color: active ? TgcgColors.accent : TgcgColors.success),
                                  const SizedBox(width: 5),
                                  Text(
                                    zone.code,
                                    style: TextStyle(
                                      color: active ? Colors.white : TgcgColors.ink,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${zone.checkIns} active',
                                style: TextStyle(
                                  color: active ? const Color(0xFFD5E4DF) : TgcgColors.muted,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );

  List<_MapNode> _nodes(Size size) => const [
        _MapNode('NW', .33, .25),
        _MapNode('NE', .66, .27),
        _MapNode('NC', .51, .48),
        _MapNode('SW', .31, .68),
        _MapNode('SE', .58, .72),
        _MapNode('SS', .48, .86),
      ];
}

class _MapNode {
  const _MapNode(this.code, this.dx, this.dy);
  final String code;
  final double dx;
  final double dy;
}

class _NigeriaOpsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = const Color(0xFFEAF2EF);
    final border = Paint()
      ..color = const Color(0xFF8FA79F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final path = Path()
      ..moveTo(size.width * .22, size.height * .10)
      ..lineTo(size.width * .52, size.height * .06)
      ..lineTo(size.width * .76, size.height * .18)
      ..lineTo(size.width * .82, size.height * .42)
      ..lineTo(size.width * .72, size.height * .62)
      ..lineTo(size.width * .67, size.height * .85)
      ..lineTo(size.width * .49, size.height * .94)
      ..lineTo(size.width * .33, size.height * .82)
      ..lineTo(size.width * .18, size.height * .70)
      ..lineTo(size.width * .14, size.height * .43)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, border);

    final line = Paint()
      ..color = const Color(0x338FA79F)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 6; i++) {
      final y = size.height * (.22 + i * .11);
      canvas.drawLine(Offset(size.width * .22, y), Offset(size.width * .74, y + math.sin(i) * 16), line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ZoneDetail extends StatelessWidget {
  const _ZoneDetail({required this.zone});
  final _ZoneOps zone;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: zone.name,
        subtitle: '${zone.code} operational desk',
        trailing: const TgcgStatusPill(label: 'ACTIVE', color: TgcgColors.success, compact: true),
        child: Column(
          children: [
            _DetailRow(label: 'Agents assigned', value: '${zone.agents}', icon: Icons.badge_outlined),
            _DetailRow(label: 'Checked in', value: '${zone.checkIns}', icon: Icons.how_to_reg_outlined),
            _DetailRow(label: 'Open incidents', value: '${zone.incidents}', icon: Icons.warning_amber_rounded),
            _DetailRow(label: 'Results received', value: '${zone.results}', icon: Icons.ballot_outlined),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            const _OperationalStatus(label: 'Field connectivity', value: 'Stable', color: TgcgColors.success),
            const _OperationalStatus(label: 'Evidence queue', value: 'Normal', color: TgcgColors.info),
            const _OperationalStatus(label: 'Result review', value: 'Active', color: TgcgColors.accent),
          ],
        ),
      );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 18, color: TgcgColors.primary),
            const SizedBox(width: 9),
            Expanded(child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 11))),
            Text(value, style: const TextStyle(color: TgcgColors.ink, fontSize: 15, fontWeight: FontWeight.w900)),
          ],
        ),
      );
}

class _OperationalStatus extends StatelessWidget {
  const _OperationalStatus({required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(Icons.circle, size: 8, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w700, fontSize: 10.5))),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 10)),
          ],
        ),
      );
}

class _ZoneStrip extends StatelessWidget {
  const _ZoneStrip({required this.zones, required this.selected, required this.onSelect});
  final List<_ZoneOps> zones;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Zone activity',
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1050 ? 6 : constraints.maxWidth >= 680 ? 3 : 2;
            const gap = 10.0;
            final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: zones.map((zone) {
                final active = zone.name == selected;
                return InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => onSelect(zone.name),
                  child: Container(
                    width: width,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: active ? TgcgColors.primarySoft : TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: active ? TgcgColors.primary : TgcgColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(zone.code, style: const TextStyle(color: TgcgColors.primary, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 3),
                        Text(zone.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w800, fontSize: 10)),
                        const SizedBox(height: 8),
                        Text('${zone.checkIns} checked in', style: const TextStyle(color: TgcgColors.muted, fontSize: 9)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
}

class _LiveActivityFeed extends StatelessWidget {
  const _LiveActivityFeed();

  @override
  Widget build(BuildContext context) => TgcgSectionCard(
        title: 'Live operational activity',
        trailing: const TgcgStatusPill(label: 'UPDATING', color: TgcgColors.info, compact: true),
        child: const Column(
          children: [
            _Activity(icon: Icons.how_to_reg_outlined, title: 'Agent checked in', location: 'Kaduna North • Ward 01 • PU 001', time: '1 min'),
            _Activity(icon: Icons.perm_media_outlined, title: 'Evidence package received', location: 'Makurdi • Ward 01 • PU 004', time: '3 min'),
            _Activity(icon: Icons.fact_check_outlined, title: 'Result moved to verification', location: 'Kaduna North • PU 002', time: '5 min'),
            _Activity(icon: Icons.warning_amber_rounded, title: 'Operational incident opened', location: 'Lagos • Ikeja', time: '7 min'),
          ],
        ),
      );
}

class _Activity extends StatelessWidget {
  const _Activity({required this.icon, required this.title, required this.location, required this.time});
  final IconData icon;
  final String title;
  final String location;
  final String time;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: TgcgColors.primarySoft, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: TgcgColors.primary, size: 19),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: TgcgColors.ink, fontWeight: FontWeight.w900, fontSize: 11.5)),
                  const SizedBox(height: 2),
                  Text(location, style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5)),
                ],
              ),
            ),
            Text(time, style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5)),
          ],
        ),
      );
}
