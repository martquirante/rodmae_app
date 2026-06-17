import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../screens/map_screen.dart'; // TransitMode

// ─────────────────────────────────────────────────────────────────────────────
// RealtimeAnimatedMarkerController
//
// Drives the three physics systems for every live marker:
//   1. 1 000 ms smooth glide  — Tween over geodesic interpolation
//   2. Bearing / heading       — great-circle bearing + shortest-arc slerp
//   3. Animation sub-system    — mode-specific:
//        Walking  → 100 ms sprite-frame cycle (frames 1-4)
//        Vehicle  → Chase-Camera Banking: Z-axis tilt proportional to Δbearing
// ─────────────────────────────────────────────────────────────────────────────

class RealtimeAnimatedMarkerController extends ChangeNotifier {
  final TickerProvider vsync;

  // ── State ─────────────────────────────────────────────────────────────────
  LatLng? _position;
  double _bearing = 0.0;        // radians, 0 = North
  double _bankAngle = 0.0;      // radians, vehicle lateral lean (Z-rotate)
  int _currentFrame = 1;        // sprite frame index (1-4)
  bool _isMoving = false;
  TransitMode _transitMode;

  // ── Public getters ────────────────────────────────────────────────────────
  LatLng?     get position    => _position;
  double      get bearing     => _bearing;
  double      get bankAngle   => _bankAngle;
  int         get currentFrame => _currentFrame;
  bool        get isMoving    => _isMoving;
  TransitMode get transitMode => _transitMode;

  // ── Private glide state ───────────────────────────────────────────────────
  AnimationController? _glideController;
  LatLng? _startPosition;
  LatLng? _targetPosition;
  double _startBearing  = 0.0;
  double _targetBearing = 0.0;
  double _prevBearing   = 0.0;  // used to compute delta for banking

  // ── Walking sprite timer ──────────────────────────────────────────────────
  Timer? _frameTimer;

  // ── Banking decay timer ───────────────────────────────────────────────────
  Timer? _bankDecayTimer;

  // Maximum bank lean in radians (~18°)
  static const double _maxBankRadians = 0.315;

