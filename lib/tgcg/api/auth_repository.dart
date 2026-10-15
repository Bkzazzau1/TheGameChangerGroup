import '../domain/models.dart';
import 'access_repository.dart';
import 'api_client.dart';

/// The signed-in account as the server describes it (`/auth/me/`).
class ServerUser {
  const ServerUser({
    required this.accessId,
    required this.fullName,
    required this.roleName,
    required this.role,
    required this.scope,
    required this.capabilities,
    this.access = const [],
    this.membershipNumber,
    this.supervises = false,
    this.identityVerified = true,
    this.phoneNumber,
    this.email,
  });

  final String accessId;
  final String fullName;

  /// Raw role from the server; [role] is null for roles this app does not
  /// serve (for example `member`, which uses the member app).
  final String roleName;
  final TgcgRole? role;
  final GeographicScope scope;
  final Set<String> capabilities;

  /// Where the access comes from: each appointment, delegation or legacy role.
  final List<AccessGrant> access;

  /// The member behind this account, when there is one.
  final String? membershipNumber;

  /// Holds a role others report to: may see, suspend and reinstate their
  /// appointments.
  final bool supervises;

  /// A coordinator has checked the identity of the member behind the account.
  /// Membership never needs it; agents, observers and appointed roles do.
  final bool identityVerified;
  final String? phoneNumber;
  final String? email;

  /// A member's own account (no former fixed role).
  bool get isMember => roleName == 'member';

  /// Any member's account without operational access gets the member app,
  /// including a member whose agent role waits for an identity check.
  bool get usesMemberApp =>
      (isMember || membershipNumber != null) && capabilities.isEmpty && !supervises;

  /// The field role this account holds but cannot use until the member's
  /// identity is checked, in words for the member.
  String? get roleAwaitingVerification => identityVerified || capabilities.isNotEmpty
      ? null
      : switch (roleName) {
          'pollingUnitAgent' => 'polling unit agent',
          'observer' => 'observer',
          _ => null,
        };

  /// Where the operator works: a former fixed role's own scope, or the
  /// smallest area containing every area their appointments cover (a member's
  /// own scope is only where they registered).
  GeographicScope get workingScope {
    final areas = [for (final grant in access) ...grant.areas];
    return role != null || areas.isEmpty ? scope : commonScope(areas);
  }

  factory ServerUser.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String;
    return ServerUser(
      accessId: json['access_id'] as String,
      fullName: json['full_name'] as String,
      roleName: roleName,
      role: TgcgRole.values.asNameMap()[roleName],
      scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
      capabilities: {...(json['capabilities'] as List<dynamic>? ?? const []).cast<String>()},
      access: [
        for (final grant in (json['access'] as List<dynamic>? ?? const []))
          AccessGrant.fromJson(grant as Map<String, dynamic>),
      ],
      membershipNumber: json['membership_number'] as String?,
      supervises: json['supervises'] as bool? ?? false,
      identityVerified: json['identity_verified'] as bool? ?? true,
      phoneNumber: json['phone_number'] as String?,
      email: json['email'] as String?,
    );
  }
}

/// Reads the scope object the backend sends (same keys as the client's).
GeographicScope geographicScopeFromJson(Map<String, dynamic> json) => GeographicScope(
      level: GeographyLevel.values.byName(json['level'] as String),
      country: (json['country'] as String?) ?? 'Nigeria',
      zoneId: json['zoneId'] as String?,
      zoneName: json['zoneName'] as String?,
      stateId: json['stateId'] as String?,
      stateName: json['stateName'] as String?,
      senatorialDistrictId: json['senatorialDistrictId'] as String?,
      senatorialDistrictName: json['senatorialDistrictName'] as String?,
      lgaId: json['lgaId'] as String?,
      lgaName: json['lgaName'] as String?,
      wardId: json['wardId'] as String?,
      wardName: json['wardName'] as String?,
      pollingUnitId: json['pollingUnitId'] as String?,
      pollingUnitName: json['pollingUnitName'] as String?,
    );

class AuthRepository {
  AuthRepository(this.client);

  final ApiClient client;

