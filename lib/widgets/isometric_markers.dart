import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/realtime_marker_controller.dart';
import '../screens/map_screen.dart'; // To access TransitMode and details

// ─────────────────────────────────────────────────────────────────────────────
// PRESENCE STATUS
// ─────────────────────────────────────────────────────────────────────────────

/// Online / offline / unknown presence for a map entity.
enum PresenceStatus { online, offline, unknown }

// ─────────────────────────────────────────────────────────────────────────────
// PAINTER: Top-down game-style VEHICLE
// Covers: car, motorcycle, bicycle, bus/transit, walking person
// ─────────────────────────────────────────────────────────────────────────────

class _VehiclePainter extends CustomPainter {
  final String vehicleType;
  final Color color;
  final double phase; // 0..1 continuous repeating from AnimationController

  const _VehiclePainter({
    required this.vehicleType,
    required this.color,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bob = math.sin(phase * math.pi * 2) * 3.0;

    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + 3, size.height * 0.88),
        width: size.width * 0.64,
        height: size.height * 0.12,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    canvas.save();
    canvas.translate(cx, size.height * 0.48 + bob);

    final t = vehicleType.toLowerCase();
    if (t == 'motorcycle') {
      _drawMoto(canvas, size);
    } else if (t == 'bicycling' || t == 'bicycle' || t == 'biking') {
      _drawBike(canvas, size);
    } else if (t == 'transit' || t == 'bus' || t == 'commuting') {
      _drawBus(canvas, size);
    } else if (t == 'walking') {
      _drawWalker(canvas, size, phase);
    } else {
      _drawCar(canvas, size); // default: car / driving
    }

    canvas.restore();
  }

  // ── A. TOP-DOWN GAME CAR ──────────────────────────────────────────────────
  void _drawCar(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();
    canvas.scale(1.0, 0.68); // isometric squish

    final lc = Color.lerp(color, Colors.white, 0.28)!;
    final dc = Color.lerp(color, Colors.black, 0.32)!;

    // Body
    final body = Rect.fromCenter(
      center: Offset.zero,
      width: w * 0.64,
      height: h * 0.60,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(9)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lc, color, dc],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(body),
    );

