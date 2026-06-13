import 'package:flutter/material.dart';

/// Global visual configurations for the AdvancedLoadingEffect.
class RodMaeLoadingTheme {
  const RodMaeLoadingTheme._();

  /// The default Gaussian blur strength (sigmaX and sigmaY).
  static const double blurStrength = 15.0;

  /// Duration of the shimmering sweep transition.
  static const Duration shimmerSpeed = Duration(milliseconds: 1600);

  /// Volume depth strength of the 3D inner shadow/highlight effect.
  static const double depthShadowStrength = 0.35;

  /// Returns HSL-harmonious 3D shimmer gradient colors.
  /// Uses a diagonal linear gradient featuring a darker neutral base,
  /// transitioning into slightly lighter neutrals, and accented by
  /// sapphire/sky blue highlights for tangible depth.
  static List<Color> getShimmerColors(bool isDark) {
    if (isDark) {
      return [
        const Color(0xFF070F2B), // deepest royal navy base
        const Color(0xFF0F1A55), // slightly lighter navy
        const Color(0xFF223580), // sapphire-tinted highlight
        const Color(0xFF0F1A55), // slightly lighter navy
        const Color(0xFF070F2B), // deepest royal navy base
      ];
    } else {
      return [
        const Color(0xFFEFF6FF), // light blue-tinted base
        const Color(0xFFDBEAFE), // soft sky neutral
        const Color(0xFFBFDBFE), // accent highlight (blue-200)
        const Color(0xFFDBEAFE), // soft sky neutral
        const Color(0xFFEFF6FF), // light blue-tinted base
      ];
    }
  }
}
