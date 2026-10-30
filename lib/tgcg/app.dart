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
                            theme: _theme(),
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

  ThemeData _theme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: TgcgColors.primary,
      brightness: Brightness.light,
      primary: TgcgColors.primary,
      onPrimary: Colors.white,
      primaryContainer: TgcgColors.primarySoft,
      onPrimaryContainer: TgcgColors.primary,
      secondary: TgcgColors.accent,
      onSecondary: TgcgColors.primaryDark,
      secondaryContainer: TgcgColors.accentSoft,
      onSecondaryContainer: TgcgColors.accentDeep,
      tertiary: TgcgColors.accentDeep,
      surface: TgcgColors.surface,
      onSurface: TgcgColors.ink,
      outline: TgcgColors.border,
      error: TgcgColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: TgcgColors.canvas,
      colorScheme: scheme,
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: -.6,
        ),
        headlineMedium: TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: -.4,
        ),
        titleLarge: TextStyle(
          color: TgcgColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: TextStyle(
          color: TgcgColors.ink,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: TextStyle(color: TgcgColors.ink, fontSize: 15, height: 1.45),
        bodyMedium: TextStyle(color: TgcgColors.ink, fontSize: 14, height: 1.45),
        bodySmall: TextStyle(color: TgcgColors.muted, fontSize: 12.5, height: 1.4),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.lg),
          side: const BorderSide(color: TgcgColors.border),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: TgcgColors.border,
        thickness: 1,
        space: 24,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: TgcgColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
        labelStyle: const TextStyle(color: TgcgColors.muted, fontSize: 14),
        hintStyle: const TextStyle(color: Color(0xFF7D8499), fontSize: 13.5),
        helperStyle: const TextStyle(color: TgcgColors.muted, fontSize: 12.5),
        errorStyle: const TextStyle(color: TgcgColors.danger, fontSize: 12.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          borderSide: const BorderSide(color: TgcgColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          borderSide: const BorderSide(color: TgcgColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          borderSide: const BorderSide(color: TgcgColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          borderSide: const BorderSide(color: TgcgColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TgcgColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.md)),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TgcgColors.primary,
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: const BorderSide(color: Color(0xFFC6CEE0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.md)),
          textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TgcgColors.primary,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: TgcgColors.primaryDark,
        contentTextStyle: TextStyle(color: Colors.white),
        actionTextColor: TgcgColors.accentBright,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: TgcgColors.primaryDark,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: TgcgColors.accentSoft,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected) ? TgcgColors.primary : TgcgColors.muted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            color: states.contains(WidgetState.selected) ? TgcgColors.primary : TgcgColors.muted,
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: TgcgColors.primary,
        titleTextStyle: TextStyle(color: TgcgColors.ink, fontSize: 14.5, fontWeight: FontWeight.w600),
        subtitleTextStyle: TextStyle(color: TgcgColors.muted, fontSize: 12.5, height: 1.35),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.md)),
        labelTextStyle: const WidgetStatePropertyAll(
          TextStyle(color: TgcgColors.ink, fontSize: 14.5, fontWeight: FontWeight.w600),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(TgcgRadius.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(TgcgRadius.lg)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: TgcgColors.primaryDark.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12.5),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: TgcgColors.accent,
        linearTrackColor: TgcgColors.primarySoft,
        circularTrackColor: TgcgColors.primarySoft,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? TgcgColors.primary
                : TgcgColors.surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? TgcgColors.accentBright
                : TgcgColors.primary,
          ),
          side: const WidgetStatePropertyAll(
            BorderSide(color: TgcgColors.border),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: TgcgColors.surface,
        selectedColor: TgcgColors.primary,
        secondarySelectedColor: TgcgColors.primary,
        checkmarkColor: TgcgColors.accentBright,
        side: const BorderSide(color: TgcgColors.border),
        labelStyle: const TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: TgcgColors.primary,
        unselectedLabelColor: TgcgColors.muted,
        indicatorColor: TgcgColors.accent,
        dividerColor: TgcgColors.border,
        labelStyle: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? TgcgColors.accentBright
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? TgcgColors.primary
              : null,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? TgcgColors.primary
              : null,
        ),
        checkColor: const WidgetStatePropertyAll(TgcgColors.accentBright),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: TgcgColors.accent,
        foregroundColor: TgcgColors.primaryDark,
      ),
    );
  }
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
