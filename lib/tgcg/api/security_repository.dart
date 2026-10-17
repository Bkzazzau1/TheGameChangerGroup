import '../domain/models.dart';
import 'api_client.dart';
import 'auth_repository.dart' show geographicScopeFromJson;

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

double? _number(Object? value) => (value as num?)?.toDouble();

/// The steps an incident goes through with a security officer.
const securitySteps = ['sent', 'accepted', 'declined', 'onTheWay', 'arrived', 'resolved', 'cancelled'];

/// Still with the officer: the incident goes to nobody else meanwhile.
const activeSecuritySteps = {'sent', 'accepted', 'onTheWay', 'arrived'};

String securityStepLabel(String step) => switch (step) {
  'sent' => 'Sent',
  'accepted' => 'Accepted',
  'declined' => 'Declined',
  'onTheWay' => 'On the way',
  'arrived' => 'Arrived',
  'resolved' => 'Resolved',
  'cancelled' => 'Cancelled',
  _ => step,
};

/// "60 m", "2.1 km", "38 km".
String distanceLabel(int meters) {
  if (meters < 1000) return '$meters m';
  final km = meters / 1000;
  return km < 10 ? '${km.toStringAsFixed(1)} km' : '${km.round()} km';
}

/// An officer the Situation Room may send an incident to, nearest first.
class SecurityCandidate {
  const SecurityCandidate({
    required this.accessId,
    required this.name,
    this.roles = const [],
    this.distanceMeters,
    this.locatedBy = '',
    this.area,
    this.seenAt,
    this.busy = false,
  });

  final String accessId;
  final String name;
  final List<String> roles;
  final int? distanceMeters;

  /// live (where they are now), area (the area of their role), or empty
  /// when the distance is unknown.
  final String locatedBy;
  final String? area;
  final DateTime? seenAt;

  /// Another incident is with them now.
  final bool busy;

  factory SecurityCandidate.fromJson(Map<String, dynamic> json) => SecurityCandidate(
    accessId: json['access_id'] as String,
    name: json['name'] as String? ?? '',
    roles: [for (final role in json['roles'] as List<dynamic>? ?? const []) '$role'],
    distanceMeters: (json['distance_m'] as num?)?.toInt(),
    locatedBy: json['located_by'] as String? ?? '',
    area: json['area'] as String?,
    seenAt: _date(json['seen_at']),
    busy: json['busy'] as bool? ?? false,
  );
}

class SecurityNearest {
  const SecurityNearest({required this.located, required this.officers});

  /// False when the incident's place is unknown, so distances are too.
  final bool located;
  final List<SecurityCandidate> officers;

  factory SecurityNearest.fromJson(Map<String, dynamic> json) => SecurityNearest(
    located: json['located'] as bool? ?? false,
    officers: [
      for (final item in json['officers'] as List<dynamic>? ?? const [])
        SecurityCandidate.fromJson(item as Map<String, dynamic>),
    ],
  );
}

/// An incident sent to a security officer, as the Situation Room follows it.
class SecurityDispatch {
  const SecurityDispatch({
    required this.id,
    required this.incident,
    required this.status,
    required this.officer,
    required this.officerName,
    required this.sentBy,
    required this.sentAt,
    this.officerPhone,
    this.note = '',
    this.distanceMeters,
    this.locatedBy = '',
    this.notified = const [],
    this.acceptedAt,
    this.onTheWayAt,
    this.arrivedAt,
    this.finishedAt,
    this.outcome = '',
    this.cancelledBy,
    this.cancelReason = '',
  });

  final String id;
  final String incident;
  final String status;
  final String officer;
  final String officerName;

  /// Only for those who may send incidents to security.
  final String? officerPhone;
  final String sentBy;
  final DateTime sentAt;
  final String note;
  final int? distanceMeters;
  final String locatedBy;

  /// How the officer was told: push (app notification), sms.
  final List<String> notified;
  final DateTime? acceptedAt;
  final DateTime? onTheWayAt;
  final DateTime? arrivedAt;
  final DateTime? finishedAt;
  final String outcome;
  final String? cancelledBy;
  final String cancelReason;

  bool get active => activeSecuritySteps.contains(status);

  factory SecurityDispatch.fromJson(Map<String, dynamic> json) => SecurityDispatch(
    id: json['id'] as String,
    incident: json['incident'] as String,
    status: json['status'] as String,
    officer: json['officer'] as String,
    officerName: json['officer_name'] as String? ?? '',
    officerPhone: json['officer_phone'] as String?,
    sentBy: json['sent_by'] as String? ?? '',
    sentAt: _date(json['sent_at'])!,
    note: json['note'] as String? ?? '',
    distanceMeters: (json['distance_m'] as num?)?.toInt(),
    locatedBy: json['located_by'] as String? ?? '',
    notified: [for (final channel in json['notified'] as List<dynamic>? ?? const []) '$channel'],
    acceptedAt: _date(json['accepted_at']),
    onTheWayAt: _date(json['on_the_way_at']),
    arrivedAt: _date(json['arrived_at']),
    finishedAt: _date(json['finished_at']),
    outcome: json['outcome'] as String? ?? '',
    cancelledBy: json['cancelled_by'] as String?,
    cancelReason: json['cancel_reason'] as String? ?? '',
  );
}

/// Who an incident was sent to, and whether this account may send it.
class IncidentSecurity {
  const IncidentSecurity({required this.canSend, required this.dispatches});

  final bool canSend;

  /// Newest first.
  final List<SecurityDispatch> dispatches;

  SecurityDispatch? get current => dispatches.where((item) => item.active).firstOrNull;

