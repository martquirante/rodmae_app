import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import 'advanced_loading_effect.dart';

class PrimaryPillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool busy;
  final Color color;

  const PrimaryPillButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.busy = false,
    this.color = RodMaeColors.electricBlue,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: busy ? null : onPressed,
      icon: busy
          ? AdvancedLoadingEffect(
              isLoading: true,
              shape: BoxShape.circle,
              placeholder: Container(
                width: 15,
                height: 15,
                decoration: const BoxDecoration(
                  color: Colors.white60,
                  shape: BoxShape.circle,
                ),
              ),
              child: const SizedBox(width: 15, height: 15),
            )
          : Icon(icon, size: 17),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        disabledBackgroundColor: color.withValues(alpha: 0.45),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        textStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }
}