  /// Sign in with an access ID or phone number and a password (or PIN).
  Future<ServerUser> login({required String identifier, required String password}) async {
    final body = await client.post(
      'auth/login/',
      body: {'username': identifier.trim(), 'password': password},
      authenticated: false,
    ) as Map<String, dynamic>;
    await client.tokens.write(
      access: body['access'] as String,
      refresh: body['refresh'] as String,
    );
    return ServerUser.fromJson(body['user'] as Map<String, dynamic>);
  }

  /// The saved session's user, or null when there is none (or it expired).
  /// Throws [ApiException] with `isOffline` when the server is unreachable,
  /// so the caller can keep the user signed in offline.
  Future<ServerUser?> restore() async {
    if (await client.tokens.read() == null) return null;
    try {
      return await me();
    } on ApiException catch (error) {
      if (error.isUnauthorized) {
        await client.tokens.clear();
        return null;
      }
      rethrow;
    }
  }

  Future<ServerUser> me() async =>
      ServerUser.fromJson(await client.get('auth/me/') as Map<String, dynamic>);

  /// Changes this account's password, or a member's 6-digit PIN. The server
  /// signs out every other device; this one carries on with new tokens.
  Future<void> changePassword({required String current, required String newPassword}) async {
    final body = await client.post(
      'auth/password/',
      body: {'current_password': current, 'new_password': newPassword},
    ) as Map<String, dynamic>;
    await client.tokens.write(
      access: body['access'] as String,
      refresh: body['refresh'] as String,
    );
  }

  /// Revokes the refresh token on the server (best effort) and forgets it.
  Future<void> logout() async {
    final saved = await client.tokens.read();
    try {
      if (saved != null) await client.post('auth/logout/', body: {'refresh': saved.refresh});
    } on ApiException {
      // Offline or already expired: the local tokens are still removed.
    } finally {
      await client.tokens.clear();
    }
  }
}


/// The smallest area that contains all of [areas]; Nigeria when they share
/// no zone.
GeographicScope commonScope(List<GeographicScope> areas) {
  if (areas.isEmpty || areas.any((area) => area.level == GeographyLevel.country)) {
    return GeographicScope.nigeria;
  }
  final first = areas.first;
  bool shared(String? Function(GeographicScope area) id) {
    final value = id(first);
    return value != null && areas.every((area) => id(area) == value);
  }

  if (!shared((area) => area.zoneId)) return GeographicScope.nigeria;
  final zone = GeographicScope(
    level: GeographyLevel.geopoliticalZone,
    country: first.country,
    zoneId: first.zoneId,
    zoneName: first.zoneName,
  );
  if (!shared((area) => area.stateId)) return zone;
  final state = GeographicScope(
    level: GeographyLevel.state,
    country: first.country,
    zoneId: first.zoneId,
    zoneName: first.zoneName,
    stateId: first.stateId,
    stateName: first.stateName,
  );
  if (!shared((area) => area.lgaId)) {
    if (!shared((area) => area.senatorialDistrictId)) return state;
    return GeographicScope(
      level: GeographyLevel.senatorialDistrict,
      country: first.country,
      zoneId: first.zoneId,
      zoneName: first.zoneName,
      stateId: first.stateId,
      stateName: first.stateName,
      senatorialDistrictId: first.senatorialDistrictId,
      senatorialDistrictName: first.senatorialDistrictName,
    );
  }
  final lga = GeographicScope(
    level: GeographyLevel.lga,
    country: first.country,
    zoneId: first.zoneId,
    zoneName: first.zoneName,
    stateId: first.stateId,
    stateName: first.stateName,
    senatorialDistrictId: first.senatorialDistrictId,
    senatorialDistrictName: first.senatorialDistrictName,
    lgaId: first.lgaId,
    lgaName: first.lgaName,
  );
  if (!shared((area) => area.wardId)) return lga;
  final ward = GeographicScope(
    level: GeographyLevel.ward,
    country: first.country,
    zoneId: first.zoneId,
    zoneName: first.zoneName,
    stateId: first.stateId,
    stateName: first.stateName,
    senatorialDistrictId: first.senatorialDistrictId,
    senatorialDistrictName: first.senatorialDistrictName,
    lgaId: first.lgaId,
    lgaName: first.lgaName,
    wardId: first.wardId,
    wardName: first.wardName,
  );
  if (!shared((area) => area.pollingUnitId)) return ward;
  return first;
}
