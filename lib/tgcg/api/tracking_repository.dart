import '../domain/models.dart';
import 'api_client.dart';
import 'auth_repository.dart';

/// How an agent's position compares with their polling unit (server's LocationStatus).
enum AgentLocationStatus { onSite, away, unverified, suspect, noGps }

AgentLocationStatus _status(Object? value) =>
    AgentLocationStatus.values.asNameMap()[value] ?? AgentLocationStatus.unverified;

/// An agent's latest GPS reading.
class AgentPosition {
  const AgentPosition({
    required this.latitude,
    required this.longitude,
    required this.status,
    this.accuracyMeters,
    this.capturedAt,
    this.isMocked = false,
    this.distanceToUnitMeters,
  });

  final double latitude;
  final double longitude;
  final AgentLocationStatus status;
  final double? accuracyMeters;
  final DateTime? capturedAt;
  final bool isMocked;

  /// Metres from the agent's polling unit, when the unit has a location.
  final int? distanceToUnitMeters;

  static AgentPosition? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    final latitude = double.tryParse('${json['latitude']}');
    final longitude = double.tryParse('${json['longitude']}');
    if (latitude == null || longitude == null) return null;
    return AgentPosition(
      latitude: latitude,
      longitude: longitude,
      status: _status(json['status']),
      accuracyMeters: (json['accuracy_m'] as num?)?.toDouble(),
      capturedAt: DateTime.tryParse('${json['captured_at']}'),
      isMocked: json['is_mocked'] as bool? ?? false,
      distanceToUnitMeters: json['distance_to_pu_m'] as int?,
    );
  }
}

/// An agent who is on duty now.
class LiveAgent {
  const LiveAgent({
    required this.agentId,
    required this.name,
    required this.onDutySince,
    required this.stale,
    this.pollingUnit,
    this.position,
  });

  final String agentId;
  final String name;
  final String? pollingUnit;
  final DateTime onDutySince;
  final AgentPosition? position;

  /// No reading for a while (the server's LIVE_STALE_MINUTES).
  final bool stale;

  factory LiveAgent.fromJson(Map<String, dynamic> json) => LiveAgent(
        agentId: json['agent'] as String,
        name: json['name'] as String,
        pollingUnit: json['polling_unit'] as String?,
        onDutySince: DateTime.parse(json['on_duty_since'] as String),
        position: AgentPosition.fromJson(json['position']),
        stale: json['stale'] as bool? ?? true,
      );
}

class LiveAgents {
  const LiveAgents({required this.scope, required this.agents});
  final GeographicScope scope;
  final List<LiveAgent> agents;

  factory LiveAgents.fromJson(Map<String, dynamic> json) => LiveAgents(
        scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
        agents: [
          for (final item in json['agents'] as List<dynamic>)
            LiveAgent.fromJson(item as Map<String, dynamic>),
        ],
      );
}

/// Today's check-in counts for one area's polling-unit agents.
class CoverageTally {
  const CoverageTally({
    this.agents = 0,
    this.checkedIn = 0,
    this.notCheckedIn = 0,
    this.onSite = 0,
    this.away = 0,
    this.unverified = 0,
    this.suspect = 0,
    this.onDutyNow = 0,
  });

  final int agents;
  final int checkedIn;
  final int notCheckedIn;
  final int onSite;
  final int away;
  final int unverified;
  final int suspect;
  final int onDutyNow;

  double get checkedInShare => agents == 0 ? 0 : checkedIn / agents;

  factory CoverageTally.fromJson(Map<String, dynamic> json) => CoverageTally(
        agents: (json['agents'] as int?) ?? 0,
        checkedIn: (json['checked_in'] as int?) ?? 0,
        notCheckedIn: (json['not_checked_in'] as int?) ?? 0,
        onSite: (json['on_site'] as int?) ?? 0,
        away: (json['away'] as int?) ?? 0,
        unverified: (json['unverified'] as int?) ?? 0,
        suspect: (json['suspect'] as int?) ?? 0,
        onDutyNow: (json['on_duty_now'] as int?) ?? 0,
      );
}

/// One sub-area in a coverage breakdown.
class CoverageArea {
  const CoverageArea({
    required this.level,
    required this.code,
    required this.name,
    required this.tally,
  });

  final GeographyLevel level;
  final String code;
  final String name;
  final CoverageTally tally;

  factory CoverageArea.fromJson(Map<String, dynamic> json) => CoverageArea(
        level: GeographyLevel.values.byName(json['level'] as String),
        code: json['code'] as String,
        name: json['name'] as String,
        tally: CoverageTally.fromJson(json),
      );
}

class Coverage {
  const Coverage({
    required this.scope,
    required this.total,
    this.children = const [],
  });

  final GeographicScope scope;
  final CoverageTally total;

  /// The next level down (e.g. LGAs of a senatorial district), when there is one.
  final List<CoverageArea> children;

  factory Coverage.fromJson(Map<String, dynamic> json) => Coverage(
        scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
        total: CoverageTally.fromJson(json),
        children: [
          for (final item in (json['children'] as List<dynamic>? ?? const []))
            CoverageArea.fromJson(item as Map<String, dynamic>),
        ],
      );
}

/// Where agents are and whether they checked in (`/tracking/...`).
class TrackingRepository {
  TrackingRepository(this.client);
  final ApiClient client;

  static Map<String, String>? _area(GeographyLevel? level, String? code) =>
      level == null ? null : {'level': level.name, 'code': ?code};

  /// On-duty agents with their latest position, in [level]/[code] or your scope.
  Future<LiveAgents> live({GeographyLevel? level, String? code}) async => LiveAgents.fromJson(
        await client.get('tracking/live/', query: _area(level, code)) as Map<String, dynamic>,
      );

  /// Today's check-in coverage, in [level]/[code] or your scope.
  Future<Coverage> coverage({GeographyLevel? level, String? code}) async => Coverage.fromJson(
        await client.get('tracking/coverage/', query: _area(level, code)) as Map<String, dynamic>,
      );
}
