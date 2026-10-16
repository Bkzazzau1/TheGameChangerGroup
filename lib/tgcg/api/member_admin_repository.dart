import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/models.dart';
import 'access_repository.dart';
import 'api_client.dart';
import 'auth_repository.dart';

DateTime? _date(Object? value) => value == null ? null : DateTime.tryParse('$value')?.toLocal();

/// A member as staff see them (`/members/`). Personal details are null unless
/// the server allows this account to see them for the member's area.
class StaffMember {
  const StaffMember({
    required this.membershipNumber,
    required this.fullName,
    required this.verificationStatus,
    required this.membershipState,
    required this.scope,
    this.phoneNumber,
    this.email,
    this.vin,
    this.photoUrl,
    this.sensitiveVisible = false,
    this.hasPvc = false,
    this.roles = const [],
    this.createdAt,
    this.gender = '',
    this.dateOfBirth,
    this.occupation = '',
    this.disabilities = const [],
    this.disabilityOther = '',
    this.registrationChannel = '',
    this.phoneVerified = false,
    this.hasAppAccount = false,
  });

  final String membershipNumber;
  final String fullName;

  /// Quick USSD membership can exist before the caller adds their name.
  String get displayName => fullName.trim().isEmpty
      ? 'Name not added yet ($membershipNumber)'
      : fullName;

  /// unverified, pendingReview, verified or rejected.
  final String verificationStatus;

  /// active, suspended or deactivated.
  final String membershipState;
  final GeographicScope scope;
  final String? phoneNumber;
  final String? email;

  /// Masked: only the last four characters.
  final String? vin;
  final String? photoUrl;

  /// False when the server withheld personal details.
  final bool sensitiveVisible;
  final bool hasPvc;

  /// Current appointments: role names.
  final List<String> roles;
  final DateTime? createdAt;

  /// male, female or empty when not given.
  final String gender;

  /// Withheld (null) like the phone unless personal details are visible.
  final DateTime? dateOfBirth;
  final String occupation;

  /// Disability codes and words for "other": private details, empty unless
  /// personal details are visible.
  final List<String> disabilities;
  final String disabilityOther;

  /// How they joined: self (the app), ussd, assisted or import.
  final String registrationChannel;
  final bool phoneVerified;
  final bool hasAppAccount;

  bool get isVerified => verificationStatus == 'verified';

  factory StaffMember.fromJson(Map<String, dynamic> json) => StaffMember(
    membershipNumber: json['membership_number'] as String,
    fullName: json['full_name'] as String,
    verificationStatus: json['verification_status'] as String? ?? 'unverified',
    membershipState: json['membership_state'] as String? ?? 'active',
    scope: json['scope'] is Map<String, dynamic>
        ? geographicScopeFromJson(json['scope'] as Map<String, dynamic>)
        : GeographicScope.nigeria,
    phoneNumber: json['phone_number'] as String?,
    email: json['email'] as String?,
    vin: json['vin'] as String?,
    photoUrl: json['photo_url'] as String?,
    sensitiveVisible: json['sensitive_visible'] as bool? ?? false,
    hasPvc: json['has_pvc'] as bool? ?? false,
    roles: [
      for (final role in (json['roles'] as List<dynamic>? ?? const []))
        ((role as Map<String, dynamic>)['role_name'] as String?) ?? '',
    ],
    createdAt: _date(json['created_at']),
    gender: json['gender'] as String? ?? '',
    dateOfBirth: DateTime.tryParse('${json['date_of_birth'] ?? ''}'),
    occupation: json['occupation'] as String? ?? '',
    disabilities: [for (final kind in (json['disabilities'] as List?) ?? const []) '$kind'],
    disabilityOther: json['disability_other'] as String? ?? '',
    registrationChannel: json['registration_channel'] as String? ?? '',
    phoneVerified: json['phone_verified'] as bool? ?? false,
    hasAppAccount: json['has_app_account'] as bool? ?? false,
  );
}

/// Registered members in each smaller area of an area (`/members/counts/`),
/// keyed by the smaller areas' codes; areas without members are left out.
class MemberCounts {
  const MemberCounts({required this.total, required this.counts});

