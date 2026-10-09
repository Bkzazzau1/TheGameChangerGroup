import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../ui/tgcg_design.dart';

const nigeriaStatesAsset = 'assets/geo/nigeria_states.json';

String nigeriaLgaAsset(String stateId) => 'assets/geo/lga/$stateId.json';

/// One boundary (state or LGA) in geographic space. Offsets are (lng, lat).
class GeoShape {
  const GeoShape({
    required this.id,
    required this.rings,
    required this.labelPoint,
    required this.bounds,
    this.name,
  });

  final String id;
  final String? name;
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

/// A set of boundaries keyed by canonical id: Nigeria's states (keyed by
/// state id) or one state's LGAs (keyed by canonical LGA id, e.g. `LA-IKEJA`).
///
/// Source: GRID3 / geoBoundaries ADM1 and ADM2 (2022), simplified, CC BY 4.0.
class GeoShapeSet {
  const GeoShapeSet({
    required this.shapes,
    required this.bounds,
    required this.attribution,
  });

  final Map<String, GeoShape> shapes;

  /// Geographic bounds: left/right are longitude, top/bottom are min/max latitude.
  final Rect bounds;
  final String attribution;

  static Future<GeoShapeSet>? _states;
  static final _lgas = <String, Future<GeoShapeSet>>{};

  /// All 36 states and FCT.
  static Future<GeoShapeSet> nigeriaStates() =>
      _states ??= _load(nigeriaStatesAsset, 'states', () => _states = null);

  /// LGAs of one state, loaded on demand.
  static Future<GeoShapeSet> lgasOf(String stateId) => _lgas[stateId] ??=
      _load(nigeriaLgaAsset(stateId), 'lgas', () => _lgas.remove(stateId));

  static Future<GeoShapeSet> _load(
    String asset,
    String key,
    void Function() evict,
  ) =>
      rootBundle
          .loadString(asset)
          .then((source) => parse(source, key))
          .catchError((Object error) {
        evict();
        throw error;
      });

  static GeoShapeSet parse(String source, String key) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final raw = json[key] as Map<String, dynamic>;
    final shapes = <String, GeoShape>{};
    Rect? all;
    for (final entry in raw.entries) {
      final item = entry.value as Map<String, dynamic>;
      final rings = <List<Offset>>[];
      Rect? shapeBounds;
      for (final flat in item['rings'] as List<dynamic>) {
        final values = (flat as List<dynamic>).cast<num>();
        final ring = <Offset>[
          for (var i = 0; i + 1 < values.length; i += 2)
            Offset(values[i].toDouble(), values[i + 1].toDouble()),
        ];
        rings.add(ring);
        final ringBounds = _boundsOf(ring);
        shapeBounds = shapeBounds?.expandToInclude(ringBounds) ?? ringBounds;
      }
      final label = (item['label'] as List<dynamic>).cast<num>();
      shapes[entry.key] = GeoShape(
        id: entry.key,
        name: item['name'] as String?,
        rings: rings,
        labelPoint: Offset(label[0].toDouble(), label[1].toDouble()),
        bounds: shapeBounds!,
      );
      all = all?.expandToInclude(shapeBounds) ?? shapeBounds;
    }
    return GeoShapeSet(
      shapes: shapes,
      bounds: all!,
      attribution: json['attribution'] as String? ?? '',
    );
  }

  /// Id of the shape containing the point, or null.
  String? idAt(double latitude, double longitude) {
    for (final shape in shapes.values) {
      if (shape.contains(latitude, longitude)) return shape.id;
    }
    return null;
  }

