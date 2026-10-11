import '../domain/models.dart';
import '../offline/offline_payloads.dart';
import 'api_client.dart';
import 'auth_repository.dart';

/// One page of a server list.
class ApiPage<T> {
  const ApiPage(this.items, {required this.count, this.hasMore = false});

  final List<T> items;
  final int count;
  final bool hasMore;

  static ApiPage<T> fromJson<T>(Object? body, T Function(Map<String, dynamic>) item) {
    if (body is List) {
      final items = [for (final json in body) item(json as Map<String, dynamic>)];
      return ApiPage(items, count: items.length);
    }
    final map = body as Map<String, dynamic>;
    return ApiPage(
      [for (final json in map['results'] as List<dynamic>) item(json as Map<String, dynamic>)],
      count: map['count'] as int? ?? 0,
      hasMore: map['next'] != null,
    );
  }
}

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

List<GeographicScope> _areas(Object? value) => [
  for (final area in (value as List<dynamic>? ?? const []))
    geographicScopeFromJson(area as Map<String, dynamic>),
];

List<String> _strings(Object? value) => [...(value as List<dynamic>? ?? const []).cast<String>()];

Map<String, Object?> _area(GeographicScope scope) =>
    geographicScopeToJson(scope)..removeWhere((key, value) => value == null);

/// What a permission means (`/access/permissions/`).
class PermissionInfo {
  const PermissionInfo({
    required this.code,
    required this.module,
    required this.action,
    required this.label,
    this.protected = false,
    this.sensitive = false,
  });

  final String code;
  final String module;
  final String action;
  final String label;

  /// Only National Administrators hold it; no custom role can.
  final bool protected;

  /// Gives access to members' personal details.
  final bool sensitive;

  factory PermissionInfo.fromJson(Map<String, dynamic> json) => PermissionInfo(
    code: json['code'] as String,
    module: json['module'] as String,
    action: json['action'] as String,
    label: json['label'] as String,
    protected: json['protected'] as bool? ?? false,
    sensitive: json['sensitive'] as bool? ?? false,
  );
}

/// Administrative powers: holding one lets a role appoint, create roles,
/// manage appointments or delegate.
const adminPowers = {'assignRoles', 'manageRoles', 'manageAssignments', 'delegateAuthority'};

enum RoleCategory { command, field, communications, legal, technical, membership, other }

String roleCategoryLabel(RoleCategory category) => switch (category) {
  RoleCategory.command => 'Command and administration',
  RoleCategory.field => 'Field operations',
  RoleCategory.communications => 'Communications and media',
  RoleCategory.legal => 'Legal',
  RoleCategory.technical => 'Technical support',
  RoleCategory.membership => 'Membership and mobilisation',
  RoleCategory.other => 'Other',
};

String geographyLevelLabel(GeographyLevel level) => switch (level) {
  GeographyLevel.country => 'National',
  GeographyLevel.geopoliticalZone => 'Zone',
  GeographyLevel.state => 'State',
  GeographyLevel.senatorialDistrict => 'Senatorial district',
  GeographyLevel.lga => 'LGA',
  GeographyLevel.ward => 'Ward',
  GeographyLevel.pollingUnit => 'Polling unit',
};

/// A role definition (`/access/roles/`).
class RoleDefinition {
  const RoleDefinition({
    required this.code,
    required this.name,
    required this.category,
    required this.permittedLevels,
    required this.permissions,
    this.description = '',
    this.supervisingRole,
    this.isSystem = false,
    this.isProtected = false,
    this.archived = false,
    this.archiveReason = '',
    this.createdBy,
    this.activeAssignments = 0,
  });

  final String code;
  final String name;
  final String description;
  final RoleCategory category;
  final List<GeographyLevel> permittedLevels;
  final Set<String> permissions;

  /// Code of the role this one reports to.
  final String? supervisingRole;
  final bool isSystem;

  /// National Administrator: changes only through the protected workflow.
  final bool isProtected;
  final bool archived;
  final String archiveReason;
  final String? createdBy;
  final int activeAssignments;

