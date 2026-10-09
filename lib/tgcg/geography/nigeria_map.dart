import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../ui/tgcg_design.dart';

const nigeriaStatesAsset = 'assets/geo/nigeria_states.json';

/// One state (or FCT) boundary in geographic space. Offsets are (lng, lat).
class NigeriaStateShape {
  const NigeriaStateShape({
    required this.stateId,
    required this.rings,
    required this.labelPoint,
    required this.bounds,
  });

  final String stateId;
  final List<List<Offset>> rings;
  final Offset labelPoint;
  final Rect bounds;

  bool contains(double latitude, double longitude) {
    if (!bounds.contains(Offset(longitude, latitude))) return false;
    var inside = false;
    for (final ring in rings) {
      for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final a = ring[i];
        final b = ring[j];
        if ((a.dy > latitude) != (b.dy > latitude) &&
            longitude < (b.dx - a.dx) * (latitude - a.dy) / (b.dy - a.dy) + a.dx) {
          inside = !inside;
        }
      }
    }
    return inside;
  }
}

/// Real Nigerian state boundaries bundled as an offline asset
/// (GRID3 / geoBoundaries ADM1, simplified, CC BY 4.0).
class NigeriaMapGeometry {
  const NigeriaMapGeometry({
    required this.states,
    required this.bounds,
    required this.attribution,
  });

  final Map<String, NigeriaStateShape> states;

  /// Geographic bounds: left/right are longitude, top/bottom are min/max latitude.
  final Rect bounds;
  final String attribution;

  static Future<NigeriaMapGeometry>? _cached;

  static Future<NigeriaMapGeometry> load() => _cached ??= rootBundle
      .loadString(nigeriaStatesAsset)
      .then(parse)
      .catchError((Object error) {
        _cached = null;
        throw error;
      });

  static NigeriaMapGeometry parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final rawStates = json['states'] as Map<String, dynamic>;
    final states = <String, NigeriaStateShape>{};
    Rect? all;
    for (final entry in rawStates.entries) {
      final raw = entry.value as Map<String, dynamic>;
      final rings = <List<Offset>>[];
      Rect? stateBounds;
      for (final flat in raw['rings'] as List<dynamic>) {
        final values = (flat as List<dynamic>).cast<num>();
        final ring = <Offset>[
          for (var i = 0; i + 1 < values.length; i += 2)
            Offset(values[i].toDouble(), values[i + 1].toDouble()),
        ];
        rings.add(ring);
        final ringBounds = _boundsOf(ring);
        stateBounds = stateBounds?.expandToInclude(ringBounds) ?? ringBounds;
      }
      final label = (raw['label'] as List<dynamic>).cast<num>();
      states[entry.key] = NigeriaStateShape(
        stateId: entry.key,
        rings: rings,
        labelPoint: Offset(label[0].toDouble(), label[1].toDouble()),
        bounds: stateBounds!,
      );
      all = all?.expandToInclude(stateBounds) ?? stateBounds;
    }
    return NigeriaMapGeometry(
      states: states,
      bounds: all!,
      attribution: json['attribution'] as String? ?? '',
    );
  }

  String? stateAt(double latitude, double longitude) {
    for (final shape in states.values) {
      if (shape.contains(latitude, longitude)) return shape.stateId;
    }
    return null;
  }

  Rect boundsFor(Iterable<String> stateIds) {
    Rect? result;
    for (final id in stateIds) {
      final shape = states[id];
      if (shape == null) continue;
      result = result?.expandToInclude(shape.bounds) ?? shape.bounds;
    }
    return result ?? bounds;
  }

  static Rect _boundsOf(List<Offset> ring) {
    var minX = double.infinity, minY = double.infinity;
    var maxX = -double.infinity, maxY = -double.infinity;
    for (final p in ring) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }
}

/// Fits geographic bounds into a widget size (equirectangular, latitude-corrected).
class NigeriaMapProjection {
  factory NigeriaMapProjection.fit(
    Rect geoBounds,
    Size size, {
    double padding = 18,
  }) {
    final kx = math.cos(geoBounds.center.dy * math.pi / 180);
    final width = math.max(geoBounds.width * kx, 1e-6);
    final height = math.max(geoBounds.height, 1e-6);
    final scale = math.max(
      0.0,
      math.min(
        (size.width - padding * 2) / width,
        (size.height - padding * 2) / height,
      ),
    );
    return NigeriaMapProjection._(
      geoBounds: geoBounds,
      size: size,
      kx: kx,
      scale: scale,
      origin: Offset(
        (size.width - width * scale) / 2,
        (size.height - height * scale) / 2,
      ),
    );
  }

