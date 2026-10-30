import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tgcg_design.dart';

/// "12,345".
String formatCount(int value) {
  final digits = '${value.abs()}';
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write(',');
    grouped.write(digits[i]);
  }
  return value < 0 ? '-$grouped' : '$grouped';
}

/// Rounded shares, keeping nonzero and incomplete totals visible at the extremes.
String share(int part, int total) {
  if (total == 0) return '0%';
  final percentage = part * 100 / total;
  if (percentage > 0 && percentage < 1) return '<1%';
  if (percentage > 99 && percentage < 100) return '>99%';
  return '${percentage.round()}%';
}

/// A thin bar from 0 to 1 on a pale track. Anything above nothing shows.
class TgcgBar extends StatelessWidget {
  const TgcgBar({
    super.key,
    required this.value,
    this.color = TgcgColors.primaryMid,
    this.track = TgcgColors.primarySoft,
    this.height = 6,
  });

  final double value;
  final Color color;
  final Color track;
  final double height;

  @override
  Widget build(BuildContext context) {
    final fraction = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    final radius = BorderRadius.circular(height / 2);
    return SizedBox(
      width: double.infinity,
      height: height,
      child: LayoutBuilder(
        builder: (context, constraints) => Container(
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(color: track, borderRadius: radius),
          child: fraction == 0
              ? null
              : Container(
                  width: math.max(height, constraints.maxWidth * fraction),
                  decoration: BoxDecoration(color: color, borderRadius: radius),
                ),
        ),
      ),
    );
  }
}

/// One bar: [value] out of [total], in a single hue on a pale track. A bar
/// that opens something carries a chevron.
class ShareBar extends StatelessWidget {
  const ShareBar({
    super.key,
    required this.label,
    required this.value,
    required this.total,
    this.onTap,
  });

  final String label;
  final int value;
  final int total;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(TgcgRadius.sm),
    child: Padding(
      padding: EdgeInsets.symmetric(vertical: onTap == null ? 5 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: TgcgType.label)),
              const SizedBox(width: 8),
              Text('${formatCount(value)} · ${share(value, total)}', style: TgcgType.caption),
              if (onTap != null)
                const Icon(Icons.chevron_right_rounded, size: 18, color: TgcgColors.muted),
            ],
          ),
          const SizedBox(height: 5),
          TgcgBar(value: total == 0 ? 0 : value / total),
        ],
      ),
    ),
  );
}