  bool get grantsAdminPowers => permissions.any(adminPowers.contains);

  factory RoleDefinition.fromJson(Map<String, dynamic> json) => RoleDefinition(
    code: json['code'] as String,
    name: json['name'] as String,
    description: json['description'] as String? ?? '',
    category: RoleCategory.values.asNameMap()[json['category']] ?? RoleCategory.other,
    permittedLevels: [
      for (final level in _strings(json['permitted_levels']))
        if (GeographyLevel.values.asNameMap()[level] case final GeographyLevel known) known,
    ],
    permissions: {..._strings(json['permissions'])},
    supervisingRole: json['supervising_role'] as String?,
    isSystem: json['is_system'] as bool? ?? false,
    isProtected: json['is_protected'] as bool? ?? false,
    archived: json['status'] == 'archived',
    archiveReason: json['archive_reason'] as String? ?? '',
    createdBy: json['created_by'] as String?,
    activeAssignments: json['active_assignments'] as int? ?? 0,
  );
}

/// What a new or edited role should be.
class RoleDraft {
  const RoleDraft({
    required this.name,
    required this.category,
    required this.permittedLevels,
    required this.permissions,
    this.description = '',
    this.supervisingRole,
  });

  final String name;
  final String description;
  final RoleCategory category;
  final List<GeographyLevel> permittedLevels;
  final Set<String> permissions;
  final String? supervisingRole;

  Map<String, Object?> toJson() => {
    'name': name.trim(),
    'description': description.trim(),
    'category': category.name,
    'permitted_levels': [for (final level in permittedLevels) level.name],
    'permissions': [...permissions]..sort(),
    'supervising_role': supervisingRole,
  };
}

/// The state of an appointment, including the ones derived from its dates.
enum AppointmentState { active, scheduled, expired, suspended, declined, resigned, revoked }

String appointmentStateLabel(AppointmentState state) => switch (state) {
  AppointmentState.active => 'Active',
  AppointmentState.scheduled => 'Scheduled',
  AppointmentState.expired => 'Expired',
  AppointmentState.suspended => 'Suspended',
  AppointmentState.declined => 'Declined',
  AppointmentState.resigned => 'Resigned',
  AppointmentState.revoked => 'Revoked',
};

/// One member holding one role over one or more areas (`/access/assignments/`).
class Appointment {
  const Appointment({
    required this.id,
    required this.member,
    required this.memberName,
    required this.role,
    required this.roleName,
    required this.areas,
    required this.permissions,
    required this.state,
    required this.startsAt,
    this.supervisingRole,
    this.restrictedPermissions,
    this.endsAt,
    this.statusReason = '',
    this.statusChangedAt,
    this.acceptedAt,
    this.grantedBy,
    this.authority = '',
  });

  final String id;
  final String member;
  final String memberName;
  final String role;
  final String roleName;
  final String? supervisingRole;
  final List<GeographicScope> areas;

  /// Null when the appointment carries all of its role's permissions.
  final List<String>? restrictedPermissions;

  /// What it carries now (the role's, narrowed by any restriction).
  final Set<String> permissions;
  final AppointmentState state;
  final DateTime startsAt;
  final DateTime? endsAt;
  final String statusReason;
  final DateTime? statusChangedAt;
  final DateTime? acceptedAt;
  final String? grantedBy;
  final String authority;

  /// Still in force, or will be (active or scheduled).
  bool get isCurrent => state == AppointmentState.active || state == AppointmentState.scheduled;

  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
    id: json['id'] as String,
    member: json['member'] as String,
    memberName: json['member_name'] as String,
    role: json['role'] as String,
    roleName: json['role_name'] as String,
    supervisingRole: json['supervising_role'] as String?,
    areas: _areas(json['areas']),
    restrictedPermissions: json['restricted_permissions'] == null
        ? null
        : _strings(json['restricted_permissions']),
    permissions: {..._strings(json['permissions'])},
    state: AppointmentState.values.asNameMap()[json['state']] ?? AppointmentState.revoked,
    startsAt: _date(json['starts_at']) ?? DateTime.now(),
    endsAt: _date(json['ends_at']),
    statusReason: json['status_reason'] as String? ?? '',
    statusChangedAt: _date(json['status_changed_at']),
    acceptedAt: _date(json['accepted_at']),
    grantedBy: json['granted_by'] as String?,
    authority: json['authority'] as String? ?? '',
  );
}

