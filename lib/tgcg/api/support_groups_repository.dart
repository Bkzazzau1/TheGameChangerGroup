import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'access_repository.dart' show ApiPage;
import 'api_client.dart';

/// What an organization covers: the server's code, and its name.
const groupCoverages = [('national', 'National'), ('regional', 'Regional'), ('state', 'State')];

/// The six geopolitical zones, for a regional organization.
const groupRegions = [
  ('NC', 'North Central'),
  ('NE', 'North East'),
  ('NW', 'North West'),
  ('SE', 'South East'),
  ('SS', 'South South'),
  ('SW', 'South West'),
];

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

/// One of an organization's other leaders, as on the paper form.
class GroupOfficial {
  const GroupOfficial({required this.name, this.position = '', this.phone = ''});

  final String name;
  final String position;
  final String phone;

  bool get isEmpty => name.trim().isEmpty && position.trim().isEmpty && phone.trim().isEmpty;

  Map<String, String> toJson() => {
    'name': name.trim(),
    'position': position.trim(),
    'phone': phone.trim(),
  };

  factory GroupOfficial.fromJson(Map<String, dynamic> json) => GroupOfficial(
    name: json['name'] as String? ?? '',
    position: json['position'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
  );
}

/// A type of support group: Support Groups, Women Groups, Youth Groups and
/// People With Disability (PWD) Groups to start with, and more as those who
/// vet groups add them.
class GroupKind {
  const GroupKind({required this.code, required this.name, this.offered = true});

  final String code;
  final String name;

  /// Offered to groups registering; groups already of it keep it either way.
  final bool offered;

  factory GroupKind.fromJson(Map<String, dynamic> json) => GroupKind(
    code: json['code'] as String? ?? '',
    name: json['name'] as String? ?? '',
    offered: json['offered'] as bool? ?? true,
  );
}

/// The organization's part of the registration form.
class OrganizationDetails {
  const OrganizationDetails({
    required this.name,
    required this.coverage,
    this.kind = '',
    this.region = '',
    this.state = '',
    this.email = '',
    this.officials = const [],
  });

  final String name;

  /// The code of its [GroupKind].
  final String kind;

  /// A code from [groupCoverages].
  final String coverage;

  /// A zone code from [groupRegions], for a regional organization.
  final String region;

  /// A state code, for a state organization.
  final String state;
  final String email;
  final List<GroupOfficial> officials;

  /// The form's fields, as joining and registering send them.
  Map<String, Object> toFields() => {
    'organization_name': name.trim(),
    'organization_kind': kind,
    'organization_coverage': coverage,
    if (coverage == 'regional') 'organization_zone': region,
    if (coverage == 'state') 'organization_state': state,
    'organization_email': email.trim(),
    'organization_officials': [
      for (final official in officials)
        if (!official.isEmpty) official.toJson(),
    ],
  };
}

/// A group's leader, as those who see the group see them.
class GroupLeader {
  const GroupLeader({
    required this.membershipNumber,
    required this.fullName,
    required this.phoneNumber,
    this.place = '',
  });

  final String membershipNumber;
  final String fullName;
  final String phoneNumber;
  final String place;

  factory GroupLeader.fromJson(Map<String, dynamic> json) => GroupLeader(
    membershipNumber: json['membership_number'] as String? ?? '',
    fullName: json['full_name'] as String? ?? '',
    phoneNumber: json['phone_number'] as String? ?? '',
    place: json['place'] as String? ?? '',
  );
}

/// A support group: for those who vet groups, or for its own leader, who
/// also gets its code and link once TGCG approves it.
class SupportGroup {
  const SupportGroup({
    required this.id,
    required this.serialNumber,
    required this.name,
    required this.coverage,
    required this.coverageLabel,
    required this.status,
    required this.statusLabel,
    required this.leader,
    this.kind = '',
    this.kindName = '',
    this.zone,
    this.state,
    this.email = '',
    this.officials = const [],
    this.leaderConfirmed = true,
    this.decisionReason = '',
    this.decidedAt,
    this.createdAt,
    this.members,
    this.approvedMembers,
    this.waiting,
    this.registeredBy = '',
    this.decidedBy = '',
    this.joinCode,
    this.link,
  });

