import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'nigeria_map.dart';

/// One INEC ward and how many polling units it has.
class WardInfo {
  const WardInfo({required this.code, required this.name, required this.pollingUnits});

  /// INEC ward code, e.g. 18-23-01.
  final String code;
  final String name;
  final int pollingUnits;
}

/// All wards of one LGA, with boundaries where GRID3 publishes them.
class LgaWards {
  const LgaWards({
    required this.lgaCode,
    required this.wards,
    required this.shapes,
    required this.attribution,
  });

  final String lgaCode;

  /// Every INEC ward in the LGA, in code order.
  final List<WardInfo> wards;

  /// Ward boundaries keyed by ward code; null when none are published for
  /// this LGA's state yet.
  final GeoShapeSet? shapes;
  final String attribution;

  int get pollingUnits => wards.fold(0, (total, ward) => total + ward.pollingUnits);
  int get mappedWards => shapes?.shapes.length ?? 0;

  static final _cache = <String, Future<LgaWards>>{};

  /// Loads `assets/geo/ward/<lga>.json` once per LGA.
  static Future<LgaWards> load(String lgaCode) => _cache[lgaCode] ??= rootBundle
      .loadString(nigeriaWardAsset(lgaCode))
      .then((source) => parse(source))
      .catchError((Object error) {
        _cache.remove(lgaCode);
        throw error;
      });

  static LgaWards parse(String source) {
    final json = jsonDecode(source) as Map<String, dynamic>;
    final raw = json['wards'] as Map<String, dynamic>;
    final attribution = json['attribution'] as String? ?? '';
    return LgaWards(
      lgaCode: json['lga'] as String,
      wards: [
        for (final entry in raw.entries)
          WardInfo(
            code: entry.key,
            name: (entry.value as Map<String, dynamic>)['name'] as String,
            pollingUnits: entry.value['pus'] as int,
          ),
      ]..sort((a, b) => a.code.compareTo(b.code)),
      shapes: GeoShapeSet.fromJsonMap(raw, attribution: attribution),
      attribution: attribution,
    );
  }
}
