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

class ServerPollingUnit {
  const ServerPollingUnit({
    required this.code,
    required this.name,
    required this.wardCode,
    this.registeredVoters,
  });

  final String code;
  final String name;
  final String wardCode;
  final int? registeredVoters;
}

/// Reference data the field screens need from the server.
class ReferenceRepository {
  ReferenceRepository(this.client);
  final ApiClient client;

  Future<List<ServerElection>> openElections() async {
    final body = await client.get('elections/', query: {'status': 'open'}) as List<dynamic>;
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

  static ServerPollingUnit _unit(Map<String, dynamic> json) => ServerPollingUnit(
        code: json['code'] as String,
        name: json['name'] as String,
        wardCode: json['ward'] as String,
        registeredVoters: json['registered_voters'] as int?,
      );
}
