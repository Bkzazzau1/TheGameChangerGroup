import '../domain/models.dart';
import 'api_client.dart';
import 'auth_repository.dart';

class ServerParty {
  const ServerParty({required this.acronym, required this.name});
  final String acronym;
  final String name;
}

class ServerElection {
  const ServerElection({
    required this.code,
    required this.name,
    required this.type,
    required this.status,
    required this.parties,
    required this.scope,
  });

  final String code;
  final String name;
  final String type;
  final String status;
  final List<ServerParty> parties;
  final GeographicScope scope;

  factory ServerElection.fromJson(Map<String, dynamic> json) => ServerElection(
        code: json['code'] as String,
        name: json['name'] as String,
        type: json['type'] as String,
        status: json['status'] as String,
        parties: [
          for (final party in json['parties'] as List<dynamic>)
            ServerParty(
              acronym: (party as Map<String, dynamic>)['acronym'] as String,
              name: party['name'] as String,
            ),
        ],
        scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
      );
}

/// Where to send someone travelling to a polling unit. The server only
/// offers it once the unit has been pinned in the mapping exercise.
class UnitDirections {
  const UnitDirections({
    required this.latitude,
    required this.longitude,
    required this.confirmed,
    this.accuracyMeters,
    this.source,
    this.note = '',
  });

  final double latitude;
  final double longitude;

  /// False until a coordinator on site has confirmed the location.
  final bool confirmed;
  final double? accuracyMeters;

  /// Where the location came from: inec, coordinator, checkIn or imported.
  final String? source;

  /// Something to check about the location, such as an INEC point that lies
  /// just inside the neighbouring LGA. Empty when there is nothing to check.
  final String note;

  static UnitDirections? fromJson(Object? json) {
    if (json is! Map<String, dynamic>) return null;
    return UnitDirections(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      confirmed: json['confirmed'] as bool? ?? false,
      accuracyMeters: (json['accuracy_m'] as num?)?.toDouble(),
      source: json['source'] as String?,
      note: (json['note'] as String?) ?? '',
    );
  }
}

class ServerPollingUnit {
  const ServerPollingUnit({
    required this.code,
    required this.name,
    required this.wardCode,
    this.registeredVoters,
    this.directions,
  });

  final String code;
  final String name;
  final String wardCode;
  final int? registeredVoters;
  final UnitDirections? directions;
}

/// The polling unit a PVC DELIM code points to.
class DelimUnit {
  const DelimUnit({
    required this.code,
    required this.name,
    required this.ward,
    required this.lga,
    required this.state,
  });

  final String code;
  final String name;
  final String ward;
  final String lga;
  final String state;

  String get label => '$name, $ward ward, $lga LGA, $state State';
}

/// A state, LGA, ward or polling unit in the lists for finding a polling
/// unit by name while registering.
class RegistrationPlace {
  const RegistrationPlace({required this.code, required this.name, this.location = ''});

  final String code;
  final String name;

  /// INEC's location note; polling units only.
  final String location;
}

/// Reference data the field screens need from the server.
class ReferenceRepository {
  ReferenceRepository(this.client);
  final ApiClient client;

  /// Elections taking results now: while a project naming them runs, or,
  /// with no project, while open.
  Future<List<ServerElection>> openElections() async {
    final body = await client.get('elections/', query: {'accepting': 'true'}) as List<dynamic>;
    return [for (final item in body) ServerElection.fromJson(item as Map<String, dynamic>)];
  }

  Future<List<ServerElection>> elections() async {
    final body = await client.get('elections/') as List<dynamic>;
    return [for (final item in body) ServerElection.fromJson(item as Map<String, dynamic>)];
  }

  /// Polling units inside [scope] (an agent gets their own unit).
  Future<List<ServerPollingUnit>> pollingUnitsWithin(GeographicScope scope) async {
    final query = <String, String>{'limit': '2000', 'ordering': 'code'};
    final filter = switch (scope.level) {
      GeographyLevel.pollingUnit => null,
      GeographyLevel.ward => ('ward__code', scope.wardId),
      GeographyLevel.lga => ('ward__lga__code', scope.lgaId),
      GeographyLevel.state => ('ward__lga__state__code', scope.stateId),
      _ => null,
    };
    if (scope.level == GeographyLevel.pollingUnit) {
      final unit = await client.get('geography/polling-units/${scope.pollingUnitId}/');
      return [_unit(unit as Map<String, dynamic>)];
    }
    if (filter == null || filter.$2 == null) return const [];
    query[filter.$1] = filter.$2!;
    final body = await client.get('geography/polling-units/', query: query) as Map<String, dynamic>;
    return [for (final item in body['results'] as List<dynamic>) _unit(item as Map<String, dynamic>)];
  }

  /// One polling unit, with directions when it has been mapped.
  Future<ServerPollingUnit> pollingUnit(String code) async =>
      _unit(await client.get('geography/polling-units/$code/') as Map<String, dynamic>);

  /// Resolves the DELIM code printed on a PVC (e.g. 18/23/01/001).
  Future<DelimUnit> pollingUnitForDelim(String delim) async {
    final json = await client.get('register/polling-unit/', query: {'delim': delim})
        as Map<String, dynamic>;
    return DelimUnit(
      code: json['code'] as String,
      name: json['name'] as String,
      ward: json['ward'] as String,
      lga: json['lga'] as String,
      state: json['state'] as String,
    );
  }

  /// A list for finding a polling unit by name while registering: the
  /// states, or the LGAs of [state], the wards of [lga] or the polling units
  /// of [ward] (give at most one), sorted by name. No sign-in is needed.
  Future<List<RegistrationPlace>> registrationPlaces({String? state, String? lga, String? ward}) async {
    final (path, query) = switch ((state, lga, ward)) {
      (_, _, final ward?) => ('polling-units', {'ward': ward}),
      (_, final lga?, _) => ('wards', {'lga': lga}),
      (final state?, _, _) => ('lgas', {'state': state}),
      _ => ('states', null),
    };
    final body = await client.get('register/places/$path/', query: query, authenticated: false)
        as List<dynamic>;
    return [
      for (final item in body.cast<Map<String, dynamic>>())
        RegistrationPlace(
          code: item['code'] as String,
          name: item['name'] as String,
          location: (item['location'] as String?) ?? '',
        ),
    ];
  }

  static ServerPollingUnit _unit(Map<String, dynamic> json) => ServerPollingUnit(
        code: json['code'] as String,
        name: json['name'] as String,
        wardCode: json['ward'] as String,
        registeredVoters: json['registered_voters'] as int?,
        directions: UnitDirections.fromJson(json['navigation']),
      );
}