/// One source of the signed-in user's access (`/me/access/`).
class AccessGrant {
  const AccessGrant({
    required this.source,
    required this.key,
    required this.role,
    required this.roleName,
    required this.areas,
    required this.permissions,
    this.protected = false,
  });

  /// `assignment`, `delegation` or `legacy`.
  final String source;
  final String key;
  final String role;
  final String roleName;
  final List<GeographicScope> areas;
  final Set<String> permissions;
  final bool protected;

  factory AccessGrant.fromJson(Map<String, dynamic> json) => AccessGrant(
    source: json['source'] as String,
    key: json['assignment'] as String? ?? '',
    role: json['role'] as String? ?? '',
    roleName: json['role_name'] as String? ?? '',
    areas: _areas(json['areas']),
    permissions: {..._strings(json['permissions'])},
    protected: json['protected'] as bool? ?? false,
  );
}

/// Delegated authority (`/access/delegations/`).
class Delegation {
  const Delegation({
    required this.id,
    required this.grantor,
    required this.grantorName,
    required this.recipient,
    required this.recipientName,
    required this.permissions,
    required this.categories,
    required this.levels,
    required this.areas,
    required this.state,
    required this.startsAt,
    this.canRedelegate = false,
    this.depth = 0,
    this.endsAt,
    this.revokedAt,
    this.revokedBy,
    this.revokeReason = '',
    this.source = '',
    this.reason = '',
  });

  final String id;
  final String grantor;
  final String grantorName;
  final String recipient;
  final String recipientName;
  final Set<String> permissions;
  final List<RoleCategory> categories;
  final List<GeographyLevel> levels;
  final List<GeographicScope> areas;

  /// active, scheduled, expired or revoked.
  final String state;
  final bool canRedelegate;
  final int depth;
  final DateTime startsAt;
  final DateTime? endsAt;
  final DateTime? revokedAt;
  final String? revokedBy;
  final String revokeReason;
  final String source;
  final String reason;

  bool get isRevoked => state == 'revoked';

  factory Delegation.fromJson(Map<String, dynamic> json) => Delegation(
    id: json['id'] as String,
    grantor: json['grantor'] as String,
    grantorName: json['grantor_name'] as String? ?? '',
    recipient: json['recipient'] as String,
    recipientName: json['recipient_name'] as String? ?? '',
    permissions: {..._strings(json['permissions'])},
    categories: [
      for (final category in _strings(json['categories']))
        if (RoleCategory.values.asNameMap()[category] case final RoleCategory known) known,
    ],
    levels: [
      for (final level in _strings(json['levels']))
        if (GeographyLevel.values.asNameMap()[level] case final GeographyLevel known) known,
    ],
    areas: _areas(json['areas']),
    state: json['state'] as String? ?? 'active',
    canRedelegate: json['can_redelegate'] as bool? ?? false,
    depth: json['depth'] as int? ?? 0,
    startsAt: _date(json['starts_at']) ?? DateTime.now(),
    endsAt: _date(json['ends_at']),
    revokedAt: _date(json['revoked_at']),
    revokedBy: json['revoked_by'] as String?,
    revokeReason: json['revoke_reason'] as String? ?? '',
    source: json['source'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
  );
}

/// What a new delegation should be.
class DelegationDraft {
  const DelegationDraft({
    required this.recipient,
    required this.permissions,
    required this.categories,
    required this.levels,
    required this.areas,
    this.canRedelegate = false,
    this.depth = 0,
    this.startsAt,
    this.endsAt,
    this.reason = '',
  });