  /// Everyone in the area, including those registered above the smaller level.
  final int total;
  final Map<String, int> counts;

  int operator [](String code) => counts[code] ?? 0;

  factory MemberCounts.fromJson(Map<String, dynamic> json) => MemberCounts(
    total: json['total'] as int? ?? 0,
    counts: {
      for (final MapEntry(:key, :value) in (json['counts'] as Map<String, dynamic>? ?? {}).entries)
        key: value as int,
    },
  );
}

String verificationLabel(String status) => switch (status) {
  'verified' => 'Verified',
  'pendingReview' => 'Awaiting review',
  'rejected' => 'Rejected',
  _ => 'Not verified',
};

String membershipStateLabel(String state) => switch (state) {
  'suspended' => 'Suspended',
  'deactivated' => 'Deactivated',
  _ => 'Active',
};

/// One identity check and what it found.
class VerificationCheckResult {
  const VerificationCheckResult({
    required this.kind,
    required this.result,
    required this.detail,
    this.checkedAt,
    this.checkedBy,
  });

  final String kind;

  /// passed, failed, pending or unsupported.
  final String result;
  final String detail;
  final DateTime? checkedAt;
  final String? checkedBy;

  factory VerificationCheckResult.fromJson(Map<String, dynamic> json) => VerificationCheckResult(
    kind: json['kind'] as String,
    result: json['result'] as String,
    detail: json['detail'] as String? ?? '',
    checkedAt: _date(json['checked_at']),
    checkedBy: json['checked_by'] as String?,
  );
}

String checkLabel(String kind) => switch (kind) {
  'pvcCaptured' => 'PVC details captured',
  'cardMatch' => 'Name and VIN match the card photo',
  'pvcValidated' => 'PVC confirmed with INEC',
  'duplicates' => 'No duplicate registration',
  'phoneVerified' => 'Phone confirmed by SMS',
  'selfieCaptured' => 'Selfie captured',
  'liveness' => 'Liveness detection',
  'faceMatch' => 'Face matches a trusted photo',
  _ => kind,
};

/// The identity decision and every check behind it.
class MemberVerification {
  const MemberVerification({
    required this.membershipNumber,
    required this.status,
    required this.checks,
    this.verifiedAt,
    this.reviewedBy,
    this.verifiedAutomatically = false,
  });

  final String membershipNumber;
  final String status;
  final List<VerificationCheckResult> checks;
  final DateTime? verifiedAt;
  final String? reviewedBy;

  /// Verified under TGCG's policy for complete profiles, not by a person.
  final bool verifiedAutomatically;

  bool get hasFailedCheck => checks.any((check) => check.result == 'failed');

  factory MemberVerification.fromJson(Map<String, dynamic> json) => MemberVerification(
    membershipNumber: json['membership_number'] as String,
    status: json['verification_status'] as String,
    checks: [
      for (final check in (json['checks'] as List<dynamic>? ?? const []))
        VerificationCheckResult.fromJson(check as Map<String, dynamic>),
    ],
    verifiedAt: _date(json['verified_at']),
    reviewedBy: json['reviewed_by'] as String?,
    verifiedAutomatically: json['verified_automatically'] as bool? ?? false,
  );
}

/// A member's request to move their registered polling unit.
class PollingUnitChange {
  const PollingUnitChange({
    required this.id,
    required this.member,
    required this.memberName,
    required this.toPollingUnit,
    required this.toPollingUnitName,
    required this.status,
    required this.createdAt,
    this.fromPollingUnit,
    this.reason = '',
    this.decidedBy,
    this.decidedAt,
    this.decisionReason = '',
  });

  final String id;
  final String member;
  final String memberName;
  final String? fromPollingUnit;
  final String toPollingUnit;
  final String toPollingUnitName;

  /// pending, approved, rejected or withdrawn.
  final String status;
  final String reason;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String decisionReason;
  final DateTime createdAt;

  bool get isPending => status == 'pending';

