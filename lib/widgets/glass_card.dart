import 'package:flutter/material.dart';
import '../core/theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final Gradient? gradient;
  final Color? color;
  final BorderRadiusGeometry borderRadius;
  final Color borderColor;
  final Clip clipBehavior;

  const GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.gradient,
    this.color,
    this.borderRadius = const BorderRadius.all(Radius.circular(22)),
    this.borderColor = const Color(0x1FFFFFFF),
    this.clipBehavior = Clip.none,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? (isDark ? RodMaeColors.navy.withValues(alpha: 0.72) : Colors.white.withValues(alpha: 0.85)),
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: clipBehavior,
      child: child,
    );
  }
}