  final String id;

  /// As on the paper form: TGCG/0001/BAT/27.
  final String serialNumber;
  final String name;

  /// Its type: the [GroupKind]'s code and name.
  final String kind;
  final String kindName;
  final String coverage;
  final String coverageLabel;

  /// pending, approved, rejected or suspended.
  final String status;
  final String statusLabel;
  final GroupLeader leader;
  final String? zone;
  final String? state;
  final String email;
  final List<GroupOfficial> officials;

  /// False while a member someone else named as leader has not said yes.
  final bool leaderConfirmed;
  final String decisionReason;
  final DateTime? decidedAt;
  final DateTime? createdAt;
  final int? members;
  final int? approvedMembers;
  final int? waiting;
  final String registeredBy;
  final String decidedBy;
  final String? joinCode;
  final String? link;

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isSuspended => status == 'suspended';

  /// National, North West, or Kaduna: what it covers, in a word or two.
  String get area => switch (coverage) {
    'regional' => zone ?? coverageLabel,
    'state' => state ?? coverageLabel,
    _ => coverageLabel,
  };

  factory SupportGroup.fromJson(Map<String, dynamic> json) => SupportGroup(
    id: json['id'] as String,
    serialNumber: json['serial_number'] as String? ?? '',
    name: json['name'] as String? ?? '',
    kind: json['kind'] as String? ?? '',
    kindName: json['kind_name'] as String? ?? '',
    coverage: json['coverage'] as String? ?? '',
    coverageLabel: json['coverage_label'] as String? ?? '',
    status: json['status'] as String? ?? '',
    statusLabel: json['status_label'] as String? ?? '',
    leader: GroupLeader.fromJson(json['leader'] as Map<String, dynamic>? ?? const {}),
    zone: json['zone'] as String?,
    state: json['state'] as String?,
    email: json['email'] as String? ?? '',
    officials: [
      for (final official in json['officials'] as List<dynamic>? ?? const [])
        GroupOfficial.fromJson(official as Map<String, dynamic>),
    ],
    leaderConfirmed: json['leader_confirmed'] as bool? ?? true,
    decisionReason: json['decision_reason'] as String? ?? '',
    decidedAt: _date(json['decided_at']),
    createdAt: _date(json['created_at']),
    members: json['members'] as int?,
    approvedMembers: json['approved_members'] as int?,
    waiting: json['waiting'] as int?,
    registeredBy: json['registered_by'] as String? ?? '',
    decidedBy: json['decided_by'] as String? ?? '',
    joinCode: json['join_code'] as String?,
    link: json['link'] as String?,
  );
}

/// Someone in a group, as its leader sees them. Until someone already
/// registered says yes, only the name and number the group gave.
class GroupPerson {
  const GroupPerson({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    required this.status,
    required this.statusLabel,
    required this.via,
    required this.viaLabel,
    this.place = '',
    this.approved,
    this.membershipNumber,
    this.addedAt,
  });

  /// The place in the group, which the leader removes it by.
  final String id;
  final String fullName;
  final String phoneNumber;

  /// active, invited, declined, left or removed.
  final String status;
  final String statusLabel;
  final String via;
  final String viaLabel;
  final String place;

  /// Whether TGCG approved them; null while they have not said yes.
  final bool? approved;

  /// For those who vet groups, to open the member's record.
  final String? membershipNumber;
  final DateTime? addedAt;

  bool get isWaiting => status == 'invited';
  bool get leads => via == 'leader';

  factory GroupPerson.fromJson(Map<String, dynamic> json) => GroupPerson(
    id: json['id'] as String,
    fullName: json['full_name'] as String? ?? '',
    phoneNumber: json['phone_number'] as String? ?? '',
    status: json['status'] as String? ?? '',
    statusLabel: json['status_label'] as String? ?? '',
    via: json['via'] as String? ?? '',
    viaLabel: json['via_label'] as String? ?? '',
    place: json['place'] as String? ?? '',
    approved: json['approved'] as bool?,
    membershipNumber: json['membership_number'] as String?,
    addedAt: _date(json['created_at']),
  );
}

/// A group the signed-in member is in, or is asked to confirm.
class MyGroupPlace {
  const MyGroupPlace({
    required this.id,
    required this.groupId,
    required this.groupName,
    required this.serialNumber,
    required this.coverageLabel,
    required this.leaderName,
    required this.status,
    this.leads = false,
    this.kindName = '',
  });

