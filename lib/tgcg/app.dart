import 'dart:async';

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/backend.dart';
import 'api/http_sync_transport.dart';
import 'communications/bulk_communications_store.dart';
import 'communications/communications_store.dart';
import 'field/field_agent_shell.dart';
import 'field/field_operations_store.dart';
import 'geography/geography_registry.dart';
import 'governance/governance_store.dart';
import 'login_page.dart';
import 'member/member_shell.dart';
import 'membership/membership_store.dart';
import 'messaging/push.dart';
import 'media/device_media.dart';
import 'offline/offline_persistence.dart';
import 'projects/project_mode.dart';
import 'reports/report_store.dart';
import 'results/result_operations_store.dart';
import 'security/emergency_response_store.dart';
import 'session.dart';
import 'shell.dart';
import 'sync/sync_controller.dart';
import 'ui/tgcg_design.dart';
import 'ui/tgcg_theme.dart';

class TgcgApp extends StatefulWidget {
  const TgcgApp({super.key, this.backend});

  /// Server connection; the TGCG server at [tgcgApiUrl] unless a test passes
  /// another.
  final BackendServices? backend;

  static const Color primary = TgcgColors.primary;
  static const Color accent = TgcgColors.accent;
  static const Color canvas = TgcgColors.canvas;
  static const Color ink = TgcgColors.ink;
  static const Color muted = TgcgColors.muted;

  @override
  State<TgcgApp> createState() => _TgcgAppState();
}

class _TgcgAppState extends State<TgcgApp> {
  late final BackendServices backend = widget.backend ?? BackendServices.connect(tgcgApiUrl);

  /// True while a saved server session is being restored at startup.
  bool restoringSession = true;
  late TgcgSessionController sessionController;
  late OfflinePersistenceController offlinePersistenceController;

  /// Uploads the offline outbox while signed in to the server.
  late SyncController syncController;
  late MembershipOperationsController membershipOperationsController;
  late GovernanceOperationsController governanceOperationsController;
  late FieldOperationsController fieldOperationsController;
  late ResultOperationsController resultOperationsController;
  late CommunicationsController communicationsController;
  late BulkCommunicationsController bulkCommunicationsController;
  late ReportOperationsController reportOperationsController;
  late EmergencyResponseController emergencyResponseController;

  @override
  void initState() {
    super.initState();
    _createControllers();
    unawaited(offlinePersistenceController.initialize());
    backend.client.onSessionExpired = () {
      if (sessionController.isServerSession) sessionController.signOut();
    };
    unawaited(_restoreSession(backend));
  }

  Future<void> _restoreSession(BackendServices services) async {
    try {
      final user = await services.auth.restore();
      if (user != null && user.usesMemberApp && mounted) {
        sessionController.signInMember(
          fullName: user.fullName,
          membershipNumber: user.membershipNumber ?? user.accessId,
          waitingRole: user.roleAwaitingVerification,
        );
      } else if (user != null && user.roleAwaitingVerification != null) {
        // An agent account that belongs to no member: signing in says why.
        await services.auth.logout();
      } else if (user != null && (user.role != null || user.capabilities.isNotEmpty) && mounted) {
        sessionController.signInFromServer(
          role: user.role,
          fullName: user.fullName,
          accessId: user.accessId,
          scope: user.workingScope,
          capabilities: user.capabilities,
          grants: user.access,
          supervises: user.supervises,
          membershipNumber: user.membershipNumber ?? (user.isMember ? user.accessId : null),
        );
      }
    } on ApiException {
      // Offline at startup: the user signs in again once connected.
    } finally {
      if (mounted) setState(() => restoringSession = false);
    }
  }

