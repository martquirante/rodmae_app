import 'package:flutter/material.dart';
import '../core/theme.dart';

/// A gold shimmer loading placeholder for list views and cards.
class ShimmerLoader extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final bool isDark;

  const ShimmerLoader({
    this.width = double.infinity,
    this.height = 80,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.isDark = true,
    super.key,
  });

  @override
  State<ShimmerLoader> createState() => _ShimmerLoaderState();
}

class _ShimmerLoaderState extends State<ShimmerLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _shimmer;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _shimmer = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmer,
      builder: (context, _) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              stops: [
                (_shimmer.value - 0.3).clamp(0.0, 1.0),
                _shimmer.value.clamp(0.0, 1.0),
                (_shimmer.value + 0.3).clamp(0.0, 1.0),
              ],
              colors: widget.isDark
                  ? [
                      RodMaeColors.navy.withValues(alpha: 0.9),
                      RodMaeColors.gold.withValues(alpha: 0.08),
                      RodMaeColors.navy.withValues(alpha: 0.9),
                    ]
                  : [
                      RodMaeColors.lightBackground2,
                      RodMaeColors.gold.withValues(alpha: 0.18),
                      RodMaeColors.lightBackground2,
                    ],
            ),
          ),
        );
      },
    );
  }
}

/// A full list of shimmer placeholders for loading states.
class ShimmerList extends StatelessWidget {
  final int count;
  final double itemHeight;

  const ShimmerList({this.count = 4, this.itemHeight = 80, super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => ShimmerLoader(
        height: itemHeight,
        isDark: isDark,
      ),
    );
  }
}
