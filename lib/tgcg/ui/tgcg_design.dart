import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Brand palette taken from the TGCG logo: deep navy ring (#001E5A) and
/// metallic gold lettering (#BE8C00).
class TgcgColors {
  const TgcgColors._();

  // Navy (logo ring)
  static const primary = Color(0xFF0A2463);
  static const primaryDark = Color(0xFF061740);
  static const primaryMid = Color(0xFF1D3F94);
  static const primarySoft = Color(0xFFE9EEF9);

  // Gold (logo lettering)
  static const accent = Color(0xFFC9971A);
  static const accentBright = Color(0xFFE6BE4C);
  static const accentDeep = Color(0xFF9A7008);
  static const accentSoft = Color(0xFFFBF3DC);

  // Neutrals, cool-tinted to sit with navy
  static const canvas = Color(0xFFF3F5FA);
  static const surface = Colors.white;
  static const surfaceSoft = Color(0xFFF7F9FD);
  static const ink = Color(0xFF101A33);
  static const muted = Color(0xFF5D6782);
  static const border = Color(0xFFDFE4EF);

  /// Secondary text on navy.
  static const onNavyMuted = Color(0xFFC9D4F0);

  // Semantic
  static const success = Color(0xFF087A55);
  static const info = Color(0xFF2563EB);
  static const warning = Color(0xFFD0690F); // orange, kept clear of brand gold
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

class TgcgRadius {
  const TgcgRadius._();

  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
}

/// The app's type scale. Nothing a person must read is smaller than
/// [caption].
class TgcgType {
  const TgcgType._();

  static const display = TextStyle(
    color: TgcgColors.ink,
    fontSize: 26,
    height: 1.15,
    fontWeight: FontWeight.w800,
    letterSpacing: -.4,
  );
  static const title = TextStyle(
    color: TgcgColors.ink,
    fontSize: 20,
    height: 1.2,
    fontWeight: FontWeight.w800,
    letterSpacing: -.2,
  );
  static const section = TextStyle(
    color: TgcgColors.ink,
    fontSize: 16,
    height: 1.25,
    fontWeight: FontWeight.w800,
  );
  static const body = TextStyle(color: TgcgColors.ink, fontSize: 14, height: 1.45);
  static const bodyStrong = TextStyle(
    color: TgcgColors.ink,
    fontSize: 14,
    height: 1.35,
    fontWeight: FontWeight.w700,
  );
  static const support = TextStyle(color: TgcgColors.muted, fontSize: 13, height: 1.4);
  static const caption = TextStyle(color: TgcgColors.muted, fontSize: 12, height: 1.35);
  static const eyebrow = TextStyle(
    color: TgcgColors.primaryMid,
    fontSize: 11.5,
    fontWeight: FontWeight.w800,
    letterSpacing: 1,
  );
}

/// A soft, restrained lift for cards that stand on the canvas.
const tgcgCardShadow = [
  BoxShadow(color: Color(0x0A0A2463), blurRadius: 16, offset: Offset(0, 4)),
];

enum TgcgMetricTone { neutral, success, info, warning, danger, ai }

Color tgcgToneColor(TgcgMetricTone tone) => switch (tone) {
      TgcgMetricTone.neutral => TgcgColors.primary,
      TgcgMetricTone.success => TgcgColors.success,
      TgcgMetricTone.info => TgcgColors.info,
      TgcgMetricTone.warning => TgcgColors.warning,
      TgcgMetricTone.danger => TgcgColors.danger,
      TgcgMetricTone.ai => TgcgColors.ai,
    };

class TgcgLogo extends StatelessWidget {
  const TgcgLogo({super.key, this.size = 40});

  static const asset = 'assets/brand/tgcg_logo.png';

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        semanticLabel: 'The Game Changer Group logo',
      );
}

/// The top bar of the member and agent apps: the logo, what this page is,
/// and the page's buttons.
class TgcgBrandBar extends StatelessWidget implements PreferredSizeWidget {
  const TgcgBrandBar({super.key, required this.title, this.subtitle, this.actions = const []});

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) => AppBar(
        toolbarHeight: 64,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: TgcgColors.surface,
        // The theme's white icons are for dark bars: this one is light.
        foregroundColor: TgcgColors.ink,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 10,
        shape: const Border(bottom: BorderSide(color: TgcgColors.border)),
        title: Row(
          children: [
            const TgcgLogo(size: 34),
            const SizedBox(width: 10),
            // Shrinks rather than overflow beside the buttons on a narrow phone.
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      color: TgcgColors.ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        color: TgcgColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [...actions, const SizedBox(width: 4)],
      );
}

/// One button of a top bar that may not have room for all of them.
class TgcgBarAction {
  const TgcgBarAction({required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}

/// A top bar's less frequent buttons: side by side where there is room, and
/// behind a "More" menu on a phone.
class TgcgBarMenu extends StatelessWidget {
  const TgcgBarMenu({super.key, required this.actions, this.color, this.inlineFrom = 600});

  final List<TgcgBarAction> actions;
  final Color? color;

  /// The screen width from which the buttons stand in the bar.
  final double inlineFrom;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= inlineFrom) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in actions)
            IconButton(
              tooltip: action.label,
              onPressed: action.onPressed,
              icon: Icon(action.icon, color: color),
            ),
        ],
      );
    }
    return PopupMenuButton<TgcgBarAction>(
      tooltip: 'More',
      icon: Icon(Icons.more_vert_rounded, color: color),
      onSelected: (action) => action.onPressed(),
      itemBuilder: (_) => [
        for (final action in actions)
          PopupMenuItem(
            value: action,
            child: Row(
              children: [
                Icon(action.icon, size: 20, color: TgcgColors.primary),
                const SizedBox(width: 12),
                Flexible(child: Text(action.label)),
              ],
            ),
          ),
      ],
    );
  }
}

