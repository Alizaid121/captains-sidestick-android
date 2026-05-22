// lib/widgets/throttle_slider.dart  —  v2.2.1
//
// Magnetic Airbus-style throttle detents.
//
// Detent behaviour — three phases:
//   1. FREE DRAG   — finger is outside every magnetic zone, slider follows
//                    finger delta precisely (1:1 pixel tracking).
//   2. ENTRY PULL  — finger crosses into a ±kMagneticZone radius around a
//                    detent. _applyDetents() immediately returns the detent
//                    value and _snapToDetent() fires a 100 ms easeOut
//                    animation from the current raw position to the detent.
//                    onChanged fires with the detent value instantly.
//   3. EXIT BREAK  — while inside a zone the raw drag position is tracked
//                    silently. The detent only releases when the raw value
//                    has moved MORE than kMagneticZone beyond the detent
//                    (i.e. the user pushes hard enough to break free). This
//                    gives the physical "gate" feel — you must push through.
//
// Animation:
//   AnimationController drives thumb + fill visuals during the 100 ms snap.
//   During free drag the displayed value = _rawValue (no animation needed).
//   During snap the displayed value = _snapAnim.value (lerp to detent).
//   After snap the displayed value = locked detent.
//
// All existing external API (value, onChanged, detentsEnabled, width) is
// preserved — cockpit_screen.dart needs no changes.

import 'package:flutter/material.dart';
import '../main.dart';

// ── Public detent table — used by this widget only ───────────────────────────
const List<Map<String, dynamic>> kDetents = [
  {'name': 'IDLE', 'value': 0.00},   // flight idle / cutoff
  {'name': 'MCT',  'value': 0.75},   // maximum continuous thrust
  {'name': 'FLEX', 'value': 0.85},   // flexible / derated take-off
  {'name': 'TOGA', 'value': 1.00},   // take-off / go-around
];

// Magnetic zone radius — ±8 % of full range on each side of a detent.
const double kMagneticZone = 0.08;

// ─────────────────────────────────────────────────────────────────────────────
class ThrottleSlider extends StatefulWidget {
  const ThrottleSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.detentsEnabled = true,
    this.width = 56.0,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final bool   detentsEnabled;
  final double width;

  @override
  State<ThrottleSlider> createState() => _ThrottleSliderState();
}

