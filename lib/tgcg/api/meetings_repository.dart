import '../domain/models.dart';
import 'api_client.dart';
import 'auth_repository.dart' show geographicScopeFromJson;

enum MeetingKind { audio, video }

/// Everyone in the meeting's area, or only the people invited.
enum MeetingAudience { area, invited }

/// Live: open to join (from 15 minutes before the start until it ends).
enum MeetingStatus { scheduled, live, ended, cancelled }

/// A meeting on the server (`/meetings/`).
class ServerMeeting {
  const ServerMeeting({
    required this.reference,
    required this.title,
    required this.kind,
    required this.audience,
    required this.scope,
    required this.startsAt,
    required this.endsAt,
    required this.durationMinutes,
    required this.status,
    required this.host,
    required this.hostName,
    this.agenda = '',
    this.invitees = const [],
    this.admitted = 0,
    this.canJoin = false,
    this.canManage = false,
    this.callsAvailable = false,
    this.cancelReason = '',
  });

  final String reference;
  final String title;
  final String agenda;
  final MeetingKind kind;
  final MeetingAudience audience;

  /// The area the meeting is for.
  final GeographicScope scope;
  final DateTime startsAt;
  final DateTime endsAt;
  final int durationMinutes;
  final MeetingStatus status;

  /// The access ID and name of whoever called it.
  final String host;
  final String hostName;

  /// Access IDs of the people invited.
  final List<String> invitees;

  /// People let in so far.
  final int admitted;
  final bool canJoin;

  /// May end or cancel it: the host, or a coordinator over the whole area.
  final bool canManage;

  /// False until calls are set up on the server.
  final bool callsAvailable;
  final String cancelReason;

  factory ServerMeeting.fromJson(Map<String, dynamic> json) => ServerMeeting(
        reference: json['reference'] as String,
        title: json['title'] as String,
        agenda: json['agenda'] as String? ?? '',
        kind: MeetingKind.values.byName(json['kind'] as String),
        audience: MeetingAudience.values.byName(json['audience'] as String),
        scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
        startsAt: DateTime.parse(json['starts_at'] as String),
        endsAt: DateTime.parse(json['ends_at'] as String),
        durationMinutes: json['duration_minutes'] as int,
        status: MeetingStatus.values.byName(json['status'] as String),
        host: json['host'] as String,
        hostName: json['host_name'] as String? ?? '',
        invitees: [for (final item in json['invitees'] as List<dynamic>? ?? const []) '$item'],
        admitted: json['admitted'] as int? ?? 0,
        canJoin: json['can_join'] as bool? ?? false,
        canManage: json['can_manage'] as bool? ?? false,
        callsAvailable: json['calls_available'] as bool? ?? false,
        cancelReason: json['cancel_reason'] as String? ?? '',
      );
}

/// What it takes to join a meeting's call: the LiveKit server and a pass
/// for its room, to use within [expiresAt].
class JoinPass {
  const JoinPass({
    required this.url,
    required this.token,
    required this.room,
    required this.expiresAt,
  });

  final String url;
  final String token;
  final String room;
  final DateTime expiresAt;

  factory JoinPass.fromJson(Map<String, dynamic> json) => JoinPass(
        url: json['url'] as String,
        token: json['token'] as String,
        room: json['room'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

/// The server's id key for an area at each level, as its scope field reads it.
Map<String, String> scopeInput(GeographicScope scope) {
  final (key, code) = switch (scope.level) {
    GeographyLevel.country => (null, null),
    GeographyLevel.geopoliticalZone => ('zoneId', scope.zoneId),
    GeographyLevel.state => ('stateId', scope.stateId),
    GeographyLevel.senatorialDistrict => ('senatorialDistrictId', scope.senatorialDistrictId),
    GeographyLevel.lga => ('lgaId', scope.lgaId),
    GeographyLevel.ward => ('wardId', scope.wardId),
    GeographyLevel.pollingUnit => ('pollingUnitId', scope.pollingUnitId),
  };
  return {'level': scope.level.name, if (key != null && code != null) key: code};
}

/// Meetings and their calls (`/meetings/`). The server decides who sees and
/// joins each meeting; the calls themselves run on LiveKit.
class MeetingsRepository {
  MeetingsRepository(this.client);
  final ApiClient client;

  /// Meetings you called, are invited to, or that are for your area, from
  /// [since] on (the server's default: the last day on).
  Future<List<ServerMeeting>> list({DateTime? since}) async {
    final body = await client.get('meetings/', query: {
      'limit': '200',
      if (since != null) 'since': since.toUtc().toIso8601String(),
    }) as Map<String, dynamic>;
    return [
      for (final item in body['results'] as List<dynamic>)
        ServerMeeting.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Calls a meeting, for your own area unless [scope] names one inside it.
  Future<ServerMeeting> create({
    required String title,
    String agenda = '',
    MeetingKind kind = MeetingKind.audio,
    MeetingAudience audience = MeetingAudience.area,
    DateTime? startsAt,
    int durationMinutes = 60,
    GeographicScope? scope,
    List<String> invitees = const [],
  }) async =>
      ServerMeeting.fromJson(
        await client.post('meetings/', body: {
          'title': title.trim(),
          'agenda': agenda.trim(),
          'kind': kind.name,
          'audience': audience.name,
          if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
          'duration_minutes': durationMinutes,
          if (scope != null) 'scope': scopeInput(scope),
          'invitees': invitees,
        }) as Map<String, dynamic>,
      );

  /// A pass to join the meeting's call, while it is open.
  Future<JoinPass> join(String reference) async =>
      JoinPass.fromJson(await client.post('meetings/$reference/join/') as Map<String, dynamic>);

  /// Ends the meeting for everyone in it.
  Future<ServerMeeting> end(String reference) async => ServerMeeting.fromJson(
        await client.post('meetings/$reference/end/') as Map<String, dynamic>,
      );

  /// Calls the meeting off; a reason is required.
  Future<ServerMeeting> cancel(String reference, {required String reason}) async =>
      ServerMeeting.fromJson(
        await client.post('meetings/$reference/cancel/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );
}