/// How far a page's content stands from the edges at [width]: phones use the
/// whole width, wider screens keep a readable column in the middle.
EdgeInsets tgcgPagePadding(
  double width, {
  double maxWidth = 760,
  double top = TgcgSpacing.md,
  double bottom = TgcgSpacing.lg,
}) {
  final side = math.max(TgcgSpacing.md, (width - maxWidth) / 2);
  return EdgeInsets.fromLTRB(side, top, side, bottom);
}

/// A scrolling page of cards, in a readable column on wide screens.
class TgcgPageList extends StatelessWidget {
  const TgcgPageList({
    super.key,
    required this.children,
    this.maxWidth = 760,
    this.bottomPadding = TgcgSpacing.lg,
  });

  final List<Widget> children;
  final double maxWidth;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => ListView(
          padding: tgcgPagePadding(
            constraints.maxWidth,
            maxWidth: maxWidth,
            bottom: bottomPadding,
          ),
          children: children,
        ),
      );
}

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

  Widget _copy({required bool compact}) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(eyebrow!.toUpperCase(), style: TgcgType.eyebrow),
            const SizedBox(height: 7),
          ],
          Text(title, style: compact ? TgcgType.title.copyWith(fontSize: 22) : TgcgType.display),
          const SizedBox(height: 6),
          Text(subtitle, style: TgcgType.support.copyWith(height: 1.45)),
        ],
      );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _copy(compact: true),
                if (trailing != null) ...[
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerLeft, child: trailing!),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _copy(compact: false)),
              if (trailing != null) ...[
                const SizedBox(width: 16),
                Flexible(flex: 0, child: trailing!),
              ],
            ],
          );
        },
      );
}

/// The heading of a group of cards, with an optional action ("See all").
class TgcgSectionHeading extends StatelessWidget {
  const TgcgSectionHeading({super.key, required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: TgcgSpacing.sm),
        child: Row(
          children: [
            Expanded(child: Text(title, style: TgcgType.section)),
            ?action,
          ],
        ),
      );
}

class TgcgSectionCard extends StatelessWidget {
  const TgcgSectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(18),
    this.backgroundColor = TgcgColors.surface,
    this.trailingBeside = false,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final EdgeInsets padding;
  final Color backgroundColor;

