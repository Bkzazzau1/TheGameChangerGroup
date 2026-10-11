import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'api_client.dart';

enum MappingStatus { unmapped, pinned, confirmed, conflict, problem }

/// Why a unit could not be pinned (matches the backend's choices).
enum MappingProblem {
  notFound('Could not find the unit'),
  moved('The unit has moved'),
  nameMismatch('Signboard shows a different name'),
  other('Other');

  const MappingProblem(this.label);
  final String label;
}

class MappingUnit {
  const MappingUnit({
    required this.code,
    required this.name,
    required this.location,
    required this.wardCode,
    required this.wardName,
    required this.status,
    required this.pins,
    this.latitude,
    this.longitude,
    this.locationSource = '',
  });

  final String code;
  final String name;
  final String location;
  final String wardCode;
  final String wardName;
  final MappingStatus status;
  final int pins;
  final double? latitude;
  final double? longitude;

  /// Where the current location came from: inec, coordinator, checkIn or imported.
  final String locationSource;

  bool get hasLocation => latitude != null && longitude != null;

  /// Placed by INEC's polling unit locator and not yet checked on site.
  bool get locatedByInec => locationSource == 'inec' && status == MappingStatus.pinned;

  factory MappingUnit.fromJson(Map<String, dynamic> json) => MappingUnit(
        code: json['code'] as String,
        name: json['name'] as String,
        location: (json['location'] as String?) ?? '',
        wardCode: json['ward'] as String,
        wardName: json['ward_name'] as String,
        status: MappingStatus.values.byName(json['mapping_status'] as String),
        pins: (json['pins'] as int?) ?? 0,
        latitude: double.tryParse('${json['latitude']}'),
        longitude: double.tryParse('${json['longitude']}'),
        locationSource: (json['location_source'] as String?) ?? '',
      );
}

class MappingProgress {
  const MappingProgress({
    required this.total,
    required this.counts,
    required this.mappedPercent,
    this.fromInec = 0,
  });

  final int total;
  final Map<MappingStatus, int> counts;
  final double mappedPercent;

  /// Units located by INEC's locator and not yet checked on site. They are
  /// counted under [MappingStatus.pinned] too.
  final int fromInec;

  int get mapped => (counts[MappingStatus.pinned] ?? 0) + (counts[MappingStatus.confirmed] ?? 0);

  factory MappingProgress.fromJson(Map<String, dynamic> json) => MappingProgress(
        total: json['total'] as int,
        counts: {for (final s in MappingStatus.values) s: (json[s.name] as int?) ?? 0},
        mappedPercent: (json['mapped_percent'] as num).toDouble(),
        fromInec: (json['from_inec'] as int?) ?? 0,
      );
}

/// The server's verdict on a pin.
class PinOutcome {
  const PinOutcome({required this.status, this.distanceMeters});

  /// pinned, confirmed, conflict or problem.
  final String status;
  final int? distanceMeters;
}

class MappingRepository {
  MappingRepository(this.client);
  final ApiClient client;

  Future<({List<MappingUnit> units, int count})> units({
    MappingStatus? status,
    String? search,
    int limit = 200,
  }) async {
    final body = await client.get('mapping/units/', query: {
      'limit': '$limit',
      if (status != null) 'mapping_status': status.name,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    }) as Map<String, dynamic>;
    return (
      units: [
        for (final item in body['results'] as List<dynamic>)
          MappingUnit.fromJson(item as Map<String, dynamic>),
      ],
      count: body['count'] as int,
    );
  }

  Future<MappingProgress> progress() async =>
      MappingProgress.fromJson(await client.get('mapping/progress/') as Map<String, dynamic>);

  Future<PinOutcome> pin({
    required String unitCode,
    required GpsFix gps,
    required List<int> photoBytes,
    required String photoName,
    String note = '',
  }) async {
    final body = await client.postMultipart(
      'mapping/units/$unitCode/pin/',
      fields: {
        'gps': gps.toJson(),
        'at_entrance': 'true',
        'name_matches': 'true',
        'note': note,
      },
      files: () async => [http.MultipartFile.fromBytes('photo', photoBytes, filename: photoName)],
    ) as Map<String, dynamic>;
    final gpsBody = body['gps'] as Map<String, dynamic>?;
    return PinOutcome(
      status: body['status'] as String,
      distanceMeters: gpsBody?['distance_to_pu_m'] as int?,
    );
  }

  Future<void> reportProblem({
    required String unitCode,
    required MappingProblem problem,
    required String note,
  }) =>
      client.post('mapping/units/$unitCode/problem/', body: {'problem': problem.name, 'note': note});
}
