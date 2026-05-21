// lib/widgets/settings_panel.dart
//
// Settings drawer that slides up from the bottom of the screen.
//
// Changes in this version:
//   • Connection dot now shows amber for WsState.connecting (was only green/red)
//   • QR scan button added next to IP field — opens _QrScanPage, extracts IP
//     from ws://IP:8888 format, fills field and connects automatically.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../main.dart';
import '../settings_model.dart';
import '../websocket_service.dart';
import '../sensor_service.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.onClose});
  final VoidCallback onClose;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController    _ctrl;
  late Animation<Offset>      _slide;
  late TextEditingController  _ipCtrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 280),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 1),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();

    _ipCtrl = TextEditingController(text: context.read<SettingsModel>().ip);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    await _ctrl.reverse();
    widget.onClose();
  }

  // ── Open QR scanner full-screen, wait for result ──────────────────────────
  Future<void> _openQrScanner() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanPage()),
    );
    if (result == null || !mounted) return;

    // Accept both raw IP strings and ws://IP:port URLs.
    final ip = _extractIp(result);
    if (ip == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:         Text('QR code not recognised — expected ws://IP:8888'),
          backgroundColor: kRed,
          duration:        Duration(seconds: 3),
        ),
      );
      return;
    }

    // Apply IP, update text field, reconnect.
    _ipCtrl.text = ip;
    if (!mounted) return;
    final settings = context.read<SettingsModel>();
    final ws       = context.read<WebSocketService>();
    settings.setIp(ip);
    ws.reconnectNow();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:         Text('IP set to $ip — connecting…'),
        backgroundColor: kAmberD,
        duration:        const Duration(seconds: 2),
      ),
    );
  }

  /// Extracts a bare IP/hostname from either "ws://IP:PORT" or plain "IP".
  String? _extractIp(String raw) {
    final trimmed = raw.trim();
    // Try parsing as a URI first.
    try {
      final uri = Uri.parse(trimmed);
      if (uri.host.isNotEmpty) return uri.host;
    } catch (_) {}
    // Fallback: if it looks like a bare IP or hostname, accept it.
    final bareIp = RegExp(r'^[\d.]+$');
    if (bareIp.hasMatch(trimmed)) return trimmed;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsModel>();
    final ws       = context.watch<WebSocketService>();
    final sensor   = context.watch<SensorService>();

    // ── Status dot colour: green=connected, amber=connecting, red=disconnected
    final dotColor = switch (ws.state) {
      WsState.connected    => kGreen,
      WsState.connecting   => kAmber,
      WsState.disconnected => kRed,
    };

    return GestureDetector(
      onTap: _close,
      child: ColoredBox(
        color: Colors.black45,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: SlideTransition(
              position: _slide,
              child: Container(
                width:       double.infinity,
                constraints: const BoxConstraints(maxHeight: 560),
                decoration:  const BoxDecoration(
                  color:        kNavy2,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                  border: Border(top: BorderSide(color: kAmber, width: 1.5)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Container(
                        width: 40, height: 4,
                        decoration: BoxDecoration(
                          color: kDim, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    // Title
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        'SETTINGS',
                        style: TextStyle(
                          color: kAmber, fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          letterSpacing: 3,
                        ),
                      ),
                    ),
                    const Divider(color: kDim, height: 1),

                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            // ── CONNECTION ──────────────────────────────────
                            _sectionHeader('CONNECTION'),
                            const SizedBox(height: 8),

                            // IP row: [text field] [QR] [APPLY]
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller:   _ipCtrl,
                                    style:        const TextStyle(
                                        color: kText, fontFamily: 'monospace'),
                                    keyboardType: TextInputType.url,
                                    decoration:   const InputDecoration(
                                      labelText: 'PC IP Address',
                                      hintText:  '192.168.1.100',
                                      isDense:   true,
                                    ),
                                    onSubmitted:      (v) => settings.setIp(v.trim()),
                                    onEditingComplete: ()  =>
                                        settings.setIp(_ipCtrl.text.trim()),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // ── QR scan button ────────────────────────
                                Tooltip(
                                  message: 'Scan QR code from PC app',
                                  child: GestureDetector(
                                    onTap: _openQrScanner,
                                    child: Container(
                                      width: 38, height: 38,
                                      decoration: BoxDecoration(
                                        border: Border.all(color: kAmber),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Icon(
                                        Icons.qr_code_scanner,
                                        color: kAmber,
                                        size:  20,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                _smallButton(
                                  label: 'APPLY',
                                  onTap: () {
                                    settings.setIp(_ipCtrl.text.trim());
                                    ws.reconnectNow();
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Status row
                            Row(children: [
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 10, height: 10,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: dotColor,
                                  boxShadow: [
                                    BoxShadow(color: dotColor, blurRadius: 4),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                ws.statusLabel,
                                style: const TextStyle(
                                  color: kText, fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const Spacer(),
                              _smallButton(
                                  label: 'RECONNECT',
                                  onTap: ws.reconnectNow),
                            ]),

                            const SizedBox(height: 18),

                            // ── SENSORS ─────────────────────────────────────
                            _sectionHeader('SENSORS'),
                            const SizedBox(height: 6),
                            _labelRow('Sensitivity',
                                settings.sensitivity.toStringAsFixed(2)),
                            Slider(
                              value:     settings.sensitivity,
                              min:       0.1, max: 2.0, divisions: 38,
                              onChanged: settings.setSensitivity,
                            ),
                            _labelRow('Dead Zone',
                                '±${settings.deadZone.toStringAsFixed(1)}°'),
                            Slider(
                              value:     settings.deadZone,
                              min:       0.0, max: 10.0, divisions: 20,
                              onChanged: settings.setDeadZone,
                            ),
                            const SizedBox(height: 8),
                            _amberButton(
                              label: '⊕  CALIBRATE (SET NEUTRAL)',
                              onTap: () {
                                sensor.calibrate();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:         Text('Neutral calibrated ✓'),
                                    backgroundColor: kAmberD,
                                    duration:        Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),

                            const SizedBox(height: 18),

                            // ── LAYOUT ───────────────────────────────────────
                            _sectionHeader('LAYOUT'),
                            const SizedBox(height: 8),
                            Row(children: [
                              _layoutBtn(
                                'CAPTAIN',
                                settings.layout == CockpitLayout.captain,
                                () => settings.setLayout(CockpitLayout.captain),
                              ),
                              const SizedBox(width: 10),
                              _layoutBtn(
                                'CO-PILOT',
                                settings.layout == CockpitLayout.copilot,
                                () => settings.setLayout(CockpitLayout.copilot),
                              ),
                            ]),
                            const SizedBox(height: 14),
                            _switchRow('Throttle Detents',
                                settings.detentsEnabled,
                                settings.setDetentsEnabled),

                            const SizedBox(height: 18),

                            // ── EXTRA BUTTONS ────────────────────────────────
                            _sectionHeader('EXTRA BUTTONS'),
                            const SizedBox(height: 4),
                            const Text(
                              'Added buttons are draggable & resizable (long-press to edit)',
                              style: TextStyle(color: kDim, fontSize: 10),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _extraToggle('A', settings.showA, settings.setShowA),
                                _extraToggle('B', settings.showB, settings.setShowB),
                                _extraToggle('X', settings.showX, settings.setShowX),
                                _extraToggle('Y', settings.showY, settings.setShowY),
                              ],
                            ),

                            const SizedBox(height: 18),
                            _amberButton(label: '✕  CLOSE', onTap: _close),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Widget _sectionHeader(String t) => Text(t,
    style: const TextStyle(
      color: kAmber, fontSize: 10, fontFamily: 'monospace',
      fontWeight: FontWeight.bold, letterSpacing: 2,
    ),
  );

  Widget _labelRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: kText, fontSize: 12)),
        Text(value,  style: const TextStyle(
            color: kAmber, fontSize: 12, fontFamily: 'monospace')),
      ],
    ),
  );

  Widget _smallButton({required String label, required VoidCallback onTap}) =>
    GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border:       Border.all(color: kAmber),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
          style: const TextStyle(
              color: kAmber, fontSize: 10, fontFamily: 'monospace')),
      ),
    );

  Widget _amberButton({required String label, required VoidCallback onTap}) =>
    SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color:        kAmber.withOpacity(0.15),
            border:       Border.all(color: kAmber),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: kAmber, fontSize: 13,
              fontFamily: 'monospace', fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );

  Widget _layoutBtn(String label, bool active, VoidCallback onTap) =>
    Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color:        active ? kAmber : Colors.transparent,
            border:       Border.all(color: kAmber),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color:      active ? kNavy : kAmber,
              fontSize:   12, fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );

  Widget _switchRow(String label, bool value, ValueChanged<bool> onChanged) =>
    Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: kText, fontSize: 13)),
        Switch(
          value:              value,
          onChanged:          onChanged,
          activeColor:        kAmber,
          inactiveThumbColor: kDim,
          inactiveTrackColor: kNavy,
        ),
      ],
    );

  Widget _extraToggle(String letter, bool active, ValueChanged<bool> onChanged) =>
    GestureDetector(
      onTap: () => onChanged(!active),
      child: Container(
        width: 52, height: 52,
        decoration: BoxDecoration(
          color:        active ? kAmber : Colors.transparent,
          border:       Border.all(color: active ? kAmber : kDim, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(letter,
              style: TextStyle(
                color:      active ? kNavy : kDim,
                fontSize:   18, fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            Text(active ? 'ON' : 'OFF',
              style: TextStyle(
                color: active ? kNavy : kDim,
                fontSize: 8, fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen QR scanner page
// ─────────────────────────────────────────────────────────────────────────────
class _QrScanPage extends StatefulWidget {
  const _QrScanPage();

  @override
  State<_QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<_QrScanPage> {
  final MobileScannerController _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing:         CameraFacing.back,
    torchEnabled:   false,
  );

  bool _popped = false;   // prevent double-pop on rapid detections

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_popped) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _popped = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera feed ──────────────────────────────────────────────────
          MobileScanner(
            controller: _scanner,
            onDetect:   _onDetect,
          ),

          // ── Dimmed overlay with centre cut-out guide ─────────────────────
          CustomPaint(
            painter: _ScanOverlayPainter(),
            child: const SizedBox.expand(),
          ),

          // ── Instructions ─────────────────────────────────────────────────
          const Positioned(
            bottom: 100,
            left: 0, right: 0,
            child: Text(
              'Point at the QR code shown\nin the PC app',
              textAlign: TextAlign.center,
              style: TextStyle(
                color:      Colors.white,
                fontSize:   16,
                fontFamily: 'monospace',
                shadows: [Shadow(blurRadius: 4)],
              ),
            ),
          ),

          // ── Close button ─────────────────────────────────────────────────
          Positioned(
            top:  48,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:        Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close, color: kAmber, size: 26),
              ),
            ),
          ),

          // ── Torch toggle ─────────────────────────────────────────────────
          Positioned(
            top:   48,
            right: 16,
            child: GestureDetector(
              onTap: () => _scanner.toggleTorch(),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color:        Colors.black54,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.flashlight_on, color: kAmber, size: 26),
              ),
            ),
          ),

          // ── Label ────────────────────────────────────────────────────────
          const Positioned(
            top:   14,
            left:  0,
            right: 0,
            child: Text(
              'SCAN QR CODE',
              textAlign: TextAlign.center,
              style: TextStyle(
                color:       kAmber,
                fontSize:    13,
                fontFamily:  'monospace',
                fontWeight:  FontWeight.bold,
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Scan overlay painter — dimmed surround + amber corner brackets ────────────
class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const boxSize = 260.0;
    final cx = size.width  / 2;
    final cy = size.height / 2 - 30;   // slightly above centre

    final boxRect = Rect.fromCenter(
      center: Offset(cx, cy),
      width:  boxSize,
      height: boxSize,
    );

    // Dim everything outside the scan box.
    final dimPaint = Paint()..color = Colors.black.withOpacity(0.55);
    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dimPaint);

    // Amber corner brackets.
    final bracketPaint = Paint()
      ..color       = kAmber
      ..strokeWidth = 3.5
      ..style       = PaintingStyle.stroke
      ..strokeCap   = StrokeCap.round;

    const arm = 28.0;
    final l = boxRect.left, r = boxRect.right;
    final t = boxRect.top,  b = boxRect.bottom;

    // Top-left
    canvas.drawLine(Offset(l, t + arm), Offset(l, t), bracketPaint);
    canvas.drawLine(Offset(l, t), Offset(l + arm, t), bracketPaint);
    // Top-right
    canvas.drawLine(Offset(r - arm, t), Offset(r, t), bracketPaint);
    canvas.drawLine(Offset(r, t), Offset(r, t + arm), bracketPaint);
    // Bottom-left
    canvas.drawLine(Offset(l, b - arm), Offset(l, b), bracketPaint);
    canvas.drawLine(Offset(l, b), Offset(l + arm, b), bracketPaint);
    // Bottom-right
    canvas.drawLine(Offset(r - arm, b), Offset(r, b), bracketPaint);
    canvas.drawLine(Offset(r, b), Offset(r, b - arm), bracketPaint);
  }

  @override
  bool shouldRepaint(_) => false;
}