  /// Membership number.
  final String recipient;
  final Set<String> permissions;
  final Set<RoleCategory> categories;
  final Set<GeographyLevel> levels;
  final List<GeographicScope> areas;
  final bool canRedelegate;
  final int depth;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final String reason;

  Map<String, Object?> toJson() => {
    'recipient': recipient.trim().toUpperCase(),
    'permissions': [...permissions]..sort(),
    'categories': [for (final category in categories) category.name],
    'levels': [for (final level in levels) level.name],
    'areas': [for (final area in areas) _area(area)],
    'can_redelegate': canRedelegate,
    'depth': canRedelegate ? depth : 0,
    'starts_at': startsAt?.toUtc().toIso8601String(),
    'ends_at': endsAt?.toUtc().toIso8601String(),
    'reason': reason.trim(),
  };
}

/// A request to suspend or remove a National Administrator.
class AdminAction {
  const AdminAction({
    required this.id,
    required this.target,
    required this.targetName,
    required this.kind,
    required this.reason,
    required this.requestedBy,
    required this.status,
    required this.approvals,
    required this.createdAt,
    this.executedAt,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason = '',
  });

  final String id;
  final String target;
  final String targetName;

  /// `suspend` or `remove`.
  final String kind;
  final String reason;
  final String requestedBy;

  /// `pending`, `executed` or `cancelled`.
  final String status;

  /// Access IDs of the administrators who approved, the requester first.
  final List<String> approvals;
  final DateTime createdAt;
  final DateTime? executedAt;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String cancelReason;

  bool get isPending => status == 'pending';

  factory AdminAction.fromJson(Map<String, dynamic> json) => AdminAction(
    id: json['id'] as String,
    target: json['target'] as String,
    targetName: json['target_name'] as String? ?? '',
    kind: json['kind'] as String,
    reason: json['reason'] as String? ?? '',
    requestedBy: json['requested_by'] as String,
    status: json['status'] as String,
    approvals: [
      for (final approval in (json['approvals'] as List<dynamic>? ?? const []))
        (approval as Map<String, dynamic>)['approver'] as String,
    ],
    createdAt: _date(json['created_at']) ?? DateTime.now(),
    executedAt: _date(json['executed_at']),
    cancelledAt: _date(json['cancelled_at']),
    cancelledBy: json['cancelled_by'] as String?,
    cancelReason: json['cancel_reason'] as String? ?? '',
  );
}

/// A National Administrator account and its standing.
class AdministratorAccount {
  const AdministratorAccount({
    required this.accessId,
    required this.fullName,
    required this.state,
    this.legacy = false,
    this.appointments = const [],
    this.pendingRequest,
  });

  final String accessId;
  final String fullName;

  /// `active`, `suspended` or `inactive`.
  final String state;
  final bool legacy;
  final List<String> appointments;
  final String? pendingRequest;

  factory AdministratorAccount.fromJson(Map<String, dynamic> json) => AdministratorAccount(
    accessId: json['access_id'] as String,
    fullName: json['full_name'] as String,
    state: json['state'] as String,
    legacy: json['legacy'] as bool? ?? false,
    appointments: _strings(json['appointments']),
    pendingRequest: json['pending_request'] as String?,
  );
}

/// One security event (`/access/audit/` and the history endpoints).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.createdAt,
    required this.actor,
    required this.action,
    required this.targetType,
    required this.targetId,
    this.targetLabel = '',
    this.reason = '',
    this.changes = const {},
    this.provenance = const {},
  });

  final int id;
  final DateTime createdAt;
  final String actor;
  final String action;
  final String targetType;
  final String targetId;
  final String targetLabel;
  final String reason;
  final Map<String, dynamic> changes;
  final Map<String, dynamic> provenance;

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
    id: json['id'] as int,
    createdAt: _date(json['created_at']) ?? DateTime.now(),
    actor: json['actor'] as String? ?? '',
    action: json['action'] as String,
    targetType: json['target_type'] as String? ?? '',
    targetId: json['target_id'] as String? ?? '',
    targetLabel: json['target_label'] as String? ?? '',
    reason: json['reason'] as String? ?? '',
    changes: json['changes'] as Map<String, dynamic>? ?? const {},
    provenance: json['provenance'] as Map<String, dynamic>? ?? const {},
  );
}