  const NigeriaMapProjection._({
    required this.geoBounds,
    required this.size,
    required this.kx,
    required this.scale,
    required this.origin,
  });

  final Rect geoBounds;
  final Size size;
  final double kx;
  final double scale;
  final Offset origin;

  Offset project(double latitude, double longitude) => Offset(
        origin.dx + (longitude - geoBounds.left) * kx * scale,
        origin.dy + (geoBounds.bottom - latitude) * scale,
      );

  Offset projectGeo(Offset lngLat) => project(lngLat.dy, lngLat.dx);

  Path pathFor(NigeriaStateShape shape) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in shape.rings) {
      if (ring.isEmpty) continue;
      path.addPolygon([for (final p in ring) projectGeo(p)], true);
    }
    return path;
  }
}

/// Visual palette for the map surface.
class NigeriaMapStyle {
  const NigeriaMapStyle({
    required this.background,
    required this.border,
    required this.mutedFill,
    required this.hoverBorder,
    required this.selectedBorder,
    required this.labelDark,
    required this.labelLight,
    required this.captionColor,
  });

  static const light = NigeriaMapStyle(
    background: TgcgColors.surfaceSoft,
    border: Colors.white,
    mutedFill: Color(0xFFE3E9E6),
    hoverBorder: TgcgColors.primary,
    selectedBorder: TgcgColors.accent,
    labelDark: TgcgColors.ink,
    labelLight: Colors.white,
    captionColor: TgcgColors.muted,
  );

  static const dark = NigeriaMapStyle(
    background: TgcgColors.primaryDark,
    border: Color(0xFF3F6A60),
    mutedFill: Color(0xFF143730),
    hoverBorder: Color(0xFFB8CEC6),
    selectedBorder: TgcgColors.accent,
    labelDark: Color(0xFF0B2520),
    labelLight: Color(0xFFB8CEC6),
    captionColor: Color(0xFF8FB0A6),
  );

  final Color background;
  final Color border;
  final Color mutedFill;
  final Color hoverBorder;
  final Color selectedBorder;
  final Color labelDark;
  final Color labelLight;
  final Color captionColor;
}

/// Interactive map of Nigeria drawn from real state boundaries.
class NigeriaStateMapView extends StatefulWidget {
  const NigeriaStateMapView({
    super.key,
    required this.fillFor,
    this.style = NigeriaMapStyle.light,
    this.selectedStateId,
    this.onStateTap,
    this.isInteractive,
    this.labelFor,
    this.tooltipFor,
    this.focusStateIds = const [],
    this.overlayBuilder,
    this.padding = 18,
  });

  /// Fill colour for each state id; null draws the style's muted fill.
  final Color? Function(String stateId) fillFor;
  final NigeriaMapStyle style;
  final String? selectedStateId;
  final ValueChanged<String>? onStateTap;
  final bool Function(String stateId)? isInteractive;

  /// Short on-map label (e.g. state code); null hides it.
  final String? Function(String stateId)? labelFor;
  final String Function(String stateId)? tooltipFor;

  /// When non-empty, the viewport fits these states instead of all of Nigeria.
  final List<String> focusStateIds;

  /// Builds positioned widgets (markers) on top of the map.
  final List<Widget> Function(
    NigeriaMapGeometry geometry,
    NigeriaMapProjection projection,
  )? overlayBuilder;
  final double padding;

  @override
  State<NigeriaStateMapView> createState() => _NigeriaStateMapViewState();
}

class _NigeriaStateMapViewState extends State<NigeriaStateMapView> {
  late final Future<NigeriaMapGeometry> _geometry = NigeriaMapGeometry.load();
  NigeriaMapProjection? _projection;
  Map<String, Path> _paths = const {};
  String? _hoveredStateId;
  Offset? _hoverPosition;

