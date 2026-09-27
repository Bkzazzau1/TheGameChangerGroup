import 'dart:async';

import 'package:flutter/material.dart';

import 'communications/communications_store.dart';
import 'field/field_agent_shell.dart';
import 'field/field_operations_store.dart';
import 'geography/geography_registry.dart';
import 'governance/governance_store.dart';
import 'membership/membership_store.dart';
import 'media/device_media.dart';
import 'offline/offline_persistence.dart';
import 'presentation_access_login.dart';
import 'reports/report_store.dart';
import 'results/result_operations_store.dart';
import 'session.dart';
import 'shell.dart';
import 'ui/tgcg_design.dart';

class TgcgApp extends StatefulWidget {
  const TgcgApp({super.key});

  static const Color primary = TgcgColors.primary;
  static const Color accent = TgcgColors.accent;
  static const Color canvas = TgcgColors.canvas;
  static const Color ink = TgcgColors.ink;
  static const Color muted = TgcgColors.muted;

  @override
  State<TgcgApp> createState() => _TgcgAppState();
}

class _TgcgAppState extends State<TgcgApp> {
  final sessionController = TgcgSessionController();
  final offlinePersistenceController = OfflinePersistenceController();
  final membershipOperationsController = MembershipOperationsController.prototypeSeed(
    GeographyRegistry.prototypeSeed(),
  );
  final governanceOperationsController = GovernanceOperationsController.prototypeSeed();

  late final FieldOperationsController fieldOperationsController =
      FieldOperationsController.prototypeSeed(
        persistence: offlinePersistenceController,
      );
  late final ResultOperationsController resultOperationsController =
      ResultOperationsController.prototypeSeed(
        persistence: offlinePersistenceController,
      );
  late final CommunicationsController communicationsController =
      CommunicationsController.prototypeSeed(governanceOperationsController);
  late final ReportOperationsController reportOperationsController =
      ReportOperationsController.prototypeSeed(governanceOperationsController);

  @override
  void initState() {
    super.initState();
    unawaited(offlinePersistenceController.initialize());
  }

  @override
  void dispose() {
    sessionController.dispose();
    fieldOperationsController.dispose();
    resultOperationsController.dispose();
    membershipOperationsController.dispose();
    communicationsController.dispose();
    reportOperationsController.dispose();
    governanceOperationsController.dispose();
    unawaited(offlinePersistenceController.close());
    offlinePersistenceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TgcgSession(
        controller: sessionController,
        child: OfflinePersistence(
          controller: offlinePersistenceController,
          child: GovernanceOperations(
            controller: governanceOperationsController,
            child: ReportOperations(
              controller: reportOperationsController,
              child: Communications(
                controller: communicationsController,
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
                        home: const _AuthenticationGate(),
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
      secondary: TgcgColors.accent,
      surface: TgcgColors.surface,
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
        hintStyle: const TextStyle(color: Color(0xFF98A39F), fontSize: 12),
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
      ),
    );
  }
}

class _AuthenticationGate extends StatelessWidget {
  const _AuthenticationGate();

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    if (!session.isAuthenticated) {
      return const PresentationAccessLogin(
        key: ValueKey('presentation-access-login'),
      );
    }
    if (session.role == TgcgRole.pollingUnitAgent) {
      return const FieldAgentShell(key: ValueKey('field-agent-shell'));
    }
    return const TgcgShell(key: ValueKey('tgcg-shell'));
  }
}
