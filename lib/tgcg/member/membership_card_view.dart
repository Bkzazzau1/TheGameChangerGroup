import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api/member_repository.dart';
import '../ui/tgcg_design.dart';

/// The member's card: navy and gold, with a QR code that TGCG staff scan to
/// check that the membership is real.
class MembershipCardView extends StatelessWidget {
  const MembershipCardView({super.key, required this.card, this.photo});

  final MemberCard card;
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) {
    final unit = card.pollingUnit;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [TgcgColors.primaryDark, TgcgColors.primary, TgcgColors.primaryMid],
          ),
          border: Border.all(color: TgcgColors.accent.withValues(alpha: .7), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: TgcgColors.primaryDark.withValues(alpha: .25),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                TgcgLogo(size: 34),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'THE GAME CHANGER GROUP',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          letterSpacing: .8,
                        ),
                      ),
                      Text(
                        'MEMBERSHIP CARD',
                        style: TextStyle(
                          color: TgcgColors.accentBright,
                          fontWeight: FontWeight.w800,
                          fontSize: 10.5,
                          letterSpacing: 1.6,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Photo(photo: photo),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        card.membershipNumber,
                        style: const TextStyle(
                          color: TgcgColors.accentBright,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (unit != null)
                        Text(
                          '${unit.name}\n${unit.ward}, ${unit.lga}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFFC9D3EC), fontSize: 11.5),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(height: 1, color: TgcgColors.accent.withValues(alpha: .5)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Member since ${card.memberSince.year}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        card.hasPvc ? 'PVC on record' : 'No PVC on record',
                        style: const TextStyle(color: Color(0xFFC9D3EC), fontSize: 11.5),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'TGCG staff scan the code to check this card.',
                        style: TextStyle(color: Color(0xFF9FB0D6), fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: QrImageView(
                    key: const ValueKey('membership-qr'),
                    data: card.qrToken,
                    size: 96,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: TgcgColors.primaryDark,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: TgcgColors.primaryDark,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({this.photo});
  final Uint8List? photo;

  @override
  Widget build(BuildContext context) => Container(
        width: 76,
        height: 92,
        decoration: BoxDecoration(
          color: TgcgColors.primaryMid,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: TgcgColors.accentBright, width: 1.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: photo == null
            ? const Icon(Icons.person_rounded, color: Colors.white70, size: 44)
            : Image.memory(photo!, fit: BoxFit.cover, gaplessPlayback: true),
      );
}
