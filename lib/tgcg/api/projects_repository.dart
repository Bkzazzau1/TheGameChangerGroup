import '../domain/models.dart';
import 'api_client.dart';
import 'auth_repository.dart' show geographicScopeFromJson;
import 'meetings_repository.dart' show scopeInput;

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

/// Someone's place in a project: where they work and their answer.
class ProjectParticipation {
  const ProjectParticipation({
    required this.id,
    required this.projectId,
    required this.projectName,
    required this.member,
    required this.memberName,
    required this.place,
    required this.status,
    this.assignedBy = '',
    this.reason = '',
  });

  final String id;
  final String projectId;
  final String projectName;
  final String member;
  final String memberName;
  final GeographicScope place;

  /// invited, accepted, declined, withdrawn or removed.
  final String status;
  final String assignedBy;
  final String reason;

  bool get invited => status == 'invited';
  bool get accepted => status == 'accepted';

  factory ProjectParticipation.fromJson(Map<String, dynamic> json) => ProjectParticipation(
    id: json['id'] as String,
    projectId: json['project'] as String,
    projectName: json['project_name'] as String? ?? '',
    member: json['member'] as String? ?? '',
    memberName: json['member_name'] as String? ?? '',
    place: geographicScopeFromJson(json['place'] as Map<String, dynamic>),
    status: json['status'] as String,
    assignedBy: json['assigned_by'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
  );
}

/// A scheduled period of field work, such as an election.
class TgcgProject {
  const TgcgProject({
    required this.id,
    required this.name,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    this.description = '',
    this.areas = const [],
    this.electionCode,
    this.electionName,
    this.checkPlace = true,
    this.cancelReason = '',
    this.myParticipation,
    this.canManage = false,
    this.canAssign = false,
  });

  final String id;
  final String name;
  final String description;
  final DateTime startsAt;
  final DateTime endsAt;

  /// scheduled, active, ended or cancelled.
  final String status;
  final List<GeographicScope> areas;
  final String? electionCode;
  final String? electionName;
  final bool checkPlace;
  final String cancelReason;
  final ProjectParticipation? myParticipation;
  final bool canManage;
  final bool canAssign;

  bool get active => status == 'active';
  bool get finished => status == 'ended' || status == 'cancelled';

  factory TgcgProject.fromJson(Map<String, dynamic> json) {
    final election = json['election'] as Map<String, dynamic>?;
    final mine = json['my_participation'] as Map<String, dynamic>?;
    return TgcgProject(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      startsAt: _date(json['starts_at'])!,
      endsAt: _date(json['ends_at'])!,
      status: json['status'] as String,
      areas: [
        for (final area in (json['areas'] as List<dynamic>? ?? const []))
          geographicScopeFromJson(area as Map<String, dynamic>),
      ],
      electionCode: election?['code'] as String?,
      electionName: election?['name'] as String?,
      checkPlace: json['check_place'] as bool? ?? true,
      cancelReason: json['cancel_reason'] as String? ?? '',
      myParticipation: mine == null ? null : ProjectParticipation.fromJson(mine),
      canManage: json['can_manage'] as bool? ?? false,
      canAssign: json['can_assign'] as bool? ?? false,
    );
  }
}

/// One person in a project, as the coordinators watching it see them.
class ProjectPerson {
  const ProjectPerson({
    required this.participation,
    required this.member,
    required this.name,
    required this.place,
    required this.status,
    required this.state,
    this.distanceMeters,
    this.lastSeen,
  });

  final String participation;
  final String member;
  final String name;
  final GeographicScope place;
  final String status;

  /// atPlace, away, unverified, suspect, noGps, notSharing, notStarted,
  /// waiting, or their answer (invited, declined, withdrawn, removed).
  final String state;
  final int? distanceMeters;
  final DateTime? lastSeen;

  factory ProjectPerson.fromJson(Map<String, dynamic> json) {
    final position = json['position'] as Map<String, dynamic>?;
    return ProjectPerson(
      participation: json['participation'] as String,
      member: json['member'] as String,
      name: json['name'] as String? ?? '',
      place: geographicScopeFromJson(json['place'] as Map<String, dynamic>),
      status: json['status'] as String,
      state: json['state'] as String,
      distanceMeters: (position?['distance_to_pu_m'] as num?)?.toInt(),
      lastSeen: _date(position?['captured_at']),
    );
  }
}

/// Who is where in a project, and the work it has brought in.
class ProjectMonitor {
  const ProjectMonitor({
    required this.counts,
    required this.people,
    this.incidents = 0,
    this.reports = 0,
    this.results = 0,
  });

