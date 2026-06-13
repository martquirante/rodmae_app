import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// A widget that renders an animated burst of gold particles from a point.
/// Usage: wrap around a button or trigger it imperatively via [ParticleBurstController].
class ParticleBurst extends StatefulWidget {
  final Widget child;
  final int particleCount;
  final Color particleColor;
  final Color particleColor2;
  final double radius;

  const ParticleBurst({
    required this.child,
    this.particleCount = 16,
    this.particleColor = RodMaeColors.gold,
    this.particleColor2 = RodMaeColors.lemon,
    this.radius = 60,
    super.key,
  });

  @override
  State<ParticleBurst> createState() => ParticleBurstState();
}

class ParticleBurstState extends State<ParticleBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _playing = false;
  final _rand = math.Random();
  late List<_Particle> _particles;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _playing = false);
        _ctrl.reset();
      }
    });
    _generateParticles();
  }

  void _generateParticles() {
    _particles = List.generate(widget.particleCount, (i) {
      final angle = (i / widget.particleCount) * 2 * math.pi +
          _rand.nextDouble() * 0.4;
      final speed = 0.6 + _rand.nextDouble() * 0.4;
      final size = 3.0 + _rand.nextDouble() * 4;
      return _Particle(
        angle: angle,
        speed: speed,
        size: size,
        color: i % 2 == 0 ? widget.particleColor : widget.particleColor2,
      );
    });
  }

  /// Call this to trigger the burst animation.
  void burst() {
    _generateParticles();
    setState(() => _playing = true);
    _ctrl.forward(from: 0);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_playing)
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                return CustomPaint(
                  painter: _ParticlePainter(
                    particles: _particles,
                    progress: _ctrl.value,
                    radius: widget.radius,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final Color color;
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.color,
  });
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final double radius;

  const _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final eased = Curves.easeOut.transform(progress);

    for (final p in particles) {
      final dist = eased * radius * p.speed;
      final opacity = (1 - Curves.easeIn.transform(progress)).clamp(0.0, 1.0);
      final particleSize = p.size * (1 - eased * 0.5);

      final pos = Offset(
        center.dx + math.cos(p.angle) * dist,
        center.dy + math.sin(p.angle) * dist,
      );

      canvas.drawCircle(
        pos,
        particleSize,
        Paint()..color = p.color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_ParticlePainter old) =>
      old.progress != progress || old.particles != particles;
}