  factory PollingUnitChange.fromJson(Map<String, dynamic> json) => PollingUnitChange(
    id: json['id'] as String,
    member: json['member'] as String,
    memberName: json['member_name'] as String? ?? '',
    fromPollingUnit: json['from_polling_unit'] as String?,
    toPollingUnit: json['to_polling_unit'] as String,
    toPollingUnitName: json['to_polling_unit_name'] as String? ?? '',
    status: json['status'] as String,
    reason: json['reason'] as String? ?? '',
    decidedBy: json['decided_by'] as String?,
    decidedAt: _date(json['decided_at']),
    decisionReason: json['decision_reason'] as String? ?? '',
    createdAt: _date(json['created_at']) ?? DateTime.now(),
  );
}

/// One detail a PVC scan changes. [from] is the member's detail now, shown
/// only while the scan waits; the server masks the VIN and withholds a date
/// of birth from those who may not see personal details.
class PvcChange {
  const PvcChange({required this.field, required this.label, this.from, this.to});

  final String field;
  final String label;
  final String? from;
  final String? to;

  factory PvcChange.fromJson(Map<String, dynamic> json) => PvcChange(
    field: json['field'] as String,
    label: json['label'] as String? ?? '',
    from: json['from'] as String?,
    to: json['to'] as String?,
  );
}

/// A checked member's PVC scan, waiting for (or past) a coordinator's second
/// check against the card.
class PvcUpdate {
  const PvcUpdate({
    required this.id,
    required this.member,
    required this.memberName,
    required this.status,
    required this.createdAt,
    this.changes = const [],
    this.decidedBy,
    this.decidedAt,
    this.decisionReason = '',
  });

  final String id;
  final String member;
  final String memberName;

  /// pending, approved, rejected or withdrawn.
  final String status;
  final List<PvcChange> changes;
  final String? decidedBy;
  final DateTime? decidedAt;
  final String decisionReason;
  final DateTime createdAt;

  bool get isPending => status == 'pending';

  factory PvcUpdate.fromJson(Map<String, dynamic> json) => PvcUpdate(
    id: json['id'] as String,
    member: json['member'] as String,
    memberName: json['member_name'] as String? ?? '',
    status: json['status'] as String,
    changes: [
      for (final change in (json['changes'] as List<dynamic>? ?? const []))
        PvcChange.fromJson(change as Map<String, dynamic>),
    ],
    decidedBy: json['decided_by'] as String?,
    decidedAt: _date(json['decided_at']),
    decisionReason: json['decision_reason'] as String? ?? '',
    createdAt: _date(json['created_at']) ?? DateTime.now(),
  );
}

/// Staff work on members: finding them, identity review, standing and
/// polling unit changes. The server enforces every area and permission.
class MemberAdminRepository {
  MemberAdminRepository(this.client);

  final ApiClient client;

  Future<ApiPage<StaffMember>> members({
    String search = '',
    String? verificationStatus,
    String? membershipState,
    String? phone,
    String? pollingUnit,
    int offset = 0,
  }) async => ApiPage.fromJson(
    await client.get(
      'members/',
      query: {
        if (search.trim().isNotEmpty) 'search': search.trim(),
        if (verificationStatus != null) 'verification_status': verificationStatus,
        if (membershipState != null) 'membership_state': membershipState,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (pollingUnit != null) ...{'polling_unit__code': pollingUnit, 'ordering': 'full_name'},
        if (offset > 0) 'offset': '$offset',
      },
    ),
    StaffMember.fromJson,
  );

  /// Registered members in each [by] area of the area [level]/[code]. The
  /// server refuses an area not wholly within this account's reach.
  Future<MemberCounts> counts({
    required GeographyLevel level,
    String? code,
    required GeographyLevel by,
  }) async => MemberCounts.fromJson(
    await client.get(
      'members/counts/',
      query: {'level': level.name, if (code != null) 'code': code, 'by': by.name},
    ) as Map<String, dynamic>,
  );

  Future<StaffMember> member(String number) async =>
      StaffMember.fromJson(await client.get('members/$number/') as Map<String, dynamic>);

  Future<MemberVerification> verification(String number) async => MemberVerification.fromJson(
    await client.get('members/$number/verification/') as Map<String, dynamic>,
  );

  Future<MemberVerification> runChecks(String number) async => MemberVerification.fromJson(
    await client.post('members/$number/verification/check/') as Map<String, dynamic>,
  );

