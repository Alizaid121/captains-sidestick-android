// lib/widgets/rudder_slider.dart
//
// Horizontal rudder pedal slider — completely rewritten for Fix 1.
//
// Root cause of previous bug: Listener + Positioned coordinate maths were
// unreliable inside a Stack with padding offsets. The thumb appeared to move
// but value updates were fired with wrong coordinates because localPosition
// was relative to the Listener widget, not the track.
//
// Fix: GestureDetector with onHorizontalDragUpdate using drag *delta*
// accumulated into a [-1, +1] value. LayoutBuilder provides exact track
// width at paint time. Thumb position is derived purely from the clamped
// value, so visual and logical positions are always in sync.
//
// Spring-back on drag end: AnimationController tweens value → 0.0 over 200ms.

import 'package:flutter/material.dart';
import '../main.dart';

class RudderSlider extends StatefulWidget {
  const RudderSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 56.0,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double height;

  @override
  State<RudderSlider> createState() => _RudderSliderState();
}

class _RudderSliderState extends State<RudderSlider>
    with SingleTickerProviderStateMixin {

  double _value    = 0.0;
  bool   _dragging = false;

  // Track width captured from LayoutBuilder — used by drag delta maths.
  double _trackWidth = 1.0;

  // Spring-back controller
  late final AnimationController _springCtrl = AnimationController(
    vsync:    this,
    duration: const Duration(milliseconds: 200),
  );
  Animation<double>? _springAnim;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void dispose() {
    _springCtrl.dispose();
    super.dispose();
  }

  // ── Drag handlers ─────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails _) {
    _springCtrl.stop();
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // Convert pixel delta to value delta:
    //   full track width = 2.0 units (−1 to +1)
    final delta = d.delta.dx / _trackWidth * 2.0;
    setState(() {
      _value = (_value + delta).clamp(-1.0, 1.0);
    });
    widget.onChanged(_value);
  }

  void _onDragEnd(DragEndDetails _) {
    setState(() => _dragging = false);
    _springBack();
  }

  void _onDragCancel() {
    setState(() => _dragging = false);
    _springBack();
  }

  void _springBack() {
    _springAnim = Tween<double>(begin: _value, end: 0.0).animate(
      CurvedAnimation(parent: _springCtrl, curve: Curves.easeOut),
    )..addListener(() {
      if (!mounted) return;
      setState(() => _value = _springAnim!.value);
      widget.onChanged(_value);
    });
    _springCtrl
      ..reset()
      ..forward();
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const trackH  = 12.0;
    const thumbW  = 22.0;
    const thumbH  = 34.0;
    const labelW  = 14.0;   // width reserved for L / R labels

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(builder: (ctx, constraints) {
        // Usable track width (excluding label gutters on each side)
        _trackWidth = (constraints.maxWidth - labelW * 2).clamp(1.0, double.infinity);

        final cy      = constraints.maxHeight / 2;
        // Thumb centre X, relative to left edge of track area (after labelW)
        final thumbCx = labelW + (_value + 1.0) / 2.0 * _trackWidth;

        // Fill from centre of track outward toward thumb
        final trackCx = labelW + _trackWidth / 2.0;
        final fillL   = _value < 0 ? thumbCx  : trackCx;
        final fillW   = (_value.abs() / 2.0 * _trackWidth).clamp(0.0, _trackWidth);

        return GestureDetector(
          behavior:          HitTestBehavior.opaque,
          onHorizontalDragStart:  _onDragStart,
          onHorizontalDragUpdate: _onDragUpdate,
          onHorizontalDragEnd:    _onDragEnd,
          onHorizontalDragCancel: _onDragCancel,
          child: Stack(
            clipBehavior: Clip.none,
            children: [

              // ── L label ─────────────────────────────────────────────────
              Positioned(
                left: 0,
                top:  cy - 7,
                child: const Text('L', style: _labelStyle),
              ),

              // ── R label ─────────────────────────────────────────────────
              Positioned(
                right: 0,
                top:   cy - 7,
                child: const Text('R', style: _labelStyle),
              ),

              // ── Track background ─────────────────────────────────────────
              Positioned(
                left:   labelW,
                top:    cy - trackH / 2,
                width:  _trackWidth,
                height: trackH,
                child: Container(
                  decoration: BoxDecoration(
                    color:        kNavy2,
                    borderRadius: BorderRadius.circular(6),
                    border:       Border.all(color: kDim, width: 1),
                  ),
                ),
              ),

              // ── Fill (centre → thumb) ─────────────────────────────────────
              if (fillW > 0)
                Positioned(
                  left:   fillL,
                  top:    cy - trackH / 2 + 1,
                  width:  fillW,
                  height: trackH - 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color:        kAmber.withOpacity(0.65),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),

              // ── Centre tick ───────────────────────────────────────────────
              Positioned(
                left:   trackCx - 1,
                top:    cy - 10,
                width:  2,
                height: 20,
                child: Container(color: kDim.withOpacity(0.6)),
              ),

              // ── Thumb ────────────────────────────────────────────────────
              Positioned(
                left:   thumbCx - thumbW / 2,
                top:    cy - thumbH / 2,
                width:  thumbW,
                height: thumbH,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 40),
                  decoration: BoxDecoration(
                    color: _dragging ? kAmber : kAmberD,
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color:      kAmber.withOpacity(_dragging ? 0.6 : 0.3),
                        blurRadius: _dragging ? 10 : 5,
                      ),
                    ],
                  ),
                ),
              ),

            ],
          ),
        );
      }),
    );
  }

  static const _labelStyle = TextStyle(
    color:      kDim,
    fontSize:   10,
    fontFamily: 'monospace',
    fontWeight: FontWeight.bold,
  );
}
