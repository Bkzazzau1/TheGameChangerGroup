import '../domain/models.dart';
import 'api_client.dart';
import 'auth_repository.dart' show geographicScopeFromJson;
import 'meetings_repository.dart' show JoinPass;

String? _text(Object? value) => value is String && value.trim().isNotEmpty ? value : null;

double? _decimal(Object? value) => value == null ? null : double.tryParse('$value');

RecordOrigin _origin(Object? value) =>
    RecordOrigin.values.asNameMap()[value] ?? RecordOrigin.localEntry;

EvidenceAttachment evidenceFromJson(Map<String, dynamic> json) => EvidenceAttachment(
      id: json['id'] as String,
      type: EvidenceType.values.byName(json['type'] as String),
      fileName: json['file_name'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      uploaderId: json['uploader'] as String? ?? '',
      contentHash: _text(json['content_hash']),
      mimeType: _text(json['mime_type']),
      caption: _text(json['caption']),
      latitude: _decimal(json['latitude']),
      longitude: _decimal(json['longitude']),
      origin: _origin(json['origin']),
    );

FieldIncident fieldIncidentFromJson(Map<String, dynamic> json) {
  final latitude = _decimal(json['latitude']);
  final longitude = _decimal(json['longitude']);
  final location = json['location'] as Map<String, dynamic>?;
  final live = json['live'] as Map<String, dynamic>?;
  final accuracy = (location?['accuracy_m'] as num?)?.toDouble();
  final capturedAt = DateTime.tryParse('${location?['captured_at']}');
  return FieldIncident(
    id: json['reference'] as String,
    title: json['title'] as String,
    category: json['category'] as String,
    severity: IncidentSeverity.values.byName(json['severity'] as String),
    status: IncidentStatus.values.byName(json['status'] as String),
    scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
    reportedAt: DateTime.parse(json['reported_at'] as String),
    reporterId: json['reporter'] as String? ?? '',
    summary: _text(json['summary']),
    assignedTeam: _text(json['assigned_team']),
    latitude: latitude,
    longitude: longitude,
    gps: latitude != null && longitude != null && accuracy != null && capturedAt != null
        ? GpsFix(
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: accuracy,
            capturedAt: capturedAt,
            isMocked: location?['is_mocked'] as bool? ?? false,
          )
        : null,
    evidence: [
      for (final item in json['evidence'] as List<dynamic>? ?? const [])
        evidenceFromJson(item as Map<String, dynamic>),
    ],
    origin: _origin(json['origin']),
    clientId: _text(json['client_id']),
    locationStatus: _text(location?['status']),
    distanceToUnitMeters: (location?['distance_to_pu_m'] as num?)?.round(),
    isLive: live?['is_live'] as bool? ?? false,
    liveRecording: _text(live?['recording']),
  );
}

FieldReport fieldReportFromJson(Map<String, dynamic> json) => FieldReport(
      id: json['reference'] as String,
      category: json['category'] as String,
      summary: json['summary'] as String? ?? '',
      scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
      reporterId: json['reporter'] as String? ?? '',
      reportedAt: DateTime.parse(json['reported_at'] as String),
      status: RecordStatus.values.byName(json['status'] as String),
      incidentId: _text(json['incident']),
      evidence: [
        for (final item in json['evidence'] as List<dynamic>? ?? const [])
          evidenceFromJson(item as Map<String, dynamic>),
      ],
      origin: _origin(json['origin']),
      clientId: _text(json['client_id']),
    );

/// One step in an incident's history (`/incidents/<reference>/events/`).
class IncidentHistoryEntry {
  const IncidentHistoryEntry({
    required this.action,
    required this.at,
    this.fromStatus,
    this.toStatus,
    this.note = '',
    this.actor,
  });

  /// reported, statusChanged, assigned, evidenceAdded or liveVideo.
  final String action;
  final DateTime at;
  final IncidentStatus? fromStatus;
  final IncidentStatus? toStatus;
  final String note;

  /// Access ID of whoever took the step.
  final String? actor;

  factory IncidentHistoryEntry.fromJson(Map<String, dynamic> json) => IncidentHistoryEntry(
        action: json['action'] as String,
        at: DateTime.parse(json['created_at'] as String),
        fromStatus: IncidentStatus.values.asNameMap()[json['from_status']],
        toStatus: IncidentStatus.values.asNameMap()[json['to_status']],
        note: json['note'] as String? ?? '',
        actor: _text(json['actor']),
      );
}

/// What the server holds for the caller's areas.
class FieldSnapshot {
  const FieldSnapshot({
    required this.incidents,
    required this.reports,
    required this.openIncidents,
  });

  /// Open incidents, most urgent first, then recently resolved and closed ones.
  final List<FieldIncident> incidents;

  /// The latest field reports.
  final List<FieldReport> reports;

  /// Every open incident the caller can see; more than were loaded when the
  /// areas are very busy.
  final int openIncidents;
}

/// Incidents and field reports (`/incidents/`, `/field-reports/`). The server
/// decides what each account sees: its own records, and every record in the
/// areas where it may view incidents or review reports. It also checks every
/// change, area by area.
class FieldRepository {
  FieldRepository(this.client);
  final ApiClient client;

  /// Loads up to [open] open incidents (most urgent first), the [closed] most
  /// recently reported resolved or closed ones, and the latest [reports].
  Future<FieldSnapshot> load({int open = 500, int closed = 100, int reports = 200}) async {
    final pages = await Future.wait([
      client.get('incidents/', query: {
        'open': 'true',
        'ordering': '-severity_rank,-reported_at',
        'limit': '$open',
      }),
      client.get('incidents/', query: {
        'open': 'false',
        'ordering': '-reported_at',
        'limit': '$closed',
      }),
      client.get('field-reports/', query: {'ordering': '-reported_at', 'limit': '$reports'}),
    ]);
    List<Map<String, dynamic>> results(Object? page) => [
          for (final item in (page as Map<String, dynamic>)['results'] as List<dynamic>)
            item as Map<String, dynamic>,
        ];
    return FieldSnapshot(
      incidents: [
        for (final item in [...results(pages[0]), ...results(pages[1])])
          fieldIncidentFromJson(item),
      ],
      reports: [for (final item in results(pages[2])) fieldReportFromJson(item)],
      openIncidents: (pages[0] as Map<String, dynamic>)['count'] as int? ?? 0,
    );
  }

  /// Moves an incident on; the server asks for a [note] when escalating,
  /// resolving, closing or reopening.
  Future<FieldIncident> changeStatus(
    String reference,
    IncidentStatus status, {
    String note = '',
  }) async =>
      fieldIncidentFromJson(
        await client.post(
          'incidents/$reference/status/',
          body: {'status': status.name, 'note': note.trim()},
        ) as Map<String, dynamic>,
      );

  /// Gives a response team the incident.
  Future<FieldIncident> assign(String reference, {required String team, String note = ''}) async =>
      fieldIncidentFromJson(
        await client.post(
          'incidents/$reference/assign/',
          body: {'team': team.trim(), 'note': note.trim()},
        ) as Map<String, dynamic>,
      );

  /// A pass to broadcast live video of the incident from this phone (its
  /// reporter only); the same stream again if already live.
  Future<JoinPass> goLive(String reference) async => JoinPass.fromJson(
        await client.post('incidents/$reference/live/start/') as Map<String, dynamic>,
      );

  /// A pass to watch the incident's live video, for whoever may see it.
  Future<JoinPass> watchLive(String reference) async => JoinPass.fromJson(
        await client.post('incidents/$reference/live/watch/') as Map<String, dynamic>,
      );

  /// Ends the live video; the recording, if any, is then kept on the incident.
  Future<FieldIncident> endLive(String reference) async => fieldIncidentFromJson(
        await client.post('incidents/$reference/live/end/') as Map<String, dynamic>,
      );

  /// Every step taken on the incident, oldest first.
  Future<List<IncidentHistoryEntry>> history(String reference) async {
    final body = await client.get('incidents/$reference/events/') as List<dynamic>;
    return [for (final item in body) IncidentHistoryEntry.fromJson(item as Map<String, dynamic>)];
  }

  /// Accepts or rejects a field report; rejecting needs a [reason].
  Future<FieldReport> review(String reference, {required bool accepted, String reason = ''}) async =>
      fieldReportFromJson(
        await client.post(
          'field-reports/$reference/review/',
          body: {'accepted': accepted, 'reason': reason.trim()},
        ) as Map<String, dynamic>,
      );
}
