import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart' hide Path;
import '../core/theme.dart';
import '../core/animations.dart';
import '../core/constants.dart';
import '../models/meal_plan.dart';
import '../models/surprise_note.dart';
import '../models/couple_location.dart';
import 'map_screen.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/common_widgets.dart';
import '../widgets/love_overlay.dart';
import '../widgets/isometric_markers.dart';
import '../widgets/cinematic_envelope.dart';
import '../widgets/advanced_loading_effect.dart';

class HomeDashboardScreen extends StatefulWidget {
  final AppStartupStatus startup;

  const HomeDashboardScreen({
    required this.startup,
    super.key,
  });

  @override
  State<HomeDashboardScreen> createState() => _HomeDashboardScreenState();
}

class _HomeDashboardScreenState extends State<HomeDashboardScreen>
    with SingleTickerProviderStateMixin {
  LoveTrigger? _activeTrigger;
  late final AnimationController _lottieController;
  int _refreshCount = 0;

  bool _isRefreshing = false;

  Future<void> _handleRefresh() async {
    if (_isRefreshing) return;
    HapticFeedback.mediumImpact();
    setState(() => _isRefreshing = true);
    try {
      await Future.wait([
        SupabaseWeddingRepository.instance.fetchNotes(),
        SupabaseWeddingRepository.instance.fetchLoveTriggers(),
        SupabaseWeddingRepository.instance.fetchFinances(),
        SupabaseWeddingRepository.instance.fetchUserProfile('Rodel'),
        SupabaseWeddingRepository.instance.fetchUserProfile('Eurine'),
        SupabaseWeddingRepository.instance.fetchLocations(),
      ]);
    } catch (e) {
      print('Refresh error: $e');
    }
    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _refreshCount++;
      });
    }
  }



  static const loveTriggers = <LoveTrigger>[
    LoveTrigger(
      title: 'I Love You',
      subtitle: 'Ruby Glass Hearts',
      icon: Icons.favorite_rounded,
      color: RodMaeColors.rose,
      animationAsset: 'assets/animations/hearts.json',
      overlayTitle: 'I-love-you signal sent',
    ),
    LoveTrigger(
      title: 'Miss You',
      subtitle: 'Bioluminescent Orbs',
      icon: Icons.blur_circular_rounded,
      color: RodMaeColors.violet,
      animationAsset: 'assets/animations/hearts.json',
      overlayTitle: 'Miss-you signal sent',
    ),
    LoveTrigger(
      title: 'Flying Kiss',
      subtitle: 'Neon Sonic Rings',
      icon: Icons.radio_button_checked_rounded,
      color: RodMaeColors.rose,
      animationAsset: 'assets/animations/kiss.json',
      overlayTitle: 'Flying kiss delivered',
    ),
    LoveTrigger(
      title: 'Warm Embrace',
      subtitle: 'Golden Stardust Aurora',
      icon: Icons.auto_awesome_rounded,
      color: RodMaeColors.gold,
      animationAsset: 'assets/animations/note.json',
      overlayTitle: 'Warm embrace delivered',
    ),
    LoveTrigger(
      title: 'Heading Home',
      subtitle: 'Partner Status',
      icon: Icons.navigation_rounded,
      color: RodMaeColors.mint,
      animationAsset: 'assets/animations/home.json',
      overlayTitle: 'Home route shared',
    ),
    LoveTrigger(
      title: 'Surprise Note',
      subtitle: 'Push Note',
      icon: Icons.sticky_note_2_rounded,
      color: RodMaeColors.electricBlue,
      animationAsset: 'assets/animations/note.json',
      overlayTitle: 'Surprise note queued',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _lottieController = AnimationController(vsync: this);
    _lottieController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _activeTrigger = null);
        _lottieController.reset();
      }
    });
  }

  @override
  void dispose() {
    _lottieController.dispose();
    super.dispose();
  }

  Future<void> _triggerLove(LoveTrigger trigger) async {
    final isHeadingHome = trigger.title == 'Heading Home';

    if (!isHeadingHome) {
      HapticFeedback.heavyImpact();
      setState(() => _activeTrigger = trigger);
      _lottieController
        ..reset()
        ..forward();
    } else {
      // Navigate straight to the map screen immediately
      Navigator.of(context).pushNamed('/map', arguments: {'autoHeadingHome': true});
    }

    final sender = PartnerIdentity.active.value.label;
    if (!AppRuntime.supabaseReady) {
      if (mounted && !isHeadingHome) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Love signal shown locally. Supabase is offline, so spouse delivery is paused.',
            ),
          ),
        );
      }
      return;
    }

    try {
      await SupabaseWeddingRepository.instance.insertLoveTrigger(trigger.title);
      await NotificationService.sendPushToSpouse(
        title: '$sender sent a love signal',
        body: trigger.title,
        type: 'signal',
        sender: sender,
        triggerType: trigger.title,
      );
      if (mounted && !isHeadingHome) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${trigger.title} sent to your spouse.')),
        );
      }
    } catch (error) {
      if (mounted && !isHeadingHome) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Love signal failed to sync: $error')),
        );
      }
    }
  }

  void _showSurpriseNoteDialog(LoveTrigger trigger) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: AlertDialog(
            backgroundColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            content: GlassCard(
              borderColor: RodMaeColors.gold.withValues(alpha: 0.3),
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sticky_note_2_rounded, color: RodMaeColors.gold, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        'SEND SURPRISE NOTE',
                        style: GoogleFonts.inter(
                          color: RodMaeColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Write a sweet note that will broadcast directly onto your spouse\'s dashboard!',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white70 : RodMaeColors.lightTextSoft,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    maxLength: 140,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: isDark ? Colors.white : RodMaeColors.lightText,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Type your message here...',
                      hintStyle: GoogleFonts.inter(color: isDark ? Colors.white30 : Colors.black38, fontSize: 13),
                      counterStyle: GoogleFonts.inter(color: isDark ? Colors.white30 : Colors.black38, fontSize: 10),
                      filled: true,
                      fillColor: Colors.black.withValues(alpha: 0.15),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: RodMaeColors.gold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(
                          'CANCEL',
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white54 : RodMaeColors.lightTextSoft,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      PrimaryPillButton(
                        label: 'SEND NOTE',
                        icon: Icons.send_rounded,
                        onPressed: () async {
                          final text = controller.text.trim();
                          if (text.isNotEmpty) {
                            Navigator.of(context).pop();
                            final messenger = ScaffoldMessenger.of(context);
                            showSurpriseNoteSendAnimation(context);
                            try {
                              await SupabaseWeddingRepository.instance.insertSurpriseNote(text);
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Surprise note sent to your spouse!')),
                              );
                            } catch (e) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('Failed to send note: $e')),
                              );
                            }
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RodMaePageFrame(
          child: RefreshIndicator(
            color: Colors.transparent,
            backgroundColor: Colors.transparent,
            displacement: 140.0,
            onRefresh: _handleRefresh,
            child: AdvancedLoadingEffect(
              isLoading: _isRefreshing,
              child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 108),
              children: [
                _WeddingLockCard(startup: widget.startup),
                const SizedBox(height: 18),
                Countdown3DCard(key: ValueKey('countdown_$_refreshCount')),
                SurpriseNoteCard(key: ValueKey('note_$_refreshCount')),
                const SectionHeader(
                  title: 'SEND LOVE SIGNALS',
                  icon: Icons.bolt_rounded,
                  trailing: 'Tap to show love',
                ),
                LoveTriggerGrid(
                  triggers: loveTriggers,
                  onTrigger: (trigger) {
                    if (trigger.title == 'Surprise Note') {
                      _showSurpriseNoteDialog(trigger);
                    } else {
                      _triggerLove(trigger);
                    }
                  },
                ),
                const SectionHeader(
                  title: 'WHERE WE ARE RIGHT NOW',
                  icon: Icons.map_rounded,
                  trailing: 'Live Location',
                ),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/map'),
                  child: CoupleMapCard(key: ValueKey('map_$_refreshCount')),
                ),
              ],
            ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: _activeTrigger == null
              ? const SizedBox.shrink()
              : Custom3DLoveOverlay(
                  key: ValueKey(_activeTrigger!.title),
                  trigger: _activeTrigger!,
                  controller: _lottieController,
                ),
        ),
      ],
    );
  }
}

