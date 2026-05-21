// lib/widgets/attitude_indicator.dart
//
// Draws a classic round artificial horizon (attitude indicator).
//   • Blue upper half = sky, brown lower half = ground
//   • Rotates by roll angle (banking)
//   • Translates vertically by pitch angle
//   • Fixed aircraft crosshair / wings symbol drawn on top
//   • Degree tick marks on horizon band

import 'dart:math' as math;
import 'package:flutter/material.dart';

class AttitudeIndicator extends StatelessWidget {
  const AttitudeIndicator({
    super.key,
    required this.pitch,    // [-1, +1]  +1 = full nose-up
    required this.roll,     // [-1, +1]  +1 = full right bank
    this.size = 260.0,
  });

  final double pitch;
  final double roll;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  size,
      height: size,
      child:  ClipOval(
        child: CustomPaint(
          painter: _AIPainter(pitch: pitch, roll: roll),
          size: Size(size, size),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _AIPainter extends CustomPainter {
  const _AIPainter({required this.pitch, required this.roll});

  final double pitch;
  final double roll;

  // Degrees shown at full deflection
  static const double _pitchRange = 30.0;
  static const double _rollRange  = 45.0;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width  / 2;
    final cy = size.height / 2;
    final r  = cx; // radius

    // ── Transform for roll & pitch ───────────────────────────────────────
    canvas.save();
    canvas.translate(cx, cy);

    // Roll rotation (about centre)
    final rollRad = roll * _rollRange * math.pi / 180.0;
    canvas.rotate(rollRad);

    // Pitch translation — positive pitch moves sky down (nose up)
    final pitchPx = -pitch * _pitchRange / 90.0 * r * 1.5;
    canvas.translate(0, pitchPx);

    // ── Ground + Sky rectangle (large enough to fill circle at any angle) ──
    final bgPaint = Paint();
    final bgRect  = Rect.fromLTRB(-r * 2, -r * 2, r * 2, r * 2);

    // Sky — upper half of the rotated rect
    bgPaint.color = const Color(0xFF1A5FA8);
    canvas.drawRect(Rect.fromLTRB(-r * 2, -r * 2, r * 2, 0), bgPaint);

    // Ground — lower half
    bgPaint.color = const Color(0xFF6B3A1F);
    canvas.drawRect(Rect.fromLTRB(-r * 2, 0, r * 2, r * 2), bgPaint);

    // ── Horizon line ─────────────────────────────────────────────────────
    final hPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(-r * 1.5, 0), Offset(r * 1.5, 0), hPaint);

    // ── Pitch ladder (every 10°) ─────────────────────────────────────────
    _drawPitchLadder(canvas, r);

    canvas.restore();

    // ── Fixed aircraft symbol (not rotated) ─────────────────────────────
    canvas.save();
    canvas.translate(cx, cy);
    _drawAircraftSymbol(canvas, r, size);
    canvas.restore();

    // ── Circular clip border ─────────────────────────────────────────────
    final borderPaint = Paint()
      ..color = const Color(0xFF243040)
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(cx, cy), r - 2, borderPaint);

    // ── Roll arc + tick marks ────────────────────────────────────────────
    _drawRollArc(canvas, Offset(cx, cy), r);
  }

  // ── Pitch ladder ──────────────────────────────────────────────────────────
  void _drawPitchLadder(Canvas canvas, double r) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.7)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final textStyle = const TextStyle(
      color: Colors.white,
      fontSize: 10,
      fontFamily: 'monospace',
    );

    for (int deg = -30; deg <= 30; deg += 10) {
      if (deg == 0) continue;
      final y = -deg / 90.0 * r * 1.5;
      final hw = deg.abs() == 10 ? r * 0.25 : r * 0.35;

      canvas.drawLine(Offset(-hw, y), Offset(hw, y), paint);

      // Degree label
      final tp = TextPainter(
        text: TextSpan(text: '${deg.abs()}', style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(hw + 4, y - tp.height / 2));
      tp.paint(canvas, Offset(-hw - tp.width - 4, y - tp.height / 2));
    }
  }

  // ── Aircraft crosshair / wings ────────────────────────────────────────────
  void _drawAircraftSymbol(Canvas canvas, double r, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE0A020)  // amber
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = const Color(0xFFE0A020)
      ..style = PaintingStyle.fill;

    // Left wing
    canvas.drawLine(const Offset(-80, 0), const Offset(-20, 0), paint);
    canvas.drawLine(const Offset(-20, 0), const Offset(-20, 10), paint);

    // Right wing
    canvas.drawLine(const Offset(20, 0), const Offset(80, 0), paint);
    canvas.drawLine(const Offset(20, 0), const Offset(20, 10), paint);

    // Centre dot
    canvas.drawCircle(Offset.zero, 5, fillPaint);

    // Centre vertical tick
    canvas.drawLine(const Offset(0, -12), const Offset(0, -4), paint);
  }

  // ── Roll arc & tick marks ─────────────────────────────────────────────────
  void _drawRollArc(Canvas canvas, Offset centre, double r) {
    final arcPaint = Paint()
      ..color = Colors.white.withOpacity(0.4)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    const arcAngles = [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60];
    for (final deg in arcAngles) {
      final rad = (deg - 90) * math.pi / 180.0;
      final inner = r - 14.0;
      final outer = r - 6.0;
      canvas.drawLine(
        centre + Offset(math.cos(rad) * inner, math.sin(rad) * inner),
        centre + Offset(math.cos(rad) * outer, math.sin(rad) * outer),
        arcPaint,
      );
    }

    // Current roll pointer
    final rollRad = roll * 45.0 * math.pi / 180.0 - math.pi / 2;
    final pointerPaint = Paint()
      ..color = const Color(0xFFE0A020)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final p1 = centre + Offset(math.cos(rollRad) * (r - 16), math.sin(rollRad) * (r - 16));
    final p2 = centre + Offset(math.cos(rollRad) * (r - 4),  math.sin(rollRad) * (r - 4));
    canvas.drawLine(p1, p2, pointerPaint);
  }

  @override
  bool shouldRepaint(_AIPainter old) =>
      old.pitch != pitch || old.roll != roll;
}
