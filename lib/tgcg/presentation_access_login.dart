import 'package:flutter/material.dart';

import 'login_page.dart';
import 'membership/membership_store.dart';
import 'session.dart';
import 'ui/tgcg_design.dart';

class PresentationAccessLogin extends StatelessWidget {
  const PresentationAccessLogin({super.key});

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(child: TgcgLoginPage()),
          Positioned(
            right: 18,
            bottom: 18,
            child: Material(
              elevation: 8,
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              child: FilledButton.icon(
                onPressed: () => _showFieldAccess(context),
                icon: const Icon(Icons.how_to_vote_rounded),
                label: const Text('Quick Field Access'),
                style: FilledButton.styleFrom(
                  backgroundColor: TgcgColors.primaryDark,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  void _showFieldAccess(BuildContext context) {
    final membership = MembershipOperations.of(context, listen: false);
    final approvedAgents = membership.agents
        .where(
          (agent) =>
              agent.role == TgcgRole.pollingUnitAgent &&
              agent.status == AccreditationStatus.approved &&
              agent.scope.pollingUnitId != null,
        )
        .toList(growable: false);

    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        constraints: const BoxConstraints(maxWidth: 720),
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: BoxDecoration(
          color: TgcgColors.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: TgcgColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const TgcgLogo(size: 40),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Polling Unit Agent Access',
                        style: TextStyle(
                          color: TgcgColors.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Select a field profile to open its assigned polling unit.',
                        style: TextStyle(
                          color: TgcgColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...approvedAgents.map((agent) {
              final member = membership.memberById(agent.memberId);
              final name = member?.fullName ?? agent.agentId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    TgcgSession.of(context, listen: false).signIn(
                      role: TgcgRole.pollingUnitAgent,
                      operatorName: name,
                      accessId: agent.agentId,
                      scope: agent.scope,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: TgcgColors.surfaceSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: TgcgColors.border),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: TgcgColors.primarySoft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.badge_outlined,
                            color: TgcgColors.primary,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  color: TgcgColors.ink,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${agent.agentId} • ${agent.scope.pollingUnitName ?? agent.scope.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 10.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${agent.scope.lgaName ?? ''}, ${agent.scope.stateName ?? ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TgcgColors.muted,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const TgcgStatusPill(
                          label: 'READY',
                          color: TgcgColors.success,
                          icon: Icons.check_circle_outline_rounded,
                          compact: true,
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: TgcgColors.primary,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
