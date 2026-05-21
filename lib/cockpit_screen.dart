// lib/cockpit_screen.dart
//
// The main full-screen cockpit UI.
//
// Layout (portrait):
//   ┌─────────────────────────────────┐
//   │  STATUS BAR (dot, IP, P/R/THR)  │  ~24 px
//   ├─────────────────────────────────┤
//   │  PTT  │  RUDDER SLIDER  │  LOCK │  ~56 px
//   ├─────────────────────────────────┤
//   │        ATTITUDE INDICATOR       │  flex
//   ├─────────────────────────────────┤
//   │ THROTTLE │  CONTROL BUTTONS     │  ~320 px
//   └─────────────────────────────────┘
//   ⚙ gear icon → settings panel slides up
//
// Captain layout: throttle LEFT, buttons RIGHT, PTT top-LEFT
// Co-Pilot layout: mirrored

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'main.dart';
import 'settings_model.dart';
import 'websocket_service.dart';
import 'sensor_service.dart';
import 'widgets/attitude_indicator.dart';
import 'widgets/throttle_slider.dart';
import 'widgets/rudder_slider.dart';
import 'widgets/settings_panel.dart';

class CockpitScreen extends StatefulWidget {
  const CockpitScreen({super.key});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> {
  // ── State ─────────────────────────────────────────────────────────────────
  double _throttle  = 0.0;
  double _rudder    = 0.0;

  // Button states (momentary or toggle)
  bool _toga      = false;
  bool _idle      = false;
  bool _reverse   = false;
  bool _gear      = false;
  bool _flapsUp   = false;
  bool _flapsDown = false;
  bool _btnA      = false;
  bool _btnB      = false;
  bool _btnX      = false;
  bool _btnY      = false;
  bool _ptt       = false;

  // Settings panel visibility
  bool _settingsOpen = false;

  // Extra button drag-edit mode
  bool _editMode = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final ws       = context.watch<WebSocketService>();
    final sensor   = context.watch<SensorService>();
    final isCaptain = settings.layout == CockpitLayout.captain;

    // Push latest axes to WS every build (driven by sensor notifyListeners)
    ws.updateAxes(
      pitch:    sensor.pitch,
      roll:     sensor.roll,
      throttle: _throttle,
      rudder:   _rudder,
    );

    final screenSize = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: kNavy,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main column ─────────────────────────────────────────────
            Column(
              children: [
                // 1. Status bar
                _StatusBar(ws: ws, sensor: sensor,
                  throttle: _throttle,
                  onSettingsTap: () => setState(() => _settingsOpen = true),
                ),

                // 2. Top row: PTT | Rudder | Lock
                _TopRow(
                  isCaptain:   isCaptain,
                  ptt:         _ptt,
                  onPttStart:  () => _setBtn('ptt', true),
                  onPttEnd:    () => _setBtn('ptt', false),
                  rudder:      _rudder,
                  onRudder:    (v) { setState(() => _rudder = v); _pushButtons(); },
                  sensorLocked: sensor.sensorLock,
                  onLockTap:   sensor.toggleLock,
                ),

                // 3. Attitude indicator — flex fill
                Expanded(
                  child: Center(
                    child: AttitudeIndicator(
                      pitch: sensor.pitch,
                      roll:  sensor.roll,
                      size:  (screenSize.width * 0.78).clamp(180, 300),
                    ),
                  ),
                ),

                // 4. Bottom row: throttle + buttons
                _BottomRow(
                  isCaptain:      isCaptain,
                  throttle:       _throttle,
                  detentsEnabled: settings.detentsEnabled,
                  onThrottle: (v) {
                    setState(() => _throttle = v);
                    _pushButtons();
                  },
                  toga:       _toga,
                  idle:       _idle,
                  reverse:    _reverse,
                  gear:       _gear,
                  flapsUp:    _flapsUp,
                  flapsDown:  _flapsDown,
                  onTogaTap:     () => _momentary('toga'),
                  onIdleTap:     () => _momentary('idle'),
                  onReverseTap:  () => _toggle('reverse'),
                  onGearTap:     () => _toggle('gear'),
                  onFlapsUpTap:  () => _momentary('flapsUp'),
                  onFlapsDownTap:() => _momentary('flapsDown'),
                ),

                const SizedBox(height: 4),
              ],
            ),

            // ── Draggable extra buttons ──────────────────────────────────
            if (settings.showA)
              _ExtraButton(
                label:     'A',
                active:    _btnA,
                editMode:  _editMode,
                posX:      settings.axPos * screenSize.width,
                posY:      settings.ayPos * screenSize.height,
                size:      settings.awSize,
                onTap:     () => _toggleExtra('a'),
                onMoved:   (x, y) => settings.setExtraAPos(
                  x / screenSize.width, y / screenSize.height),
                onResized: settings.setExtraASize,
                onLongPress: () => setState(() => _editMode = !_editMode),
              ),
            if (settings.showB)
              _ExtraButton(
                label:     'B',
                active:    _btnB,
                editMode:  _editMode,
                posX:      settings.bxPos * screenSize.width,
                posY:      settings.byPos * screenSize.height,
                size:      settings.bwSize,
                onTap:     () => _toggleExtra('b'),
                onMoved:   (x, y) => settings.setExtraBPos(
                  x / screenSize.width, y / screenSize.height),
                onResized: settings.setExtraBSize,
                onLongPress: () => setState(() => _editMode = !_editMode),
              ),
            if (settings.showX)
              _ExtraButton(
                label:     'X',
                active:    _btnX,
                editMode:  _editMode,
                posX:      settings.xxPos * screenSize.width,
                posY:      settings.xyPos * screenSize.height,
                size:      settings.xwSize,
                onTap:     () => _toggleExtra('x'),
                onMoved:   (x, y) => settings.setExtraXPos(
                  x / screenSize.width, y / screenSize.height),
                onResized: settings.setExtraXSize,
                onLongPress: () => setState(() => _editMode = !_editMode),
              ),
            if (settings.showY)
              _ExtraButton(
                label:     'Y',
                active:    _btnY,
                editMode:  _editMode,
                posX:      settings.yxPos * screenSize.width,
                posY:      settings.yyPos * screenSize.height,
                size:      settings.ywSize,
                onTap:     () => _toggleExtra('y'),
                onMoved:   (x, y) => settings.setExtraYPos(
                  x / screenSize.width, y / screenSize.height),
                onResized: settings.setExtraYSize,
                onLongPress: () => setState(() => _editMode = !_editMode),
              ),

            // ── Settings overlay ─────────────────────────────────────────
            if (_settingsOpen)
              Positioned.fill(
                child: SettingsPanel(
                  onClose: () => setState(() => _settingsOpen = false),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ── Button helpers ────────────────────────────────────────────────────────

  void _setBtn(String name, bool v) {
    setState(() {
      switch (name) {
        case 'ptt': _ptt = v;
      }
    });
    context.read<WebSocketService>().setButton(name, v);
  }

  /// Momentary: fires true for 120 ms, then false
  void _momentary(String name) {
    final ws = context.read<WebSocketService>();
    ws.setButton(name, true);
    setState(() => _setStateBtn(name, true));
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      ws.setButton(name, false);
      setState(() => _setStateBtn(name, false));
    });
  }

  /// Toggle: flips current state
  void _toggle(String name) {
    final ws = context.read<WebSocketService>();
    final next = !_getStateBtn(name);
    ws.setButton(name, next);
    setState(() => _setStateBtn(name, next));
  }

  void _toggleExtra(String name) {
    final ws   = context.read<WebSocketService>();
    final next = !_getStateBtn(name);
    ws.setButton(name, next);
    setState(() => _setStateBtn(name, next));
  }

  bool _getStateBtn(String name) => switch (name) {
    'toga'      => _toga,
    'idle'      => _idle,
    'reverse'   => _reverse,
    'gear'      => _gear,
    'flapsUp'   => _flapsUp,
    'flapsDown' => _flapsDown,
    'a'         => _btnA,
    'b'         => _btnB,
    'x'         => _btnX,
    'y'         => _btnY,
    _           => false,
  };

  void _setStateBtn(String name, bool v) {
    switch (name) {
      case 'toga':      _toga      = v;
      case 'idle':      _idle      = v;
      case 'reverse':   _reverse   = v;
      case 'gear':      _gear      = v;
      case 'flapsUp':   _flapsUp   = v;
      case 'flapsDown': _flapsDown = v;
      case 'a':         _btnA      = v;
      case 'b':         _btnB      = v;
      case 'x':         _btnX      = v;
      case 'y':         _btnY      = v;
    }
  }

  void _pushButtons() {
    // Axes are pushed continuously by the WS timer; buttons are pushed here
    // to ensure immediate responsiveness on button state changes.
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Bar
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.ws,
    required this.sensor,
    required this.throttle,
    required this.onSettingsTap,
  });

