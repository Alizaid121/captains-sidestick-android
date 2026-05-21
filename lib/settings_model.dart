// lib/settings_model.dart
//
// Persistent application settings backed by SharedPreferences.
// Notifies listeners on any change so the UI can rebuild reactively.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Which cockpit layout is active.
enum CockpitLayout { captain, copilot }

class SettingsModel extends ChangeNotifier {
  // ── Preference keys ──────────────────────────────────────────────────────
  static const _kIp               = 'ip_address';
  static const _kSensitivity      = 'sensitivity';
  static const _kDeadZone         = 'dead_zone';
  static const _kDetentsEnabled   = 'detents_enabled';
  static const _kLayout           = 'layout';
  static const _kExtraA           = 'extra_a';
  static const _kExtraB           = 'extra_b';
  static const _kExtraX           = 'extra_x';
  static const _kExtraY           = 'extra_y';
  static const _kExtraAx          = 'extra_a_x';
  static const _kExtraAy          = 'extra_a_y';
  static const _kExtraBx          = 'extra_b_x';
  static const _kExtraBy          = 'extra_b_y';
  static const _kExtraXx          = 'extra_x_x';
  static const _kExtraXy          = 'extra_x_y';
  static const _kExtraYx          = 'extra_y_x';
  static const _kExtraYy          = 'extra_y_y';
  static const _kExtraAw          = 'extra_a_w';
  static const _kExtraBw          = 'extra_b_w';
  static const _kExtraXw          = 'extra_x_w';
  static const _kExtraYw          = 'extra_y_w';

  // ── Field values (defaults) ───────────────────────────────────────────────
  String         _ip             = '192.168.1.100';
  double         _sensitivity    = 0.7;
  double         _deadZone       = 3.0;   // degrees
  bool           _detentsEnabled = true;
  CockpitLayout  _layout         = CockpitLayout.captain;

  // Extra button visibility
  bool _showA = false;
  bool _showB = false;
  bool _showX = false;
  bool _showY = false;

  // Extra button positions (normalised 0..1 of screen)
  double _axPos = 0.5, _ayPos = 0.5;
  double _bxPos = 0.6, _byPos = 0.5;
  double _xxPos = 0.7, _xyPos = 0.5;
  double _yxPos = 0.8, _yyPos = 0.5;

  // Extra button sizes (logical px, default 60)
  double _awSize = 60, _bwSize = 60, _xwSize = 60, _ywSize = 60;

  late SharedPreferences _prefs;
  bool _loaded = false;

  // ── Public getters ────────────────────────────────────────────────────────
  bool           get loaded          => _loaded;
  String         get ip              => _ip;
  double         get sensitivity     => _sensitivity;
  double         get deadZone        => _deadZone;
  bool           get detentsEnabled  => _detentsEnabled;
  CockpitLayout  get layout          => _layout;
  bool           get showA           => _showA;
  bool           get showB           => _showB;
  bool           get showX           => _showX;
  bool           get showY           => _showY;

  // Positions & sizes
  double get axPos => _axPos; double get ayPos => _ayPos;
  double get bxPos => _bxPos; double get byPos => _byPos;
  double get xxPos => _xxPos; double get xyPos => _xyPos;
  double get yxPos => _yxPos; double get yyPos => _yyPos;
  double get awSize => _awSize;
  double get bwSize => _bwSize;
  double get xwSize => _xwSize;
  double get ywSize => _ywSize;

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();

    _ip             = _prefs.getString(_kIp)            ?? _ip;
    _sensitivity    = _prefs.getDouble(_kSensitivity)   ?? _sensitivity;
    _deadZone       = _prefs.getDouble(_kDeadZone)      ?? _deadZone;
    _detentsEnabled = _prefs.getBool(_kDetentsEnabled)  ?? _detentsEnabled;
    _layout         = (_prefs.getString(_kLayout) == 'copilot')
                        ? CockpitLayout.copilot
                        : CockpitLayout.captain;
    _showA = _prefs.getBool(_kExtraA) ?? false;
    _showB = _prefs.getBool(_kExtraB) ?? false;
    _showX = _prefs.getBool(_kExtraX) ?? false;
    _showY = _prefs.getBool(_kExtraY) ?? false;

