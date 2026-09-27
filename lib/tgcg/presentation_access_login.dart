import 'package:flutter/material.dart';

import 'login_page.dart';
import 'membership/membership_store.dart';
import 'session.dart';
import 'ui/tgcg_design.dart';

class PresentationAccessLogin extends StatefulWidget {
  const PresentationAccessLogin({
    super.key,
    required this.onResetPresentation,
  });

  final Future<void> Function() onResetPresentation;

  @override
  State<PresentationAccessLogin> createState() => _PresentationAccessLoginState();
}

class _PresentationAccessLoginState extends State<PresentationAccessLogin> {
  bool resetting = false;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          const Positioned.fill(child: TgcgLoginPage()),
          Positioned(
            right: 18,
            bottom: 18,
            child: SafeArea(
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  Material(
                    elevation: 4,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: OutlinedButton.icon(
                      onPressed: resetting ? null : () => _reset(context),
                      icon: resetting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.restart_alt_rounded),
                      label: Text(
                        resetting ? 'Restoring...' : 'Reset Presentation',
                      ),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: TgcgColors.surface,
                        foregroundColor: TgcgColors.primaryDark,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 15,
                        ),
                        side: const BorderSide(color: TgcgColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                  Material(
                    elevation: 8,
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    child: FilledButton.icon(
                      onPressed: resetting ? null : () => _showFieldAccess(context),
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
                ],
              ),
            ),
          ),
        ],
      );

  Future<void> _reset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reset presentation?'),
        content: const Text(
          'Restore the original presentation data and clear actions made during this run?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            icon: const Icon(Icons.restart_alt_rounded),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => resetting = true);
    try {
      await widget.onResetPresentation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Presentation restored and ready.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to reset presentation data.')),
      );
    } finally {
      if (mounted) setState(() => resetting = false);
    }
  }

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
