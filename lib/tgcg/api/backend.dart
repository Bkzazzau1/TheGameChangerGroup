import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'access_repository.dart';
import 'api_client.dart';
import 'auth_repository.dart';
import 'field_repository.dart';
import 'forum_repository.dart';
import 'member_admin_repository.dart';
import 'mapping_repository.dart';
import 'meetings_repository.dart';
import 'overview_repository.dart';
import 'member_repository.dart';
import 'messaging_repository.dart';
import 'projects_repository.dart';
import 'reference_repository.dart';
import 'results_repository.dart';
import 'security_repository.dart';
import 'tracking_repository.dart';
import 'wallet_repository.dart';

/// Everything that talks to the TGCG server.
class BackendServices {
  BackendServices({required this.client})
      : auth = AuthRepository(client),
        reference = ReferenceRepository(client),
        mapping = MappingRepository(client),
        member = MemberRepository(client),
        tracking = TrackingRepository(client),
        field = FieldRepository(client),
        results = ResultsRepository(client),
        meetings = MeetingsRepository(client),
        overview = OverviewRepository(client, TrackingRepository(client)),
        access = AccessRepository(client),
        members = MemberAdminRepository(client),
        forum = ForumRepository(client),
        wallets = WalletRepository(client),
        projects = ProjectsRepository(client),
        messaging = MessagingRepository(client),
        security = SecurityRepository(client);

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

  /// Incidents and field reports: the Situation Room and Field Monitoring.
  final FieldRepository field;

  /// Polling-unit results, their review, and collation.
  final ResultsRepository results;

  /// Meetings, and passes to join their calls (which run on LiveKit).
  final MeetingsRepository meetings;

  /// The dashboard's counts.
  final OverviewRepository overview;

  /// Roles, appointments, delegation and administrator approvals.
  final AccessRepository access;

  /// Staff work on members: identity review, standing, polling unit changes.
  final MemberAdminRepository members;

  /// The Social Forum: posts, comments, likes and reports.
  final ForumRepository forum;

  /// Members' wallets and the payments TGCG makes into them.
  final WalletRepository wallets;

  /// Projects: scheduled field work, who takes part, and where they are.
  final ProjectsRepository projects;

  /// Bulk messages, saved lists, the inbox and phones for app notifications.
  final MessagingRepository messaging;

  /// Incidents the Situation Room sends to security officers, and their answers.
  final SecurityRepository security;
}

/// Makes [BackendServices] available below it. The app always provides
/// them; `services` is null only for a page shown on its own, as in tests.
class TgcgBackend extends InheritedWidget {
  const TgcgBackend({super.key, required this.services, required super.child});

  final BackendServices? services;

  static BackendServices? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TgcgBackend>()?.services;

  @override
  bool updateShouldNotify(TgcgBackend oldWidget) => services != oldWidget.services;
}