  /// Keeps a short [trailing] ("See all") beside the title on a phone too.
  final bool trailingBeside;

  Widget _heading() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) Text(title!, style: TgcgType.section),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!, style: TgcgType.caption),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(TgcgRadius.lg),
          border: Border.all(color: TgcgColors.border),
          boxShadow: tgcgCardShadow,
        ),
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null || trailing != null) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 540 && trailing != null && !trailingBeside) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (title != null) _heading(),
                          const SizedBox(height: 10),
                          trailing!,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment:
                          trailingBeside ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                      children: [
                        if (title != null) Expanded(child: _heading()),
                        if (trailing != null) trailing!,
                      ],
                    );
                  },
                ),
                SizedBox(height: trailingBeside ? 4 : 14),
              ],
              child,
            ],
          ),
        ),
      );
}

/// A small tinted square holding an icon: the one way the app marks a row.
class TgcgIconBadge extends StatelessWidget {
  const TgcgIconBadge({
    super.key,
    required this.icon,
    this.color = TgcgColors.primary,
    this.size = 40,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(size * .3),
        ),
        child: Icon(icon, color: color, size: size * .52),
      );
}

/// A row that opens something: an icon, what it is, and a short detail.
class TgcgActionRow extends StatelessWidget {
  const TgcgActionRow({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
    this.trailing,
    this.onTap,
    this.color = TgcgColors.primary,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                TgcgIconBadge(icon: icon, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TgcgType.bodyStrong),
                      if (detail != null && detail!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(detail!, style: TgcgType.caption),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing ??
                    (onTap == null
                        ? const SizedBox.shrink()
                        : const Icon(Icons.chevron_right_rounded, color: TgcgColors.muted)),
              ],
            ),
          ),
        ),
      );
}

/// Rows standing together in one card, with hairlines between them.
class TgcgRowGroup extends StatelessWidget {
  const TgcgRowGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: TgcgColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TgcgRadius.lg),
          side: const BorderSide(color: TgcgColors.border),
        ),
        child: Column(
          children: [
            for (final (index, child) in children.indexed) ...[
              if (index > 0) const Divider(height: 1, thickness: 1, indent: 66),
              child,
            ],
          ],
        ),
      );
}

/// A short message inside a page: something to know, or to do.
class TgcgNotice extends StatelessWidget {
  const TgcgNotice({
    super.key,
    required this.icon,
    required this.child,
    this.color = TgcgColors.primary,
    this.action,
  });

  final IconData icon;
  final Widget child;
  final Color color;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(TgcgRadius.md),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: DefaultTextStyle.merge(style: TgcgType.body, child: child),
            ),
            if (action != null) ...[const SizedBox(width: 8), action!],
          ],
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TgcgColors.surface,
        borderRadius: BorderRadius.circular(TgcgRadius.lg),
        border: Border.all(color: TgcgColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TgcgIconBadge(icon: icon, color: color),
              const Spacer(),
              if (onTap != null)
                const Icon(
                  Icons.arrow_outward_rounded,
                  size: 18,
                  color: TgcgColors.muted,
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontWeight: FontWeight.w800,
              fontSize: 26,
              letterSpacing: -.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: TgcgColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(
              detail!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TgcgType.caption,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return InkWell(
      borderRadius: BorderRadius.circular(TgcgRadius.lg),
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
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: color, size: compact ? 14 : 16),
              const SizedBox(width: 5),
            ],
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: color,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .2,
                ),
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
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Optional follow-up, e.g. a "Try again" button.
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              children: [
                TgcgIconBadge(icon: icon, size: 52),
                const SizedBox(height: 12),
                Text(title, textAlign: TextAlign.center, style: TgcgType.section),
                const SizedBox(height: 5),
                Text(message, textAlign: TextAlign.center, style: TgcgType.support),
                if (action != null) ...[
                  const SizedBox(height: 12),
                  action!,
                ],
              ],
            ),
          ),
        ),
      );
}
