// lib/websocket_service.dart
//
// Manages the WebSocket connection to the PC flight-sim server.
//   • Connects to ws://[IP]:8888
//   • Sends a full JSON frame every 50 ms
//   • Auto-reconnects every 3 s on disconnect / error
//
// BUG FIX — connection state accuracy:
//   Previous code set state=connected after a 300 ms blind delay, so the
//   green dot appeared even when no server was reachable.
//   Fix: await channel.ready — a Future that resolves only after the TCP +
//   WebSocket handshake completes, and rejects immediately on any failure.
//   State transitions are therefore driven by real socket events:
//     disconnected → connecting  (attempt started)
//     connecting   → connected   (channel.ready resolved)
//     connecting   → disconnected (channel.ready rejected / stream error)
//     connected    → disconnected (stream done / send error)

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'settings_model.dart';

enum WsState { disconnected, connecting, connected }

class WebSocketService extends ChangeNotifier {
  WebSocketService(this._settings) {
    _settings.addListener(_onSettingsChanged);
    _connect();
  }

  final SettingsModel _settings;

  // ── Public state ──────────────────────────────────────────────────────────
  WsState _state = WsState.disconnected;
  WsState get state => _state;

  String get statusLabel => switch (_state) {
    WsState.connected    => 'CONNECTED',
    WsState.connecting   => 'CONNECTING…',
    WsState.disconnected => 'DISCONNECTED',
  };

  // ── Flight data (written by cockpit screen, read by send loop) ────────────
  double _pitch = 0.0, _roll = 0.0, _thr = 0.0, _rud = 0.0;

  bool _toga = false, _idle = false, _reverse = false, _gear = false;
  bool _flapsUp = false, _flapsDown = false;
  bool _btnA = false, _btnB = false, _btnX = false, _btnY = false;
  bool _ptt = false;

  // ── Internal ──────────────────────────────────────────────────────────────
  WebSocketChannel? _channel;
  Timer?            _sendTimer;
  Timer?            _reconnectTimer;
  bool              _disposed = false;

  // Tracks the active connection attempt so a stale attempt cannot
  // transition state after a newer attempt has already started.
  int _attemptId = 0;

  // ── Public API ────────────────────────────────────────────────────────────
  void updateAxes({
    required double pitch,
    required double roll,
    required double throttle,
    required double rudder,
  }) {
    _pitch = pitch;
    _roll  = roll;
    _thr   = throttle;
    _rud   = rudder;
  }

  void setButton(String name, bool value) {
    switch (name) {
      case 'toga':      _toga      = value;
      case 'idle':      _idle      = value;
      case 'reverse':   _reverse   = value;
      case 'gear':      _gear      = value;
      case 'flapsUp':   _flapsUp   = value;
      case 'flapsDown': _flapsDown = value;
      case 'a':         _btnA      = value;
      case 'b':         _btnB      = value;
      case 'x':         _btnX      = value;
      case 'y':         _btnY      = value;
      case 'ptt':       _ptt       = value;
    }
  }

  // ── Connection lifecycle ──────────────────────────────────────────────────
  void _connect() {
    if (_disposed) return;

    // Cancel any pending reconnect timer from a previous attempt.
    _reconnectTimer?.cancel();

    // Close any existing channel without triggering another reconnect cycle.
    _channel?.sink.close(ws_status.goingAway);
    _channel = null;
    _stopSendLoop();

    _state = WsState.connecting;
    notifyListeners();

    // Stamp this attempt; callbacks check the stamp so stale attempts
    // that complete after a newer attempt started are silently discarded.
    final attempt = ++_attemptId;

    final uri = Uri.parse('ws://${_settings.ip}:8888');

    late WebSocketChannel ch;
    try {
      ch = WebSocketChannel.connect(uri);
    } catch (_) {
      // Synchronous construction failure (e.g. bad URI).
      if (!_disposed && attempt == _attemptId) _handleDisconnect();
      return;
    }

    _channel = ch;

    // ── Await the real TCP + WebSocket handshake ──────────────────────────
    // channel.ready resolves when the handshake is complete,
    // rejects (throws) when the connection is refused / unreachable.
    ch.ready.then((_) {
      if (_disposed || attempt != _attemptId) return;
      // Handshake succeeded → mark connected and start sending.
      _state = WsState.connected;
      notifyListeners();
      _startSendLoop();
    }).catchError((_) {
      // Handshake failed (refused, timeout, unreachable).
      if (_disposed || attempt != _attemptId) return;
      _handleDisconnect();
    });

    // ── Listen for incoming data / stream close ───────────────────────────
    ch.stream.listen(
      (_) {}, // server acks — ignored
      onError: (_) {
        if (!_disposed && attempt == _attemptId) _handleDisconnect();
      },
      onDone: () {
        if (!_disposed && attempt == _attemptId) _handleDisconnect();
      },
      cancelOnError: false,
    );
  }

  void _handleDisconnect() {
    if (_disposed) return;
    _stopSendLoop();
    _channel = null;
    _setState(WsState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      const Duration(seconds: 3),
      () { if (!_disposed) _connect(); },
    );
  }

  void _setState(WsState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  // ── Send loop — 50 ms ────────────────────────────────────────────────────
  void _startSendLoop() {
    _sendTimer?.cancel();
    _sendTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => _sendFrame(),
    );
  }

  void _stopSendLoop() {
    _sendTimer?.cancel();
    _sendTimer = null;
  }

  void _sendFrame() {
    if (_channel == null || _state != WsState.connected) return;
    final frame = {
      'pitch': _clamp1(_pitch),
      'roll':  _clamp1(_roll),
      'thr':   _clamp01(_thr),
      'rud':   _clamp1(_rud),
      'buttons': {
        'toga':      _toga,
        'idle':      _idle,
        'reverse':   _reverse,
        'gear':      _gear,
        'flapsUp':   _flapsUp,
        'flapsDown': _flapsDown,
        'a':         _btnA,
        'b':         _btnB,
        'x':         _btnX,
        'y':         _btnY,
        'ptt':       _ptt,
      },
    };
    try {
      _channel!.sink.add(jsonEncode(frame));
    } catch (_) {
      _handleDisconnect();
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  double _clamp1(double v)  => v.clamp(-1.0, 1.0);
  double _clamp01(double v) => v.clamp(0.0,  1.0);

  void _onSettingsChanged() {
    // IP changed — reconnect immediately regardless of current state.
    _connect();
  }

  /// Called from settings panel reconnect button or after IP is applied.
  void reconnectNow() => _connect();

  @override
  void dispose() {
    _disposed = true;
    _settings.removeListener(_onSettingsChanged);
    _stopSendLoop();
    _reconnectTimer?.cancel();
    _channel?.sink.close(ws_status.goingAway);
    super.dispose();
  }
}
