import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/meal_plan.dart';

enum LoveSignalVisualMode {
  rubyHearts,
  bioOrbs,
  neonRings,
  goldenAurora;

  static LoveSignalVisualMode fromTitle(String title) {
    switch (title.trim().toLowerCase()) {
      case 'i love you':
        return LoveSignalVisualMode.rubyHearts;
      case 'miss you':
        return LoveSignalVisualMode.bioOrbs;
      case 'flying kiss':
        return LoveSignalVisualMode.neonRings;
      case 'warm embrace':
        return LoveSignalVisualMode.goldenAurora;
      default:
        return LoveSignalVisualMode.goldenAurora;
    }
  }
}

final class CinematicParticle {
  final double x;
  final double y;
  final double radius;
  final double depth;
  final double phase;
  final double drift;
  final double twistSpeed;

  const CinematicParticle({
    required this.x,
    required this.y,
    required this.radius,
    required this.depth,
    required this.phase,
    required this.drift,
    required this.twistSpeed,
  });
}

final class RubyHeartSpec {
  final double x;
  final double y;
  final double size;
  final double depth;
  final double phase;
  final double rotation;

  const RubyHeartSpec({
    required this.x,
    required this.y,
    required this.size,
    required this.depth,
    required this.phase,
    required this.rotation,
  });
}

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