  void _createControllers() {
    final services = backend;
    final session = sessionController = TgcgSessionController(
      onSignOut: () async {
        // While still signed in: this phone stops receiving the account's
        // notifications. A slow network does not hold up the sign-out.
        await PushNotifications.stop(services).timeout(const Duration(seconds: 5), onTimeout: () {});
        await services.auth.logout();
      },
    );
    final offline = offlinePersistenceController = OfflinePersistenceController();
    final sync = syncController = SyncController(
      persistence: offline,
      transport: HttpSyncTransport(
        services.client,
        accessId: () => session.accessId,
        outbox: offline,
      ),
    );
    // Members have no field records to upload.
    session.addListener(() => sync.setEnabled(session.isServerSession && !session.isMember));
    membershipOperationsController = MembershipOperationsController.prototypeSeed(
      GeographyRegistry.prototypeSeed(),
    );
    governanceOperationsController = GovernanceOperationsController.prototypeSeed();
    final field = fieldOperationsController = FieldOperationsController.prototypeSeed(
      persistence: offlinePersistenceController,
    );
    final results = resultOperationsController = ResultOperationsController.prototypeSeed(
      persistence: offlinePersistenceController,
    );
    // Staff sessions see the server's incidents, reports and results, and act on them there.
    session.addListener(() {
      if (session.isServerSession && session.isOperator) {
        field.connect(services.field, account: session.accessId);
        results.connect(services.results, account: session.accessId);
      } else {
        field.disconnect();
        results.disconnect();
      }
    });
    communicationsController =
        CommunicationsController.prototypeSeed(governanceOperationsController);
    bulkCommunicationsController =
        BulkCommunicationsController.productionFoundation(
      membership: membershipOperationsController,
      governance: governanceOperationsController,
      persistence: offlinePersistenceController,
    );
    reportOperationsController =
        ReportOperationsController.prototypeSeed(governanceOperationsController);
    emergencyResponseController =
        EmergencyResponseController.prototypeSeed(governanceOperationsController);
  }

  @override
  void dispose() {
    syncController.dispose();
    sessionController.dispose();
    fieldOperationsController.dispose();
    resultOperationsController.dispose();
    membershipOperationsController.dispose();
    communicationsController.dispose();
    bulkCommunicationsController.dispose();
    reportOperationsController.dispose();
    emergencyResponseController.dispose();
    governanceOperationsController.dispose();
    unawaited(offlinePersistenceController.close());
    offlinePersistenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TgcgBackend(
        services: backend,
        child: TgcgSync(controller: syncController, child: _build(context)),
      );

  Widget _build(BuildContext context) => TgcgSession(
        controller: sessionController,
        child: OfflinePersistence(
          controller: offlinePersistenceController,
          child: GovernanceOperations(
            controller: governanceOperationsController,
            child: EmergencyResponse(
              controller: emergencyResponseController,
              child: ReportOperations(
                controller: reportOperationsController,
                child: Communications(
                  controller: communicationsController,
                  child: BulkCommunications(
                    controller: bulkCommunicationsController,
                    child: MembershipOperations(
                      controller: membershipOperationsController,
                      child: FieldOperations(
                        controller: fieldOperationsController,
                        child: ResultOperations(
                          controller: resultOperationsController,
                          child: MaterialApp(
                            navigatorKey: tgcgNavigatorKey,
                            debugShowCheckedModeBanner: false,
                            title: 'TGCG-EMCOP',
                            theme: tgcgTheme(),
                            home: restoringSession
                                ? const _RestoringSession()
                                : const _AuthenticationGate(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _RestoringSession extends StatelessWidget {
  const _RestoringSession();

  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: TgcgColors.primaryDark,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TgcgLogo(size: 88),
              SizedBox(height: 22),
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ],
          ),
        ),
      );
}

class _AuthenticationGate extends StatelessWidget {
  const _AuthenticationGate();

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (!session.isAuthenticated) {
      return const TgcgLoginPage(key: ValueKey('server-login'));
    }
    // Every signed-in phone may receive app notifications.
    if (session.isMember) {
      return const PushRegistration(
        key: ValueKey('member-push'),
        child: MemberShell(key: ValueKey('member-shell')),
      );
    }
    // People with a role see the projects in their areas, and share their
    // location while one they take part in runs.
    if (session.usesFieldApp) {
      return const PushRegistration(
        key: ValueKey('field-agent-push'),
        child: ProjectMode(
          key: ValueKey('field-agent-projects'),
          child: FieldAgentShell(key: ValueKey('field-agent-shell')),
        ),
      );
    }
    return const PushRegistration(
      key: ValueKey('tgcg-push'),
      child: ProjectMode(
        key: ValueKey('tgcg-projects'),
        child: TgcgShell(key: ValueKey('tgcg-shell')),
      ),
    );
  }
}