  Rect boundsFor(Iterable<String> ids) {
    Rect? result;
    for (final id in ids) {
      final shape = shapes[id];
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
class GeoProjection {
  factory GeoProjection.fit(
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
    return GeoProjection._(
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

  const GeoProjection._({
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

  double projectedWidth(Rect geo) => geo.width * kx * scale;

  Path pathFor(GeoShape shape) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final ring in shape.rings) {
      if (ring.isEmpty) continue;
      path.addPolygon([for (final p in ring) projectGeo(p)], true);
    }
    return path;
  }
}

/// Visual palette for the map surface.
class GeoMapStyle {
  const GeoMapStyle({
    required this.background,
    required this.border,
    required this.mutedFill,
    required this.hoverBorder,
    required this.selectedBorder,
    required this.labelDark,
    required this.labelLight,
    required this.captionColor,
  });

  static const light = GeoMapStyle(
    background: TgcgColors.surfaceSoft,
    border: Colors.white,
    mutedFill: Color(0xFFE3E9E6),
    hoverBorder: TgcgColors.primary,
    selectedBorder: TgcgColors.accent,
    labelDark: TgcgColors.ink,
    labelLight: Colors.white,
    captionColor: TgcgColors.muted,
  );

  static const dark = GeoMapStyle(
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

/// Interactive choropleth map of a [GeoShapeSet] (states or a state's LGAs).
class GeoShapeMapView extends StatefulWidget {
  const GeoShapeMapView({
    super.key,
    required this.source,
    required this.fillFor,
    this.style = GeoMapStyle.light,
    this.selectedId,
    this.onTap,
    this.isInteractive,
    this.labelFor,
    this.fitLabels = false,
    this.labelFontSize,
    this.tooltipFor,
    this.focusIds = const [],
    this.overlayBuilder,
    this.padding = 18,
  });

  /// Pass a cached future, e.g. [GeoShapeSet.nigeriaStates].
  final Future<GeoShapeSet> source;

  /// Fill colour for each shape id; null draws the style's muted fill.
  final Color? Function(String id) fillFor;
  final GeoMapStyle style;
  final String? selectedId;
  final ValueChanged<String>? onTap;
  final bool Function(String id)? isInteractive;

  /// Short on-map label; null hides it.
  final String? Function(String id)? labelFor;

  /// Hide labels wider than their shape (useful for dense LGA maps).
  final bool fitLabels;
  final double? labelFontSize;
  final String Function(String id)? tooltipFor;

  /// When non-empty, the viewport fits these shapes instead of the whole set.
  final List<String> focusIds;

  /// Builds positioned widgets (markers) on top of the map.
  final List<Widget> Function(GeoShapeSet shapes, GeoProjection projection)?
      overlayBuilder;
  final double padding;

  @override
  State<GeoShapeMapView> createState() => _GeoShapeMapViewState();
}

class _GeoShapeMapViewState extends State<GeoShapeMapView> {
  GeoShapeSet? _pathsFor;
  GeoProjection? _projection;
  Map<String, Path> _paths = const {};
  String? _hoveredId;
  Offset? _hoverPosition;

  @override
  Widget build(BuildContext context) => FutureBuilder<GeoShapeSet>(
        future: widget.source,
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
          final shapes = snapshot.data;
          if (shapes == null) {
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
                _buildMap(shapes, constraints.biggest),
          );
        },
      );

  Widget _buildMap(GeoShapeSet shapes, Size size) {
    final viewBounds = widget.focusIds.isEmpty
        ? shapes.bounds
        : shapes.boundsFor(widget.focusIds);
    var projection = _projection;
    if (projection == null ||
        !identical(_pathsFor, shapes) ||
        projection.size != size ||
        projection.geoBounds != viewBounds) {
      projection = _projection =
          GeoProjection.fit(viewBounds, size, padding: widget.padding);
      _pathsFor = shapes;
      _paths = {
        for (final shape in shapes.shapes.values)
          shape.id: projection.pathFor(shape),
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
        widget.onTap != null && (widget.isInteractive?.call(id) ?? true);

    final hovered = _hoveredId;
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
                if (id != _hoveredId ||
                    (id != null && widget.tooltipFor != null)) {
                  setState(() {
                    _hoveredId = id;
                    _hoverPosition = event.localPosition;
                  });
                }
              },
              onExit: (_) => setState(() {
                _hoveredId = null;
                _hoverPosition = null;
              }),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) {
                  final id = hitTest(details.localPosition);
                  if (id != null && interactive(id)) widget.onTap!(id);
                },
                child: CustomPaint(
                  size: size,
                  painter: _GeoShapePainter(
                    shapes: shapes,
                    projection: projection,
                    paths: paths,
                    style: widget.style,
                    fillFor: widget.fillFor,
                    labelFor: widget.labelFor,
                    fitLabels: widget.fitLabels,
                    labelFontSize: widget.labelFontSize,
                    selectedId: widget.selectedId,
                    hoveredId: hovered,
                  ),
                ),
              ),
            ),
          ),
          if (widget.overlayBuilder != null)
            ...widget.overlayBuilder!(shapes, projection),
          if (tooltip != null && _hoverPosition != null)
            Positioned(
              left: math.max(
                4,
                math.min(_hoverPosition!.dx + 14, size.width - 220),
              ),
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
          if (shapes.attribution.isNotEmpty)
            Positioned(
              right: 8,
              bottom: 4,
              child: IgnorePointer(
                child: Text(
                  shapes.attribution,
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

class _GeoShapePainter extends CustomPainter {
  _GeoShapePainter({
    required this.shapes,
    required this.projection,
    required this.paths,
    required this.style,
    required this.fillFor,
    required this.labelFor,
    required this.fitLabels,
    required this.labelFontSize,
    required this.selectedId,
    required this.hoveredId,
  });

  final GeoShapeSet shapes;
  final GeoProjection projection;
  final Map<String, Path> paths;
  final GeoMapStyle style;
  final Color? Function(String id) fillFor;
  final String? Function(String id)? labelFor;
  final bool fitLabels;
  final double? labelFontSize;
  final String? selectedId;
  final String? hoveredId;

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

    final hovered = paths[hoveredId];
    if (hovered != null && hoveredId != selectedId) {
      canvas.drawPath(
        hovered,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..color = style.hoverBorder,
      );
    }
    final selected = paths[selectedId];
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
    final fontSize = labelFontSize ?? (projection.scale * .2).clamp(7.0, 12.0);
    for (final shape in shapes.shapes.values) {
      final text = labeler(shape.id);
      if (text == null || text.isEmpty) continue;
      final fill = fills[shape.id] ?? style.mutedFill;
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
      if (fitLabels &&
          painter.width > projection.projectedWidth(shape.bounds) * .9) {
        continue;
      }
      final center = projection.projectGeo(shape.labelPoint);
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GeoShapePainter old) =>
      !identical(old.paths, paths) ||
      old.style != style ||
      old.selectedId != selectedId ||
      old.hoveredId != hoveredId ||
      old.fillFor != fillFor ||
      old.labelFor != labelFor;
}
