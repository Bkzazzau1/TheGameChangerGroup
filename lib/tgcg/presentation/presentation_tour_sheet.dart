import 'package:flutter/material.dart';

import '../session.dart';
import '../ui/tgcg_design.dart';

class PresentationTourStep {
  const PresentationTourStep({
    required this.number,
    required this.title,
    required this.subtitle,
    required this.module,
    required this.icon,
  });

  final int number;
  final String title;
  final String subtitle;
  final TgcgModule module;
  final IconData icon;
}

Future<void> showPresentationTour(
  BuildContext context, {
  required Set<TgcgModule> allowedModules,
  required ValueChanged<TgcgModule> onOpenModule,
}) async {
  const steps = <PresentationTourStep>[
    PresentationTourStep(
      number: 1,
      title: 'National Command',
      subtitle: 'Start with the nationwide operational picture.',
      module: TgcgModule.overview,
      icon: Icons.space_dashboard_outlined,
    ),
    PresentationTourStep(
      number: 2,
      title: 'Registered Members',
      subtitle: 'Show membership and agent coverage by zone and state.',
      module: TgcgModule.membershipNetwork,
      icon: Icons.groups_2_outlined,
    ),
    PresentationTourStep(
      number: 3,
      title: 'PVC Member Enrolment',
      subtitle: 'Scan PVC, extract identity and confirm enrolment.',
      module: TgcgModule.accreditation,
      icon: Icons.how_to_reg_outlined,
    ),
    PresentationTourStep(
      number: 4,
      title: 'AI Verification',
      subtitle: 'Demonstrate PVC OCR, result OCR and identity verification.',
      module: TgcgModule.aiVerification,
      icon: Icons.auto_awesome_rounded,
    ),
    PresentationTourStep(
      number: 5,
      title: 'Live Operations',
      subtitle: 'Show state activity, incidents, agents and reporting progress.',
      module: TgcgModule.liveOperations,
      icon: Icons.travel_explore_rounded,
    ),
    PresentationTourStep(
      number: 6,
      title: 'AI Data Analytics',
      subtitle: 'Show operational patterns, review workload, data quality and geographic activity.',
      module: TgcgModule.aiAnalytics,
      icon: Icons.query_stats_rounded,
    ),
    PresentationTourStep(
      number: 7,
      title: 'Situation Room',
      subtitle: 'Open active incidents, evidence and response coordination.',
      module: TgcgModule.situationRoom,
      icon: Icons.radar_rounded,
    ),
    PresentationTourStep(
      number: 8,
      title: 'Result Capture',
      subtitle: 'Show polling-unit result submission and review.',
      module: TgcgModule.resultCapture,
      icon: Icons.ballot_outlined,
    ),
    PresentationTourStep(
      number: 9,
      title: 'Collation',
      subtitle: 'Show hierarchical verified-result aggregation.',
      module: TgcgModule.collation,
      icon: Icons.account_tree_outlined,
    ),
    PresentationTourStep(
      number: 10,
      title: 'Alert Centre',
      subtitle: 'Show operational alerts, review items and acknowledgements.',
      module: TgcgModule.alertCenter,
      icon: Icons.notifications_active_outlined,
    ),
    PresentationTourStep(
      number: 11,
      title: 'System Monitoring',
      subtitle: 'Finish with platform health, sync and operational monitoring.',
      module: TgcgModule.systemMonitoring,
      icon: Icons.monitor_heart_outlined,
    ),
  ];

  final visible = steps
      .where((step) => allowedModules.contains(step.module))
      .toList(growable: false);

  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: .92,
      child: Container(
        decoration: const BoxDecoration(
          color: TgcgColors.canvas,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
              decoration: const BoxDecoration(
                color: TgcgColors.primaryDark,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  const TgcgLogo(size: 44),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Presentation Tour',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Recommended flow for the TGCG-EMCOP demonstration',
                          style: TextStyle(
                            color: Color(0xFFB8BECB),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: TgcgColors.accentSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: TgcgColors.accent.withValues(alpha: .25),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lightbulb_outline_rounded,
                            color: TgcgColors.warning),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'For the Polling Agent segment: sign out, use Quick Field Access, open Digital ID, check in, send a local message, open Meeting Room, capture evidence and submit a result.',
                            style: TextStyle(
                              color: TgcgColors.ink,
                              fontSize: 11,
                              height: 1.4,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  ...visible.map(
                    (step) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          onOpenModule(step.module);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: TgcgColors.surface,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: TgcgColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 42,
                                height: 42,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: TgcgColors.primarySoft,
                                  borderRadius: BorderRadius.circular(13),
                                ),
                                child: Text(
                                  '${step.number}',
                                  style: const TextStyle(
                                    color: TgcgColors.primary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: TgcgColors.surfaceSoft,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(step.icon,
                                    size: 18, color: TgcgColors.primary),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      step.title,
                                      style: const TextStyle(
                                        color: TgcgColors.ink,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      step.subtitle,
                                      style: const TextStyle(
                                        color: TgcgColors.muted,
                                        fontSize: 10.5,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.arrow_forward_rounded,
                                  color: TgcgColors.primary),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