  final Map<String, int> counts;
  final List<ProjectPerson> people;
  final int incidents;
  final int reports;
  final int results;

  factory ProjectMonitor.fromJson(Map<String, dynamic> json) {
    final work = json['work'] as Map<String, dynamic>? ?? const {};
    return ProjectMonitor(
      counts: {
        for (final entry in (json['counts'] as Map<String, dynamic>? ?? const {}).entries)
          entry.key: (entry.value as num).toInt(),
      },
      people: [
        for (final person in (json['people'] as List<dynamic>? ?? const []))
          ProjectPerson.fromJson(person as Map<String, dynamic>),
      ],
      incidents: (work['incidents'] as num?)?.toInt() ?? 0,
      reports: (work['reports'] as num?)?.toInt() ?? 0,
      results: (work['results'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Projects (`/projects/`): a National Administrator schedules them,
/// coordinators assign and watch people, and people answer and take part.
class ProjectsRepository {
  ProjectsRepository(this.client);

  final ApiClient client;

  List<TgcgProject> _list(Object? body) => [
    for (final item in body as List<dynamic>) TgcgProject.fromJson(item as Map<String, dynamic>),
  ];

  /// Projects in this account's areas (all of them for an administrator).
  Future<List<TgcgProject>> projects() async => _list(await client.get('projects/'));

  /// The projects this member is asked to, or does, take part in.
  Future<List<TgcgProject>> mine() async => _list(await client.get('me/projects/'));

  Future<TgcgProject> project(String id) async =>
      TgcgProject.fromJson(await client.get('projects/$id/') as Map<String, dynamic>);

  Map<String, Object?> _body({
    String? name,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
    List<GeographicScope>? areas,
    String? election,
    bool clearElection = false,
    bool? checkPlace,
  }) => {
    'name': ?name,
    'description': ?description,
    if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
    if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
    if (areas != null) 'areas': [for (final area in areas) scopeInput(area)],
    if (election != null || clearElection) 'election': election,
    'check_place': ?checkPlace,
  };

  Future<TgcgProject> create({
    required String name,
    required String description,
    required DateTime startsAt,
    required DateTime endsAt,
    required List<GeographicScope> areas,
    String? election,
    bool checkPlace = true,
  }) async => TgcgProject.fromJson(
    await client.post(
      'projects/',
      body: _body(
        name: name,
        description: description,
        startsAt: startsAt,
        endsAt: endsAt,
        areas: areas,
        election: election,
        checkPlace: checkPlace,
      ),
    ) as Map<String, dynamic>,
  );

  /// Only the fields given change. Once a project runs, its start, areas and
  /// election stay as they are.
  Future<TgcgProject> update(
    String id, {
    String? name,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
    List<GeographicScope>? areas,
    String? election,
    bool clearElection = false,
    bool? checkPlace,
  }) async => TgcgProject.fromJson(
    await client.patch(
      'projects/$id/',
      body: _body(
        name: name,
        description: description,
        startsAt: startsAt,
        endsAt: endsAt,
        areas: areas,
        election: election,
        clearElection: clearElection,
        checkPlace: checkPlace,
      ),
    ) as Map<String, dynamic>,
  );

  Future<TgcgProject> cancel(String id, String reason) async => TgcgProject.fromJson(
    await client.post('projects/$id/cancel/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  Future<List<ProjectParticipation>> participants(String id) async => [
    for (final item in await client.get('projects/$id/participants/') as List<dynamic>)
      ProjectParticipation.fromJson(item as Map<String, dynamic>),
  ];

  /// Puts someone with a role into the project, at [place] or by default
  /// their own polling unit.
  Future<ProjectParticipation> assign(String id, String member, {GeographicScope? place}) async =>
      ProjectParticipation.fromJson(
        await client.post(
          'projects/$id/participants/',
          body: {'member': member.trim(), if (place != null) 'place': scopeInput(place)},
        ) as Map<String, dynamic>,
      );

  Future<ProjectParticipation> remove(String participation, String reason) async =>
      ProjectParticipation.fromJson(
        await client.post(
          'project-participants/$participation/remove/',
          body: {'reason': reason.trim()},
        ) as Map<String, dynamic>,
      );

  Future<ProjectMonitor> monitor(String id) async =>
      ProjectMonitor.fromJson(await client.get('projects/$id/monitor/') as Map<String, dynamic>);

  /// `accept` (agreeing to share location while the project runs),
  /// `decline` or `withdraw`.
  Future<ProjectParticipation> answer(String participation, String answer) async =>
      ProjectParticipation.fromJson(
        await client.post('me/projects/$participation/$answer/', body: const {})
            as Map<String, dynamic>,
      );
}
