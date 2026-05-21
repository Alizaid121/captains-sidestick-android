// lib/sensor_service.dart
//
// Reads gyroscope + accelerometer via sensors_plus 4.0.2.
// Fuses both sensors with a complementary filter for stable, gimbal-lock-free
// pitch and roll — identical external API to the previous version.
//
// Complementary filter theory:
//   • Gyroscope integrates angular rate → accurate short-term, drifts long-term
//   • Accelerometer gives absolute tilt  → noisy short-term, stable long-term
//   • Filter: angle = α × (angle + gyro × dt) + (1-α) × accel_angle
//   • α = 0.96 keeps gyro dominant for fast moves, accel corrects slow drift
//
// Available sensors_plus 4.0.2 streams used:
//   gyroscopeEventStream()      → GyroscopeEvent  (x, y, z  rad/s)
//   accelerometerEventStream()  → AccelerometerEvent (x, y, z  m/s²)

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'settings_model.dart';

class SensorService extends ChangeNotifier {
  SensorService(this._settings) {
    _settings.addListener(_onSettingsChanged);
    _subscribe();
  }

  final SettingsModel _settings;

  // ── Public outputs ────────────────────────────────────────────────────────
  double get pitch      => _pitchOut;   // −1.0 … +1.0
  double get roll       => _rollOut;    // −1.0 … +1.0
  bool   get sensorLock => _locked;

  double _pitchOut = 0.0;
  double _rollOut  = 0.0;

  // ── Sensor lock ───────────────────────────────────────────────────────────
  bool _locked = false;

  void toggleLock() {
    _locked = !_locked;
    if (_locked) {
      _pitchOut = 0.0;
      _rollOut  = 0.0;
    }
    notifyListeners();
  }

  // ── Calibration offsets (degrees) ────────────────────────────────────────
  // Stored when calibrate() is called; subtracted from all future output.
  double _calPitch = 0.0;
  double _calRoll  = 0.0;

  void calibrate() {
    // Snapshot the current filtered angles as the new zero reference.
    _calPitch = _filtPitch;
    _calRoll  = _filtRoll;
    notifyListeners();
  }

  // ── Complementary filter state ────────────────────────────────────────────
  // Integrated angle estimates (degrees) — updated every gyro event.
  double _filtPitch = 0.0;
  double _filtRoll  = 0.0;

  // Complementary filter coefficient.
  // 0.96 = gyro contributes 96 % (fast response), accel corrects 4 % (drift).
  static const double _cfAlpha = 0.96;

  // Low-pass filter on final output to smooth remaining jitter.
  static const double _lpAlpha = 0.15;
  double _lpPitch = 0.0;
  double _lpRoll  = 0.0;

  // Full-scale: ±_fullScale degrees maps to ±1.0 output.
  static const double _fullScale = 60.0;

  // ── Latest accelerometer reading (m/s²) ──────────────────────────────────
  double _ax = 0.0, _ay = 0.0, _az = 9.8;   // sane defaults (phone flat)

  // ── Timing ───────────────────────────────────────────────────────────────
  DateTime? _lastGyroTime;

  // ── Subscriptions ─────────────────────────────────────────────────────────
  StreamSubscription<GyroscopeEvent>?     _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  void _subscribe() {
    // Accelerometer — store latest reading; processed inside gyro callback.
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.gameInterval,
    ).listen(
      (AccelerometerEvent e) {
        _ax = e.x;
        _ay = e.y;
        _az = e.z;
      },
      onError:       (_) {},
      cancelOnError: false,
    );

    // Gyroscope — main integration loop.
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.gameInterval,  // ~50 Hz
    ).listen(
      _onGyroEvent,
      onError:       (_) {},
      cancelOnError: false,
    );
  }

  // ── Core sensor fusion ────────────────────────────────────────────────────
  void _onGyroEvent(GyroscopeEvent e) {
    // ── 1. Compute dt ──────────────────────────────────────────────────────
    final now = DateTime.now();
    final dt  = _lastGyroTime == null
        ? 0.02   // assume 50 Hz on first tick
        : now.difference(_lastGyroTime!).inMicroseconds / 1e6;
    _lastGyroTime = now;

    // Clamp dt to avoid huge jumps after app resume / sensor gap.
    final dtClamped = dt.clamp(0.001, 0.1);

    // ── 2. Gyroscope contribution (integrate angular rate → degrees) ───────
    // sensors_plus GyroscopeEvent: x, y, z in rad/s.
    // Portrait phone held upright:
    //   pitch (nose up/down) ← gyro.x
    //   roll  (bank L/R)     ← gyro.y
    final gyroPitchDeg = e.x * dtClamped * (180.0 / math.pi);
    final gyroRollDeg  = e.y * dtClamped * (180.0 / math.pi);

    // ── 3. Accelerometer contribution (absolute tilt angle) ────────────────
    // Protect against divide-by-zero when phone is nearly vertical.
    final accelPitch = math.atan2(
      _ay,
      _az,
    ) * (180.0 / math.pi);

    final accelRoll = math.atan2(
      -_ax,
      math.sqrt(_ay * _ay + _az * _az),
    ) * (180.0 / math.pi);

    // ── 4. Complementary filter ────────────────────────────────────────────
    _filtPitch = _cfAlpha * (_filtPitch + gyroPitchDeg) +
                 (1.0 - _cfAlpha) * accelPitch;
    _filtRoll  = _cfAlpha * (_filtRoll  + gyroRollDeg)  +
                 (1.0 - _cfAlpha) * accelRoll;

    // ── 5. Apply calibration offset ────────────────────────────────────────
    final calPitch = _filtPitch - _calPitch;
    final calRoll  = _filtRoll  - _calRoll;

    // ── 6. Dead zone ───────────────────────────────────────────────────────
    final dz = _settings.deadZone;
    double p = _applyDeadZone(calPitch, dz);
    double r = _applyDeadZone(calRoll,  dz);

    // ── 7. Low-pass filter (smooths remaining jitter) ──────────────────────
    _lpPitch += _lpAlpha * (p - _lpPitch);
    _lpRoll  += _lpAlpha * (r - _lpRoll);

    // ── 8. Sensitivity + normalise to [−1, +1] ─────────────────────────────
    final sens = _settings.sensitivity;
    p = (_lpPitch / _fullScale * sens).clamp(-1.0, 1.0);
    r = (_lpRoll  / _fullScale * sens).clamp(-1.0, 1.0);

    // ── 9. Sensor lock override ────────────────────────────────────────────
    if (_locked) {
      _pitchOut = 0.0;
      _rollOut  = 0.0;
    } else {
      _pitchOut = p;
      _rollOut  = r;
    }

    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  double _applyDeadZone(double deg, double dz) {
    if (deg.abs() < dz) return 0.0;
    // Rescale so output starts at 0 just outside the dead zone edge.
    return deg > 0 ? deg - dz : deg + dz;
  }

  void _onSettingsChanged() {
    // deadZone / sensitivity are read live on every event — nothing to do.
  }

  @override
  void dispose() {
    _gyroSub?.cancel();
    _accelSub?.cancel();
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