  Future<MemberVerification> approveIdentity(String number, String notes) async =>
      MemberVerification.fromJson(
        await client.post('members/$number/verification/approve/', body: {'notes': notes.trim()})
            as Map<String, dynamic>,
      );

  Future<MemberVerification> rejectIdentity(String number, String reason) async =>
      MemberVerification.fromJson(
        await client.post('members/$number/verification/reject/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  Future<StaffMember> _standing(String number, String action, String reason) async =>
      StaffMember.fromJson(
        await client.post('members/$number/$action/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  Future<StaffMember> suspend(String number, String reason) => _standing(number, 'suspend', reason);

  Future<StaffMember> deactivate(String number, String reason) =>
      _standing(number, 'deactivate', reason);

  Future<StaffMember> restore(String number, {String reason = ''}) =>
      _standing(number, 'restore', reason);

  Future<List<AuditEntry>> history(String number) async => [
    for (final item in await client.get('members/$number/history/') as List<dynamic>)
      AuditEntry.fromJson(item as Map<String, dynamic>),
  ];

  Future<Uint8List> photo(String number) => client.getBytes('members/$number/photo/');

  Future<ApiPage<PollingUnitChange>> pollingUnitChanges({String? status, int offset = 0}) async =>
      ApiPage.fromJson(
        await client.get(
          'polling-unit-changes/',
          query: {if (status != null) 'status': status, if (offset > 0) 'offset': '$offset'},
        ),
        PollingUnitChange.fromJson,
      );

  Future<PollingUnitChange> approvePollingUnitChange(String id, {String reason = ''}) async =>
      PollingUnitChange.fromJson(
        await client.post('polling-unit-changes/$id/approve/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  Future<PollingUnitChange> rejectPollingUnitChange(String id, String reason) async =>
      PollingUnitChange.fromJson(
        await client.post('polling-unit-changes/$id/reject/', body: {'reason': reason.trim()})
            as Map<String, dynamic>,
      );

  /// The photo of the updated voter card behind a change request.
  Future<Uint8List> pollingUnitChangeCard(String id) =>
      client.getBytes('polling-unit-changes/$id/card/');

  /// Checked members' PVC scans for a second check, in the caller's areas.
  Future<ApiPage<PvcUpdate>> pvcUpdates({String? status, int offset = 0}) async =>
      ApiPage.fromJson(
        await client.get(
          'pvc-updates/',
          query: {if (status != null) 'status': status, if (offset > 0) 'offset': '$offset'},
        ),
        PvcUpdate.fromJson,
      );

  /// The card shows these details and belongs to the member: they replace theirs.
  Future<PvcUpdate> approvePvcUpdate(String id, {String reason = ''}) async => PvcUpdate.fromJson(
    await client.post('pvc-updates/$id/approve/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  Future<PvcUpdate> rejectPvcUpdate(String id, String reason) async => PvcUpdate.fromJson(
    await client.post('pvc-updates/$id/reject/', body: {'reason': reason.trim()})
        as Map<String, dynamic>,
  );

  /// The photo of the scanned voter card behind a PVC update.
  Future<Uint8List> pvcUpdateCard(String id) => client.getBytes('pvc-updates/$id/card/');
}

/// The member's own polling unit change requests.
extension MemberPollingUnitChanges on ApiClient {
  Future<List<PollingUnitChange>> myPollingUnitChanges() async => [
    for (final item in await get('me/polling-unit/changes/') as List<dynamic>)
      PollingUnitChange.fromJson(item as Map<String, dynamic>),
  ];

  Future<PollingUnitChange> requestPollingUnitChange({
    required String delim,
    required Uint8List cardImage,
    String reason = '',
  }) async => PollingUnitChange.fromJson(
    await postMultipart(
          'me/polling-unit/changes/',
          fields: {'delim': delim.trim(), 'reason': reason.trim()},
          files: () async => [
            http.MultipartFile.fromBytes('pvc_image', cardImage, filename: 'voter-card.jpg'),
          ],
        )
        as Map<String, dynamic>,
  );

  Future<PollingUnitChange> withdrawPollingUnitChange(String id) async =>
      PollingUnitChange.fromJson(
        await post('me/polling-unit/changes/$id/withdraw/') as Map<String, dynamic>,
      );
}
