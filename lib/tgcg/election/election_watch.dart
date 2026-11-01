import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui/tgcg_design.dart';
import 'election_calendar.dart';

/// How far round the dial each hand is at [now], in Nigeria, as a share of a
/// full turn from twelve o'clock.
({double hour, double minute, double second}) watchHands(DateTime now) {
  final lagos = now.toUtc().add(lagosOffset);
  final minutes = lagos.minute + lagos.second / 60;
  return (
    hour: (lagos.hour % 12 + minutes / 60) / 12,
    minute: minutes / 60,
    second: lagos.second / 60,
  );
}

/// An analogue watch on Nigerian time. Its gold ring runs down through the
/// day: at midnight it is empty, the count in its window falls by one and the
/// ring fills again.
class ElectionWatch extends StatelessWidget {
  const ElectionWatch({
    super.key,
    required this.now,
    required this.size,
    this.counting = true,
    this.headline,
    this.caption,
  });

  final DateTime now;
  final double size;

  /// The ring runs down until the election has been held.
  final bool counting;

  /// What the window on the dial says; no window without it.
  final String? headline;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final words = headline;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _WatchPainter(now: now, counting: counting),
              ),
            ),
          ),
          if (words != null)
            Align(
              alignment: const Alignment(0, .58),
              child: _Window(size: size, headline: words, caption: caption),
            ),
        ],
      ),
    );
  }
}

/// The count, in a window the hands pass behind, as on a watch with a date.
class _Window extends StatelessWidget {
  const _Window({required this.size, required this.headline, this.caption});

  final double size;
  final String headline;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final words = caption;
    return Container(
      width: size * (words == null ? .56 : .5),
      height: size * (words == null ? .32 : .31),
      padding: EdgeInsets.symmetric(horizontal: size * .025, vertical: size * .012),
      decoration: BoxDecoration(
        color: TgcgColors.primaryDark,
        borderRadius: BorderRadius.circular(size * .05),
        border: Border.all(color: TgcgColors.accentBright.withValues(alpha: .55)),
      ),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headline,
                maxLines: 1,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * (words == null ? .24 : .19),
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (words != null)
                Text(
                  words,
                  maxLines: 1,
                  style: TextStyle(
                    color: TgcgColors.accentBright,
                    fontSize: math.max(size * .066, 9),
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WatchPainter extends CustomPainter {
  const _WatchPainter({required this.now, required this.counting});

  final DateTime now;
  final bool counting;

  /// Clockwise from twelve o'clock.
  static Offset _at(double turn, double radius) {
    final angle = 2 * math.pi * turn - math.pi / 2;
    return Offset(math.cos(angle), math.sin(angle)) * radius;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.shortestSide / 2;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);

    // The case.
    canvas.drawCircle(Offset.zero, radius, Paint()..color = TgcgColors.primaryDark);
    canvas.drawCircle(
      Offset.zero,
      radius - .5,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = TgcgColors.accentBright.withValues(alpha: .5),
    );

    // The ring: what is left of the day.
    final ringRadius = radius * .925;
    final ringWidth = math.max(radius * .055, 2.5);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ringWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(Offset.zero, ringRadius, ring..color = Colors.white.withValues(alpha: .16));
    if (counting) {
      final left = leftOfLagosDay(now).inSeconds / Duration.secondsPerDay;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: ringRadius),
        -math.pi / 2,
        2 * math.pi * left,
        false,
        ring..color = TgcgColors.accentBright,
      );
    }

    // The face.
    canvas.drawCircle(
      Offset.zero,
      radius * .85,
      Paint()
        ..shader = const RadialGradient(
          colors: [TgcgColors.primary, TgcgColors.primaryDark],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius * .85)),
    );

    // Hour marks, and minute marks where there is room for them.
    final marks = radius >= 48 ? 60 : 12;
    for (var mark = 0; mark < marks; mark++) {
      final turn = mark / marks;
      final onTheHour = mark % (marks / 12) == 0;
      canvas.drawLine(
        _at(turn, radius * (onTheHour ? .68 : .75)),
        _at(turn, radius * .8),
        Paint()
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(radius * (onTheHour ? .03 : .012), onTheHour ? 1.5 : .8)
          ..color = mark == 0
              ? TgcgColors.accentBright
              : Colors.white.withValues(alpha: onTheHour ? .92 : .42),
      );
    }

    // The hands.
    final hands = watchHands(now);
    void hand(double turn, double length, double width, Color color, {double tail = 0}) =>
        canvas.drawLine(
          _at(turn, -radius * tail),
          _at(turn, radius * length),
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = width
            ..color = color,
        );
    hand(hands.hour, .42, math.max(radius * .065, 2.4), Colors.white, tail: .08);
    hand(hands.minute, .62, math.max(radius * .045, 1.8), Colors.white, tail: .08);
    hand(hands.second, .72, math.max(radius * .016, 1), TgcgColors.accentBright, tail: .16);
    canvas.drawCircle(Offset.zero, radius * .065, Paint()..color = TgcgColors.accentBright);
    canvas.drawCircle(Offset.zero, radius * .026, Paint()..color = TgcgColors.primaryDark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WatchPainter old) =>
      old.counting != counting ||
      old.now.millisecondsSinceEpoch ~/ 1000 != now.millisecondsSinceEpoch ~/ 1000;
}
