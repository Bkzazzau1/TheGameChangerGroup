import 'package:flutter/material.dart';

class TgcgColors {
  const TgcgColors._();

  static const primary = Color(0xFF123D33);
  static const primaryDark = Color(0xFF0B2520);
  static const primarySoft = Color(0xFFE8F1EE);
  static const primaryMid = Color(0xFF17614F);
  static const accent = Color(0xFFD7A928);
  static const accentSoft = Color(0xFFFFF7DB);
  static const canvas = Color(0xFFF4F7F6);
  static const surface = Colors.white;
  static const surfaceSoft = Color(0xFFF8FAF9);
  static const ink = Color(0xFF17211E);
  static const muted = Color(0xFF66726E);
  static const border = Color(0xFFE1E8E5);
  static const success = Color(0xFF087A55);
  static const info = Color(0xFF2563EB);
  static const warning = Color(0xFFB7791F);
  static const danger = Color(0xFFB42318);
  static const ai = Color(0xFF6550B5);
}

class TgcgSpacing {
  const TgcgSpacing._();

  static const double xs = 6;
  static const double sm = 10;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
}

enum TgcgMetricTone { neutral, success, info, warning, danger, ai }

Color tgcgToneColor(TgcgMetricTone tone) => switch (tone) {
      TgcgMetricTone.neutral => TgcgColors.primary,
      TgcgMetricTone.success => TgcgColors.success,
      TgcgMetricTone.info => TgcgColors.info,
      TgcgMetricTone.warning => TgcgColors.warning,
      TgcgMetricTone.danger => TgcgColors.danger,
      TgcgMetricTone.ai => TgcgColors.ai,
    };

class TgcgPageHeader extends StatelessWidget {
  const TgcgPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final String? eyebrow;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (eyebrow != null) ...[
                  Text(
                    eyebrow!.toUpperCase(),
                    style: const TextStyle(
                      color: TgcgColors.primaryMid,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.15,
                    ),
                  ),
                  const SizedBox(height: 7),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 30,
                    height: 1.05,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.7,
                    color: TgcgColors.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    height: 1.45,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            trailing!,
          ],
        ],
      );
}

class TgcgSectionCard extends StatelessWidget {
  const TgcgSectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
    this.backgroundColor = TgcgColors.surface,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: TgcgColors.border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x08000000),
              blurRadius: 18,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null || trailing != null) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title!,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                                color: TgcgColors.ink,
                              ),
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: TgcgColors.muted,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    if (trailing != null) trailing!,
                  ],
                ),
                const SizedBox(height: 16),
              ],
              child,
            ],
          ),
        ),
      );
}

class TgcgMetricCard extends StatelessWidget {
  const TgcgMetricCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.detail,
    this.tone = TgcgMetricTone.neutral,
    this.width,
    this.onTap,
  });

  final String label;
  final String value;
  final String? detail;
  final IconData icon;
  final TgcgMetricTone tone;
  final double? width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = tgcgToneColor(tone);
    final body = Container(
      width: width,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: TgcgColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              if (onTap != null)
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 17,
                  color: TgcgColors.muted,
                ),
            ],
          ),
          const SizedBox(height: 17),
          Text(
            value,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w900,
              fontSize: 27,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 5),
            Text(
              detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: TgcgColors.muted,
                fontSize: 10.5,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: body,
    );
  }
}

class TgcgStatusPill extends StatelessWidget {
  const TgcgStatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.compact = false,
  });

  final String label;
  final Color color;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 5 : 7,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .17)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: compact ? 13 : 15),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: compact ? 9.5 : 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: .25,
              ),
            ),
          ],
        ),
      );
}

class TgcgEmptyState extends StatelessWidget {
  const TgcgEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: TgcgColors.primarySoft,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(icon, color: TgcgColors.primary),
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: TgcgColors.ink,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: TgcgColors.muted,
                    fontSize: 11,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
