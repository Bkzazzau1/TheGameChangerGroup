import 'dart:async';

import 'package:flutter/material.dart';

import 'api/api_client.dart';
import 'api/backend.dart';
import 'communications/bulk_communications_store.dart';
import 'communications/communications_store.dart';
import 'field/field_agent_shell.dart';
import 'field/field_operations_store.dart';
import 'geography/geography_registry.dart';
import 'governance/governance_store.dart';
import 'login_page.dart';
import 'membership/membership_store.dart';
import 'media/device_media.dart';
import 'offline/offline_persistence.dart';
import 'presentation_access_login.dart';
import 'reports/report_store.dart';
import 'results/result_operations_store.dart';
import 'security/emergency_response_store.dart';
import 'session.dart';
import 'shell.dart';
import 'ui/tgcg_design.dart';

class TgcgApp extends StatefulWidget {
  const TgcgApp({super.key, this.backend});

  /// Server connection; defaults to TGCG_API_URL when configured.
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
  late final BackendServices? backend = widget.backend ??
      (tgcgApiConfigured ? BackendServices.connect(tgcgApiUrl) : null);

  /// True while a saved server session is being restored at startup.
  late bool restoringSession = backend != null;
  late TgcgSessionController sessionController;
  late OfflinePersistenceController offlinePersistenceController;
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
    final services = backend;
    if (services != null) {
      services.client.onSessionExpired = () {
        if (sessionController.isServerSession) sessionController.signOut();
      };
      unawaited(_restoreSession(services));
    }
  }

  Future<void> _restoreSession(BackendServices services) async {
    try {
      final user = await services.auth.restore();
      final role = user?.role;
      if (user != null && role != null && mounted) {
        sessionController.signInFromServer(
          role: role,
          fullName: user.fullName,
          accessId: user.accessId,
          scope: user.scope,
          capabilities: user.capabilities,
        );
      }
    } on ApiException {
      // Offline at startup: the user signs in again once connected.
    } finally {
      if (mounted) setState(() => restoringSession = false);
    }
  }

  void _createControllers() {
    sessionController = TgcgSessionController(onSignOut: backend?.auth.logout);
    offlinePersistenceController = OfflinePersistenceController();
    membershipOperationsController = MembershipOperationsController.prototypeSeed(
      GeographyRegistry.prototypeSeed(),
    );
    governanceOperationsController = GovernanceOperationsController.prototypeSeed();
    fieldOperationsController = FieldOperationsController.prototypeSeed(
      persistence: offlinePersistenceController,
    );
    resultOperationsController = ResultOperationsController.prototypeSeed(
      persistence: offlinePersistenceController,
    );
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

  Future<void> _resetPresentation() async {
    final oldSession = sessionController;
    final oldOffline = offlinePersistenceController;
    final oldMembership = membershipOperationsController;
    final oldGovernance = governanceOperationsController;
    final oldField = fieldOperationsController;
    final oldResults = resultOperationsController;
    final oldCommunications = communicationsController;
    final oldBulkCommunications = bulkCommunicationsController;
    final oldReports = reportOperationsController;
    final oldEmergency = emergencyResponseController;

    try {
      await oldOffline.clearPresentationData();
    } catch (_) {
      // Recreating all in-memory controllers still restores the presentation
      // even if local persistence is unavailable on this platform.
    }
    await oldOffline.close();
    if (!mounted) return;

    setState(_createControllers);
    unawaited(offlinePersistenceController.initialize());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldSession.dispose();
      oldField.dispose();
      oldResults.dispose();
      oldMembership.dispose();
      oldCommunications.dispose();
      oldBulkCommunications.dispose();
      oldReports.dispose();
      oldEmergency.dispose();
      oldGovernance.dispose();
      oldOffline.dispose();
    });
  }

  @override
  void dispose() {
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
        child: _build(context),
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
                                : _AuthenticationGate(
                                    onResetPresentation: _resetPresentation,
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
          fontWeight: FontWeight.w900,
          letterSpacing: -.7,
        ),
        headlineMedium: TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w900,
          letterSpacing: -.4,
        ),
        titleLarge: TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w900,
        ),
        titleMedium: TextStyle(
          color: TgcgColors.ink,
          fontWeight: FontWeight.w800,
        ),
        bodyLarge: TextStyle(color: TgcgColors.ink),
        bodyMedium: TextStyle(color: TgcgColors.ink),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        labelStyle: const TextStyle(color: TgcgColors.muted, fontSize: 12),
        hintStyle: const TextStyle(color: Color(0xFF979BA4), fontSize: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: TgcgColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: TgcgColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: TgcgColors.primary, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: TgcgColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: TgcgColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          side: const BorderSide(color: TgcgColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: TgcgColors.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
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
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: TgcgColors.primaryDark.withValues(alpha: .94),
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 11.5),
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
        labelStyle: TextStyle(fontWeight: FontWeight.w800),
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
  const _AuthenticationGate({required this.onResetPresentation});

  final Future<void> Function() onResetPresentation;

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (!session.isAuthenticated && TgcgBackend.of(context) != null) {
      // Connected to a server: real sign-in, no presentation controls.
      return const TgcgLoginPage(key: ValueKey('server-login'));
    }
    if (!session.isAuthenticated) {
      return PresentationAccessLogin(
        key: const ValueKey('presentation-access-login'),
        onResetPresentation: onResetPresentation,
      );
    }
    if (session.role == TgcgRole.pollingUnitAgent) {
      return const FieldAgentShell(key: ValueKey('field-agent-shell'));
    }
    return const TgcgShell(key: ValueKey('tgcg-shell'));
  }
}
