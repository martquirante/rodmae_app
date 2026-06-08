import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  final Future<AppStartupStatus> startupFuture;

  const SplashScreen({required this.startupFuture, super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late final AnimationController _entranceCtrl;
  late final AnimationController _orbitCtrl;
  
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    
    // Entrance animations (sequential staggered effect)
    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    
    _fadeAnim = CurvedAnimation(
      parent: _entranceCtrl,
      curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
    );
    
    _scaleAnim = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutBack),
      ),
    );

    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _entranceCtrl,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
      ),
    );

    // Continuous 3D orbit tilt animation controller
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    _entranceCtrl.forward();
    _checkAuthentication();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _orbitCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAuthentication() async {
    try {
      // Wait for both the startup initialization (with a 5-second failsafe timeout) 
      // and the 1.5s minimum animation timer.
      final startupFutureWithTimeout = widget.startupFuture.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('SplashScreen: Startup initialization timed out after 5 seconds. Proceeding to fallback.');
          return const AppStartupStatus(
            firebaseReady: false,
            supabaseReady: false,
            issue: 'Startup initialization timed out',
          );
        },
      );

      final results = await Future.wait([
        startupFutureWithTimeout,
        Future.delayed(const Duration(milliseconds: 1500)),
      ]);

      final startup = results[0];

      if (!mounted) return;

      final authenticated = AuthService.instance.isAuthenticated;
      if (authenticated) {
        PartnerIdentity.setFromEmail(AuthService.instance.currentUser?.email);
        Navigator.of(context).pushReplacementNamed('/home', arguments: startup);
      } else {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 700),
          ),
        );
      }
    } catch (error) {
      debugPrint('Error during splash startup: $error');
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: Stack(
        children: [
          // 1. Deep royal blue animated background
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: RodMaeColors.getAppBackground(isDark),
            ),
          ),

          // 2. Glowing floating background particles
          const _FloatingParticlesBackground(),

          // 3. Main content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),

                    // Floating 3D Logo Card with dynamic orbit tilt
                    AnimatedBuilder(
                      animation: _orbitCtrl,
                      builder: (context, child) {
                        // Calculate orbiting angles for 3D rotation
                        final angleX = math.sin(_orbitCtrl.value * 2 * math.pi) * 0.08;
                        final angleY = math.cos(_orbitCtrl.value * 2 * math.pi) * 0.08;

                        return ScaleTransition(
                          scale: _scaleAnim,
                          child: Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.identity()
                              ..setEntry(3, 2, 0.0012) // perspective
                              ..rotateX(angleX)
                              ..rotateY(angleY),
                            child: child,
                          ),
                        );
                      },
                      child: Container(
                        width: 200,
                        height: 200,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: RodMaeColors.gold.withValues(alpha: 0.22),
                              blurRadius: 36,
                              spreadRadius: 4,
                            ),
                            BoxShadow(
                              color: RodMaeColors.electricBlue.withValues(alpha: 0.16),
                              blurRadius: 50,
                              spreadRadius: 8,
                            ),
                          ],
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glowing Outer pulsing ring
                            const _OuterPulsingRing(),
                            
                            // Main avatar/logo inside gold border
                            Container(
                              width: 174,
                              height: 174,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: RodMaeColors.gold,
                                  width: 3.2,
                                ),
                              ),
                              child: ClipOval(
                                child: Image.asset(
                                  'assets/images/splash_screen.png',
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Image.asset(
                                      'assets/images/app_logo.png',
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Container(
                                          color: RodMaeColors.navy,
                                          alignment: Alignment.center,
                                          child: const Icon(
                                            Icons.favorite_rounded,
                                            color: RodMaeColors.rose,
                                            size: 76,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // Staggered slide up of title text
                    SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        children: [
                          Text(
                            'OUR FOREVER PATHWAY',
                            style: GoogleFonts.inter(
                              color: RodMaeColors.sky,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 4.0,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Rodel & Mary Mae',
                            style: GoogleFonts.playfairDisplay(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.4),
                                  offset: const Offset(0, 4),
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const Spacer(),

                    // High-end custom loading spinner
                    const _PremiumDoubleSpinner(),
                    const SizedBox(height: 14),
                    Text(
                      'ESTABLISHING CONNECTION',
                      style: GoogleFonts.inter(
                        color: RodMaeColors.textSoft.withValues(alpha: 0.5),
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 2.5,
                      ),
                    ),
                    
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A glowing outer ring that pulses gently
class _OuterPulsingRing extends StatefulWidget {
  const _OuterPulsingRing();

  @override
  State<_OuterPulsingRing> createState() => _OuterPulsingRingState();
}

class _OuterPulsingRingState extends State<_OuterPulsingRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _scale = Tween<double>(begin: 0.94, end: 1.12).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );

    _opacity = Tween<double>(begin: 0.65, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
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
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: Container(
              width: 196,
              height: 196,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: RodMaeColors.lemon,
                  width: 1.5,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Two concentric gradient spinners rotating in opposite directions
class _PremiumDoubleSpinner extends StatefulWidget {
  const _PremiumDoubleSpinner();

  @override
  State<_PremiumDoubleSpinner> createState() => _PremiumDoubleSpinnerState();
}

class _PremiumDoubleSpinnerState extends State<_PremiumDoubleSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
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
            // Outer Ring - Gold Gradient (Clockwise)
            Transform.rotate(
              angle: _ctrl.value * 2 * math.pi,
              child: Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: ShaderMask(
                  shaderCallback: (rect) => SweepGradient(
                    colors: [
                      RodMaeColors.gold.withValues(alpha: 0.02),
                      RodMaeColors.gold.withValues(alpha: 0.3),
                      RodMaeColors.gold,
                      RodMaeColors.lemon,
                      RodMaeColors.gold.withValues(alpha: 0.02),
                    ],
                    stops: const [0.0, 0.4, 0.75, 0.9, 1.0],
                  ).createShader(rect),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 3.2,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // Inner Ring - Electric Blue / Sky Gradient (Counter-Clockwise, Faster)
            Transform.rotate(
              angle: -_ctrl.value * 2 * math.pi * 1.4,
              child: Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(shape: BoxShape.circle),
                child: ShaderMask(
                  shaderCallback: (rect) => SweepGradient(
                    colors: [
                      RodMaeColors.electricBlue.withValues(alpha: 0.02),
                      RodMaeColors.electricBlue.withValues(alpha: 0.4),
                      RodMaeColors.electricBlue,
                      RodMaeColors.sky,
                      RodMaeColors.electricBlue.withValues(alpha: 0.02),
                    ],
                    stops: const [0.0, 0.3, 0.7, 0.85, 1.0],
                  ).createShader(rect),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2.2,
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

/// Floating glowing particles in background
class _ParticleInfo {
  final double xRatio;
  final double yRatio;
  final double speed;
  final double size;
  final double opacity;

  _ParticleInfo({
    required this.xRatio,
    required this.yRatio,
    required this.speed,
    required this.size,
    required this.opacity,
  });
}

class _FloatingParticlesBackground extends StatefulWidget {
  const _FloatingParticlesBackground();

  @override
  State<_FloatingParticlesBackground> createState() => _FloatingParticlesBackgroundState();
}

class _FloatingParticlesBackgroundState extends State<_FloatingParticlesBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  final _rand = math.Random(12345); // Seed for stable particle look
  late final List<_ParticleInfo> _particles;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();

    _particles = List.generate(24, (index) {
      return _ParticleInfo(
        xRatio: _rand.nextDouble(),
        yRatio: _rand.nextDouble(),
        speed: 0.06 + _rand.nextDouble() * 0.1,
        size: 1.5 + _rand.nextDouble() * 4.0,
        opacity: 0.12 + _rand.nextDouble() * 0.32,
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

class _ParticlesPainter extends CustomPainter {
  final List<_ParticleInfo> particles;
  final double progress;

  _ParticlesPainter({required this.particles, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();

    for (final p in particles) {
      // Rise up smoothly
      final currentY = (p.yRatio - (progress * p.speed)) % 1.0;
      
      // Add a slight horizontal sine wave drift
      final drift = math.sin((progress * 2 * math.pi) + (p.xRatio * 10)) * 14.0;
      final x = (p.xRatio * size.width + drift) % size.width;
      final y = currentY * size.height;

      // Glow color - alternating between Lemon and Electric Blue
      final isGold = p.size > 2.8;
      paint.color = (isGold ? RodMaeColors.lemon : RodMaeColors.sky).withValues(alpha: p.opacity);
      
      canvas.drawCircle(Offset(x, y), p.size, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlesPainter oldDelegate) => true;
}
