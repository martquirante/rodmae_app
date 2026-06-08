import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';

/// A premium, highly photorealistic 2.5D marker widget featuring image assets,
/// dynamic cast shadows that scale opposite to bobbing height, and standard physics.
class PhotorealisticMarker extends StatelessWidget {
  final String imageAsset;
  final double size;
  final AnimationController controller;
  final Widget? fallback;

  const PhotorealisticMarker({
    required this.imageAsset,
    this.size = 65.0,
    required this.controller,
    this.fallback,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // Bobbing vertical offset using a smooth sine wave (0.0 to -10.0 pixels)
        final double bobValue = math.sin(controller.value * math.pi * 2) * 5.0 - 5.0;

        // Shadow scale calculations: when bobbing higher, shadow gets smaller and fainter.
        // bobValue is between -10.0 and 0.0.
        final double shadowScale = 1.0 + (bobValue / 33.0); // 0.7 to 1.0
        final double shadowOpacity = 0.42 + (bobValue / 32.0); // 0.1 to 0.42

        return Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // Dynamic Cast Shadow
            Transform.translate(
              offset: const Offset(0, 1.5),
              child: Transform.scale(
                scaleX: shadowScale * 1.15,
                scaleY: shadowScale * 0.45,
                child: Container(
                  width: size * 0.75,
                  height: size * 0.22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.black.withValues(alpha: shadowOpacity.clamp(0.08, 0.55)),
                        Colors.black.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Bobbing Marker Image
            Transform.translate(
              offset: Offset(0, bobValue - 3.5),
              child: SizedBox(
                width: size,
                height: size,
                child: Image.asset(
                  imageAsset,
                  filterQuality: FilterQuality.high,
                  fit: BoxFit.contain,
                  isAntiAlias: true,
                  errorBuilder: (context, error, stackTrace) {
                    // Dynamic premium fallback UI in case asset files are not yet present in the directory
                    return fallback ??
                        Container(
                          decoration: BoxDecoration(
                            color: RodMaeColors.navy2.withValues(alpha: 0.9),
                            shape: BoxShape.circle,
                            border: Border.all(color: RodMaeColors.gold, width: 1.8),
                            boxShadow: [
                              BoxShadow(
                                color: RodMaeColors.gold.withValues(alpha: 0.2),
                                blurRadius: 10,
                              ),
                            ],
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.location_on_rounded,
                              color: RodMaeColors.gold,
                              size: 24,
                            ),
                          ),
                        );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// A wrapper widget to seamlessly support the old references in map_screen and home_dashboard.
/// Adapts variables (type, label, color) to select the appropriate HD asset paths automatically.
class IsometricMarker extends StatefulWidget {
  final String type; // 'home', 'work', or TransitMode name
  final String label;
  final Color color;
  final bool isAnimated;
  final String? initials;

  const IsometricMarker({
    required this.type,
    required this.label,
    required this.color,
    this.isAnimated = true,
    this.initials,
    super.key,
  });

  @override
  State<IsometricMarker> createState() => _IsometricMarkerState();
}

class _IsometricMarkerState extends State<IsometricMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController _floatController;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (widget.isAnimated) {
      _floatController.repeat();
    }
  }

  @override
  void dispose() {
    _floatController.dispose();
    super.dispose();
  }

  String _resolveAssetPath() {
    final t = widget.type.toLowerCase();
    if (t == 'home') {
      return 'assets/images/map_home_hd.png';
    } else if (t == 'work') {
      if (widget.color == RodMaeColors.rose) {
        return 'assets/images/map_marymae_hd.png';
      }
      return 'assets/images/map_rodel_hd.png';
    } else {
      // Transit modes
      switch (t) {
        case 'walking':
          return 'assets/images/map_walk_hd.png';
        case 'bicycling':
        case 'biking':
          return 'assets/images/map_bike_hd.png';
        case 'motorcycle':
          return 'assets/images/map_moto_hd.png';
        case 'driving':
        case 'car':
          return 'assets/images/map_car_hd.png';
        case 'transit':
        case 'commute':
        case 'bus':
          return 'assets/images/map_bus_hd.png';
        default:
          return 'assets/images/map_car_hd.png';
      }
    }
  }

  IconData _resolveIcon() {
    final t = widget.type.toLowerCase();
    if (t == 'home') return Icons.home_rounded;
    if (t == 'work') return Icons.business_rounded;
    switch (t) {
      case 'walking':
        return Icons.directions_walk_rounded;
      case 'bicycling':
      case 'biking':
        return Icons.directions_bike_rounded;
      case 'motorcycle':
        return Icons.motorcycle_rounded;
      case 'driving':
        return Icons.directions_car_rounded;
      case 'transit':
        return Icons.directions_bus_rounded;
      default:
        return Icons.location_on_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final assetPath = _resolveAssetPath();
    final icon = _resolveIcon();

    final Widget fallbackWidget = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            widget.color.withValues(alpha: 0.25),
            widget.color.withValues(alpha: 0.95),
          ],
        ),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2.2),
        boxShadow: [
          BoxShadow(
            color: widget.color.withValues(alpha: 0.4),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Center(
        child: widget.initials != null && widget.initials!.isNotEmpty
            ? Text(
                widget.initials!,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              )
            : Icon(
                icon,
                color: Colors.white,
                size: 25,
              ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PhotorealisticMarker(
          imageAsset: assetPath,
          size: 65,
          controller: _floatController,
          fallback: fallbackWidget,
        ),
        const SizedBox(height: 6),
        // Label badge container
        Container(
          constraints: const BoxConstraints(maxWidth: 110),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.12),
              width: 0.8,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black38,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            widget.label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
