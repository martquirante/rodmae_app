import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/utils.dart';

class ThreeDFlipSuccessCard extends StatefulWidget {
  final double amount;
  final String category;
  final String walletName;
  final String? notes;
  final bool isSynced;

  const ThreeDFlipSuccessCard({
    required this.amount,
    required this.category,
    required this.walletName,
    this.notes,
    this.isSynced = true,
    super.key,
  });

  @override
  State<ThreeDFlipSuccessCard> createState() => _ThreeDFlipSuccessCardState();
}

class _ThreeDFlipSuccessCardState extends State<ThreeDFlipSuccessCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _flipAnim;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _checkAnim;
  late final Animation<double> _detailsAnim;

  double _tiltX = 0.0;
  double _tiltY = 0.0;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // 1. 3D Flip Rotation: starts with fast spins and decelerates (0.0 to 1.0)
    _flipAnim = Tween<double>(begin: 3.5 * math.pi, end: 0.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    // 2. Scale Entry: starts tiny and expands (with a subtle elastic overshoot)
    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
      ),
    );

    // 3. Checkmark Icon scale-in
    _checkAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.55, 0.85, curve: Curves.elasticOut),
      ),
    );

    // 4. Details text reveal
    _detailsAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _ctrl,
        curve: const Interval(0.7, 1.0, curve: Curves.easeOutQuad),
      ),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _updateTilt(Offset localPos, Size size) {
    final centerX = size.width / 2;
    final centerY = size.height / 2;
    final percentX = (localPos.dx - centerX) / centerX;
    final percentY = (localPos.dy - centerY) / centerY;

    setState(() {
      _tiltX = (-percentY * 0.08).clamp(-0.08, 0.08);
      _tiltY = (percentX * 0.08).clamp(-0.08, 0.08);
      _isHovered = true;
    });
  }

  void _resetTilt() {
    setState(() {
      _tiltX = 0.0;
      _tiltY = 0.0;
      _isHovered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardSize = const Size(290, 370);

    return Center(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final flipVal = _flipAnim.value;
          final scaleVal = _scaleAnim.value;
          final checkVal = _checkAnim.value;
          final detailsVal = _detailsAnim.value;

          // Combine entry flip with touch-based dynamic tilt
          final currentTiltX = _isHovered ? _tiltX : 0.0;
          final currentTiltY = _isHovered ? _tiltY : 0.0;

          return Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.0015) // Perspective depth
              ..rotateX(currentTiltX)
              ..rotateY(flipVal + currentTiltY)
              ..scale(scaleVal * (_isHovered ? 0.98 : 1.0)),
            alignment: Alignment.center,
            child: Listener(
              onPointerDown: (event) => _updateTilt(event.localPosition, cardSize),
              onPointerMove: (event) => _updateTilt(event.localPosition, cardSize),
              onPointerUp: (_) => _resetTilt(),
              onPointerCancel: (_) => _resetTilt(),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    width: cardSize.width,
                    height: cardSize.height,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? [Colors.white.withOpacity(0.09), Colors.white.withOpacity(0.02)]
                            : [RodMaeColors.navy.withOpacity(0.08), RodMaeColors.navy.withOpacity(0.01)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: isDark ? Colors.white24 : Colors.black12,
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? Colors.black45 : Colors.black12,
                          blurRadius: 30,
                          offset: const Offset(0, 15),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Card Header
                        Column(
                          children: [
                            const SizedBox(height: 6),
                            // Spinning Checkmark Circle
                            Transform.scale(
                              scale: checkVal,
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: RodMaeColors.mint.withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: RodMaeColors.mint.withOpacity(0.4),
                                    width: 2,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: RodMaeColors.mint.withOpacity(0.25),
                                      blurRadius: 15,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.check_rounded,
                                  color: RodMaeColors.mint,
                                  size: 38,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'TRANSACTION LOGGED',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 2.0,
                                color: isDark ? RodMaeColors.gold : RodMaeColors.navy.withOpacity(0.8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Large Transaction Amount
                            Text(
                              '₱${Formatters.money(widget.amount).replaceAll('PHP', '').trim()}',
                              style: GoogleFonts.robotoMono(
                                fontSize: 26,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : RodMaeColors.navy,
                              ),
                            ),
                            const SizedBox(height: 8),
                            // Sync Status Pill
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: widget.isSynced
                                    ? RodMaeColors.mint.withOpacity(0.12)
                                    : RodMaeColors.gold.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: widget.isSynced
                                      ? RodMaeColors.mint.withOpacity(0.3)
                                      : RodMaeColors.gold.withOpacity(0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: widget.isSynced ? RodMaeColors.mint : RodMaeColors.gold,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    widget.isSynced ? 'CLOUD SYNCED' : 'LOCAL SAVE',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                      color: widget.isSynced ? RodMaeColors.mint : RodMaeColors.gold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // Divider Line with ticket notches
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 16,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black : Colors.white,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                              ),
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  return Flex(
                                    direction: Axis.horizontal,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: List.generate(
                                      (constraints.constrainWidth() / 10).floor(),
                                      (_) => SizedBox(
                                        width: 4,
                                        height: 1.5,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: isDark ? Colors.white24 : Colors.black12,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                            Container(
                              width: 8,
                              height: 16,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.black : Colors.white,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  bottomLeft: Radius.circular(8),
                                ),
                              ),
                            ),
                          ],
                        ),
                        // Transaction Details (staggered reveal)
                        Opacity(
                          opacity: detailsVal,
                          child: Transform.translate(
                            offset: Offset(0, 15 * (1 - detailsVal)),
                            child: Column(
                              children: [
                                _buildDetailRow(
                                  icon: Icons.category_outlined,
                                  label: 'Category',
                                  value: widget.category,
                                  isDark: isDark,
                                ),
                                const SizedBox(height: 10),
                                _buildDetailRow(
                                  icon: Icons.account_balance_wallet_outlined,
                                  label: 'Wallet',
                                  value: widget.walletName,
                                  isDark: isDark,
                                ),
                                if (widget.notes != null && widget.notes!.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _buildDetailRow(
                                    icon: Icons.notes_outlined,
                                    label: 'Notes',
                                    value: widget.notes!,
                                    isDark: isDark,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
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

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required bool isDark,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDark ? Colors.white38 : Colors.black38,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: isDark ? Colors.white38 : Colors.black45,
            fontWeight: FontWeight.w500,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: isDark ? Colors.white70 : RodMaeColors.navy,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