    // Windshield (front / top)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -h * 0.13),
          width: w * 0.40,
          height: h * 0.16,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFFBBDEFB).withValues(alpha: 0.85),
    );
    // Rear window (bottom)
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, h * 0.13),
          width: w * 0.34,
          height: h * 0.13,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFF90CAF9).withValues(alpha: 0.72),
    );

    // Door seam line
    canvas.drawLine(
      Offset(-w * 0.32, -h * 0.02),
      Offset(w * 0.32, -h * 0.02),
      Paint()..color = dc.withValues(alpha: 0.50)..strokeWidth = 1.2,
    );

    // 4 Wheels (dark rounded rects)
    for (final pos in [
      Offset(-w * 0.28, -h * 0.25),
      Offset(w * 0.28, -h * 0.25),
      Offset(-w * 0.28, h * 0.25),
      Offset(w * 0.28, h * 0.25),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: pos, width: w * 0.18, height: h * 0.16),
          const Radius.circular(3.5),
        ),
        Paint()..color = const Color(0xFF1A1A1A),
      );
      // Rim
      canvas.drawCircle(pos, w * 0.056, Paint()..color = const Color(0xFF9E9E9E));
    }

    // Roof glint (specular highlight)
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(-w * 0.05, -h * 0.05),
        width: w * 0.26,
        height: h * 0.14,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.25)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5),
    );

    // Headlights
    for (final xp in [-w * 0.18, w * 0.18]) {
      canvas.drawCircle(
        Offset(xp, -h * 0.27),
        w * 0.04,
        Paint()..color = const Color(0xFFFFF9C4).withValues(alpha: 0.95),
      );
    }

    canvas.restore();
  }

  // ── B. MOTORCYCLE ─────────────────────────────────────────────────────────
  void _drawMoto(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();
    canvas.scale(1.0, 0.72);

    final lc = Color.lerp(color, Colors.white, 0.30)!;
    final dc = Color.lerp(color, Colors.black, 0.28)!;
    final wheelPaint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.5;

    // Front & rear wheels (ovals)
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, -h * 0.22), width: w * 0.24, height: h * 0.26),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(0, h * 0.22), width: w * 0.24, height: h * 0.26),
      wheelPaint,
    );
    // Wheel hubs
    for (final yp in [-h * 0.22, h * 0.22]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(0, yp), width: w * 0.10, height: h * 0.10),
        Paint()..color = const Color(0xFF9E9E9E),
      );
    }

    // Frame spine
    canvas.drawLine(
      Offset(0, -h * 0.22),
      Offset(0, h * 0.22),
      Paint()
        ..color = dc
        ..strokeWidth = 4.5
        ..strokeCap = StrokeCap.round,
    );

    // Tank / body
    final tankRect = Rect.fromCenter(
      center: Offset(0, -h * 0.07),
      width: w * 0.30,
      height: h * 0.24,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(tankRect, const Radius.circular(5)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lc, color, dc],
        ).createShader(tankRect),
    );

    // Handlebars
    canvas.drawLine(
      Offset(-w * 0.20, -h * 0.30),
      Offset(w * 0.20, -h * 0.30),
      Paint()
        ..color = const Color(0xFF616161)
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  // ── C. BICYCLE ────────────────────────────────────────────────────────────
  void _drawBike(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();
    canvas.scale(1.0, 0.72);

    final wheelPaint = Paint()
      ..color = const Color(0xFF424242)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;

    // Two wheels
    canvas.drawOval(
      Rect.fromCenter(center: Offset(-w * 0.14, 0), width: w * 0.42, height: h * 0.44),
      wheelPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * 0.14, 0), width: w * 0.42, height: h * 0.44),
      wheelPaint,
    );

    // Frame triangle
    final framePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(0, -h * 0.15)
        ..lineTo(-w * 0.14, h * 0.14)
        ..lineTo(w * 0.14, h * 0.14)
        ..close(),
      framePaint,
    );
    // Top tube
    canvas.drawLine(
      Offset(-w * 0.14, -h * 0.04),
      Offset(w * 0.14, -h * 0.04),
      framePaint,
    );

    // Handlebars
    canvas.drawLine(
      Offset(-w * 0.22, -h * 0.19),
      Offset(-w * 0.04, -h * 0.19),
      Paint()
        ..color = const Color(0xFF616161)
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );

    canvas.restore();
  }

  // ── D. BUS / TRANSIT ─────────────────────────────────────────────────────
  void _drawBus(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    canvas.save();
    canvas.scale(1.0, 0.68);

    final lc = Color.lerp(color, Colors.white, 0.22)!;
    final dc = Color.lerp(color, Colors.black, 0.25)!;

    // Wide body
    final body = Rect.fromCenter(
      center: Offset.zero,
      width: w * 0.72,
      height: h * 0.66,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(body, const Radius.circular(6)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [lc, color, dc],
        ).createShader(body),
    );

    // Windows (3 across)
    final winPaint = Paint()..color = const Color(0xFF90CAF9).withValues(alpha: 0.80);
    for (var i = -1; i <= 1; i++) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(i * w * 0.21, -h * 0.10),
            width: w * 0.17,
            height: h * 0.18,
          ),
          const Radius.circular(3),
        ),
        winPaint,
      );
    }
    // Destination board
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -h * 0.29),
          width: w * 0.52,
          height: h * 0.11,
        ),
        const Radius.circular(2),
      ),
      Paint()..color = const Color(0xFFFFF9C4).withValues(alpha: 0.88),
    );

    // 4 Wheels
    final wheelPaint = Paint()..color = const Color(0xFF1A1A1A);
    for (final p in [
      Offset(-w * 0.28, -h * 0.28),
      Offset(w * 0.28, -h * 0.28),
      Offset(-w * 0.28, h * 0.28),
      Offset(w * 0.28, h * 0.28),
    ]) {
      canvas.drawOval(
        Rect.fromCenter(center: p, width: w * 0.16, height: h * 0.14),
        wheelPaint,
      );
    }

    canvas.restore();
  }

  // ── E. WALKING PERSON (animated leg swing) ────────────────────────────────
  void _drawWalker(Canvas canvas, Size size, double phase) {
    final w = size.width;
    final h = size.height;
    final swing = math.sin(phase * math.pi * 4) * 0.30;

    // Head + hair
    canvas.drawCircle(Offset(0, -h * 0.31), h * 0.12,
        Paint()..color = const Color(0xFFFFCC80));
    canvas.drawCircle(Offset(0, -h * 0.37), h * 0.09,
        Paint()..color = const Color(0xFF5D4037));

    // Shirt / torso
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, -h * 0.10), width: w * 0.28, height: h * 0.26),
        const Radius.circular(5),
      ),
      Paint()..color = color,
    );

    // Arms
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(side * w * 0.18, -h * 0.12);
      canvas.rotate(-side * swing * 1.1);
      canvas.drawLine(
        Offset.zero,
        Offset(side * w * 0.06, h * 0.18),
        Paint()
          ..color = const Color(0xFFFFCC80)
          ..strokeWidth = 5.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }

    // Legs
    final legColor = Color.lerp(color, Colors.black, 0.42)!;
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(side * w * 0.09, h * 0.06);
      canvas.rotate(side * swing);
      canvas.drawLine(
        Offset.zero,
        Offset(side * w * 0.03, h * 0.24),
        Paint()
          ..color = legColor
          ..strokeWidth = 7.0
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _VehiclePainter old) =>
      old.phase != phase || old.vehicleType != vehicleType || old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTER: 2.5D HOUSE (front + right side visible for 3D depth)