  final WebSocketService ws;
  final SensorService    sensor;
  final double           throttle;
  final VoidCallback     onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final connected = ws.state == WsState.connected;

    return Container(
      height: 26,
      color:  const Color(0xFF090F18),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // Connection dot
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected ? kGreen : kRed,
              boxShadow: [
                BoxShadow(
                  color:      connected ? kGreen : kRed,
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(settings.ip,
            style: const TextStyle(color: kDim, fontSize: 10, fontFamily: 'monospace')),
          const Spacer(),
          _statLabel('P', sensor.pitch),
          const SizedBox(width: 8),
          _statLabel('R', sensor.roll),
          const SizedBox(width: 8),
          Text(
            'THR ${(throttle * 100).round()}%',
            style: const TextStyle(color: kAmber, fontSize: 10, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onSettingsTap,
            child: const Icon(Icons.settings, color: kDim, size: 16),
          ),
        ],
      ),
    );
  }

  Widget _statLabel(String tag, double v) => Text(
    '$tag ${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}',
    style: const TextStyle(color: kText, fontSize: 10, fontFamily: 'monospace'),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Row: PTT | Rudder | Sensor Lock
// ─────────────────────────────────────────────────────────────────────────────
class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.isCaptain,
    required this.ptt,
    required this.onPttStart,
    required this.onPttEnd,
    required this.rudder,
    required this.onRudder,
    required this.sensorLocked,
    required this.onLockTap,
  });

  final bool       isCaptain;
  final bool       ptt;
  final VoidCallback onPttStart;
  final VoidCallback onPttEnd;
  final double     rudder;
  final ValueChanged<double> onRudder;
  final bool       sensorLocked;
  final VoidCallback onLockTap;

  @override
  Widget build(BuildContext context) {
    final pttWidget  = _PttButton(active: ptt, onStart: onPttStart, onEnd: onPttEnd);
    final lockWidget = _LockButton(locked: sensorLocked, onTap: onLockTap);
    final rudderWidget = Expanded(
      child: Center(
        child: RudderSlider(
          value: rudder,
          onChanged: onRudder,
          width: double.infinity,
          height: 52,
        ),
      ),
    );

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: isCaptain
            ? [pttWidget, const SizedBox(width: 8), rudderWidget, const SizedBox(width: 8), lockWidget]
            : [lockWidget, const SizedBox(width: 8), rudderWidget, const SizedBox(width: 8), pttWidget],
      ),
    );
  }
}

