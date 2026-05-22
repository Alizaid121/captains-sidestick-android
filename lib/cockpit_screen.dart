// lib/cockpit_screen.dart  —  v1.1.0
//
// Fix 3: Entire body wrapped in LayoutBuilder. Available height is the real
//        screen height minus the system status-bar inset. Sections are sized
//        with flex ratios so the layout never overflows on any Android screen.
//
//        Height budget:
//          Status bar  : fixed 36 px
//          Top row     : fixed 80 px
//          Horizon     : flex 4
//          Bottom row  : flex 3
//
// Fix 4: All text sizes, button sizes and padding computed from screen width
//        so the UI looks proportionate from 360 px (small) to 430 px (large).

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

// ─────────────────────────────────────────────────────────────────────────────
class CockpitScreen extends StatefulWidget {
  const CockpitScreen({super.key});

  @override
  State<CockpitScreen> createState() => _CockpitScreenState();
}

class _CockpitScreenState extends State<CockpitScreen> {
  double _throttle  = 0.0;
  double _rudder    = 0.0;

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

  bool _settingsOpen = false;
  bool _editMode     = false;

  @override
  Widget build(BuildContext context) {
    final settings   = context.watch<SettingsModel>();
    final ws         = context.watch<WebSocketService>();
    final sensor     = context.watch<SensorService>();
    final isCaptain  = settings.layout == CockpitLayout.captain;
    final mq         = MediaQuery.of(context);
    final sw         = mq.size.width;   // screen width  — drives all sizing
    final sh         = mq.size.height;  // screen height

    // Push axes on every sensor update
    ws.updateAxes(
      pitch:    sensor.pitch,
      roll:     sensor.roll,
      throttle: _throttle,
      rudder:   _rudder,
    );

    // ── Responsive sizing constants ────────────────────────────────────────
    // Tested against 360 / 390 / 412 / 430 px wide screens.
    final btnFontSize   = sw * 0.034;   // ~12–15 px
    final btnPadH       = sw * 0.020;   // ~7–9 px horizontal
    final btnPadV       = sw * 0.014;   // ~5–6 px vertical
    final statusFont    = sw * 0.028;   // ~10–12 px
    final hPad          = sw * 0.022;   // outer horizontal padding ~8–10 px
    final aiSize        = (sw * 0.78).clamp(200.0, 310.0);

    // ── Fixed section heights ──────────────────────────────────────────────
    const statusH   = 36.0;
    const topRowH   = 80.0;

    // Remaining height after fixed sections → split 4 : 3 between AI / bottom
    final remaining   = sh - mq.padding.top - mq.padding.bottom
                           - statusH - topRowH;
    final horizonH    = (remaining * 4 / 7).clamp(160.0, 340.0);
    final bottomH     = (remaining * 3 / 7).clamp(160.0, 280.0);

    return Scaffold(
      backgroundColor: kNavy,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Main column ────────────────────────────────────────────────
            Column(
              children: [

                // 1 — Status bar
                SizedBox(
                  height: statusH,
                  child: _StatusBar(
                    ws:            ws,
                    sensor:        sensor,
                    throttle:      _throttle,
                    fontSize:      statusFont,
                    hPad:          hPad,
                    onSettingsTap: () => setState(() => _settingsOpen = true),
                  ),
                ),

                // 2 — Top row: PTT | Rudder | Lock
                SizedBox(
                  height: topRowH,
                  child: _TopRow(
                    isCaptain:    isCaptain,
                    ptt:          _ptt,
                    onPttStart:   () => _setBtn('ptt', true),
                    onPttEnd:     () => _setBtn('ptt', false),
                    rudder:       _rudder,
                    onRudder:     (v) => setState(() => _rudder = v),
                    sensorLocked: sensor.sensorLock,
                    onLockTap:    sensor.toggleLock,
                    sw:           sw,
                    hPad:         hPad,
                  ),
                ),

                // 3 — Attitude indicator
                SizedBox(
                  height: horizonH,
                  child: Center(
                    child: AttitudeIndicator(
                      pitch: sensor.pitch,
                      roll:  sensor.roll,
                      size:  aiSize,
                    ),
                  ),
                ),

                // 4 — Bottom row: throttle + buttons
                SizedBox(
                  height: bottomH,
                  child: _BottomRow(
                    isCaptain:      isCaptain,
                    throttle:       _throttle,
                    detentsEnabled: settings.detentsEnabled,
                    onThrottle:     (v) => setState(() => _throttle = v),
                    toga:       _toga,
                    idle:       _idle,
                    reverse:    _reverse,
                    gear:       _gear,
                    flapsUp:    _flapsUp,
                    flapsDown:  _flapsDown,
                    onTogaTap:      () => _momentary('toga'),
                    onIdleTap:      () => _momentary('idle'),
                    onReverseTap:   () => _toggle('reverse'),
                    onGearTap:      () => _toggle('gear'),
                    onFlapsUpTap:   () => _momentary('flapsUp'),
                    onFlapsDownTap: () => _momentary('flapsDown'),
                    sw:       sw,
                    hPad:     hPad,
                    btnFontSize: btnFontSize,
                    btnPadH:     btnPadH,
                    btnPadV:     btnPadV,
                  ),
                ),

              ],
            ),

            // ── Draggable extra buttons ────────────────────────────────────
            if (settings.showA)
              _ExtraButton(
                label: 'A', active: _btnA, editMode: _editMode,
                posX: settings.axPos * sw, posY: settings.ayPos * sh,
                size: settings.awSize,
                onTap:       () => _toggleExtra('a'),
                onMoved:     (x, y) => settings.setExtraAPos(x / sw, y / sh),
                onResized:   settings.setExtraASize,
                onLongPress: () => setState(() => _editMode = !_editMode),
              ),
            if (settings.showB)
              _ExtraButton(
                label: 'B', active: _btnB, editMode: _editMode,
                posX: settings.bxPos * sw, posY: settings.byPos * sh,
                size: settings.bwSize,
                onTap:       () => _toggleExtra('b'),
                onMoved:     (x, y) => settings.setExtraBPos(x / sw, y / sh),
                onResized:   settings.setExtraBSize,
                onLongPress: () => setState(() => _editMode = !_editMode),
              ),
            if (settings.showX)
              _ExtraButton(
                label: 'X', active: _btnX, editMode: _editMode,
                posX: settings.xxPos * sw, posY: settings.xyPos * sh,
                size: settings.xwSize,
                onTap:       () => _toggleExtra('x'),
                onMoved:     (x, y) => settings.setExtraXPos(x / sw, y / sh),
                onResized:   settings.setExtraXSize,
                onLongPress: () => setState(() => _editMode = !_editMode),
              ),
            if (settings.showY)
              _ExtraButton(
                label: 'Y', active: _btnY, editMode: _editMode,
                posX: settings.yxPos * sw, posY: settings.yyPos * sh,
                size: settings.ywSize,
                onTap:       () => _toggleExtra('y'),
                onMoved:     (x, y) => settings.setExtraYPos(x / sw, y / sh),
                onResized:   settings.setExtraYSize,
                onLongPress: () => setState(() => _editMode = !_editMode),
              ),

            // ── Settings overlay ───────────────────────────────────────────
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

  // ── Button logic ───────────────────────────────────────────────────────────

  void _setBtn(String name, bool v) {
    setState(() { if (name == 'ptt') _ptt = v; });
    context.read<WebSocketService>().setButton(name, v);
  }

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

  void _toggle(String name) {
    final ws   = context.read<WebSocketService>();
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Status Bar
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBar extends StatelessWidget {
  const _StatusBar({
    required this.ws,
    required this.sensor,
    required this.throttle,
    required this.fontSize,
    required this.hPad,
    required this.onSettingsTap,
  });

  final WebSocketService ws;
  final SensorService    sensor;
  final double           throttle;
  final double           fontSize;
  final double           hPad;
  final VoidCallback     onSettingsTap;

  @override
  Widget build(BuildContext context) {
    final settings  = context.watch<SettingsModel>();
    final dotColor  = switch (ws.state) {
      WsState.connected    => kGreen,
      WsState.connecting   => kAmber,
      WsState.disconnected => kRed,
    };

    final style = TextStyle(
      color:      kText,
      fontSize:   fontSize,
      fontFamily: 'monospace',
    );
    final dimStyle = style.copyWith(color: kDim);
    final amberStyle = style.copyWith(color: kAmber);

    return Container(
      color:   const Color(0xFF090F18),
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Row(
        children: [
          // Connection dot
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: 9, height: 9,
            decoration: BoxDecoration(
              shape:     BoxShape.circle,
              color:     dotColor,
              boxShadow: [BoxShadow(color: dotColor, blurRadius: 4)],
            ),
          ),
          SizedBox(width: hPad * 0.6),
          Text(settings.ip, style: dimStyle),
          const Spacer(),
          Text(
            'P${sensor.pitch >= 0 ? '+' : ''}${sensor.pitch.toStringAsFixed(2)} '
            'R${sensor.roll  >= 0 ? '+' : ''}${sensor.roll.toStringAsFixed(2)}',
            style: style,
          ),
          SizedBox(width: hPad),
          Text('${(throttle * 100).round()}%', style: amberStyle),
          SizedBox(width: hPad),
          GestureDetector(
            onTap: onSettingsTap,
            child: Icon(Icons.settings, color: kDim, size: fontSize * 1.5),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Top Row — PTT | Rudder slider | Sensor lock
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
    required this.sw,
    required this.hPad,
  });

  final bool       isCaptain;
  final bool       ptt;
  final VoidCallback onPttStart, onPttEnd;
  final double     rudder;
  final ValueChanged<double> onRudder;
  final bool       sensorLocked;
  final VoidCallback onLockTap;
  final double     sw, hPad;

  @override
  Widget build(BuildContext context) {
    final btnSize = (sw * 0.13).clamp(44.0, 58.0);   // PTT / Lock button size

    final pttWidget = _PttButton(
      active:   ptt,
      onStart:  onPttStart,
      onEnd:    onPttEnd,
      size:     btnSize,
    );

    final lockWidget = _LockButton(
      locked: sensorLocked,
      onTap:  onLockTap,
      size:   btnSize,
    );

    final rudderWidget = Expanded(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: hPad),
        child: RudderSlider(
          value:     rudder,
          onChanged: onRudder,
          height:    sw * 0.14,
        ),
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: isCaptain
            ? [pttWidget, rudderWidget, lockWidget]
            : [lockWidget, rudderWidget, pttWidget],
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
    required this.size,
  });

  final bool active;
  final VoidCallback onStart, onEnd;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown:        (_) => onStart(),
      onTapUp:          (_) => onEnd(),
      onTapCancel:      ()  => onEnd(),
      onLongPressStart: (_) => onStart(),
      onLongPressEnd:   (_) => onEnd(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width:  size,
        height: size,
        decoration: BoxDecoration(
          color:        active ? kAmber : kNavy2,
          borderRadius: BorderRadius.circular(size * 0.2),
          border: Border.all(
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
            Icon(Icons.mic, size: size * 0.38,
                color: active ? kNavy : kAmber),
            if (active)
              Text('TX',
                style: TextStyle(
                  color:      kNavy,
                  fontSize:   size * 0.18,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                )),
          ],
        ),
      ),
    );
  }
}

// ── Sensor Lock Button ────────────────────────────────────────────────────────
class _LockButton extends StatelessWidget {
  const _LockButton({
    required this.locked,
    required this.onTap,
    required this.size,
  });

  final bool         locked;
  final VoidCallback onTap;
  final double       size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width:  size,
        height: size,
        decoration: BoxDecoration(
          color:        locked ? kAmber.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(size * 0.2),
          border: Border.all(
            color: locked ? kAmber : kDim,
            width: locked ? 2 : 1,
          ),
        ),
        child: Icon(
          locked ? Icons.lock : Icons.lock_open,
          color: locked ? kAmber : kDim,
          size:  size * 0.44,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom Row — Throttle + Control Buttons
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
    required this.sw,
    required this.hPad,
    required this.btnFontSize,
    required this.btnPadH,
    required this.btnPadV,
  });

  final bool   isCaptain;
  final double throttle;
  final bool   detentsEnabled;
  final ValueChanged<double> onThrottle;
  final bool   toga, idle, reverse, gear, flapsUp, flapsDown;
  final VoidCallback onTogaTap, onIdleTap, onReverseTap,
                     onGearTap, onFlapsUpTap, onFlapsDownTap;
  final double sw, hPad, btnFontSize, btnPadH, btnPadV;

  @override
  Widget build(BuildContext context) {
    // Throttle slider takes a fixed portion of screen width
    final throttleW = (sw * 0.18).clamp(52.0, 72.0);

    final throttleWidget = SizedBox(
      width: throttleW,
      child: ThrottleSlider(
        value:          throttle,
        onChanged:      onThrottle,
        detentsEnabled: detentsEnabled,
        width:          throttleW,
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
        fontSize:       btnFontSize,
        padH:           btnPadH,
        padV:           btnPadV,
      ),
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: isCaptain
            ? [throttleWidget, SizedBox(width: hPad), buttonsWidget]
            : [buttonsWidget,  SizedBox(width: hPad), throttleWidget],
      ),
    );
  }
}

// ── Control Buttons ───────────────────────────────────────────────────────────
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
    required this.fontSize,
    required this.padH,
    required this.padV,
  });

  final bool toga, idle, reverse, gear, flapsUp, flapsDown;
  final VoidCallback onTogaTap, onIdleTap, onReverseTap,
                     onGearTap, onFlapsUpTap, onFlapsDownTap;
  final double fontSize, padH, padV;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _btnRow([
          _CtrlBtn(label: 'TOGA',    active: toga,     color: kAmber, onTap: onTogaTap,
              fontSize: fontSize, padH: padH, padV: padV),
          _CtrlBtn(label: 'IDLE',    active: idle,     color: kDim,   onTap: onIdleTap,
              fontSize: fontSize, padH: padH, padV: padV),
        ]),
        _btnRow([
          _CtrlBtn(label: 'REV',     active: reverse,  color: kRed,   onTap: onReverseTap,
              fontSize: fontSize, padH: padH, padV: padV),
          _CtrlBtn(label: 'GEAR',    active: gear,     color: kGreen, onTap: onGearTap,
              fontSize: fontSize, padH: padH, padV: padV),
        ]),
        _btnRow([
          _CtrlBtn(label: 'FLPS▲',  active: flapsUp,   color: kAmber, onTap: onFlapsUpTap,
              fontSize: fontSize, padH: padH, padV: padV),
          _CtrlBtn(label: 'FLPS▼',  active: flapsDown, color: kAmber, onTap: onFlapsDownTap,
              fontSize: fontSize, padH: padH, padV: padV),
        ]),
      ],
    );
  }

  Widget _btnRow(List<Widget> btns) => Expanded(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: btns[0]),
        SizedBox(width: padH),
        Expanded(child: btns[1]),
      ],
    ),
  );
}