/// Roles, appointments, delegated authority, administrator approvals and the
/// audit log. Every rule is the server's; this only asks.
class AccessRepository {
  AccessRepository(this.client);

  final ApiClient client;

  Future<List<PermissionInfo>> permissions() async => [
    for (final item in await client.get('access/permissions/') as List<dynamic>)
      PermissionInfo.fromJson(item as Map<String, dynamic>),
  ];

  Future<ApiPage<RoleDefinition>> roles({
    String search = '',
    RoleCategory? category,
    bool? archived,
    int offset = 0,
  }) async => ApiPage.fromJson(
    await client.get(
      'access/roles/',
      query: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (category != null) 'category': category.name,
        if (archived != null) 'status': archived ? 'archived' : 'active',
        'ordering': 'name',
        if (offset > 0) 'offset': '$offset',
      },
    ),
    RoleDefinition.fromJson,
  );

  Future<RoleDefinition> role(String code) async =>
      RoleDefinition.fromJson(await client.get('access/roles/$code/') as Map<String, dynamic>);

  Future<RoleDefinition> createRole(RoleDraft draft) async => RoleDefinition.fromJson(
    await client.post('access/roles/', body: draft.toJson()) as Map<String, dynamic>,
  );

  Future<RoleDefinition> updateRole(String code, Map<String, Object?> changes) async =>
      RoleDefinition.fromJson(
        await client.patch('access/roles/$code/', body: changes) as Map<String, dynamic>,
      );

  Future<RoleDefinition> archiveRole(String code, String reason) async => RoleDefinition.fromJson(
    await client.post('access/roles/$code/archive/', body: {'reason': reason})
        as Map<String, dynamic>,
  );

  Future<RoleDefinition> restoreRole(String code, {String reason = ''}) async =>
      RoleDefinition.fromJson(
        await client.post('access/roles/$code/restore/', body: {'reason': reason})
            as Map<String, dynamic>,
      );

  Future<ApiPage<Appointment>> appointments({
    String search = '',
    String? status,
    String? role,
    String? member,
    int offset = 0,
  }) async => ApiPage.fromJson(
    await client.get(
      'access/assignments/',
      query: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (status != null) 'status': status,
        if (role != null) 'role__code': role,
        if (member != null) 'member__membership_number': member,
        if (offset > 0) 'offset': '$offset',
      },
    ),
    Appointment.fromJson,
  );

  Future<Appointment> appoint({
    required String member,
    required String role,
    required List<GeographicScope> areas,
    List<String>? restrictedPermissions,
    DateTime? startsAt,
    DateTime? endsAt,
    String reason = '',
  }) async => Appointment.fromJson(
    await client.post(
          'access/assignments/',
          body: {
            'member': member.trim().toUpperCase(),
            'role': role,
            'areas': [for (final area in areas) _area(area)],
            'restricted_permissions': restrictedPermissions,
            'starts_at': startsAt?.toUtc().toIso8601String(),
            'ends_at': endsAt?.toUtc().toIso8601String(),
            'reason': reason.trim(),
          },
        )
        as Map<String, dynamic>,
  );

  Future<Appointment> _change(String id, String action, String reason) async =>
      Appointment.fromJson(
        await client.post('access/assignments/$id/$action/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  Future<Appointment> suspendAppointment(String id, String reason) =>
      _change(id, 'suspend', reason);

  Future<Appointment> reactivateAppointment(String id, {String reason = ''}) =>
      _change(id, 'reactivate', reason);

  Future<Appointment> revokeAppointment(String id, String reason) => _change(id, 'revoke', reason);

  /// Keep only [permissions] (null lifts the restriction).
  Future<Appointment> restrictAppointment(String id, List<String>? permissions) async =>
      Appointment.fromJson(
        await client.post('access/assignments/$id/restrict/', body: {'permissions': permissions})
            as Map<String, dynamic>,
      );

  Future<List<AuditEntry>> appointmentHistory(String id) async => [
    for (final item in await client.get('access/assignments/$id/history/') as List<dynamic>)
      AuditEntry.fromJson(item as Map<String, dynamic>),
  ];

  Future<List<AccessGrant>> myAccess() async => [
    for (final item in await client.get('me/access/') as List<dynamic>)
      AccessGrant.fromJson(item as Map<String, dynamic>),
  ];

  Future<List<Appointment>> myAppointments() async => [
    for (final item in await client.get('me/assignments/') as List<dynamic>)
      Appointment.fromJson(item as Map<String, dynamic>),
  ];

  Future<Appointment> acceptAppointment(String id) async =>
      Appointment.fromJson(await client.post('me/assignments/$id/accept/') as Map<String, dynamic>);

  Future<Appointment> declineAppointment(String id, {String reason = ''}) async =>
      Appointment.fromJson(
        await client.post('me/assignments/$id/decline/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  Future<Appointment> resignAppointment(String id, {String reason = ''}) async =>
      Appointment.fromJson(
        await client.post('me/assignments/$id/resign/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  Future<ApiPage<Delegation>> delegations({String? status, int offset = 0}) async =>
      ApiPage.fromJson(
        await client.get(
          'access/delegations/',
          query: {if (status != null) 'status': status, if (offset > 0) 'offset': '$offset'},
        ),
        Delegation.fromJson,
      );

  Future<Delegation> delegate(DelegationDraft draft) async => Delegation.fromJson(
    await client.post('access/delegations/', body: draft.toJson()) as Map<String, dynamic>,
  );

  Future<Delegation> revokeDelegation(String id, String reason) async => Delegation.fromJson(
    await client.post('access/delegations/$id/revoke/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  Future<List<AuditEntry>> delegationHistory(String id) async => [
    for (final item in await client.get('access/delegations/$id/history/') as List<dynamic>)
      AuditEntry.fromJson(item as Map<String, dynamic>),
  ];

  Future<ApiPage<AdminAction>> adminActions({String? status}) async => ApiPage.fromJson(
    await client.get('access/admin-actions/', query: {if (status != null) 'status': status}),
    AdminAction.fromJson,
  );

  Future<AdminAction> requestAdminAction({
    required String target,
    required String kind,
    required String reason,
  }) async => AdminAction.fromJson(
    await client.post(
          'access/admin-actions/',
          body: {'target': target.trim().toUpperCase(), 'kind': kind, 'reason': reason.trim()},
        )
        as Map<String, dynamic>,
  );

  Future<AdminAction> approveAdminAction(String id) async => AdminAction.fromJson(
    await client.post('access/admin-actions/$id/approve/') as Map<String, dynamic>,
  );

  Future<AdminAction> cancelAdminAction(String id, {String reason = ''}) async =>
      AdminAction.fromJson(
        await client.post('access/admin-actions/$id/cancel/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  Future<List<AdministratorAccount>> administrators() async => [
    for (final item in await client.get('access/administrators/') as List<dynamic>)
      AdministratorAccount.fromJson(item as Map<String, dynamic>),
  ];

  Future<AdministratorAccount> reinstateAdministrator(String accessId, String reason) async =>
      AdministratorAccount.fromJson(
        await client.post(
              'access/administrators/$accessId/reinstate/',
              body: {'reason': reason.trim()},
            )
            as Map<String, dynamic>,
      );

  /// Checks the audit log's hash chain: the id of the first altered event,
  /// or null when it is intact.
  Future<int?> verifyAudit() async {
    final body = await client.get('access/audit/verify/') as Map<String, dynamic>;
    return body['intact'] == true ? null : body['first_broken_event'] as int?;
  }

  Future<ApiPage<AuditEntry>> audit({String? action, int offset = 0}) async => ApiPage.fromJson(
    await client.get(
      'access/audit/',
      query: {
        if (action != null) 'action__startswith': action,
        if (offset > 0) 'offset': '$offset',
      },
    ),
    AuditEntry.fromJson,
  );
}