  factory IncidentSecurity.fromJson(Map<String, dynamic> json) => IncidentSecurity(
    canSend: json['can_send'] as bool? ?? false,
    dispatches: [
      for (final item in json['dispatches'] as List<dynamic>? ?? const [])
        SecurityDispatch.fromJson(item as Map<String, dynamic>),
    ],
  );
}

/// The incident as the officer sent to it sees it.
class OfficerIncident {
  const OfficerIncident({
    required this.reference,
    required this.title,
    required this.category,
    required this.severity,
    required this.status,
    required this.reportedAt,
    required this.scope,
    required this.place,
    this.summary = '',
    this.latitude,
    this.longitude,
    this.gps = false,
    this.reporterName = '',
    this.reporterPhone = '',
  });

  final String reference;
  final String title;
  final String category;
  final IncidentSeverity severity;
  final String status;
  final String summary;
  final DateTime reportedAt;
  final GeographicScope scope;

  /// "Unit name, Ward, LGA, State".
  final String place;

  /// Where to go: the reporter's GPS fix, else the middle of the place.
  final double? latitude;
  final double? longitude;

  /// True when the point is the reporter's GPS fix.
  final bool gps;
  final String reporterName;
  final String reporterPhone;

  factory OfficerIncident.fromJson(Map<String, dynamic> json) => OfficerIncident(
    reference: json['reference'] as String,
    title: json['title'] as String? ?? '',
    category: json['category'] as String? ?? '',
    severity: IncidentSeverity.values.asNameMap()[json['severity']] ?? IncidentSeverity.info,
    status: json['status'] as String? ?? '',
    summary: json['summary'] as String? ?? '',
    reportedAt: _date(json['reported_at'])!,
    scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
    place: json['place'] as String? ?? '',
    latitude: _number(json['latitude']),
    longitude: _number(json['longitude']),
    gps: json['gps'] as bool? ?? false,
    reporterName: json['reporter_name'] as String? ?? '',
    reporterPhone: json['reporter_phone'] as String? ?? '',
  );
}

/// An incident sent to the signed-in security officer.
class OfficerDispatch {
  const OfficerDispatch({
    required this.id,
    required this.status,
    required this.incident,
    required this.sentBy,
    required this.sentAt,
    this.next = const [],
    this.note = '',
    this.distanceMeters,
    this.acceptedAt,
    this.onTheWayAt,
    this.arrivedAt,
    this.finishedAt,
    this.outcome = '',
    this.cancelReason = '',
  });

  final String id;
  final String status;

  /// The steps the officer may take now.
  final List<String> next;
  final OfficerIncident incident;
  final String sentBy;
  final DateTime sentAt;

  /// What the Situation Room told the officer.
  final String note;
  final int? distanceMeters;
  final DateTime? acceptedAt;
  final DateTime? onTheWayAt;
  final DateTime? arrivedAt;
  final DateTime? finishedAt;
  final String outcome;
  final String cancelReason;

  bool get active => activeSecuritySteps.contains(status);

  factory OfficerDispatch.fromJson(Map<String, dynamic> json) => OfficerDispatch(
    id: json['id'] as String,
    status: json['status'] as String,
    next: [for (final step in json['next'] as List<dynamic>? ?? const []) '$step'],
    incident: OfficerIncident.fromJson(json['incident'] as Map<String, dynamic>),
    sentBy: json['sent_by'] as String? ?? '',
    sentAt: _date(json['sent_at'])!,
    note: json['note'] as String? ?? '',
    distanceMeters: (json['distance_m'] as num?)?.toInt(),
    acceptedAt: _date(json['accepted_at']),
    onTheWayAt: _date(json['on_the_way_at']),
    arrivedAt: _date(json['arrived_at']),
    finishedAt: _date(json['finished_at']),
    outcome: json['outcome'] as String? ?? '',
    cancelReason: json['cancel_reason'] as String? ?? '',
  );
}

/// Security officers: the Situation Room sends an incident to the nearest
/// one (`/incidents/<reference>/security/`), who answers each step
/// (`/me/security/`).
class SecurityRepository {
  SecurityRepository(this.client);

  final ApiClient client;

  Future<IncidentSecurity> forIncident(String reference) async => IncidentSecurity.fromJson(
    await client.get('incidents/$reference/security/') as Map<String, dynamic>,
  );

  /// Officers nearest to the incident, by live location or the area of their role.
  Future<SecurityNearest> nearest(String reference, {String search = ''}) async =>
      SecurityNearest.fromJson(
        await client.get(
          'incidents/$reference/security/nearest/',
          query: {if (search.trim().isNotEmpty) 'search': search.trim(), 'limit': '20'},
        ) as Map<String, dynamic>,
      );

  Future<SecurityDispatch> send(String reference, String officer, {String note = ''}) async =>
      SecurityDispatch.fromJson(
        await client.post(
          'incidents/$reference/security/',
          body: {'officer': officer, 'note': note.trim()},
        ) as Map<String, dynamic>,
      );

  Future<SecurityDispatch> cancel(String dispatch, String reason) async =>
      SecurityDispatch.fromJson(
        await client.post('security/dispatches/$dispatch/cancel/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  /// The incidents sent to this officer: those still with them, then the
  /// ones finished in the last week.
  Future<List<OfficerDispatch>> mine() async => [
    for (final item in await client.get('me/security/') as List<dynamic>)
      OfficerDispatch.fromJson(item as Map<String, dynamic>),
  ];

  /// `accepted`, `declined` (with a reason), `onTheWay`, `arrived` or
  /// `resolved` (with what was done).
  Future<OfficerDispatch> respond(String dispatch, String step, {String note = ''}) async =>
      OfficerDispatch.fromJson(
        await client.post('me/security/$dispatch/respond/', body: {'step': step, 'note': note.trim()})
            as Map<String, dynamic>,
      );
}