// ─────────────────────────────────────────────────────────────────────────────

class _HousePainter extends CustomPainter {
  final Color roofColor;
  final Color wallColor;
  final double phase;

  const _HousePainter({
    required this.roofColor,
    required this.wallColor,
    required this.phase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bob = math.sin(phase * math.pi * 2) * 2.5;

    // Ground shadow
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + 3, size.height * 0.90),
        width: size.width * 0.70,
        height: size.height * 0.11,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
    );

    canvas.save();
    canvas.translate(cx, size.height * 0.54 + bob);

    final w = size.width * 0.52;
    final h = size.height * 0.44;
    final rh = size.height * 0.30; // roof height
    const so = 12.0; // side panel horizontal offset
    const soy = 5.0; // side panel vertical offset

    // === RIGHT SIDE PANEL (3D depth) ===
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, -h / 2)
        ..lineTo(w / 2 + so, -h / 2 - soy)
        ..lineTo(w / 2 + so, h / 2 - soy)
        ..lineTo(w / 2, h / 2)
        ..close(),
      Paint()..color = Color.lerp(wallColor, Colors.black, 0.35)!,
    );

    // === FRONT WALL ===
    final frontRect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawRect(
      frontRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(wallColor, Colors.white, 0.18)!,
            wallColor,
            Color.lerp(wallColor, Colors.black, 0.10)!,
          ],
        ).createShader(frontRect),
    );

    // Door
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, h * 0.22), width: w * 0.28, height: h * 0.42),
        const Radius.circular(4),
      ),
      Paint()..color = const Color(0xFF5D4037),
    );
    canvas.drawCircle(Offset(w * 0.08, h * 0.22), 2.5,
        Paint()..color = const Color(0xFFFFD166));

    // Windows
    for (final xOff in [-w * 0.29, w * 0.29]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(xOff, -h * 0.05),
            width: w * 0.22,
            height: h * 0.26,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = const Color(0xFF90CAF9).withValues(alpha: 0.85),
      );
      // Cross pane lines
      canvas.drawLine(
        Offset(xOff, -h * 0.05 - h * 0.13),
        Offset(xOff, -h * 0.05 + h * 0.13),
        Paint()..color = Colors.white.withValues(alpha: 0.42)..strokeWidth = 1.2,
      );
      canvas.drawLine(
        Offset(xOff - w * 0.11, -h * 0.05),
        Offset(xOff + w * 0.11, -h * 0.05),
        Paint()..color = Colors.white.withValues(alpha: 0.42)..strokeWidth = 1.2,
      );
    }

    // === RIGHT ROOF SIDE (3D depth) ===
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, -h / 2)
        ..lineTo(w / 2 + so, -h / 2 - soy)
        ..lineTo(so, -h / 2 - rh - soy)
        ..lineTo(0, -h / 2 - rh)
        ..close(),
      Paint()..color = Color.lerp(roofColor, Colors.black, 0.30)!,
    );

    // === FRONT ROOF ===
    final roofPath = Path()
      ..moveTo(-w / 2, -h / 2)
      ..lineTo(w / 2, -h / 2)
      ..lineTo(0, -h / 2 - rh)
      ..close();
    canvas.drawPath(
      roofPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.lerp(roofColor, Colors.white, 0.22)!,
            roofColor,
            Color.lerp(roofColor, Colors.black, 0.15)!,
          ],
        ).createShader(Rect.fromLTWH(-w / 2, -h / 2 - rh, w, rh)),
    );
    // Roof edge outline
    canvas.drawPath(
      roofPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Color.lerp(roofColor, Colors.black, 0.30)!
        ..strokeWidth = 1.3,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _HousePainter old) =>
      old.phase != phase || old.roofColor != roofColor || old.wallColor != wallColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// PAINTER: 2.5D OFFICE BUILDING with lit window grid
