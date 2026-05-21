// lib/widgets/throttle_slider.dart
//
// Vertical throttle slider with named detents:
//   IDLE (0%), MCT (75%), FLEX (85%), TOGA (100%)
//
// When detents are enabled:
//   • The slider snaps to the nearest detent when the finger lifts within
//     ±5% of a detent value.
//   • During drag the value moves freely (no mid-drag snapping).
//
// Exposes onChanged(double value) where value is 0.0–1.0.

import 'package:flutter/material.dart';
import '../main.dart';   // colour constants

class ThrottleSlider extends StatefulWidget {
  const ThrottleSlider({
    super.key,
    required this.value,           // 0.0 – 1.0
    required this.onChanged,
    this.detentsEnabled = true,
    this.height = 300.0,
    this.width  = 60.0,
  });

  final double  value;
  final ValueChanged<double> onChanged;
  final bool    detentsEnabled;
  final double  height;
  final double  width;

  @override
  State<ThrottleSlider> createState() => _ThrottleSliderState();
}

class _ThrottleSliderState extends State<ThrottleSlider> {
  // Named detents (0.0–1.0)
  static const List<(String, double)> _detents = [
    ('TOGA', 1.00),
    ('FLEX', 0.85),
    ('MCT',  0.75),
    ('IDLE', 0.00),
  ];

  static const double _snapThreshold = 0.05;

  double _dragValue = 0.0;
  bool   _dragging  = false;

  @override
  void initState() {
    super.initState();
    _dragValue = widget.value;
  }

  @override
  void didUpdateWidget(ThrottleSlider old) {
    super.didUpdateWidget(old);
    if (!_dragging) _dragValue = widget.value;
  }

  double _yToValue(double localY, double trackHeight) {
    // Top of track = TOGA (1.0), Bottom = IDLE (0.0)
    final v = 1.0 - (localY / trackHeight);
    return v.clamp(0.0, 1.0);
  }

  void _onPointerMove(PointerMoveEvent e, double trackH, double offsetY) {
    final v = _yToValue(e.localPosition.dy - offsetY, trackH);
    setState(() => _dragValue = v);
    widget.onChanged(v);
  }

  void _onPointerUp() {
    if (widget.detentsEnabled) {
      for (final (_, dv) in _detents) {
        if ((_dragValue - dv).abs() <= _snapThreshold) {
          setState(() => _dragValue = dv);
          widget.onChanged(dv);
          break;
        }
      }
    }
    setState(() => _dragging = false);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  widget.width,
      height: widget.height,
      child:  LayoutBuilder(
        builder: (ctx, constraints) {
          final trackH    = constraints.maxHeight;
          const padTop    = 20.0; // space for TOGA label above track
          final innerH    = trackH - padTop - 4;

          return Stack(
            children: [
              // ── Track background ─────────────────────────────────────
              Positioned(
                top:   padTop,
                left:  (widget.width - 14) / 2,
                child: Container(
                  width:  14,
                  height: innerH,
                  decoration: BoxDecoration(
                    color:        kNavy2,
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: kDim, width: 1),
                  ),
                ),
              ),

              // ── Filled portion (amber) ────────────────────────────────
              Positioned(
                bottom: 4,
                left:   (widget.width - 14) / 2,
                child:  Container(
                  width:  14,
                  height: _dragValue * innerH,
                  decoration: BoxDecoration(
                    color:        kAmber.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),

              // ── Detent lines + labels ────────────────────────────────
              ..._detents.map((d) {
                final label = d.$1;
                final dv    = d.$2;
                final y     = padTop + (1.0 - dv) * innerH;
                return Positioned(
                  top:  y - 1,
                  left: 0,
                  right: 0,
                  child: Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color:    dv == _dragValue ? kAmber : kDim,
                          fontSize: 8,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1.5,
                          color:  dv == _dragValue ? kAmber : kDim.withOpacity(0.4),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // ── Thumb ────────────────────────────────────────────────
              Positioned(
                top:  padTop + (1.0 - _dragValue) * innerH - 12,
                left: (widget.width - 28) / 2,
                child: Container(
                  width:  28,
                  height: 24,
                  decoration: BoxDecoration(
                    color:        _dragging ? kAmber : kAmberD,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color:      kAmber.withOpacity(0.5),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                ),
              ),

              // ── Touch detector ────────────────────────────────────────
              Positioned.fill(
                child: Listener(
                  onPointerDown:  (e) => setState(() {
                    _dragging  = true;
                    _dragValue = _yToValue(e.localPosition.dy - padTop, innerH);
                    widget.onChanged(_dragValue);
                  }),
                  onPointerMove:  (e) => _onPointerMove(e, innerH, padTop),
                  onPointerUp:    (_) => _onPointerUp(),
                  onPointerCancel:(_) => _onPointerUp(),
                  child: const SizedBox.expand(),
                ),
              ),

              // ── Percentage label ──────────────────────────────────────
              Positioned(
                top:  0,
                left: 0,
                right: 0,
                child: Text(
                  '${(_dragValue * 100).round()}%',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color:    kAmber,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
