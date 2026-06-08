import 'package:flutter/material.dart';

/// Shared animation constants for the entire RodMae app.
final class RodMaeAnimations {
  RodMaeAnimations._();

  // === DURATIONS ===
  static const Duration instant     = Duration(milliseconds: 120);
  static const Duration fast        = Duration(milliseconds: 220);
  static const Duration normal      = Duration(milliseconds: 360);
  static const Duration slow        = Duration(milliseconds: 520);
  static const Duration verySlow    = Duration(milliseconds: 800);
  static const Duration entrance    = Duration(milliseconds: 600);

  // === CURVES ===
  static const Curve spring         = Curves.elasticOut;
  static const Curve smooth         = Curves.easeInOutCubic;
  static const Curve snappy         = Curves.easeOutBack;
  static const Curve gentle         = Curves.easeInOut;
  static const Curve bouncy         = Curves.bounceOut;

  // === STAGGER DELAYS (for list items entering) ===
  static Duration staggerDelay(int index, {int baseMs = 60}) =>
      Duration(milliseconds: baseMs * index);

  // === 3D PERSPECTIVE DEPTH ===
  /// Apply perspective to a Matrix4 for 3D tilt effects.
  static Matrix4 perspective({
    double tiltX = 0,
    double tiltY = 0,
    double depth = 0.001,
  }) {
    return Matrix4.identity()
      ..setEntry(3, 2, depth)
      ..rotateX(tiltX)
      ..rotateY(tiltY);
  }

  // === PAGE TRANSITION ===
  static Widget buildSlide3DTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    final tween = Tween(begin: begin, end: end).chain(
      CurveTween(curve: Curves.easeOutCubic),
    );
    final fadeTween = Tween<double>(begin: 0.0, end: 1.0).chain(
      CurveTween(curve: const Interval(0.0, 0.7)),
    );
    final scaleTween = Tween<double>(begin: 0.94, end: 1.0).chain(
      CurveTween(curve: Curves.easeOutCubic),
    );
    return SlideTransition(
      position: animation.drive(tween),
      child: FadeTransition(
        opacity: animation.drive(fadeTween),
        child: ScaleTransition(
          scale: animation.drive(scaleTween),
          child: child,
        ),
      ),
    );
  }
}

/// A widget that fades + slides in on first build, with optional stagger delay.
class StaggeredEntrance extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final Duration duration;
  final Offset beginOffset;

  const StaggeredEntrance({
    required this.child,
    this.delay = Duration.zero,
    this.duration = const Duration(milliseconds: 500),
    this.beginOffset = const Offset(0, 0.08),
    super.key,
  });

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: widget.beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// A pulsing glow ring animation widget.
class PulseGlow extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final double minScale;
  final double maxScale;
  final Duration duration;

  const PulseGlow({
    required this.child,
    required this.glowColor,
    this.minScale = 0.95,
    this.maxScale = 1.05,
    this.duration = const Duration(milliseconds: 1400),
    super.key,
  });

  @override
  State<PulseGlow> createState() => _PulseGlowState();
}

class _PulseGlowState extends State<PulseGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration)
      ..repeat(reverse: true);
    _scale = Tween<double>(begin: widget.minScale, end: widget.maxScale)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scale, child: widget.child);
  }
}