class _ThrottleSliderState extends State<ThrottleSlider>
    with SingleTickerProviderStateMixin {

  // ── Animation controller for magnetic snap ────────────────────────────────
  late final AnimationController _snapCtrl = AnimationController(
    vsync: this,
  );
  Animation<double>? _snapAnim;

  // ── Value state ───────────────────────────────────────────────────────────
  /// Raw value tracking the finger, regardless of detents. [0.0, 1.0]
  double _rawValue      = 0.0;

  /// Displayed / reported value — may differ from raw during snap animation.
  double _displayValue  = 0.0;

  /// The detent we are currently locked to, null if in free range.
  double? _lockedDetent;

  bool _dragging = false;

  // Track height set by LayoutBuilder on every frame.
  double _trackHeight = 1.0;

  @override
  void initState() {
    super.initState();
    _rawValue     = widget.value;
    _displayValue = widget.value;
    // If initial value sits on a detent, lock to it immediately.
    _lockedDetent = _findDetent(widget.value);
  }

  @override
  void didUpdateWidget(ThrottleSlider old) {
    super.didUpdateWidget(old);
    if (!_dragging && !_snapCtrl.isAnimating) {
      _rawValue     = widget.value;
      _displayValue = widget.value;
      _lockedDetent = _findDetent(widget.value);
    }
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  // ── Detent helpers ────────────────────────────────────────────────────────

  /// Returns the detent value if [v] is within kMagneticZone, else null.
  double? _findDetent(double v) {
    if (!widget.detentsEnabled) return null;
    for (final d in kDetents) {
      final dv = d['value'] as double;
      if ((v - dv).abs() <= kMagneticZone) return dv;
    }
    return null;
  }

  /// Returns the name of the detent at exactly [v], or '' if none.
  String _detentName(double v) {
    for (final d in kDetents) {
      if ((v - (d['value'] as double)).abs() < 0.001) {
        return d['name'] as String;
      }
    }
    return '';
  }

  /// Core magnetic logic called on every drag update.
  /// Returns the value that should be reported + displayed.
  double _applyDetents(double rawValue) {
    if (!widget.detentsEnabled) return rawValue;

    for (final d in kDetents) {
      final double dv       = d['value'] as double;
      final double distance = (rawValue - dv).abs();

      if (distance <= kMagneticZone) {
        // Inside magnetic zone — snap to detent with full force.
        return dv;
      }
    }
    return rawValue;
  }

  /// Animate the thumb from its current display position to [detentValue]
  /// over 100 ms with an easeOut curve — gives the "magnetic click" feel.
  void _snapToDetent(double detentValue) {
    _snapCtrl.stop();
    _snapCtrl.duration = const Duration(milliseconds: 100);

    _snapAnim = Tween<double>(
      begin: _displayValue,
      end:   detentValue,
    ).animate(CurvedAnimation(
      parent: _snapCtrl,
      curve:  Curves.easeOut,
    ))..addListener(() {
      if (!mounted) return;
      setState(() => _displayValue = _snapAnim!.value);
      widget.onChanged(_displayValue);
    })..addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _displayValue = detentValue;
          _lockedDetent = detentValue;
        });
      }
    });

    _snapCtrl.forward(from: 0);
  }

  // ── Drag handlers ─────────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails _) {
    _snapCtrl.stop();
    setState(() => _dragging = true);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    // 1. Accumulate raw position from drag delta.
    final delta   = -d.delta.dy / _trackHeight;
    final newRaw  = (_rawValue + delta).clamp(0.0, 1.0);
    _rawValue = newRaw;

    // 2. Evaluate magnetic zones.
    final snapped = _applyDetents(newRaw);
    final isOnDetent = (snapped - newRaw).abs() > 0.0001;

    if (isOnDetent) {
      // Entering or staying in a magnetic zone.
      if (_lockedDetent != snapped) {
        // First entry into this detent zone — fire snap animation.
        _lockedDetent = snapped;
        _snapToDetent(snapped);
        widget.onChanged(snapped);
      }
      // While locked: do not move display value — detent holds.
    } else {
      // Free range — finger has broken out of all zones.
      _lockedDetent = null;
      if (_snapCtrl.isAnimating) _snapCtrl.stop();
      setState(() => _displayValue = newRaw);
      widget.onChanged(newRaw);
    }
  }

  void _onDragEnd(DragEndDetails _) {
    setState(() => _dragging = false);
    // If we ended in free space with detents on, do a final snap check.
    // This catches slow, careful releases right beside a detent.
    if (widget.detentsEnabled && _lockedDetent == null) {
      final snapped = _applyDetents(_rawValue);
      if ((snapped - _rawValue).abs() > 0.001) {
        _lockedDetent = snapped;
        _snapToDetent(snapped);
        widget.onChanged(snapped);
      }
    }
  }

  void _onDragCancel() {
    setState(() => _dragging = false);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const trackW  = 14.0;
    const thumbW  = 32.0;
    const thumbH  = 22.0;
    const padTop  = 18.0;
    const padBot  = 4.0;

    return SizedBox(
      width: widget.width,
      child: LayoutBuilder(builder: (ctx, constraints) {
        _trackHeight = (constraints.maxHeight - padTop - padBot)
            .clamp(1.0, double.infinity);

        final cx = constraints.maxWidth / 2;

        // Visual position derived from _displayValue (animated during snap).
        final thumbTop = padTop + (1.0 - _displayValue) * _trackHeight
                         - thumbH / 2;
        final fillH    = (_displayValue * _trackHeight)
                         .clamp(0.0, _trackHeight);

        // Which detent are we snapped to right now (for label highlight)?
        final activeDetentValue = _lockedDetent;
        final activeName        = activeDetentValue != null
            ? _detentName(activeDetentValue)
            : '';

        return GestureDetector(
          behavior:              HitTestBehavior.opaque,
          onVerticalDragStart:   _onDragStart,
          onVerticalDragUpdate:  _onDragUpdate,
          onVerticalDragEnd:     _onDragEnd,
          onVerticalDragCancel:  _onDragCancel,
          child: Stack(
            clipBehavior: Clip.none,
            children: [

              // ── Percentage / detent label ──────────────────────────────────
              Positioned(
                top: 0, left: 0, right: 0,
                child: Text(
                  activeName.isNotEmpty
                      ? activeName                                   // e.g. "TOGA"
                      : '${(_displayValue * 100).round()}%',        // e.g. "63%"
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color:      activeName.isNotEmpty ? kAmber : kAmber,
                    fontSize:   activeName.isNotEmpty ? 9 : 10,
                    fontFamily: 'monospace',
                    fontWeight: activeName.isNotEmpty
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
              ),

              // ── Track background ───────────────────────────────────────────
              Positioned(
                top:    padTop,
                left:   cx - trackW / 2,
                width:  trackW,
                height: _trackHeight,
                child: Container(
                  decoration: BoxDecoration(
                    color:        kNavy2,
                    borderRadius: BorderRadius.circular(7),
                    border:       Border.all(color: kDim, width: 1),
                  ),
                ),
              ),

              // ── Fill (bottom of track up to thumb) ─────────────────────────
              Positioned(
                top:    padTop + _trackHeight - fillH,
                left:   cx - trackW / 2 + 1,
                width:  trackW - 2,
                height: fillH.clamp(0.0, _trackHeight),
                child: Container(
                  decoration: BoxDecoration(
                    color: kAmber.withOpacity(
                      activeDetentValue != null ? 0.90 : 0.65,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),

              // ── Detent lines + labels ──────────────────────────────────────
              ...kDetents.map((d) {
                final label    = d['name']  as String;
                final dv       = d['value'] as double;
                final isActive = activeDetentValue != null &&
                                 (activeDetentValue - dv).abs() < 0.001;
                // Exact pixel Y for this detent on the track.
                final lineY = padTop + (1.0 - dv) * _trackHeight;

                return Stack(
                  children: [
                    // Full-width amber line across the track
                    Positioned(
                      top:   lineY - 1.0,
                      left:  cx - trackW / 2,
                      width: trackW,
                      height: isActive ? 2.5 : 1.5,
                      child: Container(
                        color: isActive
                            ? kAmber
                            : kDim.withOpacity(0.45),
                      ),
                    ),

                    // Detent name label to the left of track
                    Positioned(
                      top:  lineY - 7,
                      left: 0,
                      width: cx - trackW / 2 - 2,
                      child: Text(
                        label,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color:      isActive ? kAmber : kDim.withOpacity(0.6),
                          fontSize:   isActive ? 8 : 7,
                          fontFamily: 'monospace',
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                );
              }),

              // ── Thumb ──────────────────────────────────────────────────────
              Positioned(
                top:    thumbTop,
                left:   cx - thumbW / 2,
                width:  thumbW,
                height: thumbH,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 40),
                  decoration: BoxDecoration(
                    color: _dragging
                        ? kAmber
                        : activeDetentValue != null
                            ? kAmber          // bright when locked to detent
                            : kAmberD,        // dim in free range
                    borderRadius: BorderRadius.circular(5),
                    boxShadow: [
                      BoxShadow(
                        color: kAmber.withOpacity(
                          activeDetentValue != null ? 0.75 : (_dragging ? 0.55 : 0.30),
                        ),
                        blurRadius: activeDetentValue != null ? 14 : (_dragging ? 10 : 5),
                      ),
                    ],
                  ),
                  // Notch lines on thumb to indicate it's a gate lever
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _thumbNotch(activeDetentValue != null),
                      const SizedBox(height: 3),
                      _thumbNotch(activeDetentValue != null),
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

  /// Two small horizontal lines on the thumb face — like a real throttle lever.
  Widget _thumbNotch(bool active) => Container(
    width:  18,
    height: 1.5,
    decoration: BoxDecoration(
      color:        active ? kNavy : kNavy2,
      borderRadius: BorderRadius.circular(1),
    ),
  );
}