class _Custom3DLoveOverlayState extends State<Custom3DLoveOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ambientController;
  late final List<CinematicParticle> _particles;
  late final List<RubyHeartSpec> _hearts;
  late final LoveSignalVisualMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = LoveSignalVisualMode.fromTitle(widget.trigger.title);
    widget.controller.duration = const Duration(milliseconds: 4200);
    if (!widget.controller.isAnimating) {
      widget.controller.forward(from: 0);
    }

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    final random = math.Random(widget.trigger.title.hashCode);

    // Aurora gets 320 particles; rings get 48; others get 88
    final particleCount = switch (_mode) {
      LoveSignalVisualMode.goldenAurora => 320,
      LoveSignalVisualMode.neonRings   => 48,
      _                                 => 88,
    };

    _particles = List.generate(
      particleCount,
      (index) => CinematicParticle(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: 0.4 + random.nextDouble() * 3.2,
        depth: 0.3 + random.nextDouble() * 1.4,
        phase: random.nextDouble() * math.pi * 2,
        drift: -0.8 + random.nextDouble() * 1.6,
        twistSpeed: 0.6 + random.nextDouble() * 1.2,
      ),
    );

    _hearts = List.generate(
      28,
      (index) => RubyHeartSpec(
        x: random.nextDouble(),
        y: random.nextDouble(),
        size: 0.38 + random.nextDouble() * 1.32,
        depth: 0.42 + random.nextDouble() * 1.5,
        phase: random.nextDouble() * math.pi * 2,
        rotation: -0.55 + random.nextDouble() * 1.1,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant Custom3DLoveOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trigger.title != widget.trigger.title) {
      widget.controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ambientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: RepaintBoundary(
        child: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: AnimatedBuilder(
              animation: Listenable.merge([widget.controller, _ambientController]),
              builder: (context, _) {
                final progress = widget.controller.value.clamp(0.0, 1.0);
                final time = _ambientController.value;
                final entrance =
                    Curves.easeOutCubic.transform((progress * 1.5).clamp(0.0, 1.0));
                final exitFade = progress > 0.84
                    ? (1.0 - ((progress - 0.84) / 0.16)).clamp(0.0, 1.0)
                    : 1.0;

                return DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.78 * exitFade),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── Background particle field ────────────────────────
                      CustomPaint(
                        painter: CinematicLoveSignalPainter(
                          mode: _mode,
                          progress: progress,
                          time: time,
                          particles: _particles,
                          hearts: _hearts,
                        ),
                      ),
                      // ── Hero 3D icon in the centre ───────────────────────
                      Center(
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..setEntry(3, 2, 0.0015)
                            ..translateByDouble(
                              0,
                              math.sin(time * math.pi * 2) * 10,
                              0,
                              1,
                            )
                            ..rotateX(math.sin(time * math.pi * 2) * 0.09)
                            ..rotateY(math.cos(time * math.pi * 2) * 0.20)
                            ..scaleByDouble(
                              0.72 + entrance * 0.28,
                              0.72 + entrance * 0.28,
                              0.72 + entrance * 0.28,
                              1,
                            ),
                          child: SizedBox.square(
                            dimension: 240,
                            child: CustomPaint(
                              painter: HeroSignalPainter(
                                mode: _mode,
                                progress: progress,
                                time: time,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // ── Overlay label at bottom ──────────────────────────
                      Positioned(
                        left: 28,
                        right: 28,
                        bottom: MediaQuery.sizeOf(context).height * 0.13,
                        child: Opacity(
                          opacity: exitFade,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0012)
                              ..translateByDouble(0, (1 - entrance) * 40, 0, 1)
                              ..scaleByDouble(entrance, entrance, entrance, 1),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.trigger.overlayTitle,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 23,
                                    height: 1.15,
                                    fontWeight: FontWeight.w900,
                                    shadows: [
                                      Shadow(
                                        blurRadius: 28,
                                        color: _accentColor(_mode)
                                            .withValues(alpha: 0.90),
                                      ),
                                      Shadow(
                                        blurRadius: 48,
                                        color: Colors.black.withValues(alpha: 0.88),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  _modeLabel(_mode),
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: Colors.white.withValues(alpha: 0.68),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  static Color _accentColor(LoveSignalVisualMode mode) {
    switch (mode) {
      case LoveSignalVisualMode.rubyHearts:
        return const Color(0xFFFF1744);
      case LoveSignalVisualMode.bioOrbs:
        return const Color(0xFF22D3EE);
      case LoveSignalVisualMode.neonRings:
        return const Color(0xFFFF2D95);
      case LoveSignalVisualMode.goldenAurora:
        return const Color(0xFFFFD166);
    }
  }

  static String _modeLabel(LoveSignalVisualMode mode) {
    switch (mode) {
      case LoveSignalVisualMode.rubyHearts:
        return 'GLOSSY RUBY GLASS HEARTS';
      case LoveSignalVisualMode.bioOrbs:
        return 'ETHEREAL BIOLUMINESCENT ORBS';
      case LoveSignalVisualMode.neonRings:
        return 'NEON SONIC SHOCKWAVES';
      case LoveSignalVisualMode.goldenAurora:
        return 'GOLDEN STARDUST AURORA';
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background Painter — particle fields & ambient effects
// ─────────────────────────────────────────────────────────────────────────────

class CinematicLoveSignalPainter extends CustomPainter {
  final LoveSignalVisualMode mode;
  final double progress;
  final double time;
  final List<CinematicParticle> particles;
  final List<RubyHeartSpec> hearts;

  const CinematicLoveSignalPainter({
    required this.mode,
    required this.progress,
    required this.time,
    required this.particles,
    required this.hearts,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _paintVignette(canvas, size);
    switch (mode) {
      case LoveSignalVisualMode.rubyHearts:
        _paintRubyHeartField(canvas, size);
      case LoveSignalVisualMode.bioOrbs:
        _paintBioluminescentOrbs(canvas, size);
      case LoveSignalVisualMode.neonRings:
        _paintNeonRings(canvas, size);
      case LoveSignalVisualMode.goldenAurora:
        _paintGoldenAurora(canvas, size);
    }
  }

  // ── Deep edge vignette for cinematic framing ─────────────────────────────
  void _paintVignette(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 1.10,
        colors: [
          Colors.transparent,
          Colors.black.withValues(alpha: 0.28),
          Colors.black.withValues(alpha: 0.78),
        ],
        stops: const [0.0, 0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  // ── A. I Love You — Floating Glossy 3D Ruby Glass Hearts ────────────────
  void _paintRubyHeartField(Canvas canvas, Size size) {
    for (final heart in hearts) {
      final local = (progress * heart.depth + heart.phase / (math.pi * 2)) % 1.0;
      final x = heart.x * size.width +
          math.sin(time * math.pi * 2 + heart.phase) * 38 * heart.depth;
      final y = size.height * (1.14 - local * 1.32);
      final opacity =
          (math.sin(local * math.pi).clamp(0.0, 1.0) * progress).clamp(0.0, 0.92);
      final side = 16 + heart.size * 24;

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(heart.rotation + math.sin(time * 5.5 + heart.phase) * 0.22);
      canvas.scale(0.65 + heart.depth * 0.28);
      _paintRubyHeart(
        canvas,
        Size(side, side),
        opacity: opacity,
        shadowLift: 10 + heart.depth * 10,
      );
      canvas.restore();
    }
  }

  // ── B. Miss You — Ethereal Bioluminescent Orbs ───────────────────────────
  void _paintBioluminescentOrbs(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // Ambient atmospheric haze
    final haze = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.22, -0.38),
        radius: 1.18,
        colors: [
          const Color(0xFF312E81).withValues(alpha: 0.48),
          const Color(0xFF0E7490).withValues(alpha: 0.26),
          Colors.transparent,
        ],
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40);
    canvas.drawRect(rect, haze);

    // Secondary haze from opposite corner
    final haze2 = Paint()
      ..shader = RadialGradient(
        center: const Alignment(0.6, 0.5),
        radius: 0.9,
        colors: [
          const Color(0xFF4C1D95).withValues(alpha: 0.28 * progress),
          Colors.transparent,
        ],
      ).createShader(rect)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 32);
    canvas.drawRect(rect, haze2);

    for (final particle in particles) {
      final drift = time * 1.8 + progress * 0.6;
      final x =
          ((particle.x + math.sin(drift + particle.phase) * 0.055) % 1.0) *
              size.width;
      final y = ((particle.y -
                  progress * 0.20 * particle.depth +
                  math.cos(drift + particle.phase) * 0.04) %
              1.0) *
          size.height;
      final pulse =
          0.52 + math.sin(time * math.pi * 3.5 + particle.phase) * 0.48;
      final radius = particle.radius * (5.5 + particle.depth * 4.8);
      final opacity = (0.20 + pulse * 0.48) * progress;
      final orbRect = Rect.fromCircle(center: Offset(x, y), radius: radius * 2.6);

      // Outer glow aura
      final glow = Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFECFEFF).withValues(alpha: opacity),
            const Color(0xFF22D3EE).withValues(alpha: opacity * 0.75),
            const Color(0xFF7C3AED).withValues(alpha: opacity * 0.50),
            Colors.transparent,
          ],
          stops: const [0.0, 0.18, 0.52, 1.0],
        ).createShader(orbRect)
        ..maskFilter =
            MaskFilter.blur(BlurStyle.normal, 14 + radius * 0.40);
      canvas.drawCircle(Offset(x, y), radius * 2.2, glow);

      // Bright core with glass-like highlight
      final core = Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.38, -0.44),
          colors: [
            Colors.white.withValues(alpha: opacity * 1.3),
            const Color(0xFF67E8F9).withValues(alpha: opacity),
            const Color(0xFF4C1D95).withValues(alpha: opacity * 0.62),
          ],
        ).createShader(
            Rect.fromCircle(center: Offset(x, y), radius: radius));
      canvas.drawCircle(Offset(x, y), radius * 0.45, core);
    }
  }

  // ── C. Flying Kiss — Neon Sonic Shockwave Rings ──────────────────────────
  void _paintNeonRings(Canvas canvas, Size size) {
    final center = Offset(
      size.width * 0.5 + math.sin(time * math.pi * 2) * 20,
      size.height * 0.43 + math.cos(time * math.pi * 2) * 16,
    );

    // Pulsing background bloom
    final bloom = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF2D95).withValues(alpha: 0.22 * progress),
          const Color(0xFF7C3AED).withValues(alpha: 0.12 * progress),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * 0.68))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 36);
    canvas.drawCircle(center, size.width * 0.64, bloom);

    // 10 expanding shockwave rings with sweep gradient glow
    for (var i = 0; i < 10; i++) {
      final wave = (progress * 1.5 + i / 10 + time * 0.06) % 1.0;
      final radius = size.shortestSide * (0.06 + wave * 0.76);
      final opacity = math.pow(1.0 - wave, 1.6).toDouble() * progress;
      if (opacity < 0.02) continue;

      // Thick glow stroke
      final blurPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10 + (1.0 - wave) * 12
        ..shader = SweepGradient(
          colors: [
            const Color(0xFFFF2D95).withValues(alpha: opacity),
            const Color(0xFFFF77E9).withValues(alpha: opacity * 0.85),
            const Color(0xFFFB7185).withValues(alpha: opacity),
            const Color(0xFFFF2D95).withValues(alpha: opacity),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawCircle(center, radius, blurPaint);

      // Thin crisp white rim for definition
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFFFFF1F8).withValues(alpha: opacity * 0.90),
      );
    }

    // Orbiting spark particles
    for (final particle in particles) {
      final angle =
          particle.phase + time * math.pi * 2 * particle.twistSpeed;
      final dist = size.shortestSide * (0.15 + particle.x * 0.50);
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * dist;
      final sparkOpacity =
          progress * (0.55 + math.sin(time * math.pi * 6 + particle.phase) * 0.45);
      canvas.drawCircle(
        point,
        particle.radius * 1.8,
        Paint()
          ..color = const Color(0xFFFFB7DB).withValues(alpha: sparkOpacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5),
      );
    }
  }

  // ── D. Warm Embrace — Golden Stardust Aurora ─────────────────────────────
  void _paintGoldenAurora(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 4 undulating aurora ribbon bands
    for (var band = 0; band < 4; band++) {
      final yBase = size.height * (0.20 + band * 0.17);
      final path = Path()..moveTo(-size.width * 0.08, yBase);
      for (var i = 0; i <= 6; i++) {
        final x = size.width * (i / 6);
        final y = yBase +
            math.sin(time * math.pi * 2 + i * 0.8 + band * 0.7) *
                (38 + band * 14);
        path.cubicTo(
          x - size.width * 0.10,
          y - 38,
          x - size.width * 0.04,
          y + 48,
          x,
          y,
        );
      }

      final aurora = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 34 + band * 14
        ..strokeCap = StrokeCap.round
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            const Color(0xFFFFF1B8).withValues(alpha: 0.08 * progress),
            const Color(0xFFFFD166).withValues(alpha: 0.22 * progress),
            const Color(0xFFD97706).withValues(alpha: 0.10 * progress),
            Colors.transparent,
          ],
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 30 + band * 10);
      canvas.drawPath(path, aurora);
    }

    // 320 golden stardust particles with twinkle + drift
    for (final particle in particles) {
      final rise = progress * (0.28 + particle.depth * 0.22);
      final x = ((particle.x +
                  math.sin(time * math.pi * 2 + particle.phase) *
                      0.032 *
                      particle.depth +
                  particle.drift * time * 0.022) %
              1.0) *
          size.width;
      final y = ((particle.y - rise + 1.0) % 1.0) * size.height;
      final twinkle =
          0.44 + math.sin(time * math.pi * particle.twistSpeed * 6 + particle.phase) * 0.56;
      final radius = particle.radius * (0.72 + particle.depth * 0.38);
      final opacity = progress * (0.22 + twinkle * 0.78);

      if (opacity < 0.04) continue;

      // Soft outer glow
      canvas.drawCircle(
        Offset(x, y),
        radius * 2.4,
        Paint()
          ..color = const Color(0xFFFFE8A3).withValues(alpha: opacity * 0.68)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 2.6),
      );

      // Bright core star dot
      canvas.drawCircle(
        Offset(x, y),
        radius * 0.52,
        Paint()
          ..color = Colors.white.withValues(alpha: opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8),
      );

      // Occasional larger sparkle for variety
      if (particle.phase > math.pi * 1.5) {
        final sparkle = twinkle * progress;
        canvas.drawCircle(
          Offset(x, y),
          radius * 1.4,
          Paint()
            ..color = const Color(0xFFFFF1B8).withValues(alpha: sparkle * 0.42)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 1.2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CinematicLoveSignalPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.time != time ||
        oldDelegate.mode != mode;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Painter — the large central 3D icon
// ─────────────────────────────────────────────────────────────────────────────

class HeroSignalPainter extends CustomPainter {
  final LoveSignalVisualMode mode;
  final double progress;
  final double time;

  const HeroSignalPainter({
    required this.mode,
    required this.progress,
    required this.time,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (mode) {
      case LoveSignalVisualMode.rubyHearts:
        _paintRubyHeart(canvas, size, opacity: progress, shadowLift: 22);
      case LoveSignalVisualMode.bioOrbs:
        _paintHeroOrb(canvas, size);
      case LoveSignalVisualMode.neonRings:
        _paintHeroRing(canvas, size);
      case LoveSignalVisualMode.goldenAurora:
        _paintHeroAurora(canvas, size);
    }
  }

  // ── Hero Orb for Miss You ─────────────────────────────────────────────────
  void _paintHeroOrb(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * 0.35;
    final glowRect = Rect.fromCircle(center: center, radius: radius * 2.5);

    // Outer atmospheric glow
    canvas.drawCircle(
      center,
      radius * 2.2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.32 * progress),
            const Color(0xFF22D3EE).withValues(alpha: 0.32 * progress),
            const Color(0xFF7C3AED).withValues(alpha: 0.28 * progress),
            Colors.transparent,
          ],
          stops: const [0.0, 0.22, 0.56, 1.0],
        ).createShader(glowRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // Glossy glass orb body
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.44, -0.46),
          colors: [
            Colors.white.withValues(alpha: 0.96 * progress),
            const Color(0xFF67E8F9).withValues(alpha: 0.94 * progress),
            const Color(0xFF2563EB).withValues(alpha: 0.76 * progress),
            const Color(0xFF2E1065).withValues(alpha: 0.94 * progress),
          ],
          stops: const [0.0, 0.20, 0.60, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // Specular highlight glint
    canvas.drawOval(
      Rect.fromCenter(
        center: center.translate(-radius * 0.30, -radius * 0.42),
        width: radius * 0.70,
        height: radius * 0.32,
      ),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.52 * progress)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
    );
  }

  // ── Hero Rings for Flying Kiss ────────────────────────────────────────────
  void _paintHeroRing(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    for (var i = 0; i < 6; i++) {
      final wave = (progress + i * 0.15 + time * 0.07) % 1.0;
      final radius = size.shortestSide * (0.14 + wave * 0.36);
      final opacity = math.pow(1.0 - wave, 1.4).toDouble() * progress;
      if (opacity < 0.02) continue;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (11 - i).toDouble()
          ..shader = SweepGradient(
            colors: [
              const Color(0xFFFF2D95).withValues(alpha: opacity),
              const Color(0xFFFF77E9).withValues(alpha: opacity),
              const Color(0xFFFF2D95).withValues(alpha: opacity),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: radius))
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = Colors.white.withValues(alpha: opacity * 0.84),
      );
    }
  }

  // ── Hero Aurora for Warm Embrace ─────────────────────────────────────────
  void _paintHeroAurora(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final haloRect =
        Rect.fromCircle(center: center, radius: size.shortestSide * 0.60);

    // Golden radial halo
    canvas.drawCircle(
      center,
      size.shortestSide * 0.50,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0xFFFFF7D1).withValues(alpha: 0.38 * progress),
            const Color(0xFFFFD166).withValues(alpha: 0.28 * progress),
            const Color(0xFFB45309).withValues(alpha: 0.14 * progress),
            Colors.transparent,
          ],
        ).createShader(haloRect)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20),
    );

    // Animated golden ribbon
    final ribbonPath = Path()
      ..moveTo(size.width * 0.12, size.height * 0.60)
      ..cubicTo(
        size.width * 0.30,
        size.height * 0.24 + math.sin(time * math.pi * 2) * 14,
        size.width * 0.68,
        size.height * 0.86,
        size.width * 0.90,
        size.height * 0.36,
      );

    canvas.drawPath(
      ribbonPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 28
        ..strokeCap = StrokeCap.round
        ..shader = const LinearGradient(
          colors: [
            Color(0x00FFFFFF),
            Color(0xFFFFF1B8),
            Color(0xFFFFD166),
            Color(0x00FFFFFF),
          ],
        ).createShader(Offset.zero & size)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 11),
    );

    // 56 orbiting stardust dots
    for (var i = 0; i < 56; i++) {
      final angle = i / 56 * math.pi * 2 + time * math.pi * 2;
      final distance = size.shortestSide * (0.16 + (i % 10) * 0.016);
      final point =
          center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final a = progress * (0.34 + (i % 5) * 0.11);
      canvas.drawCircle(
        point,
        1.2 + (i % 4) * 0.50,
        Paint()
          ..color = const Color(0xFFFFF1B8).withValues(alpha: a)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant HeroSignalPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.time != time ||
        oldDelegate.mode != mode;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared Ruby Heart drawing function (used by both field and hero painters)
// ─────────────────────────────────────────────────────────────────────────────

void _paintRubyHeart(
  Canvas canvas,
  Size size, {
  required double opacity,
  required double shadowLift,
}) {
  if (opacity <= 0) {
    return;
  }

  final w = size.width;
  final h = size.height;
  final path = _heartPath(size);
  final rect = Rect.fromLTWH(0, 0, w, h);

  canvas.save();
  canvas.translate(-w / 2, -h / 2);

  // Deep shadow below the heart
  canvas.drawPath(
    path.shift(Offset(0, h * 0.10)),
    Paint()
      ..color = const Color(0xFF210006).withValues(alpha: 0.65 * opacity)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, shadowLift),
  );

  // Main ruby glass body — radial gradient simulates a glossy glass gemstone
  canvas.drawPath(
    path,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.48, -0.58),
        radius: 1.06,
        colors: [
          Colors.white.withValues(alpha: 0.97 * opacity),         // top-left specular
          const Color(0xFFFFB3C7).withValues(alpha: 0.98 * opacity), // pink highlight
          const Color(0xFFE11D48).withValues(alpha: opacity),         // mid ruby red
          const Color(0xFF7F1024).withValues(alpha: opacity),         // deep crimson
          const Color(0xFF2A0009).withValues(alpha: opacity),         // shadow maroon
        ],
        stops: const [0.0, 0.11, 0.36, 0.70, 1.0],
      ).createShader(rect),
  );

  // Inner rim — light top, dark bottom for glass depth illusion
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.058
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: 0.60 * opacity),
          Colors.transparent,
          const Color(0xFF140003).withValues(alpha: 0.72 * opacity),
        ],
      ).createShader(rect),
  );

  // Small top-left glint oval — the key to making it look 3D glass
  canvas.drawOval(
    Rect.fromCenter(
      center: Offset(w * 0.33, h * 0.27),
      width: w * 0.38,
      height: h * 0.17,
    ),
    Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.96 * opacity),
          Colors.white.withValues(alpha: 0.12 * opacity),
          Colors.transparent,
        ],
      ).createShader(
        Rect.fromCenter(
          center: Offset(w * 0.33, h * 0.27),
          width: w * 0.44,
          height: h * 0.28,
        ),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.6),
  );

  // Outer rim outline for edge clarity
  canvas.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Colors.white.withValues(alpha: 0.46 * opacity),
  );

  canvas.restore();
}

Path _heartPath(Size size) {
  final w = size.width;
  final h = size.height;
  return Path()
    ..moveTo(w * 0.50, h * 0.86)
    ..cubicTo(w * 0.16, h * 0.56, w * 0.05, h * 0.30, w * 0.20, h * 0.16)
    ..cubicTo(w * 0.34, h * 0.03, w * 0.49, h * 0.12, w * 0.50, h * 0.31)
    ..cubicTo(w * 0.51, h * 0.12, w * 0.66, h * 0.03, w * 0.80, h * 0.16)
    ..cubicTo(w * 0.95, h * 0.30, w * 0.84, h * 0.56, w * 0.50, h * 0.86)
    ..close();
}
