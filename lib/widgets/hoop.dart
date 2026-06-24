import 'dart:math';
import 'package:flutter/material.dart';

/// A fully drawn basketball hoop (backboard + rim + animated net).
///
/// The ring opening center sits at the fraction [ringCenterYFactor] of the
/// widget height, so the game can align the scoring plane precisely.
class HoopWidget extends StatelessWidget {
  final double width;

  /// 0 = relaxed net, 1 = fully bulged (ball just swished through).
  final double swish;

  const HoopWidget({super.key, required this.width, this.swish = 0});

  /// Ring center as a fraction of total widget height.
  static const double ringCenterYFactor = 0.40;

  /// Total height as a multiple of width.
  static const double heightFactor = 1.05;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: width * heightFactor,
      child: CustomPaint(painter: _HoopPainter(swish: swish)),
    );
  }
}

class _HoopPainter extends CustomPainter {
  final double swish;
  _HoopPainter({required this.swish});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final cx = w / 2;
    final rimCy = size.height * HoopWidget.ringCenterYFactor;
    final rimRx = w * 0.40;
    final rimRy = w * 0.12;

    // ---- Backboard ----
    final boardW = w * 0.72;
    final boardH = w * 0.50;
    final boardRect = Rect.fromCenter(
      center: Offset(cx, rimCy - rimRy - boardH * 0.55),
      width: boardW,
      height: boardH,
    );
    final boardRRect = RRect.fromRectAndRadius(boardRect, const Radius.circular(8));
    canvas.drawRRect(
      boardRRect.shift(const Offset(0, 3)),
      Paint()..color = Colors.black.withValues(alpha: 0.18),
    );
    canvas.drawRRect(boardRRect, Paint()..color = const Color(0xFFFDFBF4));
    canvas.drawRRect(
      boardRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.018
        ..color = const Color(0xFF8A5A2B),
    );
    // Inner target square.
    final innerW = boardW * 0.34;
    final innerH = boardH * 0.42;
    final innerRect = Rect.fromCenter(
      center: Offset(cx, boardRect.bottom - innerH * 0.75),
      width: innerW,
      height: innerH,
    );
    canvas.drawRect(
      innerRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.016
        ..color = const Color(0xFFE8612C),
    );

    // ---- Net ----
    final netBottomY = rimCy + w * 0.55 + swish * w * 0.12;
    final netBottomRx = rimRx * 0.42;
    final netBottomRy = rimRy * 0.5;
    const cols = 12;
    final netPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.012
      ..color = Colors.white.withValues(alpha: 0.92);

    final topPts = <Offset>[];
    final botPts = <Offset>[];
    for (int i = 0; i < cols; i++) {
      final a = (i / cols) * 2 * pi;
      topPts.add(Offset(cx + rimRx * cos(a), rimCy + rimRy * sin(a)));
      botPts.add(Offset(cx + netBottomRx * cos(a), netBottomY + netBottomRy * sin(a)));
    }
    // Vertical strands.
    for (int i = 0; i < cols; i++) {
      canvas.drawLine(topPts[i], botPts[i], netPaint);
    }
    // Diagonal cross strands (two mid rings).
    for (final f in [0.4, 0.72]) {
      final ringY = rimCy + (netBottomY - rimCy) * f;
      final ringRx = rimRx + (netBottomRx - rimRx) * f;
      final ringRy = rimRy + (netBottomRy - rimRy) * f;
      final pts = <Offset>[];
      for (int i = 0; i < cols; i++) {
        final a = (i / cols) * 2 * pi;
        pts.add(Offset(cx + ringRx * cos(a), ringY + ringRy * sin(a)));
      }
      for (int i = 0; i < cols; i++) {
        canvas.drawLine(pts[i], pts[(i + 1) % cols], netPaint);
      }
    }

    // ---- Rim (front) ----
    final rimRect = Rect.fromCenter(center: Offset(cx, rimCy), width: rimRx * 2, height: rimRy * 2);
    // Back of rim (dim).
    canvas.drawArc(
      rimRect,
      pi,
      pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.05
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFB8431A),
    );
    // Front of rim (bright).
    canvas.drawArc(
      rimRect,
      0,
      pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.06
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xFFFF6B1A),
    );
  }

  @override
  bool shouldRepaint(covariant _HoopPainter old) => old.swish != swish;
}
