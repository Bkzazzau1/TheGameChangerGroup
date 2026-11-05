import 'package:flutter/material.dart';

import '../ui/tgcg_design.dart';

/// A voter card's shape: the ID-1 size of bank cards, 85.6 by 54 mm.
const voterCardAspectRatio = 85.6 / 53.98;

/// Where the card goes in a camera preview of [size]: as wide as the
/// preview allows, leaving room around it.
Rect cardFrameIn(Size size) {
  var width = size.width * 0.86;
  var height = width / voterCardAspectRatio;
  if (height > size.height * 0.78) {
    height = size.height * 0.78;
    width = height * voterCardAspectRatio;
  }
  return Rect.fromCenter(center: size.center(Offset.zero), width: width, height: height);
}

/// Where the card goes on a screen of [size], with [margin] kept clear.
Rect cardFrameWithin(Size size, EdgeInsets margin) {
  final area = margin.deflateRect(Offset.zero & size);
  return cardFrameIn(area.size).shift(area.topLeft);
}

/// Drawn over the camera preview while a PVC is photographed, as identity
/// checks do: the card's outline with its corners marked, a faint sketch of
/// the card's front (photo on the left, its lines of text on the right) so it
/// is held the right way round, and everything outside it darkened.
class CardScanFrame extends StatelessWidget {
  const CardScanFrame({super.key, this.margin = EdgeInsets.zero});

  /// Kept clear of the card (the bars and the hint over the picture); it is
  /// darkened with the rest.
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Frame for the front of your PVC',
    child: CustomPaint(painter: _CardFramePainter(margin), child: const SizedBox.expand()),
  );
}

class _CardFramePainter extends CustomPainter {
  _CardFramePainter(this.margin);

  final EdgeInsets margin;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = cardFrameWithin(size, margin);
    final radius = Radius.circular(frame.width * 0.045);
    final card = RRect.fromRectAndRadius(frame, radius);

    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(card),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.58),
    );

    // The card's front, faintly: a band across the top, the photo, the text.
    final w = frame.width;
    final h = frame.height;
    final ghost = Paint()..color = Colors.white.withValues(alpha: 0.14);
    RRect part(double left, double top, double width, double height) =>
        RRect.fromRectAndRadius(
          Rect.fromLTWH(frame.left + w * left, frame.top + h * top, w * width, h * height),
          Radius.circular(h * 0.03),
        );
    canvas.drawRRect(part(0.05, 0.07, 0.9, 0.11), ghost);
    canvas.drawRRect(part(0.05, 0.27, 0.24, 0.58), ghost);
    for (var line = 0; line < 5; line++) {
      canvas.drawRRect(part(0.34, 0.3 + line * 0.11, line.isEven ? 0.5 : 0.38, 0.05), ghost);
    }

    canvas.drawRRect(
      card,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // Corner marks, as on an identity check's frame.
    final corner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..color = TgcgColors.accentBright;
    final arm = h * 0.2;
    final r = radius.x;
    for (final (x, y, dx, dy) in [
      (frame.left, frame.top, 1.0, 1.0),
      (frame.right, frame.top, -1.0, 1.0),
      (frame.left, frame.bottom, 1.0, -1.0),
      (frame.right, frame.bottom, -1.0, -1.0),
    ]) {
      canvas.drawPath(
        Path()
          ..moveTo(x, y + dy * (r + arm))
          ..lineTo(x, y + dy * r)
          ..quadraticBezierTo(x, y, x + dx * r, y)
          ..lineTo(x + dx * (r + arm), y),
        corner,
      );
    }
  }

  @override
  bool shouldRepaint(_CardFramePainter oldDelegate) => oldDelegate.margin != margin;
}
