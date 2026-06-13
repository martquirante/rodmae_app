import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/connectivity_service.dart';
import 'advanced_loading_effect.dart';

// ═════════════════════════════════════════════════════════════════════════════
// NETWORK STATUS BANNER
//
// A non-blocking, animated top-of-screen overlay that:
//   • Slides down + fades in when the device goes offline.
//   • Briefly shows a "Connected" confirmation then slides back up when
//     connectivity is restored.
//   • Reads ConnectivityService.isOnline via ValueListenableBuilder so it
//     reacts to any network change anywhere in the app.
//
// Usage — place inside MaterialApp's builder, above all routes:
//
//   MaterialApp(
//     builder: (context, child) => NetworkStatusBannerHost(child: child!),
//   )
// ═════════════════════════════════════════════════════════════════════════════

class NetworkStatusBannerHost extends StatefulWidget {
  final Widget child;

  const NetworkStatusBannerHost({required this.child, super.key});

  @override
  State<NetworkStatusBannerHost> createState() =>
      _NetworkStatusBannerHostState();
}

class _NetworkStatusBannerHostState extends State<NetworkStatusBannerHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  bool _showing = false;       // banner is visible (offline or recovery flash)
  bool _isRecovery = false;    // true while showing the green "Connected" flash
  Timer? _dismissTimer;

  static const _slideDuration = Duration(milliseconds: 380);
  static const _recoveryHold  = Duration(milliseconds: 1800);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _slideDuration);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));

    ConnectivityService.isOnline.addListener(_onConnectivityChanged);
    // Evaluate initial state (in case already offline at launch)
    WidgetsBinding.instance.addPostFrameCallback((_) => _onConnectivityChanged());
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    ConnectivityService.isOnline.removeListener(_onConnectivityChanged);
    _ctrl.dispose();
    super.dispose();
  }

  void _onConnectivityChanged() {
    final online = ConnectivityService.isOnline.value;

    if (!online) {
      // ── Go offline: show the red banner and keep it until reconnected ──────
      _dismissTimer?.cancel();
      if (mounted) {
        setState(() {
          _showing    = true;
          _isRecovery = false;
        });
        _ctrl.forward();
      }
    } else {
      // ── Came online: swap to green "Connected" flash then auto-dismiss ──────
      if (_showing) {
        if (mounted) {
          setState(() => _isRecovery = true);
        }
        _dismissTimer?.cancel();
        _dismissTimer = Timer(_recoveryHold, _hideBanner);
      }
    }
  }

  void _hideBanner() {
    if (!mounted) return;
    _ctrl.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showing    = false;
          _isRecovery = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Stack(
        children: [
          AdvancedLoadingEffect(
            isLoading: _showing,
            child: widget.child,
          ),
          if (_showing)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _slide,
                child: FadeTransition(
                  opacity: _fade,
                  child: _NetworkBannerContent(isRecovery: _isRecovery),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// The actual banner visual — swaps between offline (red) and recovery (green).
// ─────────────────────────────────────────────────────────────────────────────

class _NetworkBannerContent extends StatelessWidget {
  final bool isRecovery;

  const _NetworkBannerContent({required this.isRecovery});

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;

    final bgColor = isRecovery
        ? const Color(0xFF16A34A) // emerald-700
        : const Color(0xFFDC2626); // red-600

    final icon   = isRecovery ? Icons.wifi_rounded : Icons.wifi_off_rounded;
    final label  = isRecovery
        ? 'Back online!'
        : 'Unable to connect';
    final sub    = isRecovery
        ? 'Syncing your data in the background...'
        : 'Please check your internet connection.';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      color: bgColor,
      padding: EdgeInsets.fromLTRB(18, topPadding + 10, 18, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  sub,
                  style: GoogleFonts.inter(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // Animated connectivity dot
          _PulsingDot(color: Colors.white, pulse: !isRecovery),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small pulsing dot for the banner (reuse pattern from PresenceController)
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingDot extends StatefulWidget {
  final Color color;
  final bool pulse;

  const _PulsingDot({required this.color, required this.pulse});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = Tween<double>(begin: 0.7, end: 1.4)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    if (widget.pulse) _ctrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_PulsingDot old) {
    super.didUpdateWidget(old);
    if (widget.pulse && !_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    } else if (!widget.pulse && _ctrl.isAnimating) {
      _ctrl.stop();
      _ctrl.value = 1.0;
    }
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
      builder: (_, child) => Transform.scale(
        scale: widget.pulse ? _scale.value : 1.0,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.55),
                blurRadius: 6,
                spreadRadius: 2,
              )
            ],
          ),
        ),
      ),
    );
  }
}