// ─────────────────────────────────────────────────────────────────────────────

class _BuildingPainter extends CustomPainter {
  final Color accentColor;
  final double phase;

  const _BuildingPainter({required this.accentColor, required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final bob = math.sin(phase * math.pi * 2) * 2.0;

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(cx + 4, size.height * 0.90),
        width: size.width * 0.68,
        height: size.height * 0.11,
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );

    canvas.save();
    canvas.translate(cx, size.height * 0.52 + bob);

    final w = size.width * 0.48;
    final h = size.height * 0.70;
    const so = 14.0;
    const soy = 6.0;
    const wallColor = Color(0xFF37474F);
    const sideColor = Color(0xFF263238);

    // Right side face
    canvas.drawPath(
      Path()
        ..moveTo(w / 2, -h / 2)
        ..lineTo(w / 2 + so, -h / 2 - soy)
        ..lineTo(w / 2 + so, h / 2 - soy)
        ..lineTo(w / 2, h / 2)
        ..close(),
      Paint()..color = sideColor,
    );

    // Top face
    canvas.drawPath(
      Path()
        ..moveTo(-w / 2, -h / 2)
        ..lineTo(w / 2, -h / 2)
        ..lineTo(w / 2 + so, -h / 2 - soy)
        ..lineTo(-w / 2 + so, -h / 2 - soy)
        ..close(),
      Paint()..color = const Color(0xFF455A64),
    );

    // Front face
    final frontRect = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    canvas.drawRect(
      frontRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(wallColor, Colors.white, 0.10)!,
            wallColor,
            sideColor,
          ],
        ).createShader(frontRect),
    );

    // Window grid: 3 columns × 4 rows
    final litWin = Paint()..color = accentColor.withValues(alpha: 0.92);
    final dimWin = Paint()..color = const Color(0xFF546E7A).withValues(alpha: 0.72);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 3; col++) {
        final wx = -w * 0.30 + col * w * 0.30;
        final wy = -h * 0.36 + row * h * 0.22;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset(wx, wy), width: w * 0.20, height: h * 0.12),
            const Radius.circular(2),
          ),
          (row + col).isEven ? litWin : dimWin,
        );
      }
    }

    // Bottom door
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(0, h * 0.38), width: w * 0.25, height: h * 0.16),
        const Radius.circular(3),
      ),
      Paint()..color = sideColor,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BuildingPainter old) =>
      old.phase != phase || old.accentColor != accentColor;
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: PersonGameMarker — avatar on glowing 3D ring + presence indicator
// This replaces the plain CircleAvatar markers on the map.
// ─────────────────────────────────────────────────────────────────────────────

class PersonGameMarker extends StatefulWidget {
  final String name;
  final Color markerColor;
  final String? avatarUrl;
  final PresenceStatus presence;
  final bool isMe;
  final String? initials;
  final String? lastSeenLabel;
  final bool showHomeHighlight;

  const PersonGameMarker({
    required this.name,
    required this.markerColor,
    this.avatarUrl,
    this.presence = PresenceStatus.unknown,
    this.isMe = false,
    this.initials,
    this.lastSeenLabel,
    this.showHomeHighlight = false,
    super.key,
  });

  @override
  State<PersonGameMarker> createState() => _PersonGameMarkerState();
}

