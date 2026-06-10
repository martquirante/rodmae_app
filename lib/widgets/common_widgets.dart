import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/constants.dart';
import '../models/chat_message.dart';
import '../models/love_trigger_event.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/supabase_service.dart';
import '../services/presence_controller.dart';
import '../services/connectivity_service.dart';

class RodMaePageFrame extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool? hasKeyboard;

  const RodMaePageFrame({
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(18, 8, 18, 12),
    this.hasKeyboard,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedHasKeyboard = hasKeyboard ?? (MediaQuery.viewInsetsOf(context).bottom > 0);

    return DecoratedBox(
      decoration: BoxDecoration(gradient: RodMaeColors.getAppBackground(isDark)),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            if (!resolvedHasKeyboard)
              Padding(
                padding: padding,
                child: const RodMaeHeader(),
              ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class RodMaeHeader extends StatefulWidget {
  const RodMaeHeader({super.key});

  @override
  State<RodMaeHeader> createState() => _RodMaeHeaderState();
}

class _RodMaeHeaderState extends State<RodMaeHeader> {
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadAvatar();
    PartnerIdentity.active.addListener(_loadAvatar);
    ProfileNotifier.updateNotifier.addListener(_loadAvatar);
  }

  @override
  void dispose() {
    PartnerIdentity.active.removeListener(_loadAvatar);
    ProfileNotifier.updateNotifier.removeListener(_loadAvatar);
    super.dispose();
  }

  Future<void> _loadAvatar() async {
    try {
      final active = PartnerIdentity.active.value;
      final profile = await SupabaseWeddingRepository.instance.fetchUserProfile(active.label);
      if (mounted) {
        setState(() {
          _avatarUrl = profile?.avatarUrl;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Row 1: App Title & User Avatar Info
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OUR ROYAL JOURNEY',
                    style: GoogleFonts.inter(
                      color: RodMaeColors.gold,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2.1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'RodMae App',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ],
              ),
            ),
            ValueListenableBuilder<PartnerProfile>(
              valueListenable: PartnerIdentity.active,
              builder: (context, active, _) {
                return GestureDetector(
                  onTap: () async {
                    await Navigator.pushNamed(context, '/settings');
                    _loadAvatar();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutBack,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: isDark
                          ? LinearGradient(
                              colors: [
                                RodMaeColors.royalBlue.withValues(alpha: 0.35),
                                RodMaeColors.navy,
                              ],
                            )
                          : LinearGradient(
                              colors: [
                                Colors.white,
                                RodMaeColors.lightBackground2,
                              ],
                            ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: RodMaeColors.gold.withValues(alpha: isDark ? 0.5 : 0.35),
                        width: 1.4,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: RodMaeColors.gold.withValues(alpha: 0.18),
                          blurRadius: 10,
                          spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                         // ── Avatar wrapped with partner presence badge ────
                        PresenceAvatarBadge(
                          partnerName: active == PartnerProfile.rodel
                              ? 'Eurine'
                              : 'Rodel',
                          radius: 15,
                          badgeSize: 10,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _avatarUrl == null ? RodMaeColors.goldGradient : null,
                              border: _avatarUrl != null
                                  ? Border.all(color: RodMaeColors.gold, width: 1.5)
                                  : null,
                              boxShadow: [
                                BoxShadow(
                                  color: RodMaeColors.gold.withValues(alpha: 0.45),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            alignment: Alignment.center,
                            child: _avatarUrl != null
                                ? ClipOval(
                                    child: Image.network(
                                      _avatarUrl!,
                                      width: 30,
                                      height: 30,
                                      fit: BoxFit.cover,
                                      errorBuilder: (context, error, stackTrace) {
                                        return Text(
                                          active.initials,
                                          style: GoogleFonts.inter(
                                            color: RodMaeColors.navy,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                : Text(
                                    active.initials,
                                    style: GoogleFonts.inter(
                                      color: RodMaeColors.navy,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        // Name column
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Logged in as',
                              style: GoogleFonts.inter(
                                color: isDark
                                    ? Colors.white38
                                    : RodMaeColors.lightTextMuted.withValues(alpha: 0.6),
                                fontSize: 8,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.3,
                              ),
                            ),
                            Text(
                              active.label,
                              style: GoogleFonts.inter(
                                color: isDark ? Colors.white : RodMaeColors.lightText,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          Icons.settings_outlined,
                          size: 12,
                          color: RodMaeColors.gold.withValues(alpha: 0.7),
                        ),
                        const SizedBox(width: 2),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        
        const SizedBox(height: 10),

        // Row 2: Live partner presence + network status + theme toggle
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // ── Left: connectivity-aware status chip ─────────────────────────
            ValueListenableBuilder<bool>(
              valueListenable: ConnectivityService.isOnline,
              builder: (context, online, _) {
                // When online, show live partner presence text
                if (online && AppRuntime.supabaseReady) {
                  return ValueListenableBuilder<PartnerProfile>(
                    valueListenable: PartnerIdentity.active,
                    builder: (context, active, _) {
                      final partnerName = active == PartnerProfile.rodel
                          ? 'Eurine'
                          : 'Rodel';
                      return PresenceIndicatorText(
                        partnerName: partnerName,
                        dotSize: 7,
                      );
                    },
                  );
                }
                // Offline or Supabase not ready: show static chip
                return _StatusChip(
                  label: online ? 'CONNECTED' : 'UNABLE TO CONNECT',
                  icon: online
                      ? Icons.cloud_done_rounded
                      : Icons.wifi_off_rounded,
                  online: online,
                );
              },
            ),
            // ── Right: theme toggle ──────────────────────────────────────────
            ValueListenableBuilder<ThemeMode>(
              valueListenable: RodMaeTheme.themeNotifier,
              builder: (context, currentMode, _) {
                final isCurrentlyDark = currentMode == ThemeMode.dark ||
                    (currentMode == ThemeMode.system &&
                        MediaQuery.platformBrightnessOf(context) == Brightness.dark);

                return GestureDetector(
                  onTap: () {
                    RodMaeTheme.themeNotifier.value =
                        isCurrentlyDark ? ThemeMode.light : ThemeMode.dark;
                  },
                  child: Container(
                    width: 74,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.06),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.3),
                        width: 1.2,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        AnimatedAlign(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOutCubic,
                          alignment: isCurrentlyDark ? Alignment.centerRight : Alignment.centerLeft,
                          child: Container(
                            width: 32,
                            height: 28,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: RodMaeColors.gold,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: RodMaeColors.gold.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Icon(
                              Icons.light_mode_rounded,
                              size: 15,
                              color: !isCurrentlyDark ? RodMaeColors.navy : (isDark ? Colors.white30 : Colors.black38),
                            ),
                            Icon(
                              Icons.dark_mode_rounded,
                              size: 15,
                              color: isCurrentlyDark ? RodMaeColors.navy : (isDark ? Colors.white30 : Colors.black38),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}


class _StatusChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool online;

  const _StatusChip({
    required this.label,
    required this.icon,
    this.online = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipColor = online ? RodMaeColors.electricBlue : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark 
              ? chipColor.withValues(alpha: 0.22) 
              : Colors.black.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: chipColor, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: GoogleFonts.inter(
              color: isDark ? (online ? RodMaeColors.sky : const Color(0xFFFCA5A5)) : RodMaeColors.navy2,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }
}


class ChatBadgeWrapper extends StatelessWidget {
  final Widget Function(BuildContext context, int count) builder;

  const ChatBadgeWrapper({required this.builder, super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PartnerProfile>(
      valueListenable: PartnerIdentity.active,
      builder: (context, activeProfile, _) {
        final myLabel = activeProfile.label.toLowerCase();
        return StreamBuilder<List<ChatMessage>>(
          stream: SupabaseWeddingRepository.instance.watchChat(),
          builder: (context, chatSnapshot) {
            final chatList = chatSnapshot.data ?? [];
            final chatUnread = chatList.where((m) =>
                m.sender.toLowerCase() != myLabel &&
                m.status != MessageStatus.seen).length;

            return StreamBuilder<List<LoveTriggerEvent>>(
              stream: SupabaseWeddingRepository.instance.watchLoveTriggers(),
              builder: (context, signalSnapshot) {
                final signalList = signalSnapshot.data ?? [];
                final signalUnread = signalList.where((s) =>
                    s.sender.toLowerCase() != myLabel &&
                    s.status != MessageStatus.seen).length;

                return builder(context, chatUnread + signalUnread);
              },
            );
          },
        );
      },
    );
  }
}

class RodMaeBottomNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  const RodMaeBottomNavBar({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [
      const _NavSpec(Icons.favorite_border_rounded, 'Home'),
      const _NavSpec(Icons.chat_bubble_outline_rounded, 'Chat'),
      const _NavSpec(Icons.grid_view_rounded, 'Hub'),
      const _NavSpec(Icons.lock_outline_rounded, 'Vault'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 76,
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF04091A).withValues(alpha: 0.94)
                  : Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: RodMaeColors.gold.withValues(alpha: isDark ? 0.2 : 0.15),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.12),
                  blurRadius: 30,
                  offset: const Offset(0, 14),
                ),
                BoxShadow(
                  color: RodMaeColors.gold.withValues(alpha: 0.06),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(items.length, (index) {
                final spec = items[index];
                if (index == 1) {
                  return ChatBadgeWrapper(
                    builder: (context, count) {
                      return _NavButton(
                        spec: spec,
                        selected: selectedIndex == index,
                        badgeCount: count,
                        onTap: () => onSelected(index),
                      );
                    },
                  );
                }
                return _NavButton(
                  spec: spec,
                  selected: selectedIndex == index,
                  onTap: () => onSelected(index),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavSpec {
  final IconData icon;
  final String label;

  const _NavSpec(this.icon, this.label);
}

class _NavButton extends StatelessWidget {
  final _NavSpec spec;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  const _NavButton({
    required this.spec,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scale = selected ? 1.1 : 1.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 64,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      RodMaeColors.royalBlue.withValues(alpha: isDark ? 0.6 : 0.18),
                      RodMaeColors.sapphire.withValues(alpha: isDark ? 0.4 : 0.1),
                    ],
                  )
                : null,
            border: Border.all(
              color: selected
                  ? RodMaeColors.gold.withValues(alpha: 0.7)
                  : Colors.transparent,
              width: 1.4,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: RodMaeColors.gold.withValues(alpha: 0.18),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    spec.icon,
                    color: selected
                        ? RodMaeColors.gold
                        : (isDark ? Colors.white38 : RodMaeColors.lightTextMuted),
                    size: 22,
                  ),
                  if (badgeCount > 0)
                    Positioned(
                      top: -4,
                      right: -6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: RodMaeColors.rose,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '$badgeCount',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                spec.label.toUpperCase(),
                style: GoogleFonts.inter(
                  color: selected
                      ? RodMaeColors.lemon
                      : (isDark ? Colors.white38 : RodMaeColors.lightTextMuted),
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final IconData icon;

  const SectionHeader({
    required this.title,
    required this.icon,
    this.trailing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(
        children: [
          Icon(icon, color: RodMaeColors.electricBlue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.inter(
                color: isDark ? RodMaeColors.sky : RodMaeColors.sapphire,
                fontSize: 13,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
              ),
            ),
          ),
          if (trailing != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.8),
                borderRadius: BorderRadius.circular(16),
                border: isDark ? null : Border.all(color: Colors.black.withValues(alpha: 0.1)),
              ),
              child: Text(
                trailing!,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white70 : RodMaeColors.lightText,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SegmentedSwitcher extends StatelessWidget {
  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onSelected;
  final List<int>? badgeCounts;

  const SegmentedSwitcher({
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onSelected,
    this.badgeCounts,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.04),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.2)),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = selected == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? RodMaeColors.sapphire : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: active ? RodMaeColors.electricBlue : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          icons[index],
                          size: 15,
                          color: active ? Colors.white : (isDark ? Colors.white38 : RodMaeColors.lightTextSoft),
                        ),
                        if (badgeCounts != null &&
                            index < badgeCounts!.length &&
                            badgeCounts![index] > 0)
                          Positioned(
                            top: -4,
                            right: -5,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: RodMaeColors.rose,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        labels[index],
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          color: active
                              ? Colors.white
                              : (isDark ? Colors.white.withValues(alpha: 0.45) : RodMaeColors.lightTextSoft),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class Sliding3DNotificationBanner extends StatefulWidget {
  const Sliding3DNotificationBanner({super.key});

  @override
  State<Sliding3DNotificationBanner> createState() => _Sliding3DNotificationBannerState();
}

class _Sliding3DNotificationBannerState extends State<Sliding3DNotificationBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;

  AppNotification? _currentNotification;
  Timer? _dismissTimer;

  // 3D tilt parameters
  double _tiltX = 0.0;
  double _tiltY = 0.0;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0.0, -1.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.elasticOut,
      reverseCurve: Curves.easeInCubic,
    ));

    _fadeAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOut,
    ));

    AppNotificationNavigation.activeNotificationNotifier.addListener(_onNotificationChanged);
  }

  @override
  void dispose() {
    AppNotificationNavigation.activeNotificationNotifier.removeListener(_onNotificationChanged);
    _dismissTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  void _onNotificationChanged() {
    final newNotif = AppNotificationNavigation.activeNotificationNotifier.value;
    if (newNotif != null) {
      _dismissTimer?.cancel();
      // Always reset + forward so repeated notifications always animate in
      _animCtrl.reset();
      setState(() {
        _currentNotification = newNotif;
      });
      HapticFeedback.lightImpact();
      _animCtrl.forward();

      _dismissTimer = Timer(const Duration(seconds: 4), () {
        _dismiss();
      });
    } else {
      _dismissTimer?.cancel();
      if (_animCtrl.isCompleted || _animCtrl.isAnimating) {
        _animCtrl.reverse().then((_) {
          if (mounted && AppNotificationNavigation.activeNotificationNotifier.value == null) {
            setState(() {
              _currentNotification = null;
            });
          }
        });
      } else {
        if (mounted) {
          setState(() {
            _currentNotification = null;
          });
        }
      }
    }
  }

  void _dismiss() {
    HapticFeedback.lightImpact();
    AppNotificationNavigation.clear();
  }

  void _resetTilt() {
    setState(() {
      _tiltX = 0.0;
      _tiltY = 0.0;
      _pressed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentNotification == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: GestureDetector(
              onTap: () {
                if (_currentNotification?.onTap != null) {
                  _currentNotification!.onTap!();
                }
                _dismiss();
              },
              onVerticalDragUpdate: (details) {
                if (details.primaryDelta! < -6) {
                  _dismiss();
                }
              },
              onPanUpdate: (details) {
                setState(() {
                  _pressed = true;
                  _tiltY = (_tiltY + details.delta.dx / 320).clamp(-0.14, 0.14);
                  _tiltX = (_tiltX - details.delta.dy / 320).clamp(-0.14, 0.14);
                });
              },
              onPanEnd: (_) => _resetTilt(),
              onPanCancel: _resetTilt,
              child: AnimatedScale(
                scale: _pressed ? 0.98 : 1.0,
                duration: const Duration(milliseconds: 100),
                child: Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.0015)
                    ..rotateX(_tiltX)
                    ..rotateY(_tiltY),
                  child: Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: _currentNotification!.color.withValues(alpha: 0.25),
                          blurRadius: 24,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            gradient: isDark
                                ? LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      RodMaeColors.navy2.withValues(alpha: 0.85),
                                      RodMaeColors.navy.withValues(alpha: 0.95),
                                    ],
                                  )
                                : LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Colors.white.withValues(alpha: 0.9),
                                      RodMaeColors.lightBackground.withValues(alpha: 0.95),
                                    ],
                                  ),
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(
                              color: _currentNotification!.color.withValues(alpha: 0.4),
                              width: 1.8,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: _currentNotification!.color.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  _currentNotification!.icon,
                                  color: _currentNotification!.color,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _currentNotification!.title.toUpperCase(),
                                      style: GoogleFonts.inter(
                                        color: _currentNotification!.color,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1.5,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      _currentNotification!.message,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.inter(
                                        color: isDark ? Colors.white : RodMaeColors.lightText,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: isDark ? Colors.white30 : Colors.black26,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
