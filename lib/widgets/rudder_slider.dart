// lib/widgets/rudder_slider.dart
//
// Horizontal rudder pedal slider.
//   • Neutral at centre (value 0.0)
//   • Deflects left (−1.0) or right (+1.0)
//   • Spring-returns to 0.0 when finger lifts
//   • Amber filled bar grows from centre outward

import 'package:flutter/material.dart';
import '../main.dart';

class RudderSlider extends StatefulWidget {
  const RudderSlider({
    super.key,
    required this.value,        // −1.0 … +1.0
    required this.onChanged,
    this.width  = 240.0,
    this.height = 44.0,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double width;
  final double height;

  @override
  State<RudderSlider> createState() => _RudderSliderState();
}

class _RudderSliderState extends State<RudderSlider>
    with SingleTickerProviderStateMixin {
  double _value    = 0.0;
  bool   _dragging = false;

  // Spring-back animation
  late AnimationController _springCtrl;
  late Animation<double>   _springAnim;

  @override
  void initState() {
    super.initState();
    _value = widget.value;

    _springCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _springCtrl.dispose();
    super.dispose();
  }

  void _startSpringBack() {
    _springAnim = Tween<double>(begin: _value, end: 0.0).animate(
      CurvedAnimation(parent: _springCtrl, curve: Curves.easeOut),
    )..addListener(() {
      setState(() => _value = _springAnim.value);
      widget.onChanged(_springAnim.value);
    });
    _springCtrl
      ..reset()
      ..forward();
  }

  double _xToValue(double localX, double trackW) {
    final v = (localX / trackW) * 2.0 - 1.0;
    return v.clamp(-1.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    const padH = 8.0;   // horizontal padding inside container

    return SizedBox(
      width:  widget.width,
      height: widget.height,
      child:  LayoutBuilder(
        builder: (ctx, constraints) {
          final trackW = constraints.maxWidth - padH * 2;
          final trackH = 14.0;
          final cy     = constraints.maxHeight / 2;

          // Thumb position 0..trackW
          final thumbX = padH + ((_value + 1.0) / 2.0) * trackW;

          // Fill rect from centre outward
          final centreX = padH + trackW / 2;
          final fillL   = _value < 0 ? thumbX  : centreX;
          final fillW   = (_value.abs() / 2.0) * trackW;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Track ────────────────────────────────────────────────
              Positioned(
                top:  cy - trackH / 2,
                left: padH,
                child: Container(
                  width:  trackW,
                  height: trackH,
                  decoration: BoxDecoration(
                    color:        kNavy2,
                    borderRadius: BorderRadius.circular(7),
                    border:       Border.all(color: kDim, width: 1),
                  ),
                ),
              ),

              // ── Filled portion ────────────────────────────────────────
              Positioned(
                top:  cy - trackH / 2,
                left: fillL,
                child: Container(
                  width:  fillW,
                  height: trackH,
                  decoration: BoxDecoration(
                    color: kAmber.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),

              // ── Centre tick ───────────────────────────────────────────
              Positioned(
                top:  cy - 10,
                left: padH + trackW / 2 - 1,
                child: Container(width: 2, height: 20, color: kDim),
              ),

              // ── L / R labels ──────────────────────────────────────────
              Positioned(
                top:  cy - 8,
                left: 0,
                child: Text('L', style: _labelStyle),
              ),
              Positioned(
                top:  cy - 8,
                right: 0,
                child: Text('R', style: _labelStyle),
              ),

              // ── Thumb ─────────────────────────────────────────────────
              Positioned(
                top:  cy - 14,
                left: thumbX - 10,
                child: Container(
                  width:  20,
                  height: 28,
                  decoration: BoxDecoration(
                    color:        _dragging ? kAmber : kAmberD,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(color: kAmber.withOpacity(0.4), blurRadius: 6),
                    ],
                  ),
                ),
              ),

              // ── Touch layer ───────────────────────────────────────────
              Positioned.fill(
                child: Listener(
                  onPointerDown: (e) {
                    _springCtrl.stop();
                    setState(() {
                      _dragging = true;
                      _value = _xToValue(e.localPosition.dx - padH, trackW);
                    });
                    widget.onChanged(_value);
                  },
                  onPointerMove: (e) {
                    setState(() {
                      _value = _xToValue(e.localPosition.dx - padH, trackW);
                    });
                    widget.onChanged(_value);
                  },
                  onPointerUp: (_) {
                    setState(() => _dragging = false);
                    _startSpringBack();
                    widget.onChanged(0.0);
                  },
                  onPointerCancel: (_) {
                    setState(() => _dragging = false);
                    _startSpringBack();
                    widget.onChanged(0.0);
                  },
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static const _labelStyle = TextStyle(
    color:      kDim,
    fontSize:   10,
    fontFamily: 'monospace',
    fontWeight: FontWeight.bold,
  );
}