    _axPos = _prefs.getDouble(_kExtraAx) ?? _axPos;
    _ayPos = _prefs.getDouble(_kExtraAy) ?? _ayPos;
    _bxPos = _prefs.getDouble(_kExtraBx) ?? _bxPos;
    _byPos = _prefs.getDouble(_kExtraBy) ?? _byPos;
    _xxPos = _prefs.getDouble(_kExtraXx) ?? _xxPos;
    _xyPos = _prefs.getDouble(_kExtraXy) ?? _xyPos;
    _yxPos = _prefs.getDouble(_kExtraYx) ?? _yxPos;
    _yyPos = _prefs.getDouble(_kExtraYy) ?? _yyPos;

    _awSize = _prefs.getDouble(_kExtraAw) ?? _awSize;
    _bwSize = _prefs.getDouble(_kExtraBw) ?? _bwSize;
    _xwSize = _prefs.getDouble(_kExtraXw) ?? _xwSize;
    _ywSize = _prefs.getDouble(_kExtraYw) ?? _ywSize;

    _loaded = true;
    notifyListeners();
  }

  // ── Setters (save immediately) ────────────────────────────────────────────
  void setIp(String v) {
    _ip = v;
    _prefs.setString(_kIp, v);
    notifyListeners();
  }

  void setSensitivity(double v) {
    _sensitivity = v.clamp(0.1, 2.0);
    _prefs.setDouble(_kSensitivity, _sensitivity);
    notifyListeners();
  }

  void setDeadZone(double v) {
    _deadZone = v.clamp(0.0, 10.0);
    _prefs.setDouble(_kDeadZone, _deadZone);
    notifyListeners();
  }

  void setDetentsEnabled(bool v) {
    _detentsEnabled = v;
    _prefs.setBool(_kDetentsEnabled, v);
    notifyListeners();
  }

  void setLayout(CockpitLayout v) {
    _layout = v;
    _prefs.setString(_kLayout, v == CockpitLayout.copilot ? 'copilot' : 'captain');
    notifyListeners();
  }

  void setShowA(bool v) { _showA = v; _prefs.setBool(_kExtraA, v); notifyListeners(); }
  void setShowB(bool v) { _showB = v; _prefs.setBool(_kExtraB, v); notifyListeners(); }
  void setShowX(bool v) { _showX = v; _prefs.setBool(_kExtraX, v); notifyListeners(); }
  void setShowY(bool v) { _showY = v; _prefs.setBool(_kExtraY, v); notifyListeners(); }

  void setExtraAPos(double x, double y) {
    _axPos = x; _ayPos = y;
    _prefs.setDouble(_kExtraAx, x); _prefs.setDouble(_kExtraAy, y);
    notifyListeners();
  }

  void setExtraBPos(double x, double y) {
    _bxPos = x; _byPos = y;
    _prefs.setDouble(_kExtraBx, x); _prefs.setDouble(_kExtraBy, y);
    notifyListeners();
  }

  void setExtraXPos(double x, double y) {
    _xxPos = x; _xyPos = y;
    _prefs.setDouble(_kExtraXx, x); _prefs.setDouble(_kExtraXy, y);
    notifyListeners();
  }

  void setExtraYPos(double x, double y) {
    _yxPos = x; _yyPos = y;
    _prefs.setDouble(_kExtraYx, x); _prefs.setDouble(_kExtraYy, y);
    notifyListeners();
  }

  void setExtraASize(double w) { _awSize = w; _prefs.setDouble(_kExtraAw, w); notifyListeners(); }
  void setExtraBSize(double w) { _bwSize = w; _prefs.setDouble(_kExtraBw, w); notifyListeners(); }
  void setExtraXSize(double w) { _xwSize = w; _prefs.setDouble(_kExtraXw, w); notifyListeners(); }
  void setExtraYSize(double w) { _ywSize = w; _prefs.setDouble(_kExtraYw, w); notifyListeners(); }
}
