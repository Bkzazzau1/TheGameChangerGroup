import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../membership/membership_store.dart';
import '../session.dart';
import '../ui/tgcg_design.dart';

class DigitalAgentIdPage extends StatelessWidget {
  const DigitalAgentIdPage({super.key});

  @override
  Widget build(BuildContext context) {
    final session = TgcgSession.of(context);
    final membership = MembershipOperations.of(context);
    final normalized = session.accessId.trim().toLowerCase();
    AccreditedAgent? agent;
    for (final item in membership.agents) {
      if (item.role != TgcgRole.pollingUnitAgent) continue;
      final byId = item.agentId.toLowerCase() == normalized;
      final byPhone = (item.registeredPhoneNumber ?? '').trim().toLowerCase() == normalized;
      if (byId || byPhone) {
        agent = item;
        break;
      }
    }

    if (agent == null) {
      return const Scaffold(
        body: Center(child: Text('Agent assignment not available.')),
      );
    }

    final member = membership.memberById(agent.memberId);
    final name = member?.fullName ?? session.operatorName;
    final ready = agent.status == AccreditationStatus.approved &&
        agent.trainingCompleted &&
        agent.biometricEnrolled &&
        (agent.deviceId ?? '').trim().isNotEmpty;

    return Scaffold(
      backgroundColor: TgcgColors.canvas,
      appBar: AppBar(
        backgroundColor: TgcgColors.surface,
        surfaceTintColor: Colors.transparent,
        title: const Text('Digital Agent ID'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: TgcgColors.primary.withValues(alpha: .16),
                        blurRadius: 28,
                        offset: const Offset(0, 14),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.fromLTRB(22, 22, 22, 20),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [TgcgColors.primaryDark, TgcgColors.primary],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Column(
                            children: [
                              const Row(
                                children: [
                                  TgcgLogo(size: 48),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'TGCG-EMCOP',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 16,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: .8,
                                          ),
                                        ),
                                        SizedBox(height: 2),
                                        Text(
                                          'POLLING UNIT AGENT',
                                          style: TextStyle(
                                            color: Color(0xFFBDC3D0),
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 22),
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 94,
                                    height: 108,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF162B5D),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: Colors.white.withValues(alpha: .18)),
                                    ),
                                    child: Center(
                                      child: Text(
                                        _initials(name),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 30,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          name,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 21,
                                            height: 1.1,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                        const SizedBox(height: 7),
                                        Text(
                                          agent.agentId,
                                          style: const TextStyle(
                                            color: TgcgColors.accent,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 13,
                                            letterSpacing: .5,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        TgcgStatusPill(
                                          label: ready ? 'ACTIVE & VERIFIED' : 'ACCREDITED',
                                          color: ready ? TgcgColors.success : TgcgColors.accent,
                                          icon: Icons.verified_rounded,
                                          compact: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          color: Colors.white,
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      children: [
                                        _Detail('Polling Unit', agent.scope.pollingUnitName ?? '—'),
                                        _Detail('Ward', agent.scope.wardName ?? '—'),
                                        _Detail('LGA', agent.scope.lgaName ?? '—'),
                                        _Detail('State', agent.scope.stateName ?? '—'),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Container(
                                    width: 116,
                                    height: 116,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: TgcgColors.border),
                                    ),
                                    child: CustomPaint(
                                      painter: _IdCodePainter(seed: agent.agentId),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 18),
                              const Divider(),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _StatusChip('Identity', agent.biometricEnrolled),
                                  _StatusChip('Training', agent.trainingCompleted),
                                  _StatusChip('Device', (agent.deviceId ?? '').isNotEmpty),
                                  _StatusChip('SIM', (agent.simFingerprint ?? '').isNotEmpty),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: TgcgColors.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: TgcgColors.border),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: TgcgColors.primary),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This digital credential is tied to the assigned field account and polling-unit duty profile.',
                          style: TextStyle(color: TgcgColors.ink, fontSize: 10.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'AG';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 13),
        child: Row(
          children: [
            SizedBox(
              width: 86,
              child: Text(label, style: const TextStyle(color: TgcgColors.muted, fontSize: 9.5)),
            ),
            Expanded(
              child: Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: TgcgColors.ink, fontSize: 11.5, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.label, this.ready);
  final String label;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final color = ready ? TgcgColors.success : TgcgColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ready ? Icons.check_circle_rounded : Icons.schedule_rounded, color: color, size: 14),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 9.5)),
        ],
      ),
    );
  }
}

class _IdCodePainter extends CustomPainter {
  const _IdCodePainter({required this.seed});
  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    final n = 17;
    final cell = math.min(size.width, size.height) / n;
    final paint = Paint()..color = TgcgColors.primaryDark;
    final hash = seed.codeUnits.fold<int>(19, (a, b) => (a * 31 + b) & 0x7fffffff);
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final finder = (x < 5 && y < 5) || (x > n - 6 && y < 5) || (x < 5 && y > n - 6);
        final value = ((x * 17 + y * 29 + hash) % 7) < 3;
        if (finder || value) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell * .86, cell * .86), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _IdCodePainter oldDelegate) => oldDelegate.seed != seed;
}
