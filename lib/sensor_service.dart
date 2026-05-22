// lib/sensor_service.dart  —  v2.2.0
//
// Fix 1 changes:
//   • _lpAlpha  : 0.15 → 0.85  (less smoothing, faster response)
//   • _cfAlpha  : 0.96 → 0.85  (less gyro weight, less drift accumulation)
//   • Sensor processing moved to a dedicated background Isolate so the
//     complementary-filter maths never blocks the main/UI thread.
//   • samplingPeriod changed to SensorInterval.uiInterval (~60 Hz) on both
//     streams to match the new 16 ms WS send rate.
//   • No additional throttling anywhere in the pipeline.
//
// Isolate design:
//   Main isolate  → subscribes to platform sensor streams (required — platform
//                   channels cannot be used off main isolate).
//   Main isolate  → forwards raw {ax,ay,az,gx,gy,dt,dz,sens} to background
//                   isolate via SendPort on every gyro event.
//   Background    → runs all maths (complementary filter, dead zone, LPF,
//                   normalisation) and sends {pitch,roll} back via SendPort.
//   Main isolate  → receives result, applies sensor-lock override, notifies.

import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'settings_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Background isolate entry point — MUST be a top-level function.
// Receives Map messages from main, returns Map results.
// ─────────────────────────────────────────────────────────────────────────────
void _sensorProcessingIsolate(SendPort toMain) {
  final fromMain = ReceivePort();
  // First thing: send our ReceivePort's SendPort back so main can reach us.
  toMain.send(fromMain.sendPort);

  // ── Filter state (lives entirely inside this isolate) ────────────────────
  double _filtPitch = 0.0, _filtRoll  = 0.0;
  double _lpPitch   = 0.0, _lpRoll    = 0.0;
  double _calPitch  = 0.0, _calRoll   = 0.0;

  // Tuned constants
  const double cfAlpha   = 0.85;   // complementary filter — gyro weight
  const double lpAlpha   = 0.85;   // low-pass filter — higher = faster
  const double fullScale = 60.0;   // ±60 ° → ±1.0
  const double rad2deg   = 180.0 / math.pi;

  fromMain.listen((dynamic msg) {
    if (msg is! Map) return;

    switch (msg['cmd'] as String) {

      // Calibrate: snapshot current filtered angles as new zero reference.
      case 'calibrate':
        _calPitch = _filtPitch;
        _calRoll  = _filtRoll;
        return;

      // Reset: called on dispose / re-subscribe.
      case 'reset':
        _filtPitch = _filtRoll = _lpPitch = _lpRoll = _calPitch = _calRoll = 0.0;
        return;

      // Process: main sensor event → run full pipeline → return pitch+roll.
      case 'process':
        final ax   = (msg['ax']   as num).toDouble();
        final ay   = (msg['ay']   as num).toDouble();
        final az   = (msg['az']   as num).toDouble();
        final gx   = (msg['gx']   as num).toDouble();
        final gy   = (msg['gy']   as num).toDouble();
        final dt   = (msg['dt']   as num).toDouble();
        final dz   = (msg['dz']   as num).toDouble();
        final sens = (msg['sens'] as num).toDouble();

        // 1. Gyroscope integration (rad/s → degrees)
        final gyroPitchDeg = gx * dt * rad2deg;
        final gyroRollDeg  = gy * dt * rad2deg;

        // 2. Accelerometer absolute tilt
        final accelPitch = math.atan2(ay, az) * rad2deg;
        final accelRoll  = math.atan2(
          -ax,
          math.sqrt(ay * ay + az * az),
        ) * rad2deg;

        // 3. Complementary filter
        _filtPitch = cfAlpha * (_filtPitch + gyroPitchDeg) +
                    (1.0 - cfAlpha) * accelPitch;
        _filtRoll  = cfAlpha * (_filtRoll  + gyroRollDeg)  +
                    (1.0 - cfAlpha) * accelRoll;

        // 4. Calibration offset
        final calP = _filtPitch - _calPitch;
        final calR = _filtRoll  - _calRoll;

        // 5. Dead zone
        double p = calP.abs() < dz ? 0.0 : (calP > 0 ? calP - dz : calP + dz);
        double r = calR.abs() < dz ? 0.0 : (calR > 0 ? calR - dz : calR + dz);

        // 6. Low-pass filter
        _lpPitch += lpAlpha * (p - _lpPitch);
        _lpRoll  += lpAlpha * (r - _lpRoll);

        // 7. Sensitivity + normalise to [−1, +1]
        p = (_lpPitch / fullScale * sens).clamp(-1.0, 1.0);
        r = (_lpRoll  / fullScale * sens).clamp(-1.0, 1.0);

        toMain.send({'pitch': p, 'roll': r});
        return;
    }
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// SensorService
// ─────────────────────────────────────────────────────────────────────────────
class SensorService extends ChangeNotifier {
  SensorService(this._settings) {
    _settings.addListener(_onSettingsChanged);
    _initIsolate();
  }

  final SettingsModel _settings;

  // ── Public outputs ────────────────────────────────────────────────────────
  double get pitch      => _pitchOut;
  double get roll       => _rollOut;
  bool   get sensorLock => _locked;

  double _pitchOut = 0.0;
  double _rollOut  = 0.0;

  // ── Sensor lock (handled on main isolate — no maths needed) ──────────────
  bool _locked = false;

  void toggleLock() {
    _locked = !_locked;
    if (_locked) { _pitchOut = 0.0; _rollOut = 0.0; }
    notifyListeners();
  }

  // ── Calibrate: send command to background isolate ─────────────────────────
  void calibrate() {
    _toBackground?.send({'cmd': 'calibrate'});
    notifyListeners();
  }

  // ── Isolate handles ───────────────────────────────────────────────────────
  Isolate?   _isolate;
  SendPort?  _toBackground;          // main → background
  ReceivePort? _fromBackground;      // background → main

  // ── Sensor subscriptions (main isolate only) ──────────────────────────────
  StreamSubscription<GyroscopeEvent>?     _gyroSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  // Latest raw accel values — updated by accel stream, read in gyro callback
  double _ax = 0.0, _ay = 0.0, _az = 9.8;

  // Timing for dt calculation
  DateTime? _lastGyroTime;

  // ── Isolate init ──────────────────────────────────────────────────────────
  Future<void> _initIsolate() async {
    _fromBackground = ReceivePort();

    // Spawn background processing isolate
    _isolate = await Isolate.spawn(
      _sensorProcessingIsolate,
      _fromBackground!.sendPort,
      debugName: 'sensor_processing',
    );

    // First message back is the background's SendPort
    _fromBackground!.listen((dynamic msg) {
      if (msg is SendPort) {
        // Handshake complete — background is ready
        _toBackground = msg;
        _subscribe();   // start sensor streams only after isolate is ready
        return;
      }

      // All subsequent messages are {pitch, roll} result maps
      if (msg is Map) {
        final p = (msg['pitch'] as num).toDouble();
        final r = (msg['roll']  as num).toDouble();

        if (_locked) {
          _pitchOut = 0.0;
          _rollOut  = 0.0;
        } else {
          _pitchOut = p;
          _rollOut  = r;
        }
        notifyListeners();
      }
    });
  }

  // ── Sensor streams ────────────────────────────────────────────────────────
  void _subscribe() {
    // Accelerometer: store latest values for use in gyro callback
    _accelSub = accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,   // ~60 Hz
    ).listen(
      (AccelerometerEvent e) { _ax = e.x; _ay = e.y; _az = e.z; },
      onError:       (_) {},
      cancelOnError: false,
    );

    // Gyroscope: drives the processing pipeline
    _gyroSub = gyroscopeEventStream(
      samplingPeriod: SensorInterval.uiInterval,   // ~60 Hz
    ).listen(
      _onGyroEvent,
      onError:       (_) {},
      cancelOnError: false,
    );
  }

  void _onGyroEvent(GyroscopeEvent e) {
    if (_toBackground == null) return;   // isolate not ready yet

    // Compute dt
    final now = DateTime.now();
    final dt  = _lastGyroTime == null
        ? 0.016   // first tick — assume 60 Hz
        : now.difference(_lastGyroTime!).inMicroseconds / 1e6;
    _lastGyroTime = now;

    // Send raw data to background isolate — no processing on main thread
    _toBackground!.send({
      'cmd':  'process',
      'ax':   _ax,
      'ay':   _ay,
      'az':   _az,
      'gx':   e.x,
      'gy':   e.y,
      'dt':   dt.clamp(0.001, 0.1),
      'dz':   _settings.deadZone,
      'sens': _settings.sensitivity,
    });
  }

  void _onSettingsChanged() {
    // deadZone and sensitivity are passed with every 'process' message live —
    // no action needed here.
  }

  @override
  void dispose() {
    _toBackground?.send({'cmd': 'reset'});
    _gyroSub?.cancel();
    _accelSub?.cancel();
    _fromBackground?.close();
    _isolate?.kill(priority: Isolate.immediate);
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
