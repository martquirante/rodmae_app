import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Public API
// ─────────────────────────────────────────────────────────────────────────────

/// Shows the cinematic envelope launch animation.
Future<void> showSurpriseNoteSendAnimation(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 1400),
      pageBuilder: (ctx, anim, _) => _CinematicSendOverlay(animation: anim),
    ),
  );
}

/// Shows the cinematic envelope arrival overlay.
Future<void> showSurpriseNoteReceiveAnimation(
  BuildContext context, {
  required String content,
  required String senderName,
}) {
  HapticFeedback.heavyImpact();
  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder(
      opaque: false,
      barrierDismissible: false,
      transitionDuration: const Duration(milliseconds: 800),
      pageBuilder: (ctx, anim, _) => _CinematicReceiveOverlay(
        content: content,
        senderName: senderName,
      ),
      transitionsBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Send (Launch) Overlay
// ─────────────────────────────────────────────────────────────────────────────

class _CinematicSendOverlay extends StatefulWidget {
  final Animation<double> animation;
  const _CinematicSendOverlay({required this.animation});

  @override
  State<_CinematicSendOverlay> createState() => _CinematicSendOverlayState();
}

class _CinematicSendOverlayState extends State<_CinematicSendOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _launchCtrl;
  late Animation<double> _yOffset;
  late Animation<double> _xOffset;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  late Animation<double> _rotateZ;
  late Animation<double> _rotateX;

  @override
  void initState() {
    super.initState();
    _launchCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Envelope starts at bottom center and sails upwards off the screen
    _yOffset = Tween<double>(begin: 250, end: -850).animate(
      CurvedAnimation(parent: _launchCtrl, curve: Curves.easeInBack),
    );

    // Subtle drift left/right like a paper plane
    _xOffset = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -35.0), weight: 35),
      TweenSequenceItem(tween: Tween(begin: -35.0, end: 40.0), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 40.0, end: 10.0), weight: 20),
    ]).animate(CurvedAnimation(parent: _launchCtrl, curve: Curves.easeInOut));

    _scale = Tween<double>(begin: 1.0, end: 0.55).animate(
      CurvedAnimation(parent: _launchCtrl, curve: Curves.easeInBack),
    );

    _opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 70),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_launchCtrl);

    _rotateZ = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.12), weight: 40),
      TweenSequenceItem(tween: Tween(begin: -0.12, end: 0.15), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: 0.0), weight: 15),
    ]).animate(CurvedAnimation(parent: _launchCtrl, curve: Curves.easeInOut));

    _rotateX = Tween<double>(begin: 0.0, end: 0.45).animate(
      CurvedAnimation(parent: _launchCtrl, curve: Curves.easeInBack),
    );

    _launchCtrl.forward().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });

    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _launchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final envelopeW = size.width * 0.76;
    final envelopeH = envelopeW * 0.65;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AnimatedBuilder(
        animation: _launchCtrl,
        builder: (context, child) {
          return Center(
            child: Transform.translate(
              offset: Offset(_xOffset.value, _yOffset.value),
              child: Opacity(
                opacity: _opacity.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0015)
                      ..rotateZ(_rotateZ.value)
                      ..rotateX(_rotateX.value),
                    child: _EnvelopeWidget(
                      width: envelopeW,
                      height: envelopeH,
                      flapAngle: 0, // closed
                      sealScale: 1.0,
                      sealOpacity: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receive (Arrival) Overlay
// ─────────────────────────────────────────────────────────────────────────────

class _CinematicReceiveOverlay extends StatefulWidget {
  final String content;
  final String senderName;

  const _CinematicReceiveOverlay({
    required this.content,
    required this.senderName,
  });

  @override
  State<_CinematicReceiveOverlay> createState() => _CinematicReceiveOverlayState();
}

enum _ReceiveStage { arrival, idle, opening, reading, closing }

class _CinematicReceiveOverlayState extends State<_CinematicReceiveOverlay>
    with TickerProviderStateMixin {
  late AnimationController _arrivalCtrl;
  late AnimationController _wiggleCtrl;
  late AnimationController _openRevealCtrl;

  late Animation<double> _yArrival;
  late Animation<double> _wiggleRotate;
  late Animation<double> _flapAngle;
  late Animation<double> _noteSlide;
  late Animation<double> _noteExpand;
  late Animation<double> _sealScale;
  late Animation<double> _sealOpacity;

  _ReceiveStage _stage = _ReceiveStage.arrival;

  @override
  void initState() {
    super.initState();

    // 1. Arrival from top of screen to center
    _arrivalCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _yArrival = Tween<double>(begin: -800, end: 0).animate(
      CurvedAnimation(parent: _arrivalCtrl, curve: Curves.elasticOut),
    );

    // 2. Gentle wiggle loop
    _wiggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _wiggleRotate = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.06), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.06, end: -0.06), weight: 50),
      TweenSequenceItem(tween: Tween(begin: -0.06, end: 0.0), weight: 25),
    ]).animate(CurvedAnimation(parent: _wiggleCtrl, curve: Curves.easeInOut));

    // 3. Opening the flap and expanding note paper
    _openRevealCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _flapAngle = Tween<double>(begin: 0.0, end: -math.pi).animate(
      CurvedAnimation(
        parent: _openRevealCtrl,
        curve: const Interval(0.0, 0.40, curve: Curves.easeInOutCubic),
      ),
    );

    _noteSlide = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _openRevealCtrl,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
      ),
    );

    _noteExpand = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _openRevealCtrl,
        curve: const Interval(0.60, 1.0, curve: Curves.easeOutCubic),
      ),
    );

    _sealScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.0), weight: 50),
    ]).animate(CurvedAnimation(
      parent: _openRevealCtrl,
      curve: const Interval(0.0, 0.40, curve: Curves.easeOut),
    ));

    _sealOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _openRevealCtrl,
        curve: const Interval(0.25, 0.40, curve: Curves.easeOut),
      ),
    );

    // Start arrival animation
    _arrivalCtrl.forward().then((_) {
      if (mounted) {
        setState(() => _stage = _ReceiveStage.idle);
        _wiggleCtrl.repeat();
      }
    });
  }

  @override
  void dispose() {
    _arrivalCtrl.dispose();
    _wiggleCtrl.dispose();
    _openRevealCtrl.dispose();
    super.dispose();
  }

  void _onEnvelopeTap() {
    if (_stage != _ReceiveStage.idle) return;
    _wiggleCtrl.stop();
    setState(() => _stage = _ReceiveStage.opening);
    HapticFeedback.mediumImpact();
    _openRevealCtrl.forward().then((_) {
      if (mounted) {
        setState(() => _stage = _ReceiveStage.reading);
      }
    });
  }

  void _onClose() {
    if (_stage != _ReceiveStage.reading) return;
    setState(() => _stage = _ReceiveStage.closing);
    HapticFeedback.lightImpact();
    _openRevealCtrl.reverse().then((_) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final envelopeW = size.width * 0.78;
    final envelopeH = envelopeW * 0.65;
    final noteW = size.width * 0.85;
    final noteH = size.height * 0.72;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Blurred background
          GestureDetector(
            onTap: _stage == _ReceiveStage.reading ? _onClose : null,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: Container(
                color: const Color(0xFF04091A).withValues(alpha: 0.78),
              ),
            ),
          ),

          // Center interactive envelope and note
          Center(
            child: AnimatedBuilder(
              animation: Listenable.merge([
                _arrivalCtrl,
                _wiggleCtrl,
                _openRevealCtrl,
              ]),
              builder: (context, _) {
                final slide = _noteSlide.value;
                final expand = _noteExpand.value;

                // Note Y offset goes from 0 (inside envelope) to -envelopeH (slides up)
                // then floats back to 0 (perfect center on screen) as it expands.
                final double noteY = -envelopeH * slide * (1.0 - expand);
                final double noteScale = 0.65 + (0.35 * expand);
                final double noteOpacity = slide.clamp(0.0, 1.0);

                final double currentWidth = envelopeW + (noteW - envelopeW) * expand;
                final double currentHeight = envelopeH + (noteH - envelopeH) * expand;

                // Build the main display stack
                Widget mainStack = SizedBox(
                  width: noteW,
                  height: noteH + envelopeH,
                  child: Stack(
                    alignment: Alignment.center, // Centered layout avoids clipping!
                    clipBehavior: Clip.none,
                    children: [
                      // ── Note paper (slides up and expands to center) ───────
                      Opacity(
                        opacity: noteOpacity,
                        child: Transform.translate(
                          offset: Offset(0, noteY),
                          child: Transform.scale(
                            scale: noteScale,
                            child: _NotePaper(
                              content: widget.content,
                              senderName: widget.senderName,
                              onClose: _onClose,
                              isReading: _stage == _ReceiveStage.reading,
                              width: currentWidth,
                              height: currentHeight,
                            ),
                          ),
                        ),
                      ),

                      // ── Envelope (back, front, flap) ────────────────────────
                      Opacity(
                        opacity: (1.0 - expand).clamp(0.0, 1.0),
                        child: GestureDetector(
                          onTap: _onEnvelopeTap,
                          behavior: HitTestBehavior.opaque,
                          child: _EnvelopeWidget(
                            width: envelopeW,
                            height: envelopeH,
                            flapAngle: _flapAngle.value,
                            sealScale: _sealScale.value,
                            sealOpacity: _sealOpacity.value,
                          ),
                        ),
                      ),
                    ],
                  ),
                );

                // Apply arrival offset
                mainStack = Transform.translate(
                  offset: Offset(0, _yArrival.value),
                  child: mainStack,
                );

                // Apply wiggle rotation (only when idle)
                if (_stage == _ReceiveStage.idle) {
                  mainStack = Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.001)
                      ..rotateZ(_wiggleRotate.value),
                    child: mainStack,
                  );
                }

                return mainStack;
              },
            ),
          ),

          // Action prompts
          if (_stage == _ReceiveStage.idle)
            Positioned(
              bottom: size.height * 0.16,
              left: 0,
              right: 0,
              child: Center(
                child: FadeTransition(
                  opacity: _arrivalCtrl,
                  child: _TapPulsePrompt(
                    text: 'You received a surprise note!\nTap the envelope to open',
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-Widget: Envelope (Back + Front + Flap Stack)
// ─────────────────────────────────────────────────────────────────────────────

class _EnvelopeWidget extends StatelessWidget {
  final double width;
  final double height;
  final double flapAngle; // 0 = closed, -π = open
  final double sealScale;
  final double sealOpacity;

  const _EnvelopeWidget({
    required this.width,
    required this.height,
    required this.flapAngle,
    required this.sealScale,
    required this.sealOpacity,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // 1. Inner back panel background
            Container(
              width: width,
              height: height,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEADBAB), Color(0xFFD4B96A)],
                ),
              ),
            ),

            // 2. Front folds (left, right, bottom triangles)
            Positioned.fill(
              child: CustomPaint(
                painter: _EnvelopeFrontFoldsPainter(),
              ),
            ),

            // 3. Top flap (rotates around top edge on X axis)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Transform(
                alignment: Alignment.topCenter,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateX(flapAngle),
                child: CustomPaint(
                  size: Size(width, height * 0.48),
                  painter: _EnvelopeFlapPainter(),
                ),
              ),
            ),

            // 4. Wax seal stamp
            if (sealOpacity > 0.01)
              Positioned(
                top: height * 0.44,
                child: Opacity(
                  opacity: sealOpacity,
                  child: Transform.scale(
                    scale: sealScale,
                    child: const _WaxSeal(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painters & Sub-components
// ─────────────────────────────────────────────────────────────────────────────

class _EnvelopeFrontFoldsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Body gradient (cream-ivory)
    final foldPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFFDFC),
          Color(0xFFFAF7EE),
          Color(0xFFF3EDD7),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    // Soft drop shadows under folds for depth
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    // Left fold triangle
    final leftPath = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.52, h * 0.5)
      ..lineTo(0, h)
      ..close();

    // Right fold triangle
    final rightPath = Path()
      ..moveTo(w, 0)
      ..lineTo(w * 0.48, h * 0.5)
      ..lineTo(w, h)
      ..close();

    // Bottom center triangle (bottom flap)
    final bottomPath = Path()
      ..moveTo(0, h)
      ..lineTo(w * 0.5, h * 0.48)
      ..lineTo(w, h)
      ..close();

    final bottomPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFAF6E9),
          Color(0xFFEADBAB),
        ],
      ).createShader(Rect.fromLTWH(0, h * 0.48, w, h * 0.52))
      ..style = PaintingStyle.fill;

    canvas.drawPath(leftPath, shadowPaint);
    canvas.drawPath(leftPath, foldPaint);

    canvas.drawPath(rightPath, shadowPaint);
    canvas.drawPath(rightPath, foldPaint);

    canvas.drawPath(bottomPath, shadowPaint);
    canvas.drawPath(bottomPath, bottomPaint);

    // Crease outlines
    final borderPaint = Paint()
      ..color = const Color(0xFFDCD2C0).withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawPath(leftPath, borderPaint);
    canvas.drawPath(rightPath, borderPaint);
    canvas.drawPath(bottomPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _EnvelopeFlapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.5, h)
      ..lineTo(w, 0)
      ..close();

    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFFFFFDFC),
          Color(0xFFEADBAB),
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h))
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    canvas.drawPath(path, shadowPaint);
    canvas.drawPath(path, paint);

    final borderPaint = Paint()
      ..color = const Color(0xFFDCD2C0).withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _NotePaper extends StatelessWidget {
  final String content;
  final String senderName;
  final VoidCallback onClose;
  final bool isReading;
  final double width;
  final double height;

  const _NotePaper({
    required this.content,
    required this.senderName,
    required this.onClose,
    required this.isReading,
    required this.width,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFFFFDF2), // Warm Parchment
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: const Color(0xFFD4B062).withValues(alpha: 0.08),
            blurRadius: 40,
            spreadRadius: -4,
          ),
        ],
        border: Border.all(
          color: const Color(0xFFEADDB8),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // ruled lines background
            CustomPaint(
              painter: _PaperLinePainter(),
              child: const SizedBox.expand(),
            ),

            // Scrollable Content positioned specifically to prevent cut-offs
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 76),
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const RadialGradient(
                                colors: [Color(0xFFFF4C6A), Color(0xFFAA1133)],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF4C6A).withValues(alpha: 0.4),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.favorite,
                              color: Colors.white,
                              size: 15,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'A SURPRISE FROM',
                            style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2.0,
                              color: const Color(0xFFB8860A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        senderName,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFF3B2D18),
                          fontStyle: FontStyle.italic,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    const Color(0xFFCBAD47).withValues(alpha: 0.4),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        content,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 18,
                          height: 1.75,
                          color: const Color(0xFF2C1E0A),
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'With all my heart,',
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 12,
                                color: const Color(0xFF8B6914),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              senderName,
                              style: GoogleFonts.playfairDisplay(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF4A2C00),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Close button (only shown when the note is opened and in reading stage)
            if (isReading)
              Positioned(
                bottom: 20,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: onClose,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(32),
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFD4A017),
                            Color(0xFFB8860A),
                          ],
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55B8860A),
                            blurRadius: 14,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.close_rounded,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'CLOSE NOTE',
                            style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PaperLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFCBAD47).withValues(alpha: 0.12)
      ..strokeWidth = 0.8;

    // Draw horizontal ruled lines
    const spacing = 28.0;
    const topOffset = 88.0;
    for (double y = topOffset; y < size.height - 20; y += spacing) {
      canvas.drawLine(
        Offset(20, y),
        Offset(size.width - 20, y),
        paint,
      );
    }

    // Left margin line
    final marginPaint = Paint()
      ..color = const Color(0xFFE8A0A0).withValues(alpha: 0.30)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      const Offset(52, 88),
      Offset(52, size.height - 20),
      marginPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _WaxSeal extends StatelessWidget {
  const _WaxSeal();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          colors: [
            Color(0xFFFF3355),
            Color(0xFFCC0022),
            Color(0xFF880011),
          ],
          stops: [0.0, 0.6, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFCC0022).withValues(alpha: 0.55),
            blurRadius: 12,
            spreadRadius: 1,
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(painter: _SealStampPainter()),
    );
  }
}

class _SealStampPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    const pts = 8;
    const innerR = 6.0;
    const outerR = 8.5;
    final starPath = Path();
    for (int i = 0; i < pts * 2; i++) {
      final r = i.isOdd ? innerR : outerR;
      final angle = (i * math.pi / pts) - math.pi / 2;
      final x = cx + r * math.cos(angle);
      final y = cy + r * math.sin(angle);
      if (i == 0) {
        starPath.moveTo(x, y);
      } else {
        starPath.lineTo(x, y);
      }
    }
    starPath.close();
    canvas.drawPath(starPath, paint);

    canvas.drawCircle(
      Offset(cx, cy),
      2.5,
      Paint()..color = Colors.white.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _TapPulsePrompt extends StatefulWidget {
  final String text;
  const _TapPulsePrompt({required this.text});

  @override
  State<_TapPulsePrompt> createState() => _TapPulsePromptState();
}

class _TapPulsePromptState extends State<_TapPulsePrompt>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _opacity = Tween<double>(begin: 0.35, end: 0.85).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
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
      animation: _opacity,
      builder: (context, _) => Opacity(
        opacity: _opacity.value,
        child: Text(
          widget.text,
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.4,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }
}