  final String id;
  final String groupId;
  final String groupName;

  /// The group's type, e.g. Women Groups.
  final String kindName;
  final String serialNumber;
  final String coverageLabel;
  final String leaderName;
  final String status;

  /// Asked to lead it, or leading it.
  final bool leads;

  factory MyGroupPlace.fromJson(Map<String, dynamic> json) {
    final group = json['group'] as Map<String, dynamic>? ?? const {};
    return MyGroupPlace(
      id: json['id'] as String,
      groupId: group['id'] as String? ?? '',
      groupName: group['name'] as String? ?? '',
      kindName: group['kind_name'] as String? ?? '',
      serialNumber: group['serial_number'] as String? ?? '',
      coverageLabel: group['coverage_label'] as String? ?? '',
      leaderName: group['leader'] as String? ?? '',
      status: json['status'] as String? ?? '',
      leads: json['leads'] as bool? ?? false,
    );
  }
}

/// The signed-in member's groups.
class MySupportGroups {
  const MySupportGroups({
    this.invitations = const [],
    this.groups = const [],
    this.leading = const [],
    this.vets = false,
  });

  final List<MyGroupPlace> invitations;
  final List<MyGroupPlace> groups;
  final List<SupportGroup> leading;

  /// Whether they vet groups themselves.
  final bool vets;

  factory MySupportGroups.fromJson(Map<String, dynamic> json) => MySupportGroups(
    invitations: [
      for (final item in json['invitations'] as List<dynamic>? ?? const [])
        MyGroupPlace.fromJson(item as Map<String, dynamic>),
    ],
    groups: [
      for (final item in json['groups'] as List<dynamic>? ?? const [])
        MyGroupPlace.fromJson(item as Map<String, dynamic>),
    ],
    leading: [
      for (final item in json['leading'] as List<dynamic>? ?? const [])
        SupportGroup.fromJson(item as Map<String, dynamic>),
    ],
    vets: json['vets'] as bool? ?? false,
  );
}

/// A line of an uploaded list, as the server read it, to check before adding.
class ListedPerson {
  const ListedPerson({
    required this.line,
    required this.fullName,
    required this.phoneNumber,
    this.gender = '',
    this.place = '',
    this.scope,
    this.problem = '',
  });

  final int line;
  final String fullName;
  final String phoneNumber;
  final String gender;
  final String place;

  /// Where to register them, as the server takes it; null when unknown.
  final Map<String, dynamic>? scope;

  /// Why the line cannot be added as it is.
  final String problem;

  bool get canAdd => problem.isEmpty;

  factory ListedPerson.fromJson(Map<String, dynamic> json) => ListedPerson(
    line: json['line'] as int? ?? 0,
    fullName: json['full_name'] as String? ?? '',
    phoneNumber: json['phone_number'] as String? ?? '',
    gender: json['gender'] as String? ?? '',
    place: json['place'] as String? ?? '',
    scope: json['scope'] as Map<String, dynamic>?,
    problem: json['problem'] as String? ?? '',
  );

  Map<String, Object?> toJson() => {
    'line': line,
    'full_name': fullName,
    'phone_number': phoneNumber,
    if (scope != null) 'scope': scope,
    if (gender.isNotEmpty) 'gender': gender,
  };
}

/// What an uploaded list holds.
class ReadList {
  const ReadList({required this.people, this.notes = const []});

  final List<ListedPerson> people;

  /// What could not be read, such as pages of a long scan.
  final List<String> notes;

  factory ReadList.fromJson(Map<String, dynamic> json) => ReadList(
    people: [
      for (final item in json['people'] as List<dynamic>? ?? const [])
        ListedPerson.fromJson(item as Map<String, dynamic>),
    ],
    notes: [for (final note in json['notes'] as List<dynamic>? ?? const []) '$note'],
  );
}

/// What happened to one person sent to be added.
class AddResult {
  const AddResult({required this.outcome, this.line, this.detail = ''});

