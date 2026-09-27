import 'package:flutter/material.dart';

class TgcgApp extends StatelessWidget {
  const TgcgApp({super.key});

  static const Color primary = Color(0xFF123D33);
  static const Color accent = Color(0xFFD7A928);
  static const Color canvas = Color(0xFFF4F6F5);
  static const Color ink = Color(0xFF17211E);
  static const Color muted = Color(0xFF66726E);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TGCG-EMCOP',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: canvas,
        colorScheme: ColorScheme.fromSeed(
          seedColor: primary,
          primary: primary,
          secondary: accent,
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
      ),
      home: const TgcgFoundationPage(),
    );
  }
}

class TgcgFoundationPage extends StatelessWidget {
  const TgcgFoundationPage({super.key});

  static const modules = <({String title, String description, IconData icon})>[
    (
      title: 'Accreditation',
      description: 'Members, agents, roles and polling-unit assignments.',
      icon: Icons.badge_outlined,
    ),
    (
      title: 'Field Monitoring',
      description: 'Incidents, reports, evidence and escalation workflows.',
      icon: Icons.radar_rounded,
    ),
    (
      title: 'Result Capture',
      description: 'Manual, image, SMS and USSD result submissions.',
      icon: Icons.ballot_outlined,
    ),
    (
      title: 'Collation',
      description: 'Verified roll-up from polling unit to national level.',
      icon: Icons.account_tree_outlined,
    ),
    (
      title: 'GIS Operations',
      description: 'Polling-unit maps, geotagging and operational coverage.',
      icon: Icons.map_outlined,
    ),
    (
      title: 'Situation Room',
      description: 'Live operational command, verification and audit oversight.',
      icon: Icons.dashboard_customize_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TGCG-EMCOP',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: TgcgApp.ink,
              ),
            ),
            Text(
              'Election Monitoring & Collation Programme',
              style: TextStyle(
                fontSize: 11,
                color: TgcgApp.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth >= 760 ? 32.0 : 18.0;
          final cardWidth = constraints.maxWidth >= 1120
              ? (constraints.maxWidth - horizontal * 2 - 32) / 3
              : constraints.maxWidth >= 700
                  ? (constraints.maxWidth - horizontal * 2 - 16) / 2
                  : constraints.maxWidth - horizontal * 2;

          return ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 28, horizontal, 40),
            children: [
              const Text(
                'National Operations Foundation',
                style: TextStyle(
                  fontSize: 28,
                  height: 1.15,
                  fontWeight: FontWeight.w900,
                  color: TgcgApp.ink,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'The Benue prototype is being generalized into a national, offline-first monitoring and collation platform. This screen is the temporary foundation shell while reusable modules are migrated.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.55,
                  color: TgcgApp.muted,
                ),
              ),
              const SizedBox(height: 26),
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: modules
                    .map(
                      (module) => SizedBox(
                        width: cardWidth,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: TgcgApp.primary.withValues(alpha: .08),
                                    borderRadius: BorderRadius.circular(13),
                                  ),
                                  child: Icon(
                                    module.icon,
                                    color: TgcgApp.primary,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  module.title,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w900,
                                    color: TgcgApp.ink,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  module.description,
                                  style: const TextStyle(
                                    height: 1.45,
                                    color: TgcgApp.muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          );
        },
      ),
    );
  }
}