  // ── Constructor ───────────────────────────────────────────────────────────
  RealtimeAnimatedMarkerController({
    required this.vsync,
    LatLng?     initialPosition,
    TransitMode initialMode = TransitMode.walking,
  })  : _position    = initialPosition,
        _transitMode = initialMode {
    _glideController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1000),
    )..addListener(_onGlideUpdate);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PUBLIC API
  // ══════════════════════════════════════════════════════════════════════════

  /// Feed a new real-world coordinate. Triggers glide + animation sub-system.
  void updatePosition(LatLng newPos, {TransitMode? newMode}) {
    if (newMode != null) _transitMode = newMode;

    // First ever fix — just plant the marker silently.
    if (_position == null) {
      _position = newPos;
      _targetPosition = newPos;
      notifyListeners();
      return;
    }

    // No meaningful movement — ignore.
    if (newPos.latitude  == _position!.latitude &&
        newPos.longitude == _position!.longitude) {
      return;
    }

    // ── 1. Calculate new heading ───────────────────────────────────────────
    final newBearing = _calculateBearing(_position!, newPos);

    // ── 2. For vehicles: compute delta bearing → bank angle ───────────────
    if (_isVehicleMode(_transitMode)) {
      final double deltaBearing = _shortestAngleDiff(_prevBearing, newBearing);
      // Clamp to ±maxBank; invert so left-turn = negative lean.
      _bankAngle = (deltaBearing * 2.5).clamp(-_maxBankRadians, _maxBankRadians);
      _scheduleBankDecay();
    } else {
      _bankAngle = 0.0;
    }
    _prevBearing = _bearing;

    // ── 3. Store interpolation endpoints ──────────────────────────────────
    _startPosition  = _position;
    _targetPosition = newPos;
    _startBearing   = _bearing;
    _targetBearing  = newBearing;

    // ── 4. Mark moving, start mode-specific animation ─────────────────────
    _isMoving = true;
    if (_isWalkingMode(_transitMode)) {
      _startFrameCycle();
    } else {
      _stopFrameCycle(); // vehicles don't use frame swapping
    }

    // ── 5. Fire the 1 000 ms glide ────────────────────────────────────────
    _glideController!.stop();
    _glideController!.forward(from: 0.0).then((_) {
      _isMoving = false;
      if (_isWalkingMode(_transitMode)) _stopFrameCycle();
      notifyListeners();
    });
  }

  /// Change transit mode without moving (e.g., user manually picks a mode).
  void updateTransitMode(TransitMode newMode) {
    if (_transitMode == newMode) return;
    _transitMode = newMode;
    if (!_isWalkingMode(newMode)) {
      _stopFrameCycle();
      _bankAngle = 0.0;
    }
    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE — GLIDE UPDATE  (fires every AnimationController tick)
  // ══════════════════════════════════════════════════════════════════════════

  void _onGlideUpdate() {
    final t = Curves.easeInOutCubic.transform(_glideController!.value);

    // Position lerp
    if (_startPosition != null && _targetPosition != null) {
      _position = LatLng(
        _startPosition!.latitude  + (_targetPosition!.latitude  - _startPosition!.latitude)  * t,
        _startPosition!.longitude + (_targetPosition!.longitude - _startPosition!.longitude) * t,
      );
    }

    // Bearing slerp (shortest arc)
    _bearing = _lerpAngle(_startBearing, _targetBearing, t);

    notifyListeners();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE — WALKING SPRITE FRAME CYCLE
  // ══════════════════════════════════════════════════════════════════════════

  void _startFrameCycle() {
    if (_frameTimer != null) return; // already running
    _frameTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _currentFrame = (_currentFrame % 4) + 1;
      notifyListeners();
    });
  }

  void _stopFrameCycle() {
    _frameTimer?.cancel();
    _frameTimer = null;
    _currentFrame = 1; // idle pose
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE — VEHICLE BANKING DECAY
  // Smoothly returns the lean to 0 over 800 ms once we stop updating.
  // ══════════════════════════════════════════════════════════════════════════

  void _scheduleBankDecay() {
    _bankDecayTimer?.cancel();
    _bankDecayTimer = Timer(const Duration(milliseconds: 800), () {
      // Lerp bank back to zero in small steps
      Timer.periodic(const Duration(milliseconds: 32), (t) {
        _bankAngle *= 0.8;
        if (_bankAngle.abs() < 0.005) {
          _bankAngle = 0.0;
          t.cancel();
        }
        notifyListeners();
      });
    });
  }

  // ══════════════════════════════════════════════════════════════════════════
  // PRIVATE — MATH HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  /// Great-circle bearing from [start] → [end] in radians, 0 = North.
  double _calculateBearing(LatLng start, LatLng end) {
    final lat1 = start.latitude  * math.pi / 180.0;
    final lon1 = start.longitude * math.pi / 180.0;
    final lat2 = end.latitude    * math.pi / 180.0;
    final lon2 = end.longitude   * math.pi / 180.0;

    final dLon = lon2 - lon1;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
              math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

    return math.atan2(y, x);
  }

  /// Shortest angular difference between [from] and [to], both in radians.
  double _shortestAngleDiff(double from, double to) {
    double diff = (to - from) % (2 * math.pi);
    if (diff < -math.pi) diff += 2 * math.pi;
    if (diff >  math.pi) diff -= 2 * math.pi;
    return diff;
  }

  /// Smoothly interpolates between angles [from] → [to] using shortest arc.
  double _lerpAngle(double from, double to, double t) =>
      from + _shortestAngleDiff(from, to) * t;

  // ── Mode helpers ──────────────────────────────────────────────────────────
  static bool _isWalkingMode(TransitMode m) => m == TransitMode.walking;
  static bool _isVehicleMode(TransitMode m) => m != TransitMode.walking;

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _glideController?.dispose();
    _frameTimer?.cancel();
    _bankDecayTimer?.cancel();
    super.dispose();
  }
}