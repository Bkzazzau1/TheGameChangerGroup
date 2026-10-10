import '../domain/models.dart';
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
  final String? phoneNumber;
  final String? email;

  bool get isMember => roleName == 'member';

  factory ServerUser.fromJson(Map<String, dynamic> json) {
    final roleName = json['role'] as String;
    return ServerUser(
      accessId: json['access_id'] as String,
      fullName: json['full_name'] as String,
      roleName: roleName,
      role: TgcgRole.values.asNameMap()[roleName],
      scope: geographicScopeFromJson(json['scope'] as Map<String, dynamic>),
      capabilities: {...(json['capabilities'] as List<dynamic>? ?? const []).cast<String>()},
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
