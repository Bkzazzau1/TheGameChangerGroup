import 'package:flutter/material.dart';

import 'communications/communications_store.dart';
import 'field/field_operations_store.dart';
import 'geography/geography_registry.dart';
import 'governance/governance_store.dart';
import 'login_page.dart';
import 'membership/membership_store.dart';
import 'results/result_operations_store.dart';
import 'session.dart';
import 'shell.dart';

class TgcgApp extends StatefulWidget {
  const TgcgApp({super.key});

  static const Color primary = Color(0xFF123D33);
  static const Color accent = Color(0xFFD7A928);
  static const Color canvas = Color(0xFFF4F6F5);
  static const Color ink = Color(0xFF17211E);
  static const Color muted = Color(0xFF66726E);

  @override
  State<TgcgApp> createState() => _TgcgAppState();
}

class _TgcgAppState extends State<TgcgApp> {
  final sessionController = TgcgSessionController();
  final fieldOperationsController = FieldOperationsController.prototypeSeed();
  final resultOperationsController = ResultOperationsController.prototypeSeed();
  final membershipOperationsController = MembershipOperationsController.prototypeSeed(
    GeographyRegistry.prototypeSeed(),
  );
  final governanceOperationsController = GovernanceOperationsController.prototypeSeed();

  late final CommunicationsController communicationsController =
      CommunicationsController.prototypeSeed(governanceOperationsController);

  @override
  void dispose() {
    sessionController.dispose();
    fieldOperationsController.dispose();
    resultOperationsController.dispose();
    membershipOperationsController.dispose();
    communicationsController.dispose();
    governanceOperationsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TgcgSession(
        controller: sessionController,
        child: GovernanceOperations(
          controller: governanceOperationsController,
          child: Communications(
            controller: communicationsController,
            child: MembershipOperations(
              controller: membershipOperationsController,
              child: FieldOperations(
                controller: fieldOperationsController,
                child: ResultOperations(
                  controller: resultOperationsController,
                  child: MaterialApp(
                    debugShowCheckedModeBanner: false,
                    title: 'TGCG-EMCOP',
                    theme: ThemeData(
                      useMaterial3: true,
                      scaffoldBackgroundColor: TgcgApp.canvas,
                      colorScheme: ColorScheme.fromSeed(
                        seedColor: TgcgApp.primary,
                        primary: TgcgApp.primary,
                        secondary: TgcgApp.accent,
                        surface: Colors.white,
                      ),
                      cardTheme: CardThemeData(
                        elevation: 0,
                        color: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                          side: const BorderSide(color: Color(0xFFE3E8E6)),
                        ),
                      ),
                      inputDecorationTheme: InputDecorationTheme(
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFDDE5E2)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFDDE5E2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: TgcgApp.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    home: const _AuthenticationGate(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _AuthenticationGate extends StatelessWidget {
  const _AuthenticationGate();

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      child: session.isAuthenticated
          ? const TgcgShell(key: ValueKey('tgcg-shell'))
          : const TgcgLoginPage(key: ValueKey('tgcg-login')),
    );
  }
}