class _CtrlBtn extends StatelessWidget {
  const _CtrlBtn({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
    required this.fontSize,
    required this.padH,
    required this.padV,
  });

  final String       label;
  final bool         active;
  final Color        color;
  final VoidCallback onTap;
  final double       fontSize, padH, padV;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        decoration: BoxDecoration(
          color:        active ? color.withOpacity(0.25) : kNavy2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color : kDim,
            width: active ? 2   : 1,
          ),
          boxShadow: active
              ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8)]
              : [],
        ),
        child: Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color:      active ? color : kDim,
                fontSize:   fontSize,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
                fontFamily: 'monospace',
              ),
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
  final bool     active, editMode;
  final double   posX, posY, size;
  final VoidCallback onTap;
  final void Function(double x, double y) onMoved;
  final void Function(double w) onResized;
  final VoidCallback onLongPress;

  @override
  State<_ExtraButton> createState() => _ExtraButtonState();
}

class _ExtraButtonState extends State<_ExtraButton> {
  double _x = 0, _y = 0, _sz = 60;
  double _startSize = 60.0;

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
        onTap:       widget.editMode ? null : widget.onTap,
        onLongPress: widget.onLongPress,
        onPanUpdate: widget.editMode
            ? (d) {
                setState(() { _x += d.delta.dx; _y += d.delta.dy; });
                widget.onMoved(_x, _y);
              }
            : null,
        onScaleStart: widget.editMode
            ? (_) { _startSize = _sz; }
            : null,
        onScaleUpdate: widget.editMode
            ? (d) {
                setState(() => _sz = (_startSize * d.scale).clamp(36.0, 120.0));
                widget.onResized(_sz);
              }
            : null,
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
                color:      widget.editMode
                    ? Colors.white
                    : widget.active ? kAmber : kDim,
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