class _WeddingLockCard extends StatelessWidget {
  final AppStartupStatus startup;

  const _WeddingLockCard({required this.startup});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GlassCard(
      padding: const EdgeInsets.all(15),
      borderColor: RodMaeColors.sky.withValues(alpha: isDark ? 0.12 : 0.4),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: RodMaeColors.electricBlue.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.favorite_rounded,
              color: RodMaeColors.electricBlue,
              size: 26,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OUR WEDDING CELEBRATION',
                  style: GoogleFonts.inter(
                    color: isDark ? RodMaeColors.sky : RodMaeColors.sapphire,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'June 3, 2026',
                  style: GoogleFonts.playfairDisplay(
                    color: isDark ? Colors.white : RodMaeColors.lightText,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: RodMaeColors.electricBlue.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: RodMaeColors.sky.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  startup.supabaseReady ? Icons.verified_rounded : Icons.lock,
                  color: RodMaeColors.sky,
                  size: 15,
                ),
                const SizedBox(width: 6),
                Text(
                  startup.supabaseReady ? 'Live Connected' : 'Offline Mode',
                  style: GoogleFonts.inter(
                    color: RodMaeColors.sky,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Countdown3DCard extends StatefulWidget {
  const Countdown3DCard({super.key});

  @override
  State<Countdown3DCard> createState() => _Countdown3DCardState();
}

class _Countdown3DCardState extends State<Countdown3DCard> {
  late Timer _timer;
  Duration _remaining = Duration.zero;
  double _tiltX = 0;
  double _tiltY = 0;

  @override
  void initState() {
    super.initState();
    _tick();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _tick() {
    final diff = AppConfig.weddingDate.difference(DateTime.now());
    if (mounted) {
      setState(() => _remaining = diff);
    }
  }

  void _updateTilt(DragUpdateDetails details) {
    setState(() {
      _tiltX = (_tiltX - details.delta.dy / 220).clamp(-0.18, 0.18);
      _tiltY = (_tiltY + details.delta.dx / 220).clamp(-0.18, 0.18);
    });
  }

  void _resetTilt() {
    setState(() {
      _tiltX = 0;
      _tiltY = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isPast = _remaining.isNegative;
    final absDiff = _remaining.abs();

    final days = absDiff.inDays;
    final months = days ~/ 30;
    final dayRemainder = days % 30;
    final hours = absDiff.inHours % 24;
    final minutes = absDiff.inMinutes % 60;
    final seconds = absDiff.inSeconds % 60;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onPanUpdate: _updateTilt,
      onPanCancel: _resetTilt,
      onPanEnd: (_) => _resetTilt(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.002)
          ..rotateX(_tiltX)
          ..rotateY(_tiltY),
        transformAlignment: Alignment.center,
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
          gradient: isDark
              ? RadialGradient(
                  radius: 1.2,
                  center: Alignment.topRight,
                  colors: [
                    RodMaeColors.electricBlue.withValues(alpha: 0.42),
                    RodMaeColors.sapphire.withValues(alpha: 0.45),
                    RodMaeColors.navy.withValues(alpha: 0.95),
                  ],
                )
              : null,
          borderColor: Colors.white.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(28),
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: RodMaeColors.electricBlue.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: RodMaeColors.sky.withValues(alpha: 0.62),
                  ),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: RodMaeColors.rose,
                  size: 34,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                isPast ? 'TIME SINCE WE SAID I DO' : 'COUNTDOWN TO OUR BIG DAY',
                style: GoogleFonts.inter(
                  color: isDark ? RodMaeColors.sky : RodMaeColors.sapphire,
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                isPast
                    ? '$months Months, $dayRemainder Days'
                    : '$months Months, $dayRemainder Days',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : RodMaeColors.lightText,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: RodMaeColors.sky.withValues(alpha: 0.12),
                  ),
                ),
                child: Text(
                  '${isPast ? "+" : "-"} ${hours.toString().padLeft(2, '0')}h : '
                  '${minutes.toString().padLeft(2, '0')}m : '
                  '${seconds.toString().padLeft(2, '0')}s',
                  style: GoogleFonts.robotoMono(
                    color: isDark ? RodMaeColors.sky : RodMaeColors.sapphire,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

}

class SurpriseNoteCard extends StatelessWidget {
  const SurpriseNoteCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return StreamBuilder<List<SurpriseNote>>(
      stream: SupabaseWeddingRepository.instance.watchNotes(),
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final spouseLabel = PartnerIdentity.active.value == PartnerProfile.rodel
            ? 'Eurine'
            : 'Rodel';
        
        final spouseNotes = snapshot.data!
            .where((n) => n.sender.toLowerCase().contains(spouseLabel.toLowerCase()))
            .toList();

        if (spouseNotes.isEmpty) {
          return const SizedBox.shrink();
        }

        final latestNote = spouseNotes.first;

        return GlassCard(
          margin: const EdgeInsets.only(top: 18),
          borderColor: RodMaeColors.gold.withValues(alpha: 0.18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.sticky_note_2_outlined,
                    color: RodMaeColors.gold,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'SWEET NOTE FROM SPOUSE',
                      style: GoogleFonts.inter(
                        color: RodMaeColors.gold,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  Text(
                    'Just received',
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white38 : RodMaeColors.lightTextSoft.withValues(alpha: 0.5),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '"${latestNote.content}"',
                style: GoogleFonts.playfairDisplay(
                  color: isDark ? Colors.white : RodMaeColors.lightText,
                  fontSize: 16,
                  height: 1.32,
                  fontStyle: FontStyle.italic,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Sent with love',
                    style: GoogleFonts.robotoMono(
                      color: RodMaeColors.sky.withValues(alpha: 0.72),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class LoveTriggerGrid extends StatelessWidget {
  final List<LoveTrigger> triggers;
  final ValueChanged<LoveTrigger> onTrigger;

  const LoveTriggerGrid({
    required this.triggers,
    required this.onTrigger,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      itemCount: triggers.length,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.35,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (context, index) {
        final trigger = triggers[index];
        return _LoveTriggerTile(
          trigger: trigger,
          onTap: () => onTrigger(trigger),
        );
      },
    );
  }
}

class _LoveTriggerTile extends StatelessWidget {
  final LoveTrigger trigger;
  final VoidCallback onTap;

  const _LoveTriggerTile({
    required this.trigger,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Ink(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isDark ? RodMaeColors.navy.withValues(alpha: 0.82) : Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: trigger.color.withValues(alpha: isDark ? 0.2 : 0.4),
            ),
            boxShadow: isDark ? null : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: trigger.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(trigger.icon, color: trigger.color, size: 22),
              ),
              const Spacer(),
              Text(
                trigger.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white : RodMaeColors.lightText,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                trigger.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white54 : RodMaeColors.lightTextSoft,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



class CoupleMapCard extends StatefulWidget {
  const CoupleMapCard({super.key});

  @override
  State<CoupleMapCard> createState() => _CoupleMapCardState();
}

class _CoupleMapCardState extends State<CoupleMapCard> {
  final MapController _mapController = MapController();
  String? _rodelAvatarUrl;
  String? _maryAvatarUrl;
  MapType _dashboardMapType = MapType.hybrid;
  bool _isLayersExpanded = false;
  LatLng? _deviceLocation;

  @override
  void initState() {
    super.initState();
    _loadAvatars();
    _determineDeviceLocation();
  }

  Future<void> _determineDeviceLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        return;
      }
      if (permission == LocationPermission.deniedForever) return;

      Position position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
      if (mounted) {
        setState(() {
          _deviceLocation = LatLng(position.latitude, position.longitude);
        });
      }
    } catch (_) {}
  }

  Future<void> _loadAvatars() async {
    try {
      final rProfile = await SupabaseWeddingRepository.instance.fetchUserProfile('Rodel');
      final mProfile = await SupabaseWeddingRepository.instance.fetchUserProfile('Eurine');
      if (mounted) {
        setState(() {
          _rodelAvatarUrl = rProfile?.avatarUrl;
          _maryAvatarUrl = mProfile?.avatarUrl;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<CoupleLocation>>(
      stream: SupabaseWeddingRepository.instance.watchLocations(),
      builder: (context, snapshot) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        
        LatLng? rodelLoc;
        LatLng? maryLoc;
        LatLng? homeLoc;
        LatLng? rodelWork;
        LatLng? maryWork;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final list = snapshot.data!;
          for (final loc in list) {
            if (loc.locationType == 'live') {
              if (loc.partner.toLowerCase() == 'rodel') {
                rodelLoc = loc.position;
              } else if (loc.partner.toLowerCase().contains('mary') || loc.partner.toLowerCase().contains('mae')) {
                maryLoc = loc.position;
              }
            } else if (loc.locationType == 'home') {
              homeLoc = loc.position;
            } else if (loc.locationType == 'work') {
              if (loc.partner.toLowerCase() == 'rodel') {
                rodelWork = loc.position;
              } else if (loc.partner.toLowerCase().contains('mary') || loc.partner.toLowerCase().contains('mae')) {
                maryWork = loc.position;
              }
            }
          }
        }

        if (rodelLoc == null && maryLoc == null) {
          return GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 26),
            borderColor: RodMaeColors.gold.withValues(alpha: 0.18),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Center(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: RodMaeColors.electricBlue.withValues(alpha: 0.08),
                        ),
                      ),
                      PulseGlow(
                        glowColor: RodMaeColors.gold,
                        duration: const Duration(milliseconds: 2000),
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: RodMaeColors.gold, width: 2),
                            color: RodMaeColors.navy2,
                          ),
                          child: const Icon(
                            Icons.location_off_rounded,
                            color: RodMaeColors.gold,
                            size: 26,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'NO LIVE LOCATIONS DETECTED',
                  style: GoogleFonts.inter(
                    color: RodMaeColors.gold,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Open the map screen to establish a real-time connection and share your location.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    color: isDark ? Colors.white70 : RodMaeColors.lightTextSoft,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RodMaeColors.electricBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  icon: const Icon(Icons.map_rounded, size: 16),
                  label: Text(
                    'OPEN INTERACTIVE MAP',
                    style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  onPressed: () => Navigator.pushNamed(context, '/map'),
                ),
              ],
            ),
          );
        }

        // Calculate map center dynamically:
        LatLng center;
        double zoom = 12.0;

        if (rodelLoc != null && maryLoc != null) {
          center = LatLng(
            (rodelLoc.latitude + maryLoc.latitude) / 2,
            (rodelLoc.longitude + maryLoc.longitude) / 2,
          );
        } else if (rodelLoc != null) {
          center = rodelLoc;
          zoom = 13.5;
        } else if (maryLoc != null) {
          center = maryLoc;
          zoom = 13.5;
        } else {
          // If both are missing, center on device's location or Taguig default
          center = _deviceLocation ?? const LatLng(14.5547, 121.0244);
          zoom = _deviceLocation != null ? 14.0 : 11.5;
        }

        // Calculate distance between the two spouses' live locations
        double? distance;
        if (rodelLoc != null && maryLoc != null) {
          distance = const Distance().as(
            LengthUnit.Kilometer,
            rodelLoc,
            maryLoc,
          );
        }

        // Helper to check where Rodel and Eurine are
        String getStatusText() {
          LatLng? rLoc = rodelLoc;
          LatLng? mLoc = maryLoc;

          if (rLoc == null && mLoc == null) {
            return 'Waiting for spouse location updates...';
          }

          String rStatus = rLoc == null ? 'offline' : 'on the move';
          String mStatus = mLoc == null ? 'offline' : 'on the move';

          double getDist(LatLng p1, LatLng p2) => const Distance().as(LengthUnit.Meter, p1, p2);

          if (homeLoc != null) {
            if (rLoc != null && getDist(rLoc, homeLoc) < 250) rStatus = 'at Home';
            if (mLoc != null && getDist(mLoc, homeLoc) < 250) mStatus = 'at Home';
          }
          if (rodelWork != null && rLoc != null && getDist(rLoc, rodelWork) < 250) {
            rStatus = 'at Work';
          }
          if (maryWork != null && mLoc != null && getDist(mLoc, maryWork) < 250) {
            mStatus = 'at Work';
          }

          // fallback to mock labels if no custom addresses are set yet and locations are active
          if (homeLoc == null && rodelWork == null && maryWork == null && rLoc != null && mLoc != null) {
            rStatus = 'in Office';
            mStatus = 'at Home';
          }

          if (rLoc == null) {
            return 'Eurine is $mStatus. Rodel\'s location is offline.';
          }
          if (mLoc == null) {
            return 'Rodel is $rStatus. Eurine\'s location is offline.';
          }

          return 'Eurine is $mStatus. Rodel is $rStatus.';
        }

        // Build list of markers to display on dashboard map card
        final markers = <Marker>[];
        
        // Rodel live (only add if present)
        if (rodelLoc != null) {
          markers.add(
            Marker(
              point: rodelLoc,
              width: 75,
              height: 65,
              child: _buildDashboardUserMarker('Rodel', RodMaeColors.electricBlue, Icons.work_rounded),
            ),
          );
        }

        // Eurine live (only add if present)
        if (maryLoc != null) {
          markers.add(
            Marker(
              point: maryLoc,
              width: 75,
              height: 65,
              child: _buildDashboardUserMarker('Eurine', RodMaeColors.rose, Icons.home_rounded),
            ),
          );
        }

        // Home marker (if set)
        if (homeLoc != null) {
          markers.add(
            Marker(
              point: homeLoc,
              width: 54,
              height: 54,
              alignment: Alignment.topCenter,
              child: const IsometricMarker(
                type: 'home',
                label: 'Home',
                color: RodMaeColors.gold,
                isAnimated: false,
              ),
            ),
          );
        }

        return GestureDetector(
          onDoubleTap: () => Navigator.of(context).pushNamed('/map'),
          child: GlassCard(
            padding: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SizedBox(
                  height: 238,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: center,
                            initialZoom: zoom,
                            interactionOptions: const InteractionOptions(
                              flags: InteractiveFlag.pinchZoom |
                                  InteractiveFlag.drag |
                                  InteractiveFlag.doubleTapZoom,
                            ),
                          ),
                          children: [
                            if (_dashboardMapType == MapType.street)
                              TileLayer(
                                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                userAgentPackageName: 'com.example.rodmae_app',
                              ),
                            if (_dashboardMapType == MapType.satellite || _dashboardMapType == MapType.hybrid)
                              TileLayer(
                                urlTemplate: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                                userAgentPackageName: 'com.example.rodmae_app',
                              ),
                            if (_dashboardMapType == MapType.satellite || _dashboardMapType == MapType.hybrid)
                              TileLayer(
                                urlTemplate: 'https://mt1.google.com/vt/lyrs=h&x={x}&y={y}&z={z}',
                                userAgentPackageName: 'com.example.rodmae_app',
                              ),
                            if (rodelLoc != null && maryLoc != null)
                              PolylineLayer(
                                polylines: [
                                  Polyline(
                                    points: [rodelLoc, maryLoc],
                                    color: RodMaeColors.electricBlue.withValues(alpha: 0.6),
                                    strokeWidth: 4,
                                  ),
                                ],
                              ),
                            MarkerLayer(markers: markers),
                          ],
                        ),
                      ),
                      
                      // Floating Mini Focus Target Controls (Top Left)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Row(
                          children: [
                            _buildMiniFocusButton(
                              label: 'Rodel',
                              child: CircleAvatar(
                                radius: 9,
                                backgroundColor: RodMaeColors.electricBlue,
                                backgroundImage: _rodelAvatarUrl != null ? NetworkImage(_rodelAvatarUrl!) : null,
                                child: _rodelAvatarUrl == null
                                    ? Text('R', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))
                                    : null,
                              ),
                              onPressed: () {
                                if (rodelLoc != null) {
                                  _animateMapTo(rodelLoc, 13.5);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Rodel\'s location is offline.')),
                                  );
                                }
                              },
                              isDark: isDark,
                            ),
                            const SizedBox(width: 6),
                            _buildMiniFocusButton(
                              label: 'Eurine',
                              child: CircleAvatar(
                                radius: 9,
                                backgroundColor: RodMaeColors.rose,
                                backgroundImage: _maryAvatarUrl != null ? NetworkImage(_maryAvatarUrl!) : null,
                                child: _maryAvatarUrl == null
                                    ? Text('M', style: GoogleFonts.inter(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white))
                                    : null,
                              ),
                              onPressed: () {
                                if (maryLoc != null) {
                                  _animateMapTo(maryLoc, 13.5);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Eurine\'s location is offline.')),
                                  );
                                }
                              },
                              isDark: isDark,
                            ),
                            const SizedBox(width: 6),
                            if (homeLoc != null) ...[
                              _buildMiniFocusButton(
                                label: 'Home',
                                child: const Icon(Icons.home_rounded, color: RodMaeColors.gold, size: 12),
                                onPressed: () => _animateMapTo(homeLoc!, 14.5),
                                isDark: isDark,
                              ),
                              const SizedBox(width: 6),
                            ],
                            _buildMiniFocusButton(
                              label: 'Fit Both',
                              child: const Icon(Icons.zoom_out_map_rounded, color: Colors.white, size: 12),
                              onPressed: () {
                                if (rodelLoc != null && maryLoc != null) {
                                  _fitBoth(rodelLoc, maryLoc);
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Both locations must be active.')),
                                  );
                                }
                              },
                              isDark: isDark,
                            ),
                          ],
                        ),
                      ),

                      // Expandable Map Layer Toggler on Dashboard (Top Right)
                      Positioned(
                        top: 10,
                        right: 10,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_isLayersExpanded) ...[
                              _buildMiniLayerButton('Street', Icons.map_outlined, _dashboardMapType == MapType.street, () {
                                setState(() {
                                  _dashboardMapType = MapType.street;
                                  _isLayersExpanded = false;
                                });
                              }, isDark),
                              const SizedBox(height: 6),
                              _buildMiniLayerButton('Sat', Icons.satellite_outlined, _dashboardMapType == MapType.satellite, () {
                                setState(() {
                                  _dashboardMapType = MapType.satellite;
                                  _isLayersExpanded = false;
                                });
                              }, isDark),
                              const SizedBox(height: 6),
                              _buildMiniLayerButton('Hybrid', Icons.layers_outlined, _dashboardMapType == MapType.hybrid, () {
                                setState(() {
                                  _dashboardMapType = MapType.hybrid;
                                  _isLayersExpanded = false;
                                });
                              }, isDark),
                              const SizedBox(height: 6),
                            ],
                            GestureDetector(
                              onTap: () {
                                setState(() {
                                  _isLayersExpanded = !_isLayersExpanded;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.72),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white24, width: 1),
                                ),
                                child: Icon(
                                  _isLayersExpanded ? Icons.close_rounded : Icons.layers_rounded,
                                  color: Colors.white,
                                  size: 15,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          getStatusText(),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.3,
                            color: isDark ? Colors.white : RodMaeColors.lightText,
                          ),
                        ),
                      ),
                      if (distance != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: RodMaeColors.electricBlue.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${distance.toStringAsFixed(2)} KM',
                            style: GoogleFonts.robotoMono(
                              color: RodMaeColors.sky,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'OFF-GRID',
                            style: GoogleFonts.robotoMono(
                              color: isDark ? Colors.white30 : Colors.black38,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDashboardUserMarker(String name, Color color, IconData icon) {
    final initials = name.substring(0, 1).toUpperCase();
    final avatarUrl = name.toLowerCase() == 'rodel' ? _rodelAvatarUrl : _maryAvatarUrl;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PulseGlow(
          glowColor: color,
          child: Transform(
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001) // perspective
              ..rotateX(0.12) // subtle 3D tilt forward
              ..rotateY(0.08),
            alignment: Alignment.center,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.8),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 14,
                backgroundColor: color,
                backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        initials,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
        const SizedBox(height: 2),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            name,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  void _animateMapTo(LatLng target, double zoom) {
    _mapController.move(target, zoom);
  }

  void _fitBoth(LatLng p1, LatLng p2) {
    final bounds = LatLngBounds(p1, p2);
    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(36),
      ),
    );
  }

  Widget _buildMiniFocusButton({
    required String label,
    required Widget child,
    required VoidCallback onPressed,
    required bool isDark,
  }) {
    return Tooltip(
      message: 'Focus on $label',
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildMiniLayerButton(
    String label,
    IconData icon,
    bool isActive,
    VoidCallback onPressed,
    bool isDark,
  ) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? RodMaeColors.gold : Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? RodMaeColors.navy : Colors.white,
              size: 11,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isActive ? RodMaeColors.navy : Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
