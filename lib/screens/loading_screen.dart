import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';

class ElegantLoadingScreen extends StatefulWidget {
  const ElegantLoadingScreen({super.key});

  @override
  State<ElegantLoadingScreen> createState() => _ElegantLoadingScreenState();
}

class _ElegantLoadingScreenState extends State<ElegantLoadingScreen>
    with TickerProviderStateMixin {
  late final AnimationController _rotationCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _textFadeCtrl;

  int _statusIndex = 0;
  Timer? _statusTimer;
  bool _isExiting = false;

  final List<String> _loadingStatuses = [
    'Authenticating secure session...',
    'Syncing real-time coordinate maps...',
    'Warming up memory vault assets...',
    'Decrypting shared couple database...',
    'Preparing dashboard interface...',
    'Welcome back! Redirecting...',
  ];

  @override
  void initState() {
    super.initState();

    // 3D card continuous rotation controller
    _rotationCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();

    // Pulse glow animation
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    // Text fade transitions
    _textFadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();

    // Stagger loading status messages
    _statusTimer = Timer.periodic(const Duration(milliseconds: 400), (timer) {
      if (_statusIndex < _loadingStatuses.length - 1) {
        if (mounted) {
          _textFadeCtrl.reverse().then((_) {
            if (mounted) {
              setState(() {
                _statusIndex++;
              });
              _textFadeCtrl.forward();
            }
          });
        }
      } else {
        timer.cancel();
      }
    });

    // Navigate to home after loading completion (approx 2.5 seconds to feel smooth and premium)
    Future.delayed(const Duration(milliseconds: 2600), () {
      _exitToHome();
    });
  }

  void _exitToHome() {
    if (_isExiting || !mounted) return;
    setState(() => _isExiting = true);

    final startup = AppStartupStatus(
      firebaseReady: AppRuntime.firebaseReady,
      supabaseReady: AppRuntime.supabaseReady,
      issue: AppRuntime.startupIssue,
    );

    Navigator.of(context).pushReplacementNamed('/home', arguments: startup);
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _rotationCtrl.dispose();
    _pulseCtrl.dispose();
    _textFadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final partner = PartnerIdentity.active.value;

    return Scaffold(
      body: Stack(
        children: [
          // 1. App background gradient
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: RodMaeColors.getAppBackground(isDark),
            ),
          ),

          // 2. Rising glowing background particles
          const _FloatingParticlesLayer(),

          // 3. Central content with 3D effects
          SafeArea(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),

                  // Dynamic 3D Rotating Glass Gemstone/Monogram
                  AnimatedBuilder(
                    animation: _rotationCtrl,
                    builder: (context, child) {
                      // Custom 3D Y-axis rotation combined with X-axis bobbing tilt
                      final angleY = _rotationCtrl.value * 2 * math.pi;
                      final angleX = math.sin(_rotationCtrl.value * 2 * math.pi) * 0.18;

                      return Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0015) // perspective
                          ..rotateY(angleY)
                          ..rotateX(angleX),
                        child: child,
                      );
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Floating concentric glowing orbits
                        AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (context, child) {
                            return Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: RodMaeColors.gold.withValues(
                                    alpha: 0.1 + (_pulseCtrl.value * 0.15),
                                  ),
                                  width: 2.0,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: RodMaeColors.gold.withValues(
                                      alpha: 0.05 + (_pulseCtrl.value * 0.1),
                                    ),
                                    blurRadius: 24,
                                    spreadRadius: 2,
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        
                        // Inner elegant 3D card
                        Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: RodMaeColors.getCardGradient(isDark),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.35),
                                blurRadius: 16,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: partner.color.withValues(alpha: 0.18),
                                blurRadius: 28,
                                spreadRadius: 1,
                              ),
                            ],
                            border: Border.all(
                              color: RodMaeColors.gold.withValues(alpha: 0.35),
                              width: 1.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Backdrop golden lighting flare
                              Container(
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: RadialGradient(
                                    colors: [
                                      RodMaeColors.lemon.withValues(alpha: 0.45),
                                      Colors.transparent,
                                    ],
                                  ),
                                ),
                              ),
                              // Spouses Monogram Letters
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'R ❤ M',
                                    style: GoogleFonts.playfairDisplay(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withValues(alpha: 0.5),
                                          blurRadius: 4,
                                          offset: const Offset(1, 2),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '2026',
                                    style: GoogleFonts.inter(
                                      color: RodMaeColors.sky,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 2,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 54),

                  // Elegant Spinning Rings
                  const _ElegantDoubleOrbits(),

                  const SizedBox(height: 36),

                  // Fading Status Messages
                  SizedBox(
                    height: 24,
                    child: FadeTransition(
                      opacity: _textFadeCtrl,
                      child: Text(
                        _loadingStatuses[_statusIndex],
                        style: GoogleFonts.inter(
                          color: isDark ? RodMaeColors.textSoft : RodMaeColors.lightTextSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Bottom brand watermark
                  Text(
                    'RODMAE FOREVER',
                    style: GoogleFonts.inter(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : RodMaeColors.lightTextSoft.withValues(alpha: 0.25),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 4.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ElegantDoubleOrbits extends StatefulWidget {
  const _ElegantDoubleOrbits();

  @override
  State<_ElegantDoubleOrbits> createState() => _ElegantDoubleOrbitsState();
}

class _ElegantDoubleOrbitsState extends State<_ElegantDoubleOrbits>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
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
        return Stack(
          alignment: Alignment.center,
          children: [
            // Outer Sweep Ring (Clockwise)
            Transform.rotate(
              angle: _ctrl.value * 2 * math.pi,
              child: Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: ShaderMask(
                  shaderCallback: (rect) => SweepGradient(
                    colors: [
                      RodMaeColors.gold.withValues(alpha: 0.0),
                      RodMaeColors.gold.withValues(alpha: 0.25),
                      RodMaeColors.gold,
                      RodMaeColors.lemon,
                      RodMaeColors.gold.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.4, 0.75, 0.9, 1.0],
                  ).createShader(rect),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2.8,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Inner Sweep Ring (Counter-Clockwise)
            Transform.rotate(
              angle: -_ctrl.value * 2 * math.pi * 1.5,
              child: Container(
                width: 30,
                height: 30,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: ShaderMask(
                  shaderCallback: (rect) => SweepGradient(
                    colors: [
                      RodMaeColors.electricBlue.withValues(alpha: 0.0),
                      RodMaeColors.electricBlue.withValues(alpha: 0.35),
                      RodMaeColors.electricBlue,
                      RodMaeColors.sky,
                      RodMaeColors.electricBlue.withValues(alpha: 0.0),
                    ],
                    stops: const [0.0, 0.3, 0.7, 0.85, 1.0],
                  ).createShader(rect),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _FloatingParticlesLayer extends StatefulWidget {
  const _FloatingParticlesLayer();

  @override
  State<_FloatingParticlesLayer> createState() => _FloatingParticlesLayerState();
}

class _FloatingParticlesLayerState extends State<_FloatingParticlesLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final _rand = math.Random(54321);
  late final List<_ParticleItem> _particles;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    _particles = List.generate(20, (index) {
      return _ParticleItem(
        xRatio: _rand.nextDouble(),
        yRatio: _rand.nextDouble(),
        speed: 0.08 + _rand.nextDouble() * 0.08,
        size: 2.0 + _rand.nextDouble() * 3.5,
        opacity: 0.15 + _rand.nextDouble() * 0.3,
      );
    });
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
        return CustomPaint(
          painter: _ParticlesPainter(
            particles: _particles,
            progress: _ctrl.value,
          ),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

class _ParticleItem {
  final double xRatio;
  final double yRatio;
  final double speed;
  final double size;
  final double opacity;

  _ParticleItem({
    required this.xRatio,
    required this.yRatio,
    required this.speed,
    required this.size,
    required this.opacity,
  });
}

class _ParticlesPainter extends CustomPainter {
  final List<_ParticleItem> particles;
  final double progress;

  _ParticlesPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (final p in particles) {
      final currentY = (p.yRatio - (progress * p.speed)) % 1.0;
      final drift = math.sin((progress * 2 * math.pi) + (p.xRatio * 8)) * 12.0;
      final x = (p.xRatio * size.width + drift) % size.width;
      final y = currentY * size.height;

      final isGold = p.size > 3.2;
      paint.color = (isGold ? RodMaeColors.gold : RodMaeColors.sky).withValues(alpha: p.opacity);
      
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) => true;
}
