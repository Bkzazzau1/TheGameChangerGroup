import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'access_repository.dart';
import 'api_client.dart';
import 'auth_repository.dart';
import 'member_admin_repository.dart';
import 'mapping_repository.dart';
import 'member_repository.dart';
import 'reference_repository.dart';
import 'tracking_repository.dart';

/// Everything that talks to the TGCG server.
class BackendServices {
  BackendServices({required this.client})
      : auth = AuthRepository(client),
        reference = ReferenceRepository(client),
        mapping = MappingRepository(client),
        member = MemberRepository(client),
        tracking = TrackingRepository(client),
        access = AccessRepository(client),
        members = MemberAdminRepository(client);

  factory BackendServices.connect(
    String baseUrl, {
    TokenStore? tokens,
    http.Client? httpClient,
  }) =>
      BackendServices(
        client: ApiClient(
          baseUrl: baseUrl,
          tokens: tokens ?? SecureTokenStore(),
          httpClient: httpClient,
        ),
      );

  final ApiClient client;
  final AuthRepository auth;
  final ReferenceRepository reference;
  final MappingRepository mapping;

  /// Member registration and the member app.
  final MemberRepository member;

  /// Live agent positions and check-in coverage.
  final TrackingRepository tracking;

  /// Roles, appointments, delegation and administrator approvals.
  final AccessRepository access;

  /// Staff work on members: identity review, standing, polling unit changes.
  final MemberAdminRepository members;
}

/// Makes [BackendServices] available below it. `services` is null in
/// offline presentation mode (no TGCG_API_URL configured).
class TgcgBackend extends InheritedWidget {
  const TgcgBackend({super.key, required this.services, required super.child});

  final BackendServices? services;

  static BackendServices? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TgcgBackend>()?.services;

  @override
  bool updateShouldNotify(TgcgBackend oldWidget) => services != oldWidget.services;
}