// ── PTT Button ────────────────────────────────────────────────────────────────
class _PttButton extends StatelessWidget {
  const _PttButton({
    required this.active,
    required this.onStart,
    required this.onEnd,
  });

  final bool active;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onStart(),
      onLongPressEnd:   (_) => onEnd(),
      onTapDown:        (_) => onStart(),
      onTapUp:          (_) => onEnd(),
      onTapCancel:      ()  => onEnd(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width:  52,
        height: 44,
        decoration: BoxDecoration(
          color:        active ? kAmber : kNavy2,
          borderRadius: BorderRadius.circular(10),
          border:       Border.all(
            color: active ? kAmber : kDim,
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [BoxShadow(color: kAmber.withOpacity(0.6), blurRadius: 12)]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.mic,
              size:  20,
              color: active ? kNavy : kAmber,
            ),
            if (active)
              const Text(
                'TX',
                style: TextStyle(
                  color:    kNavy,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Sensor Lock Button ────────────────────────────────────────────────────────
class _LockButton extends StatelessWidget {
  const _LockButton({required this.locked, required this.onTap});
  final bool         locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width:  44,
        height: 44,
        decoration: BoxDecoration(
          color:        locked ? kAmber.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: locked ? kAmber : kDim,
            width: locked ? 2 : 1,
          ),
        ),
        child: Icon(
          locked ? Icons.lock : Icons.lock_open,
          color: locked ? kAmber : kDim,
          size:  22,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Row: Throttle + Control Buttons
// ─────────────────────────────────────────────────────────────────────────────
class _BottomRow extends StatelessWidget {
  const _BottomRow({
    required this.isCaptain,
    required this.throttle,
    required this.detentsEnabled,
    required this.onThrottle,
    required this.toga,
    required this.idle,
    required this.reverse,
    required this.gear,
    required this.flapsUp,
    required this.flapsDown,
    required this.onTogaTap,
    required this.onIdleTap,
    required this.onReverseTap,
    required this.onGearTap,
    required this.onFlapsUpTap,
    required this.onFlapsDownTap,
  });

  final bool   isCaptain;
  final double throttle;
  final bool   detentsEnabled;
  final ValueChanged<double> onThrottle;
  final bool toga, idle, reverse, gear, flapsUp, flapsDown;
  final VoidCallback onTogaTap, onIdleTap, onReverseTap,
                     onGearTap, onFlapsUpTap, onFlapsDownTap;

  @override
  Widget build(BuildContext context) {
    final throttleWidget = SizedBox(
      width: 70,
      child: ThrottleSlider(
        value:          throttle,
        onChanged:      onThrottle,
        detentsEnabled: detentsEnabled,
        height:         300,
        width:          70,
      ),
    );

    final buttonsWidget = Expanded(
      child: _ControlButtons(
        toga:           toga,
        idle:           idle,
        reverse:        reverse,
        gear:           gear,
        flapsUp:        flapsUp,
        flapsDown:      flapsDown,
        onTogaTap:      onTogaTap,
        onIdleTap:      onIdleTap,
        onReverseTap:   onReverseTap,
        onGearTap:      onGearTap,
        onFlapsUpTap:   onFlapsUpTap,
        onFlapsDownTap: onFlapsDownTap,
      ),
    );

    return SizedBox(
      height: 310,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: isCaptain
              ? [throttleWidget, const SizedBox(width: 12), buttonsWidget]
              : [buttonsWidget,  const SizedBox(width: 12), throttleWidget],
        ),
      ),
    );
  }
}

// ── Control Buttons Column ────────────────────────────────────────────────────
class _ControlButtons extends StatelessWidget {
  const _ControlButtons({
    required this.toga,
    required this.idle,
    required this.reverse,
    required this.gear,
    required this.flapsUp,
    required this.flapsDown,
    required this.onTogaTap,
    required this.onIdleTap,
    required this.onReverseTap,
    required this.onGearTap,
    required this.onFlapsUpTap,
    required this.onFlapsDownTap,
  });

  final bool toga, idle, reverse, gear, flapsUp, flapsDown;
  final VoidCallback onTogaTap, onIdleTap, onReverseTap,
                     onGearTap, onFlapsUpTap, onFlapsDownTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Row(
          children: [
            Expanded(child: _CtrlBtn(label: 'TOGA',    active: toga,    color: kAmber,  onTap: onTogaTap)),
            const SizedBox(width: 6),
            Expanded(child: _CtrlBtn(label: 'IDLE',    active: idle,    color: kDim,    onTap: onIdleTap)),
          ],
        ),
        Row(
          children: [
            Expanded(child: _CtrlBtn(label: 'REV',     active: reverse, color: kRed,    onTap: onReverseTap)),
            const SizedBox(width: 6),
            Expanded(child: _CtrlBtn(label: 'GEAR',    active: gear,    color: kGreen,  onTap: onGearTap)),
          ],
        ),
        Row(
          children: [
            Expanded(child: _CtrlBtn(label: 'FLAPS ▲', active: flapsUp,   color: kAmber, onTap: onFlapsUpTap)),
            const SizedBox(width: 6),
            Expanded(child: _CtrlBtn(label: 'FLAPS ▼', active: flapsDown, color: kAmber, onTap: onFlapsDownTap)),
          ],
        ),
      ],
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  const _CtrlBtn({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  final String     label;
  final bool       active;
  final Color      color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        height: 56,
        decoration: BoxDecoration(
          color:        active ? color.withOpacity(0.25) : kNavy2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color : kDim,
            width: active ? 2 : 1,
          ),
          boxShadow: active
              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8)]
              : [],
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color:      active ? color : kDim,
              fontSize:   12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Draggable / resizable extra button overlay
// ─────────────────────────────────────────────────────────────────────────────
class _ExtraButton extends StatefulWidget {
  const _ExtraButton({
    required this.label,
    required this.active,
    required this.editMode,
    required this.posX,
    required this.posY,
    required this.size,
    required this.onTap,
    required this.onMoved,
    required this.onResized,
    required this.onLongPress,
  });

  final String   label;
  final bool     active;
  final bool     editMode;
  final double   posX, posY, size;
  final VoidCallback  onTap;
  final void Function(double x, double y) onMoved;
  final void Function(double w) onResized;
  final VoidCallback onLongPress;

  @override
  State<_ExtraButton> createState() => _ExtraButtonState();
}

class _ExtraButtonState extends State<_ExtraButton> {
  double _x = 0, _y = 0, _sz = 60;
  double _startScale = 1.0;
  double _startSize  = 60.0;

  @override
  void initState() {
    super.initState();
    _x  = widget.posX;
    _y  = widget.posY;
    _sz = widget.size;
  }

  @override
  void didUpdateWidget(_ExtraButton old) {
    super.didUpdateWidget(old);
    if (!widget.editMode) {
      _x  = widget.posX;
      _y  = widget.posY;
      _sz = widget.size;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _x - _sz / 2,
      top:  _y - _sz / 2,
      child: GestureDetector(
        onTap: widget.editMode ? null : widget.onTap,
        onLongPress: widget.onLongPress,
        onPanUpdate: widget.editMode ? (d) {
          setState(() {
            _x += d.delta.dx;
            _y += d.delta.dy;
          });
          widget.onMoved(_x, _y);
        } : null,
        onScaleStart: widget.editMode ? (d) {
          _startScale = 1.0;
          _startSize  = _sz;
        } : null,
        onScaleUpdate: widget.editMode ? (d) {
          setState(() {
            _sz = (_startSize * d.scale).clamp(36.0, 120.0);
          });
          widget.onResized(_sz);
        } : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width:  _sz,
          height: _sz,
          decoration: BoxDecoration(
            color: widget.active
                ? kAmber.withOpacity(0.25)
                : kNavy2.withOpacity(0.9),
            borderRadius: BorderRadius.circular(_sz * 0.2),
            border: Border.all(
              color: widget.editMode
                  ? Colors.white
                  : widget.active ? kAmber : kDim,
              width: 2,
            ),
            boxShadow: widget.editMode
                ? [const BoxShadow(color: Colors.white30, blurRadius: 12)]
                : widget.active
                    ? [BoxShadow(color: kAmber.withOpacity(0.4), blurRadius: 8)]
                    : [],
          ),
          child: Center(
            child: Text(
              widget.label,
              style: TextStyle(
                color:      widget.editMode ? Colors.white : widget.active ? kAmber : kDim,
                fontSize:   _sz * 0.32,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