  /// registered, asked, already, declined, left or problem.
  final String outcome;
  final int? line;
  final String detail;

  factory AddResult.fromJson(Map<String, dynamic> json) => AddResult(
    outcome: json['outcome'] as String? ?? 'problem',
    line: json['line'] as int?,
    detail: json['detail'] as String? ?? '',
  );
}

Map<String, int> _byStatus(Object? json) => {
  for (final entry in (json as Map<String, dynamic>? ?? const {}).entries)
    entry.key: entry.value as int,
};

/// One type of group: its groups by status, and the people in its approved
/// groups counted once.
class GroupKindTotals {
  const GroupKindTotals({required this.kind, this.byStatus = const {}, this.people = 0});

  final GroupKind kind;
  final Map<String, int> byStatus;
  final int people;

  factory GroupKindTotals.fromJson(Map<String, dynamic> json) => GroupKindTotals(
    kind: GroupKind.fromJson(json),
    byStatus: _byStatus(json['groups']),
    people: json['people'] as int? ?? 0,
  );
}

/// Groups by status, and people in approved groups counted once; and the
/// same for each type of group.
class SupportGroupTotals {
  const SupportGroupTotals({
    this.byStatus = const {},
    this.people = 0,
    this.approvedPeople = 0,
    this.kinds = const [],
  });

  final Map<String, int> byStatus;
  final int people;
  final int approvedPeople;
  final List<GroupKindTotals> kinds;

  factory SupportGroupTotals.fromJson(Map<String, dynamic> json) => SupportGroupTotals(
    byStatus: _byStatus(json['groups']),
    people: json['people'] as int? ?? 0,
    approvedPeople: json['approved_people'] as int? ?? 0,
    kinds: [
      for (final item in json['kinds'] as List<dynamic>? ?? const [])
        GroupKindTotals.fromJson(item as Map<String, dynamic>),
    ],
  );
}

/// People sent to be added in one request. A new account takes the server
/// about half a second to secure, so a batch answers well within the app's
/// wait; the server takes at most 25.
const addBatchSize = 10;

/// Support groups: the member's own, the leader's, and vetting.
class SupportGroupsRepository {
  SupportGroupsRepository(this.client);

  final ApiClient client;

  // --- the member's own ---------------------------------------------------------

  Future<MySupportGroups> mine() async =>
      MySupportGroups.fromJson(await client.get('me/support-groups/') as Map<String, dynamic>);

  /// Registers an organization, led by the member, or by someone named with
  /// [leaderName] and [leaderPhone]. It waits for vetting.
  Future<SupportGroup> register(
    OrganizationDetails details, {
    String leaderName = '',
    String leaderPhone = '',
    bool consent = false,
  }) async => SupportGroup.fromJson(
    await client.post(
          'me/support-groups/register/',
          body: {
            ...details.toFields(),
            if (leaderPhone.trim().isNotEmpty) 'leader_full_name': leaderName.trim(),
            if (leaderPhone.trim().isNotEmpty) 'leader_phone_number': leaderPhone.trim(),
            if (consent) 'consent': true,
          },
        )
        as Map<String, dynamic>,
  );

  Future<void> join(String code) async {
    await client.post('me/support-groups/join/', body: {'code': code.trim()});
  }

  Future<void> answer(String placeId, {required bool yes}) async {
    await client.post('me/support-groups/$placeId/answer/', body: {'yes': yes});
  }

  Future<void> leave(String placeId) async {
    await client.post('me/support-groups/$placeId/leave/');
  }

  /// The types of group a registering organization chooses from. No
  /// sign-in is needed: the joining page asks too.
  Future<List<GroupKind>> offeredKinds() async {
    final body =
        await client.get('register/support-group-kinds/', authenticated: false) as List<dynamic>;
    return [for (final item in body) GroupKind.fromJson(item as Map<String, dynamic>)];
  }

  /// The name of the group whose link opened joining.
  Future<String> nameForCode(String code) async {
    final body =
        await client.get('register/support-group/', query: {'code': code}, authenticated: false)
            as Map<String, dynamic>;
    return body['name'] as String? ?? '';
  }

  // --- the leader's group ----------------------------------------------------------

