import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/theme.dart';

/// A card that tilts in 3D when pressed — gyroscope-style effect using
/// touch position tracking + Matrix4 perspective transform.
class Animated3DCard extends StatefulWidget {
  final Widget child;
  final double maxTiltDegrees;
  final double elevation;
  final BorderRadius borderRadius;
  final Color? borderColor;
  final Gradient? gradient;
  final Color? backgroundColor;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool enableTilt;

  const Animated3DCard({
    required this.child,
    this.maxTiltDegrees = 6.0,
    this.elevation = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.borderColor,
    this.gradient,
    this.backgroundColor,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.enableTilt = true,
    super.key,
  });

  @override
  State<Animated3DCard> createState() => _Animated3DCardState();
}

class _Animated3DCardState extends State<Animated3DCard>
    with SingleTickerProviderStateMixin {
  double _tiltX = 0;
  double _tiltY = 0;
  bool _pressed = false;
  late final AnimationController _resetCtrl;
  late final Animation<double> _resetAnim;
  double _savedTiltX = 0;
  double _savedTiltY = 0;

  @override
  void initState() {
    super.initState();
    _resetCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _resetAnim = CurvedAnimation(parent: _resetCtrl, curve: Curves.elasticOut);
    _resetCtrl.addListener(() {
      setState(() {
        _tiltX = _savedTiltX * (1 - _resetAnim.value);
        _tiltY = _savedTiltY * (1 - _resetAnim.value);
      });
    });
  }

  @override
  void dispose() {
    _resetCtrl.dispose();
    super.dispose();
  }

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    if (!widget.enableTilt) return;
    final w = constraints.maxWidth;
    final h = constraints.maxHeight;
    final x = details.localPosition.dx;
    final y = details.localPosition.dy;
    final maxRad = widget.maxTiltDegrees * math.pi / 180;
    setState(() {
      _tiltY = ((x / w) - 0.5) * 2 * maxRad;  // left-right
      _tiltX = -((y / h) - 0.5) * 2 * maxRad; // up-down
      _pressed = true;
    });
  }

  void _onPanEnd(DragEndDetails _) {
    _savedTiltX = _tiltX;
    _savedTiltY = _tiltY;
    _pressed = false;
    _resetCtrl.forward(from: 0);
  }

  void _onPanCancel() {
    _savedTiltX = _tiltX;
    _savedTiltY = _tiltY;
    _pressed = false;
    _resetCtrl.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          onTap: widget.onTap,
          onPanUpdate: (d) => _onPanUpdate(d, constraints),
          onPanEnd: _onPanEnd,
          onPanCancel: _onPanCancel,
          child: AnimatedScale(
            scale: _pressed ? 0.975 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.001)
                ..rotateX(_tiltX)
                ..rotateY(_tiltY),
              child: Container(
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: widget.backgroundColor ??
                      (isDark
                          ? RodMaeColors.navy.withValues(alpha: 0.8)
                          : Colors.white.withValues(alpha: 0.9)),
                  gradient: widget.gradient,
                  borderRadius: widget.borderRadius,
                  border: Border.all(
                    color: widget.borderColor ??
                        (isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : RodMaeColors.royalBlue.withValues(alpha: 0.12)),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _pressed ? 0.45 : (isDark ? 0.35 : 0.08),
                      ),
                      blurRadius: _pressed ? widget.elevation * 1.5 : widget.elevation,
                      offset: Offset(
                        _tiltY * 8,
                        _pressed ? widget.elevation * 0.4 : widget.elevation * 0.5,
                      ),
                    ),
                    if (_pressed)
                      BoxShadow(
                        color: RodMaeColors.gold.withValues(alpha: 0.18),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                  ],
                ),
                child: widget.child,
              ),
            ),
          ),
        );
      },
    );
  }
}
