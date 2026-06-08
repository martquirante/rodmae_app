import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../models/meal_plan.dart';
import '../services/auth_service.dart';

class Custom3DLoveOverlay extends StatefulWidget {
  final LoveTrigger trigger;
  final AnimationController controller;

  const Custom3DLoveOverlay({
    required this.trigger,
    required this.controller,
    super.key,
  });

  @override
  State<Custom3DLoveOverlay> createState() => _Custom3DLoveOverlayState();
}

class _Custom3DLoveOverlayState extends State<Custom3DLoveOverlay> with TickerProviderStateMixin {
  late final List<math.Point<double>> _particles;
  late final AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    widget.controller.duration = const Duration(milliseconds: 3000);
    if (!widget.controller.isAnimating) {
      widget.controller.forward(from: 0);
    }
    
    final rand = math.Random();
    _particles = List.generate(35, (index) {
      return math.Point(
        rand.nextDouble(),
        rand.nextDouble() * 0.8 + 0.2,
      );
    });

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: Colors.black.withValues(alpha: 0.76),
            child: AnimatedBuilder(
              animation: widget.controller,
              builder: (context, _) {
                final progress = widget.controller.value;
                final scale = Curves.elasticOut.transform((progress * 2.0).clamp(0.0, 1.0)) * 0.95 +
                    (progress > 0.8 ? (1.0 - progress) * 5.0 : 0.0).clamp(0.0, 0.05);

                return Stack(
                  alignment: Alignment.center,
                  children: [
                    // Hearts Shower Particle Layer
                    if (widget.trigger.title == 'Miss You' || widget.trigger.title == 'I Love You')
                      ..._particles.map((p) {
                        final speed = p.y * 1.6;
                        final double yPos = 1.0 - ((progress * speed) % 1.25);
                        final double xOffset = math.sin(progress * 8.0 + p.x * 100.0) * 45.0;
                        final double opacity = (1.0 - yPos).clamp(0.0, 1.0) * (yPos > 0.1 ? 1.0 : (yPos / 0.1));
                        
                        return Positioned(
                          left: MediaQuery.of(context).size.width * p.x + xOffset,
                          bottom: MediaQuery.of(context).size.height * yPos,
                          child: Opacity(
                            opacity: opacity.clamp(0.0, 1.0),
                            child: Transform.scale(
                              scale: 0.4 + p.y * 0.5,
                              child: CustomPaint(
                                size: const Size(30, 30),
                                painter: HeartPainter(color: widget.trigger.color),
                              ),
                            ),
                          ),
                        );
                      }),

                    // Center 3D rotating sticker
                    Center(
                      child: Transform(
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0018)
                          ..scale(scale)
                          ..rotateY(_rotationController.value * 2.0 * math.pi)
                          ..rotateX(math.sin(_rotationController.value * 2.0 * math.pi) * 0.18),
                        alignment: Alignment.center,
                        child: _buildMainStickerWidget(),
                      ),
                    ),

                    // Title & Description
                    Positioned(
                      bottom: MediaQuery.of(context).size.height * 0.18,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.trigger.overlayTitle,
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(
                                  blurRadius: 16.0,
                                  color: widget.trigger.color.withValues(alpha: 0.6),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Sent with love',
                            style: GoogleFonts.inter(
                              color: Colors.white60,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainStickerWidget() {
    final t = widget.trigger.title;
    if (t == 'Miss You' || t == 'I Love You') {
      return CustomPaint(
        size: const Size(190, 190),
        painter: HeartPainter(color: widget.trigger.color),
      );
    } else if (t == 'Flying Kiss') {
      final isRodel = PartnerIdentity.active.value == PartnerProfile.rodel;
      final senderEmoji = isRodel ? '🤵' : '👰';
      final progress = widget.controller.value;
      final heartScale = progress * 2.8;
      final double heartOpacity = (1.0 - progress).clamp(0.0, 1.0);
      
      return SizedBox(
        width: 200,
        height: 200,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.12),
                border: Border.all(color: widget.trigger.color.withValues(alpha: 0.55), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: widget.trigger.color.withValues(alpha: 0.35),
                    blurRadius: 28,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                senderEmoji,
                style: const TextStyle(fontSize: 68),
              ),
            ),
            if (progress > 0.15)
              Positioned(
                top: 40 - (progress * 65),
                child: Opacity(
                  opacity: heartOpacity,
                  child: Transform.scale(
                    scale: heartScale.clamp(0.0, 2.8),
                    child: Transform(
                      transform: Matrix4.identity()
                        ..setEntry(3, 2, 0.0012)
                        ..rotateY(progress * 5.0 * math.pi),
                      alignment: Alignment.center,
                      child: CustomPaint(
                        size: const Size(60, 60),
                        painter: HeartPainter(color: widget.trigger.color),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    } else if (t == 'Heading Home') {
      return CustomPaint(
        size: const Size(190, 190),
        painter: CompassPainter(color: widget.trigger.color),
      );
    } else {
      // Surprise Note Envelope
      return Container(
        width: 190,
        height: 130,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [
              Colors.white.withValues(alpha: 0.94),
              Colors.white.withValues(alpha: 0.55),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: widget.trigger.color.withValues(alpha: 0.5),
              blurRadius: 36,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 14,
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.trigger.color.withValues(alpha: 0.18),
                ),
                child: Icon(Icons.sticky_note_2_rounded, color: widget.trigger.color, size: 24),
              ),
            ),
            Positioned(
              bottom: 20,
              child: Text(
                '❤️ Sweet Note Received ❤️',
                style: GoogleFonts.inter(
                  color: RodMaeColors.navy,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }
}

class HeartPainter extends CustomPainter {
  final Color color;
  const HeartPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          color,
          color.withValues(alpha: 0.75),
          Colors.black.withValues(alpha: 0.35),
        ],
        stops: const [0.0, 0.4, 0.75, 1.0],
        center: const Alignment(-0.25, -0.35),
        radius: 0.95,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final w = size.width;
    final h = size.height;
    
    path.moveTo(w / 2, h * 0.85);
    path.cubicTo(w * 0.12, h * 0.45, w * 0.08, h * 0.08, w / 2, h * 0.32);
    path.cubicTo(w * 0.92, h * 0.08, w * 0.88, h * 0.45, w / 2, h * 0.85);
    path.close();

    canvas.drawShadow(
      path.shift(const Offset(0, 12)),
      color.withValues(alpha: 0.6),
      14.0,
      true,
    );
    
    canvas.drawPath(path, paint);
    
    final highlightPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: 0.7),
          Colors.white.withValues(alpha: 0.0),
        ],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(w * 0.22, h * 0.18, w * 0.56, h * 0.22));
      
    final highlightPath = Path()
      ..moveTo(w * 0.32, h * 0.24)
      ..cubicTo(w * 0.22, h * 0.34, w * 0.42, h * 0.34, w * 0.52, h * 0.36)
      ..cubicTo(w * 0.42, h * 0.28, w * 0.37, h * 0.24, w * 0.32, h * 0.24)
      ..close();
      
    canvas.drawPath(highlightPath, highlightPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CompassPainter extends CustomPainter {
  final Color color;
  const CompassPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0
      ..shader = SweepGradient(
        colors: [color.withValues(alpha: 0.2), color, color.withValues(alpha: 0.2)],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final w = size.width;
    final h = size.height;
    
    canvas.drawCircle(Offset(w / 2, h / 2), w * 0.4, paint);

    final pointerPaint = Paint()
      ..style = PaintingStyle.fill
      ..shader = RadialGradient(
        colors: [Colors.white, color],
        center: const Alignment(-0.2, -0.2),
      ).createShader(Rect.fromLTWH(w * 0.35, h * 0.35, w * 0.3, h * 0.3));

    final path = Path()
      ..moveTo(w / 2, h * 0.25)
      ..lineTo(w * 0.62, h * 0.68)
      ..lineTo(w / 2, h * 0.58)
      ..lineTo(w * 0.38, h * 0.68)
      ..close();

    canvas.drawShadow(path.shift(const Offset(0, 6)), Colors.black.withValues(alpha: 0.4), 8.0, true);
    canvas.drawPath(path, pointerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
