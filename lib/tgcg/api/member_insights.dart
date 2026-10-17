import '../domain/models.dart';
import 'auth_repository.dart' show geographicScopeFromJson;

/// An area by level and code (none for Nigeria), with its name.
class AreaRef {
  const AreaRef(this.level, this.code, this.name);

  static const nigeria = AreaRef(GeographyLevel.country, null, 'Nigeria');

  /// The area [scope] names (its most specific unit).
  factory AreaRef.of(GeographicScope scope) => switch (scope.level) {
    GeographyLevel.country => nigeria,
    GeographyLevel.geopoliticalZone => AreaRef(scope.level, scope.zoneId, scope.zoneName ?? ''),
    GeographyLevel.state => AreaRef(scope.level, scope.stateId, scope.stateName ?? ''),
    GeographyLevel.senatorialDistrict => AreaRef(
      scope.level,
      scope.senatorialDistrictId,
      scope.senatorialDistrictName ?? '',
    ),
    GeographyLevel.lga => AreaRef(scope.level, scope.lgaId, scope.lgaName ?? ''),
    GeographyLevel.ward => AreaRef(scope.level, scope.wardId, scope.wardName ?? ''),
    GeographyLevel.pollingUnit => AreaRef(
      scope.level,
      scope.pollingUnitId,
      scope.pollingUnitName ?? '',
    ),
  };

  final GeographyLevel level;
  final String? code;
  final String name;

  Map<String, String> get query => {'level': level.name, 'code': ?code};

  /// The member list filter for this area, e.g. `lga__code`; null for Nigeria.
  String? get filterKey => switch (level) {
    GeographyLevel.country => null,
    GeographyLevel.geopoliticalZone => 'zone__code',
    GeographyLevel.state => 'state__code',
    GeographyLevel.senatorialDistrict => 'senatorial_district__code',
    GeographyLevel.lga => 'lga__code',
    GeographyLevel.ward => 'ward__code',
    GeographyLevel.pollingUnit => 'polling_unit__code',
  };
}

int _int(Object? value) => (value as num?)?.toInt() ?? 0;

Map<String, int> _counts(Object? value) => {
  for (final MapEntry(:key, :value) in ((value as Map<String, dynamic>?) ?? const {}).entries)
    key: _int(value),
};

List<String> _strings(Object? value) => [for (final item in (value as List?) ?? const []) '$item'];

/// "No VIN", "No selfie"... for what a profile lacks.
String gapLabel(String gap) => switch (gap) {
  'vin' => 'No VIN',
  'cardPhoto' => 'No card photo',
  'selfie' => 'No selfie',
  'gender' => 'No gender',
  'dateOfBirth' => 'No date of birth',
  _ => gap,
};

/// How a verified identity was confirmed.
String verifiedHowLabel(String? how) => switch (how) {
  'automatic' => 'checked by the system',
  'chapter' => "on the chapter's list",
  'person' => 'by a coordinator',
  _ => '',
};

/// Members in an area: totals and how they break down.
class MembersFigures {
  const MembersFigures({
    required this.total,
    this.new7Days = 0,
    this.new30Days = 0,
    this.fullyVerified = 0,
    this.withRole = 0,
    this.withDisability = 0,
    this.verification = const {},
    this.standing = const {},
    this.gender = const {},
    this.channel = const {},
    this.age = const {},
    this.profile = const {},
    this.weekly = const [],
  });

  final int total;
  final int new7Days;
  final int new30Days;
  final int fullyVerified;
  final int withRole;
  final int withDisability;

  /// verified, pendingReview, unverified, rejected.
  final Map<String, int> verification;

  /// active, suspended, deactivated.
  final Map<String, int> standing;

  /// male, female, and '' (not given).
  final Map<String, int> gender;

  /// self, assisted, ussd, import, referred.
  final Map<String, int> channel;

  /// Age bands in order (under18, 18-24 ... 65+), then unknown.
  final Map<String, int> age;

  /// How many have each: vin, cardPhoto, selfie, gender, dateOfBirth,
  /// phoneConfirmed, appAccount, signedIn.
  final Map<String, int> profile;

  /// New members in each of the last 12 weeks, by the Monday that starts it.
  final List<(DateTime, int)> weekly;

  factory MembersFigures.fromJson(Map<String, dynamic> json) => MembersFigures(
    total: _int(json['total']),
    new7Days: _int(json['new_7_days']),
    new30Days: _int(json['new_30_days']),
    fullyVerified: _int(json['fully_verified']),
    withRole: _int(json['with_role']),
    withDisability: _int(json['with_disability']),
    verification: _counts(json['verification']),
    standing: _counts(json['standing']),
    gender: _counts(json['gender']),
    channel: _counts(json['channel']),
    age: _counts(json['age']),
    profile: _counts(json['profile']),
    weekly: [
      for (final week in (json['weekly'] as List<dynamic>? ?? const []))
        (DateTime.parse((week as Map<String, dynamic>)['week'] as String), _int(week['count'])),
    ],
  );
}

/// Exco in an area: who holds posts there, at which levels, and their profiles.
class ExcoFigures {
  const ExcoFigures({
    this.people = 0,
    this.appointments = 0,
    this.here = 0,
    this.suspended = 0,
    this.verified = 0,
    this.fullyVerified = 0,
    this.women = 0,
    this.profile = const {},
    this.byLevel = const {},
    this.roles = const [],
  });

  final int people;

  /// Posts held: one person may hold several.
  final int appointments;

  /// Posts at this area itself (a state's own exco), not below it.
  final int here;
  final int suspended;
  final int verified;
  final int fullyVerified;
  final int women;
  final Map<String, int> profile;