class _PersonGameMarkerState extends State<PersonGameMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final bob = math.sin(_ctrl.value * math.pi * 2) * 4.0;
        final pulse =
            0.5 + 0.5 * math.sin(_ctrl.value * math.pi * 2 + math.pi);

        final presenceColor = switch (widget.presence) {
          PresenceStatus.online  => const Color(0xFF4ADE80),
          PresenceStatus.offline => const Color(0xFF6B7280),
          PresenceStatus.unknown => const Color(0xFF6B7280),
        };

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.translate(
              offset: Offset(0, bob),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // Dynamic expanding accuracy circle (Google Maps style)
                  AnimatedBuilder(
                    animation: _ctrl,
                    builder: (context, child) {
                      final scale = 1.0 + _ctrl.value * 1.5;
                      final opacity = (0.32 * (1.0 - _ctrl.value)).clamp(0.0, 1.0);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.markerColor.withValues(alpha: opacity * 0.2),
                            border: Border.all(
                              color: widget.markerColor.withValues(alpha: opacity * 0.5),
                              width: 1.5,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  // Outer glow halo
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (widget.showHomeHighlight ? const Color(0xFF4ADE80) : widget.markerColor)
                              .withValues(alpha: widget.showHomeHighlight ? (0.50 + pulse * 0.30) : (0.38 + pulse * 0.22)),
                          blurRadius: widget.showHomeHighlight ? (24 + pulse * 10) : (20 + pulse * 8),
                          spreadRadius: widget.showHomeHighlight ? (4 + pulse * 2) : 2,
                        ),
                      ],
                    ),
                  ),
                  // Pulsing ring border
                  Container(
                    width: 66,
                    height: 66,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: (widget.showHomeHighlight ? const Color(0xFF4ADE80) : widget.markerColor)
                            .withValues(alpha: widget.showHomeHighlight ? (0.45 + pulse * 0.45) : (0.30 + pulse * 0.42)),
                        width: widget.showHomeHighlight ? 3.5 : 2.5,
                      ),
                    ),
                  ),
                  // Inner translucent fill
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (widget.showHomeHighlight ? const Color(0xFF4ADE80) : widget.markerColor).withValues(alpha: 0.10),
                    ),
                  ),
                  // Avatar circle
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.markerColor,
                      border: Border.all(
                        color: widget.showHomeHighlight ? const Color(0xFF4ADE80) : Colors.white,
                        width: widget.showHomeHighlight ? 4.0 : 2.5,
                      ),
                      boxShadow: [
                        if (widget.showHomeHighlight)
                          BoxShadow(
                            color: const Color(0xFF4ADE80).withValues(alpha: 0.6 + pulse * 0.4),
                            blurRadius: 12 + pulse * 6,
                            spreadRadius: 3 + pulse * 2,
                          )
                        else
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.45),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                      ],
                      image: widget.avatarUrl != null
                          ? DecorationImage(
                              image: NetworkImage(widget.avatarUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: widget.avatarUrl == null
                        ? Center(
                            child: Text(
                              widget.initials ??
                                  widget.name
                                      .substring(0, 1)
                                      .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                ),
                              ),
                            )
                          : null,
                    ),
                  // Presence dot (bottom-right)
                  Positioned(
                    right: 6,
                    bottom: 6,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: presenceColor,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: presenceColor.withValues(alpha: 0.65),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Name + status badge
            Container(
              constraints: const BoxConstraints(maxWidth: 108),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.82),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.markerColor.withValues(alpha: 0.35),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.name,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.3,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (widget.presence != PresenceStatus.unknown)
                    Text(
                      widget.presence == PresenceStatus.online
                          ? '● Online'
                          : widget.lastSeenLabel != null
                              ? '● ${widget.lastSeenLabel}'
                              : '● Offline',
                      style: TextStyle(
                        color: presenceColor.withValues(alpha: 0.90),
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: IsometricMarker — compatibility adapter (SAME external API)
// Routes to the correct Canvas-based game marker based on `type`.
// ─────────────────────────────────────────────────────────────────────────────

class IsometricMarker extends StatefulWidget {
  final String type; // 'home', 'work', or vehicle type name
  final String label;
  final Color color;
  final bool isAnimated;
  final String? initials;
  final PresenceStatus presence;
  final String? lastSeenLabel;

  const IsometricMarker({
    required this.type,
    required this.label,
    required this.color,
    this.isAnimated = true,
    this.initials,
    this.presence = PresenceStatus.unknown,
    this.lastSeenLabel,
    super.key,
  });

  @override
  State<IsometricMarker> createState() => _IsometricMarkerState();
}

class _IsometricMarkerState extends State<IsometricMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    if (widget.isAnimated) _ctrl.repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.type.toLowerCase();
    if (t == 'home') return _buildHome();
    if (t == 'work') return _buildBuilding();
    return _buildVehicle(t);
  }

  Widget _buildHome() {
    final wallColor = Color.lerp(Colors.white, widget.color, 0.30)!;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 88,
            child: Image.asset(
              'assets/maps_res/markers/home/home_marker.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              errorBuilder: (_, _, _) => CustomPaint(
                painter: _HousePainter(
                  roofColor: widget.color,
                  wallColor: wallColor,
                  phase: _ctrl.value,
                ),
              ),
            ),
          ),
          _buildLabel(),
        ],
      ),
    );
  }

  Widget _buildBuilding() {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 88,
            child: Image.asset(
              'assets/maps_res/markers/office/office_marker.png',
              fit: BoxFit.contain,
              filterQuality: FilterQuality.high,
              isAntiAlias: true,
              errorBuilder: (_, _, _) => CustomPaint(
                painter: _BuildingPainter(
                  accentColor: widget.color,
                  phase: _ctrl.value,
                ),
              ),
            ),
          ),
          _buildLabel(),
        ],
      ),
    );
  }

  Widget _buildVehicle(String type) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 88,
            child: CustomPaint(
              painter: _VehiclePainter(
                vehicleType: type,
                color: widget.color,
                phase: _ctrl.value,
              ),
            ),
          ),
          _buildLabel(),
        ],
      ),
    );
  }

  Widget _buildLabel() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 115),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Text(
        widget.label,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: PhotorealisticMarker — kept for backward compatibility
// Falls back to a themed gold location pin if the asset is missing.
// ─────────────────────────────────────────────────────────────────────────────

class PhotorealisticMarker extends StatelessWidget {
  final String imageAsset;
  final double size;
  final AnimationController controller;
  final Widget? fallback;

  const PhotorealisticMarker({
    required this.imageAsset,
    this.size = 65.0,
    required this.controller,
    this.fallback,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final bobValue =
            math.sin(controller.value * math.pi * 2) * 5.0 - 5.0;
        final shadowScale = 1.0 + (bobValue / 33.0);
        final shadowOpacity = 0.42 + (bobValue / 32.0);

        return Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            Transform.translate(
              offset: const Offset(0, 1.5),
              child: Transform.scale(
                scaleX: shadowScale * 1.15,
                scaleY: shadowScale * 0.45,
                child: Container(
                  width: size * 0.75,
                  height: size * 0.22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.black.withValues(
                            alpha: shadowOpacity.clamp(0.08, 0.55)),
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, bobValue - 3.5),
              child: SizedBox(
                width: size,
                height: size,
                child: Image.asset(
                  imageAsset,
                  filterQuality: FilterQuality.high,
                  fit: BoxFit.contain,
                  isAntiAlias: true,
                  errorBuilder: (context, error, stackTrace) {
                    return fallback ??
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1A55)
                                .withValues(alpha: 0.90),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFFF59E0B),
                              width: 1.8,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.location_on_rounded,
                              color: Color(0xFFF59E0B),
                              size: 24,
                            ),
                          ),
                        );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// WIDGET: Animated3DTrackingMarker — PNG-asset driven live tracking marker
//
// WALKING (TransitMode.walking)
//   • Cycles through assets/maps_res/walking/{person}/frame_{1-4}.png
//   • Controller fires 100 ms frame timer only while isMoving == true
//   • Sprite image is pinned at Alignment.bottomCenter to prevent jitter
//   • person folder: 'rodel' or 'eurine' (derived from [label])
//
// VEHICLE (all other TransitMode values)
//   • Single rear-view PNG: assets/maps_res/markers/{mode}/{stem}_rear.png
//   • bearing rotation    → heading direction
//   • bankAngle rotation  → Z-axis lean (Chase Camera Banking on turns)
//
// Both modes fall back to the _VehiclePainter canvas if the PNG is missing.
// ─────────────────────────────────────────────────────────────────────────────

class Animated3DTrackingMarker extends StatefulWidget {
  final RealtimeAnimatedMarkerController controller;

  /// Display name of the person, used to pick the walking sprite folder.
  /// 'Rodel' → assets/maps_res/walking/rodel/
  /// Anything else (e.g. 'Eurine') → assets/maps_res/walking/eurine/
  final String label;
  final Color markerColor;

  const Animated3DTrackingMarker({
    required this.controller,
    required this.label,
    required this.markerColor,
    super.key,
  });

  @override
  State<Animated3DTrackingMarker> createState() =>
      _Animated3DTrackingMarkerState();
}

class _Animated3DTrackingMarkerState extends State<Animated3DTrackingMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bobController;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bobController.dispose();
    super.dispose();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Determines the walking sprite sub-folder from the person's display name.
  String get _walkingFolder =>
      widget.label.toLowerCase().startsWith('rodel') ? 'rodel' : 'eurine';

  /// Returns (asset sub-folder, image stem) for a vehicle transit mode.
  (String, String) _vehicleAsset(TransitMode mode) {
    return switch (mode) {
      TransitMode.bicycling  => ('biking',     'bike'),
      TransitMode.motorcycle => ('motorcycle', 'aerox'),
      TransitMode.driving    => ('driving',    'everest'),
      TransitMode.transit    => ('transit',    'bus'),
      _                      => ('driving',    'everest'),
    };
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final mode      = widget.controller.transitMode;
        final bearing   = widget.controller.bearing;
        final bankAngle = widget.controller.bankAngle;
        final frame     = widget.controller.currentFrame;
        final isMoving  = widget.controller.isMoving;
        final isWalking = mode == TransitMode.walking;

        return AnimatedBuilder(
          animation: _bobController,
          builder: (context, _) {
            final bob           = _bobController.value * -4.0;
            final shadowScale   = 1.0 - (_bobController.value * 0.12);
            final shadowOpacity = 0.32 - (_bobController.value * 0.08);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.bottomCenter,
                  clipBehavior: Clip.none,
                  children: [
                    // ── Soft radial drop-shadow grounding the marker ────────
                    Transform.scale(
                      scaleX: shadowScale * 1.40,
                      scaleY: shadowScale * 0.45,
                      child: Container(
                        width: 52,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.black.withValues(
                                  alpha: shadowOpacity.clamp(0.0, 0.45)),
                              Colors.black.withValues(alpha: 0.0),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Sprite / vehicle image with bobbing offset ──────────
                    Transform.translate(
                      offset: Offset(0, bob - 10.0),
                      child: isWalking
                          ? _buildWalkingSprite(frame, bearing)
                          : _buildVehicleImage(
                              mode, bearing, bankAngle, isMoving),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _buildLabel(),
              ],
            );
          },
        );
      },
    );
  }

  // ── Walking sprite: frame-cycled PNG, bottom-center pinned ───────────────
  Widget _buildWalkingSprite(int frame, double bearing) {
    final path =
        'assets/maps_res/walking/$_walkingFolder/frame_$frame.png';
    // Check if moving West/Leftwards (bearing is between -pi and 0)
    // bearing = 0 is North, pi/2 is East, pi is South, -pi/2 is West.
    final bool isMovingLeft = bearing < 0 && bearing > -math.pi;

    return SizedBox(
      width: 64,
      height: 72,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Transform(
          alignment: Alignment.center,
          transform: isMovingLeft ? Matrix4.rotationY(math.pi) : Matrix4.identity(),
          child: Image.asset(
            path,
            width: 64,
            height: 72,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            errorBuilder: (_, _, _) => CustomPaint(
              size: const Size(64, 72),
              painter: _VehiclePainter(
                vehicleType: 'walking',
                color: widget.markerColor,
                phase: frame / 4.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Vehicle image: rear-view PNG with bearing + Z-axis banking ────────────
  Widget _buildVehicleImage(
    TransitMode mode,
    double bearing,
    double bankAngle,
    bool isMoving,
  ) {
    final (folder, stem) = _vehicleAsset(mode);
    final path = 'assets/maps_res/markers/$folder/${stem}_rear.png';

    // bearing  = heading rotation (which direction the vehicle faces)
    // bankAngle = lean/tilt on Z-axis when turning (Chase Camera Banking)
    return Transform.rotate(
      angle: bearing,
      child: Transform.rotate(
        angle: bankAngle,
        child: SizedBox(
          width: 68,
          height: 68,
          child: Image.asset(
            path,
            width: 68,
            height: 68,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            isAntiAlias: true,
            errorBuilder: (_, _, _) => CustomPaint(
              size: const Size(68, 68),
              painter: _VehiclePainter(
                vehicleType: mode.name,
                color: widget.markerColor,
                phase: isMoving ? 0.5 : 0.0,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Label bubble ─────────────────────────────────────────────────────────
  Widget _buildLabel() {
    return Container(
      constraints: const BoxConstraints(maxWidth: 115),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.markerColor.withValues(alpha: 0.30),
          width: 0.8,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black38,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        widget.label,
        style: GoogleFonts.inter(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