  Future<SupportGroup> led(String id) async =>
      SupportGroup.fromJson(await client.get('my-groups/$id/') as Map<String, dynamic>);

  Future<ApiPage<GroupPerson>> people(String id, {int offset = 0}) async => ApiPage.fromJson(
    await client.get('my-groups/$id/members/', query: {if (offset > 0) 'offset': '$offset'}),
    GroupPerson.fromJson,
  );

  /// Reads an uploaded list; nothing is kept until people are added.
  Future<ReadList> readList(String id, ({Uint8List bytes, String name}) file) async =>
      ReadList.fromJson(
        await client.postMultipart(
              'my-groups/$id/read-list/',
              fields: const {},
              files: () async => [
                http.MultipartFile.fromBytes('file', file.bytes, filename: file.name),
              ],
              // A scan is read page by page on the server.
              requestTimeout: const Duration(minutes: 2),
            )
            as Map<String, dynamic>,
      );

  /// Adds a batch of at most [addBatchSize] people.
  Future<List<AddResult>> add(
    String id,
    List<Map<String, Object?>> people, {
    required bool consent,
  }) async {
    final body =
        await client.post('my-groups/$id/add/', body: {'people': people, 'consent': consent})
            as Map<String, dynamic>;
    return [
      for (final item in body['results'] as List<dynamic>? ?? const [])
        AddResult.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<void> remove(String id, String placeId) async {
    await client.post('my-groups/$id/members/$placeId/remove/');
  }

  /// A message in the app to everyone in the group; returns how many.
  Future<int> message(String id, {required String title, required String body}) async {
    final answer =
        await client.post(
              'my-groups/$id/message/',
              body: {'title': title.trim(), 'body': body.trim()},
            )
            as Map<String, dynamic>;
    return answer['people'] as int? ?? 0;
  }

  // --- vetting --------------------------------------------------------------------

  /// Every group, or those of one [status] and of one type ([kind], its code).
  Future<ApiPage<SupportGroup>> all({
    String status = '',
    String kind = '',
    String search = '',
    int offset = 0,
  }) async => ApiPage.fromJson(
    await client.get(
      'support-groups/',
      query: {
        if (status.isNotEmpty) 'status': status,
        if (kind.isNotEmpty) 'kind': kind,
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (offset > 0) 'offset': '$offset',
      },
    ),
    SupportGroup.fromJson,
  );

  Future<SupportGroupTotals> totals() async => SupportGroupTotals.fromJson(
    await client.get('support-groups/totals/') as Map<String, dynamic>,
  );

  Future<SupportGroup> decide(String id, String decision, {String reason = ''}) async =>
      SupportGroup.fromJson(
        await client.post(
              'support-groups/$id/$decision/',
              body: {if (reason.trim().isNotEmpty) 'reason': reason.trim()},
            )
            as Map<String, dynamic>,
      );

  Future<ApiPage<GroupPerson>> groupPeople(String id, {int offset = 0}) async => ApiPage.fromJson(
    await client.get('support-groups/$id/members/', query: {if (offset > 0) 'offset': '$offset'}),
    GroupPerson.fromJson,
  );

  /// Moves a group to another type.
  Future<SupportGroup> changeKind(String id, String kind) async => SupportGroup.fromJson(
    await client.post('support-groups/$id/kind/', body: {'kind': kind}) as Map<String, dynamic>,
  );

  // --- types of group ---------------------------------------------------------------

  /// Every type, offered or not.
  Future<List<GroupKind>> kinds() async {
    final body = await client.get('support-groups/kinds/') as List<dynamic>;
    return [for (final item in body) GroupKind.fromJson(item as Map<String, dynamic>)];
  }

  /// Adds a type, offered at once.
  Future<GroupKind> addKind(String name) async => GroupKind.fromJson(
    await client.post('support-groups/kinds/', body: {'name': name.trim()})
        as Map<String, dynamic>,
  );

  /// Renames a type, or stops or starts offering it.
  Future<GroupKind> updateKind(String code, {String? name, bool? offered}) async =>
      GroupKind.fromJson(
        await client.patch(
              'support-groups/kinds/$code/',
              body: {'name': ?name?.trim(), 'offered': ?offered},
            )
            as Map<String, dynamic>,
      );
}
