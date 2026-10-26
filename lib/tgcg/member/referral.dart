import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../api/backend.dart';
import '../api/member_repository.dart';
import '../ui/tgcg_design.dart';

/// The referral code in the link the web app was opened with
/// (app.tgcg.online/?ref=1234567), or null.
String? referralFromLink([Uri? link]) {
  final code = ((link ?? Uri.base).queryParameters['ref'] ?? '').replaceAll(RegExp(r'\D'), '');
  return code.length == 7 ? code : null;
}

/// Shares text (replaced in tests).
typedef ShareText = Future<void> Function(String text);

Future<void> shareTextWithDevice(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}

/// The member's referral code and link: everyone who joins with it earns the
/// member registration credits.
class ReferralCard extends StatefulWidget {
  const ReferralCard({super.key, this.share = shareTextWithDevice});

  final ShareText share;

  @override
  State<ReferralCard> createState() => _ReferralCardState();
}

class _ReferralCardState extends State<ReferralCard> {
  Future<MyReferral>? _referral;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _referral ??= TgcgBackend.of(context)?.member.referral();
  }

  String _message(MyReferral referral) =>
      'Join The Game Changer Group (TGCG) with my referral code ${referral.code}: ${referral.link}';

  Future<void> _copy(MyReferral referral) async {
    await Clipboard.setData(ClipboardData(text: referral.link));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied.')));
    }
  }

  Future<void> _share(MyReferral referral) async {
    try {
      await widget.share(_message(referral));
    } catch (_) {
      // No share sheet here (some browsers): copy instead.
      await _copy(referral);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<MyReferral>(
    future: _referral,
    builder: (context, snapshot) {
      final referral = snapshot.data;
      if (referral == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TgcgSectionCard(
          title: 'Invite with your code',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                referral.code,
                style: const TextStyle(
                  color: TgcgColors.ink,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 4),
              SelectableText(referral.link, style: const TextStyle(color: TgcgColors.muted)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _share(referral),
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Share'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _copy(referral),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copy link'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${referral.joined} joined with your code · ${referral.credited} rewarded',
                style: const TextStyle(color: TgcgColors.muted),
              ),
            ],
          ),
        ),
      );
    },
  );
}