  /// Posts at each level (state, senatorialDistrict, lga, ward, pollingUnit).
  final Map<String, int> byLevel;

  /// Positions, most held first: (role code, name, posts).
  final List<(String, String, int)> roles;

  factory ExcoFigures.fromJson(Map<String, dynamic> json) => ExcoFigures(
    people: _int(json['people']),
    appointments: _int(json['appointments']),
    here: _int(json['here']),
    suspended: _int(json['suspended']),
    verified: _int(json['verified']),
    fullyVerified: _int(json['fully_verified']),
    women: _int(json['women']),
    profile: _counts(json['profile']),
    byLevel: _counts(json['by_level']),
    roles: [
      for (final role in (json['roles'] as List<dynamic>? ?? const []))
        (
          (role as Map<String, dynamic>)['role'] as String,
          role['name'] as String? ?? '',
          _int(role['count']),
        ),
    ],
  );
}

/// One smaller area of the area analysed.
class AreaFigures {
  const AreaFigures({
    required this.area,
    this.members = 0,
    this.verified = 0,
    this.fullyVerified = 0,
    this.women = 0,
    this.new30Days = 0,
    this.exco = 0,
    this.excoPeople = 0,
  });

  final AreaRef area;
  final int members;
  final int verified;
  final int fullyVerified;
  final int women;
  final int new30Days;

  /// Exco posts in the area, and the people holding them.
  final int exco;
  final int excoPeople;
}

/// Members and exco in an area, with each smaller area beside it.
class MemberAnalysis {
  const MemberAnalysis({
    required this.scope,
    required this.members,
    required this.exco,
    this.by,
    this.parts = const [],
    this.withMembers = 0,
    this.withExco = 0,
  });

  final GeographicScope scope;
  final MembersFigures members;
  final ExcoFigures exco;

  /// The level of [parts]: states for Nigeria, LGAs for a state; none for a unit.
  final GeographyLevel? by;
  final List<AreaFigures> parts;
  final int withMembers;
  final int withExco;

  factory MemberAnalysis.fromJson(Map<String, dynamic> json) {
    final by = GeographyLevel.values.asNameMap()[json['by']];
    final coverage = json['coverage'] as Map<String, dynamic>? ?? const {};
    return MemberAnalysis(
      scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
      members: MembersFigures.fromJson(json['members'] as Map<String, dynamic>),
      exco: ExcoFigures.fromJson(json['exco'] as Map<String, dynamic>),
      by: by,
      parts: [
        if (by != null)
          for (final part in (json['parts'] as List<dynamic>? ?? const []))
            AreaFigures(
              area: AreaRef(
                by,
                (part as Map<String, dynamic>)['code'] as String,
                part['name'] as String? ?? '',
              ),
              members: _int(part['members']),
              verified: _int(part['verified']),
              fullyVerified: _int(part['fully_verified']),
              women: _int(part['women']),
              new30Days: _int(part['new_30_days']),
              exco: _int(part['exco']),
              excoPeople: _int(part['exco_people']),
            ),
      ],
      withMembers: _int(coverage['with_members']),
      withExco: _int(coverage['with_exco']),
    );
  }
}

/// Whoever holds an exco post. The phone is null unless this account may see it.
class ExcoHolder {
  const ExcoHolder({
    required this.membershipNumber,
    required this.fullName,
    required this.verificationStatus,
    required this.scope,
    this.phoneNumber,
    this.gender = '',
    this.verifiedHow,
    this.membershipState = 'active',
    this.gaps = const [],
    this.signedIn = false,
    this.hasAppAccount = false,
  });

  final String membershipNumber;
  final String fullName;
  final String? phoneNumber;
  final String gender;
  final String verificationStatus;
  final String? verifiedHow;
  final String membershipState;

  /// Where they registered.
  final GeographicScope scope;
  final List<String> gaps;
  final bool signedIn;
  final bool hasAppAccount;

  bool get fullyVerified => verificationStatus == 'verified' && gaps.isEmpty;

  factory ExcoHolder.fromJson(Map<String, dynamic> json) => ExcoHolder(
    membershipNumber: json['membership_number'] as String,
    fullName: json['full_name'] as String? ?? '',
    phoneNumber: json['phone_number'] as String?,
    gender: json['gender'] as String? ?? '',
    verificationStatus: json['verification_status'] as String? ?? 'unverified',
    verifiedHow: json['verified_how'] as String?,
    membershipState: json['membership_state'] as String? ?? 'active',
    scope: json['scope'] is Map<String, dynamic>
        ? geographicScopeFromJson(json['scope'] as Map<String, dynamic>)
        : GeographicScope.nigeria,
    gaps: _strings(json['gaps']),
    signedIn: json['signed_in'] as bool? ?? false,
    hasAppAccount: json['has_app_account'] as bool? ?? false,
  );
}

/// One exco post: a position held over one area.
class ExcoPost {
  const ExcoPost({
    required this.appointment,
    required this.role,
    required this.roleName,
    required this.area,
    required this.areaName,
    required this.holder,
    this.state = 'active',
  });

  final String appointment;
  final String role;
  final String roleName;

  /// active, suspended or scheduled.
  final String state;
  final GeographicScope area;
  final String areaName;
  final ExcoHolder holder;

  factory ExcoPost.fromJson(Map<String, dynamic> json) => ExcoPost(
    appointment: json['appointment'] as String,
    role: json['role'] as String,
    roleName: json['role_name'] as String? ?? '',
    state: json['appointment_state'] as String? ?? 'active',
    area: geographicScopeFromJson(json['area'] as Map<String, dynamic>),
    areaName: json['area_name'] as String? ?? '',
    holder: ExcoHolder.fromJson(json['member'] as Map<String, dynamic>),
  );
}