  @override
  Widget build(BuildContext context) => FutureBuilder<NigeriaMapGeometry>(
        future: _geometry,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Map boundaries could not be loaded.',
                style: TextStyle(
                  color: widget.style.captionColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            );
          }
          final geometry = snapshot.data;
          if (geometry == null) {
            return const Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) =>
                _buildMap(geometry, constraints.biggest),
          );
        },
      );

  Widget _buildMap(NigeriaMapGeometry geometry, Size size) {
    final viewBounds = widget.focusStateIds.isEmpty
        ? geometry.bounds
        : geometry.boundsFor(widget.focusStateIds);
    var projection = _projection;
    if (projection == null ||
        projection.size != size ||
        projection.geoBounds != viewBounds) {
      projection = _projection =
          NigeriaMapProjection.fit(viewBounds, size, padding: widget.padding);
      _paths = {
        for (final shape in geometry.states.values)
          shape.stateId: projection.pathFor(shape),
      };
    }
    final paths = _paths;

    String? hitTest(Offset position) {
      for (final entry in paths.entries) {
        if (entry.value.contains(position)) return entry.key;
      }
      return null;
    }

    bool interactive(String id) =>
        widget.onStateTap != null && (widget.isInteractive?.call(id) ?? true);

    final hovered = _hoveredStateId;
    final tooltip = hovered == null ? null : widget.tooltipFor?.call(hovered);

    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: MouseRegion(
              cursor: hovered != null && interactive(hovered)
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onHover: (event) {
                final id = hitTest(event.localPosition);
                // Tooltip follows the cursor, so only skip when nothing changes.
                if (id != _hoveredStateId ||
                    (id != null && widget.tooltipFor != null)) {
                  setState(() {
                    _hoveredStateId = id;
                    _hoverPosition = event.localPosition;
                  });
                }
              },
              onExit: (_) => setState(() {
                _hoveredStateId = null;
                _hoverPosition = null;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final id = hitTest(details.localPosition);
                  if (id != null && interactive(id)) widget.onStateTap!(id);
                },
                child: CustomPaint(
                  size: size,
                  painter: _NigeriaMapPainter(
                    geometry: geometry,
                    projection: projection,
                    paths: paths,
                    style: widget.style,
                    fillFor: widget.fillFor,
                    labelFor: widget.labelFor,
                    selectedStateId: widget.selectedStateId,
                    hoveredStateId: hovered,
                  ),
                ),
              ),
            ),
          ),
          if (widget.overlayBuilder != null)
            ...widget.overlayBuilder!(geometry, projection),
          if (tooltip != null && _hoverPosition != null)
            Positioned(
              left: math.min(_hoverPosition!.dx + 14, size.width - 220),
              top: math.max(_hoverPosition!.dy - 34, 4),
              child: IgnorePointer(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 210),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xEE0B2520),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tooltip,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          if (geometry.attribution.isNotEmpty)
            Positioned(
              right: 8,
              bottom: 4,
              child: IgnorePointer(
                child: Text(
                  geometry.attribution,
                  style: TextStyle(
                    color: widget.style.captionColor.withValues(alpha: .8),
                    fontSize: 8,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NigeriaMapPainter extends CustomPainter {
  _NigeriaMapPainter({
    required this.geometry,
    required this.projection,
    required this.paths,
    required this.style,
    required this.fillFor,
    required this.labelFor,
    required this.selectedStateId,
    required this.hoveredStateId,
  });

  final NigeriaMapGeometry geometry;
  final NigeriaMapProjection projection;
  final Map<String, Path> paths;
  final NigeriaMapStyle style;
  final Color? Function(String stateId) fillFor;
  final String? Function(String stateId)? labelFor;
  final String? selectedStateId;
  final String? hoveredStateId;

  @override
  void paint(Canvas canvas, Size size) {
    final fills = <String, Color>{};
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeJoin = StrokeJoin.round
      ..color = style.border;

    for (final entry in paths.entries) {
      final fill = fillFor(entry.key) ?? style.mutedFill;
      fills[entry.key] = fill;
      canvas.drawPath(entry.value, Paint()..color = fill);
    }
    for (final path in paths.values) {
      canvas.drawPath(path, borderPaint);
    }

    final hovered = paths[hoveredStateId];
    if (hovered != null && hoveredStateId != selectedStateId) {
      canvas.drawPath(
        hovered,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = style.hoverBorder,
      );
    }
    final selected = paths[selectedStateId];
    if (selected != null) {
      canvas.drawPath(
        selected,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeJoin = StrokeJoin.round
          ..color = style.selectedBorder,
      );
    }

    final labeler = labelFor;
    if (labeler == null) return;
    final fontSize = (projection.scale * .2).clamp(7.0, 12.0);
    for (final shape in geometry.states.values) {
      final text = labeler(shape.stateId);
      if (text == null || text.isEmpty) continue;
      final fill = fills[shape.stateId] ?? style.mutedFill;
      final color = fill.computeLuminance() > .45
          ? style.labelDark
          : style.labelLight;
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            color: color,
            fontSize: fontSize,
            height: 1.1,
            fontWeight: FontWeight.w900,
            letterSpacing: .2,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      final center = projection.projectGeo(shape.labelPoint);
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NigeriaMapPainter old) =>
      old.projection.size != projection.size ||
      old.projection.geoBounds != projection.geoBounds ||
      old.style != style ||
      old.selectedStateId != selectedStateId ||
      old.hoveredStateId != hoveredStateId ||
      old.fillFor != fillFor ||
      old.labelFor != labelFor;
}
