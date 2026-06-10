import 'dart:ui';
import 'package:flutter/material.dart';
import '../themes/loading_theme.dart';

/// A premium, reusable loading effect widget featuring BackdropFilter Gaussian blur,
/// custom animations, and tactile 3D shimmering placeholders with depth.
class AdvancedLoadingEffect extends StatelessWidget {
  /// The main content child.
  final Widget child;

  /// Whether the loading state is active.
  final bool isLoading;

  /// Optional skeleton placeholder widget that mimics the shape of the content to come.
  /// If null, a generic box or circle matching [shape] is rendered.
  final Widget? placeholder;

  /// Optional override for the Gaussian blur strength.
  final double? blurStrength;

  /// Optional custom border radius for the blur/shimmer region.
  final BorderRadius? borderRadius;

  /// The shape of the loading effect container. Defaults to [BoxShape.rectangle].
  final BoxShape shape;

  const AdvancedLoadingEffect({
    required this.child,
    required this.isLoading,
    this.placeholder,
    this.blurStrength,
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final blur = blurStrength ?? RodMaeLoadingTheme.blurStrength;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Layer 1: The child widget
        child,

        // Layer 2 & 3: Overlay active while loading
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !isLoading,
            child: AnimatedOpacity(
              opacity: isLoading ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOut,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Layer 2: BackdropFilter Gaussian blur
                  ClipPath(
                    clipper: _ShapeClipper(shape: shape, borderRadius: borderRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                      child: Container(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.25)
                            : Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                  ),

                  // Layer 3: Animated shimmering gradient placeholder with 3D bevels
                  Center(
                    child: _ShimmerAnimator(
                      shape: shape,
                      borderRadius: borderRadius,
                      placeholder: placeholder,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHIMMER ANIMATOR (Internal stateful component to host animation loop)
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerAnimator extends StatefulWidget {
  final BoxShape shape;
  final BorderRadius? borderRadius;
  final Widget? placeholder;

  const _ShimmerAnimator({
    required this.shape,
    this.borderRadius,
    this.placeholder,
  });

  @override
  State<_ShimmerAnimator> createState() => _ShimmerAnimatorState();
}

class _ShimmerAnimatorState extends State<_ShimmerAnimator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: RodMaeLoadingTheme.shimmerSpeed,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = RodMaeLoadingTheme.getShimmerColors(isDark);

    // 1. Shimmer shader overlay applied to the placeholder content
    final shimmerChild = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) {
        final double slidePercent = _controller.value;
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
          colors: colors,
          transform: _SlidingGradientTransform(slidePercent: slidePercent),
        ).createShader(bounds);
      },
      child: widget.placeholder ?? _DefaultPlaceholder(
        shape: widget.shape,
        borderRadius: widget.borderRadius,
      ),
    );

    // 2. Stack the shimmer shape and the 3D volume depth lines overlay
    return Stack(
      fit: widget.placeholder != null ? StackFit.loose : StackFit.expand,
      children: [
        shimmerChild,
        Positioned.fill(
          child: CustomPaint(
            painter: Inner3DPainter(
              shape: widget.shape,
              borderRadius: widget.borderRadius,
              shadowStrength: RodMaeLoadingTheme.depthShadowStrength,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SLIDING GRADIENT TRANSFORM (Shifts linear gradient stops horizontally)
// ─────────────────────────────────────────────────────────────────────────────

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;

  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    final double width = bounds.width;
    final double translation = -width + (2 * width * slidePercent);
    return Matrix4.translationValues(translation, 0, 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// INNER 3D PAINTER (Renders top-left white highlight and bottom-right shadow)
// ─────────────────────────────────────────────────────────────────────────────

class Inner3DPainter extends CustomPainter {
  final BorderRadius? borderRadius;
  final BoxShape shape;
  final double shadowStrength;

  Inner3DPainter({
    this.borderRadius,
    this.shape = BoxShape.rectangle,
    this.shadowStrength = 0.35,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = Path();
    
    if (shape == BoxShape.circle) {
      path.addOval(rect);
    } else {
      path.addRRect(
        borderRadius?.toRRect(rect) ?? BorderRadius.circular(12).toRRect(rect),
      );
    }

    // Clip painting to the shape boundary so borders bleed inwards (inner shadow effect)
    canvas.save();
    canvas.clipPath(path);

    // Draw Top-Left Bevel Highlight (White, soft glow)
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: shadowStrength * 0.42)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2);

    canvas.save();
    canvas.translate(-0.8, -0.8);
    canvas.drawPath(path, highlightPaint);
    canvas.restore();

    // Draw Bottom-Right Bevel Shadow (Black, depth sink)
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: shadowStrength * 0.50)
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.6);

    canvas.save();
    canvas.translate(1.2, 1.2);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant Inner3DPainter oldDelegate) =>
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.shape != shape ||
      oldDelegate.shadowStrength != shadowStrength;
}

// ─────────────────────────────────────────────────────────────────────────────
// SHAPE CLIPPER (Clips BackdropFilter so blurs do not bleed outer margins)
// ─────────────────────────────────────────────────────────────────────────────

class _ShapeClipper extends CustomClipper<Path> {
  final BoxShape shape;
  final BorderRadius? borderRadius;

  _ShapeClipper({required this.shape, this.borderRadius});

  @override
  Path getClip(Size size) {
    final path = Path();
    final rect = Offset.zero & size;
    if (shape == BoxShape.circle) {
      path.addOval(rect);
    } else {
      path.addRRect(
        borderRadius?.toRRect(rect) ?? BorderRadius.circular(12).toRRect(rect),
      );
    }
    return path;
  }

  @override
  bool shouldReclip(covariant _ShapeClipper oldClipper) =>
      oldClipper.shape != shape || oldClipper.borderRadius != borderRadius;
}

// ─────────────────────────────────────────────────────────────────────────────
// DEFAULT SKELETON PLACEHOLDER
// ─────────────────────────────────────────────────────────────────────────────

class _DefaultPlaceholder extends StatelessWidget {
  final BoxShape shape;
  final BorderRadius? borderRadius;

  const _DefaultPlaceholder({required this.shape, this.borderRadius});

  @override
  Widget build(BuildContext context) {
    if (shape == BoxShape.circle) {
      return Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: borderRadius ?? BorderRadius.circular(12),
      ),
    );
  }
}
