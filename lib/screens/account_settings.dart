import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/theme.dart';
import '../core/animations.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/supabase_service.dart';
import '../models/user_profile.dart';
import '../models/couple_settings.dart';
import '../widgets/glass_card.dart';
import '../widgets/animated_3d_card.dart';
import '../widgets/particle_burst.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen>
    with TickerProviderStateMixin {

  // State
  CoupleSettings _settings = CoupleSettings.defaults();
  UserProfile? _profile;
  bool _loadingProfile = true;
  bool _uploadingAvatar = false;
  bool _savingProfile = false;
  bool _savingSettings = false;
  double _uploadProgress = 0;

  // Controllers
  final _displayNameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  final _imagePicker = ImagePicker();
  final _particleBurstKey = GlobalKey<ParticleBurstState>();

  // Animations
  late final AnimationController _fadeCtrl;
  late final AnimationController _avatarRingCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _avatarRingAnim;

  // Bubble color options
  static const _bubbleColors = <String, Color>{
    '#3B82F6': RodMaeColors.electricBlue,
    '#F59E0B': RodMaeColors.gold,
    '#FF5E8D': RodMaeColors.rose,
    '#34D399': RodMaeColors.mint,
    '#7C3AED': RodMaeColors.violet,
    '#FF6B6B': RodMaeColors.coral,
  };

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: RodMaeAnimations.entrance);
    _avatarRingCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _avatarRingAnim = CurvedAnimation(parent: _avatarRingCtrl, curve: Curves.linear);

    _fadeCtrl.forward();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loadingProfile = true);
    try {
      final partner = PartnerIdentity.active.value.label;
      final settingsFuture = SupabaseWeddingRepository.instance.fetchCoupleSettings();
      final profileFuture = SupabaseWeddingRepository.instance.fetchUserProfile(partner);

      final results = await Future.wait([settingsFuture, profileFuture]);
      final settings = results[0] as CoupleSettings;
      final profile = results[1] as UserProfile?;

      if (mounted) {
        setState(() {
          _settings = settings;
          _profile = profile;
          _displayNameCtrl.text = profile?.displayName ?? partner;
          _bioCtrl.text = profile?.bio ?? '';
          _nicknameCtrl.text = settings.coupleNickname ?? '';
          _loadingProfile = false;
        });
      }
    } catch (_) {
      // Fallback to local prefs
      try {
        final prefs = await SharedPreferences.getInstance();
        final partner = PartnerIdentity.active.value.label;
        if (mounted) {
          setState(() {
            _nicknameCtrl.text = prefs.getString('couple_nickname') ?? '';
            _displayNameCtrl.text = partner;
            _loadingProfile = false;
          });
        }
      } catch (__) {
        if (mounted) setState(() => _loadingProfile = false);
      }
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final source = await _showImageSourceSheet();
    if (source == null) return;

    final file = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 800,
      maxHeight: 800,
    );
    if (file == null) return;

    setState(() {
      _uploadingAvatar = true;
      _uploadProgress = 0;
    });

    try {
      final bytes = await file.readAsBytes();
      // Simulate progress
      for (int i = 1; i <= 5; i++) {
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) setState(() => _uploadProgress = i / 6);
      }

      final partner = PartnerIdentity.active.value.label;
      final url = await SupabaseWeddingRepository.instance.uploadAvatar(bytes, partner);

      if (url != null) {
        await SupabaseWeddingRepository.instance.upsertUserProfile(
          partner: partner,
          avatarUrl: url,
          displayName: _displayNameCtrl.text.trim().isEmpty ? null : _displayNameCtrl.text.trim(),
        );
        if (mounted) {
          setState(() {
            _profile = _profile?.copyWith(avatarUrl: url) ??
                UserProfile(
                  id: '',
                  coupleId: 'couple-rodel-marymae-2026',
                  partner: partner,
                  avatarUrl: url,
                  updatedAt: DateTime.now(),
                );
          });
          HapticFeedback.mediumImpact();
          _particleBurstKey.currentState?.burst();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile photo updated! 🎉')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _uploadingAvatar = false;
          _uploadProgress = 0;
        });
      }
    }
  }

  Future<ImageSource?> _showImageSourceSheet() async {
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDark ? RodMaeColors.navy : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : RodMaeColors.royalBlue.withValues(alpha: 0.12),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Choose Photo',
                style: GoogleFonts.playfairDisplay(
                  color: isDark ? Colors.white : RodMaeColors.lightText,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.camera_alt_rounded,
                      label: 'Camera',
                      color: RodMaeColors.electricBlue,
                      isDark: isDark,
                      onTap: () => Navigator.pop(ctx, ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.photo_library_rounded,
                      label: 'Gallery',
                      color: RodMaeColors.gold,
                      isDark: isDark,
                      onTap: () => Navigator.pop(ctx, ImageSource.gallery),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _saveProfile() async {
    final name = _displayNameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingProfile = true);
    try {
      final partner = PartnerIdentity.active.value.label;
      await SupabaseWeddingRepository.instance.upsertUserProfile(
        partner: partner,
        displayName: name,
        bio: bio.isEmpty ? null : bio,
      );
      HapticFeedback.lightImpact();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile saved! 💕')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved locally. Will sync when connected.')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingProfile = false);
    }
  }

  Future<void> _saveSetting<T>({
    required CoupleSettings Function(CoupleSettings) update,
  }) async {
    final updated = update(_settings);
    setState(() => _settings = updated);
    try {
      final prefs = await SharedPreferences.getInstance();
      // Save local first
      await prefs.setBool('notif_love_signals', updated.notifLoveSignals);
      await prefs.setBool('notif_sweet_notes', updated.notifSweetNotes);
      await prefs.setBool('notif_chat_messages', updated.notifChatMessages);
      await prefs.setBool('notif_milestones', updated.notifMilestones);
      await prefs.setBool('show_online_status', updated.showOnlineStatus);
      await prefs.setBool('show_last_seen', updated.showLastSeen);
      // Sync to Supabase
      await SupabaseWeddingRepository.instance.upsertCoupleSettings(updated);
    } catch (_) {}
  }

  Future<void> _saveNickname() async {
    final name = _nicknameCtrl.text.trim();
    if (name.isEmpty) return;
    await _saveSetting(update: (s) => s.copyWith(coupleNickname: name));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('couple_nickname', name);
    HapticFeedback.lightImpact();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Couple name saved! 💍')),
      );
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? RodMaeColors.navy2 : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          title: Text(
            'Sign Out',
            style: GoogleFonts.playfairDisplay(
              color: isDark ? Colors.white : RodMaeColors.lightText,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'Are you sure you want to sign out?',
            style: GoogleFonts.inter(
              color: isDark ? RodMaeColors.textSoft : RodMaeColors.lightTextSoft,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(
                'Stay',
                style: GoogleFonts.inter(color: RodMaeColors.sky, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                'Sign Out',
                style: GoogleFonts.inter(color: RodMaeColors.coral, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await AuthService.instance.signOut();
      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _avatarRingCtrl.dispose();
    _displayNameCtrl.dispose();
    _bioCtrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(gradient: RodMaeColors.getAppBackground(isDark)),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Column(
              children: [
                _buildTopBar(isDark),
                Expanded(
                  child: ListView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 120),
                    children: [
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(0),
                        child: _buildProfileCard(isDark),
                      ),
                      const SizedBox(height: 20),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(1),
                        child: _buildSectionLabel('APPEARANCE', Icons.palette_outlined, isDark),
                      ),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(1),
                        child: _buildAppearanceCard(isDark),
                      ),
                      const SizedBox(height: 20),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(2),
                        child: _buildSectionLabel('LOVE SIGNALS & NOTIFICATIONS', Icons.notifications_outlined, isDark),
                      ),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(2),
                        child: _buildNotificationsCard(isDark),
                      ),
                      const SizedBox(height: 20),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(3),
                        child: _buildSectionLabel('CHAT BUBBLE COLOR', Icons.chat_bubble_outline_rounded, isDark),
                      ),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(3),
                        child: _buildBubbleColorCard(isDark),
                      ),
                      const SizedBox(height: 20),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(4),
                        child: _buildSectionLabel('PRIVACY', Icons.shield_outlined, isDark),
                      ),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(4),
                        child: _buildPrivacyCard(isDark),
                      ),
                      const SizedBox(height: 20),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(5),
                        child: _buildSectionLabel('OUR LOVE STORY', Icons.favorite_outline_rounded, isDark),
                      ),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(5),
                        child: _buildCoupleCard(isDark),
                      ),
                      const SizedBox(height: 20),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(6),
                        child: _buildSectionLabel('ABOUT', Icons.info_outline_rounded, isDark),
                      ),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(6),
                        child: _buildAboutCard(isDark),
                      ),
                      const SizedBox(height: 24),
                      StaggeredEntrance(
                        delay: RodMaeAnimations.staggerDelay(7),
                        child: _buildSignOutButton(isDark),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 18, 8),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white70 : RodMaeColors.lightText,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MY ACCOUNT',
                  style: GoogleFonts.inter(
                    color: isDark ? RodMaeColors.gold : RodMaeColors.amber,
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 2.2,
                  ),
                ),
                Text(
                  'Settings',
                  style: GoogleFonts.playfairDisplay(
                    color: isDark ? Colors.white : RodMaeColors.lightText,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppRuntime.supabaseReady
                  ? RodMaeColors.mint.withValues(alpha: 0.15)
                  : RodMaeColors.coral.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppRuntime.supabaseReady
                    ? RodMaeColors.mint.withValues(alpha: 0.3)
                    : RodMaeColors.coral.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppRuntime.supabaseReady ? RodMaeColors.mint : RodMaeColors.coral,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  AppRuntime.supabaseReady ? 'Connected' : 'Offline',
                  style: GoogleFonts.inter(
                    color: AppRuntime.supabaseReady ? RodMaeColors.mint : RodMaeColors.coral,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(bool isDark) {
    final profile = PartnerIdentity.active.value;
    final avatarUrl = _profile?.avatarUrl;

    return Animated3DCard(
      borderColor: RodMaeColors.gold.withValues(alpha: 0.3),
      gradient: isDark
          ? LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                RodMaeColors.royalBlue.withValues(alpha: 0.25),
                RodMaeColors.navy,
              ],
            )
          : null,
      child: Column(
        children: [
          Row(
            children: [
              // Avatar with upload ring
              ParticleBurst(
                key: _particleBurstKey,
                child: GestureDetector(
                  onTap: _pickAndUploadAvatar,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Spinning gold ring
                      AnimatedBuilder(
                        animation: _avatarRingAnim,
                        builder: (context, _) {
                          return Transform.rotate(
                            angle: _avatarRingAnim.value * 2 * 3.14159,
                            child: Container(
                              width: 82,
                              height: 82,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: SweepGradient(
                                  colors: [
                                    RodMaeColors.gold,
                                    RodMaeColors.lemon,
                                    RodMaeColors.gold.withValues(alpha: 0.2),
                                    RodMaeColors.gold,
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                      // Avatar circle
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: avatarUrl == null
                              ? RodMaeColors.royalGradient
                              : null,
                          color: avatarUrl != null ? Colors.transparent : null,
                          boxShadow: RodMaeColors.blueGlow(),
                        ),
                        child: ClipOval(
                          child: _uploadingAvatar
                              ? Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    CircularProgressIndicator(
                                      value: _uploadProgress,
                                      color: RodMaeColors.gold,
                                      backgroundColor: RodMaeColors.navy,
                                      strokeWidth: 3,
                                    ),
                                    Text(
                                      '${(_uploadProgress * 100).toInt()}%',
                                      style: GoogleFonts.inter(
                                        color: Colors.white,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                )
                              : avatarUrl != null
                                  ? Image.network(
                                      avatarUrl,
                                      fit: BoxFit.cover,
                                      loadingBuilder: (_, child, progress) =>
                                          progress == null
                                              ? child
                                              : const Center(
                                                  child: CircularProgressIndicator(
                                                    color: RodMaeColors.gold,
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                      errorBuilder: (_, __, ___) => _avatarInitials(profile.initials),
                                    )
                                  : _avatarInitials(profile.initials),
                        ),
                      ),
                      // Camera badge
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: RodMaeColors.gold,
                            boxShadow: RodMaeColors.goldGlow(intensity: 0.6),
                          ),
                          child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TAP PHOTO TO CHANGE',
                      style: GoogleFonts.inter(
                        color: RodMaeColors.gold,
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: RodMaeColors.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: RodMaeColors.gold.withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        '💍 RodMae Couple',
                        style: GoogleFonts.inter(
                          color: RodMaeColors.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Editable display name
          _buildField(
            controller: _displayNameCtrl,
            label: 'Your Name',
            hint: profile.label,
            icon: Icons.person_outline_rounded,
            iconColor: RodMaeColors.electricBlue,
            isDark: isDark,
          ),
          const SizedBox(height: 10),
          // Bio / tagline
          _buildField(
            controller: _bioCtrl,
            label: 'Your Tagline',
            hint: 'e.g. Always in your heart 💙',
            icon: Icons.format_quote_rounded,
            iconColor: RodMaeColors.gold,
            isDark: isDark,
            maxLines: 2,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: _savingProfile ? null : _saveProfile,
            child: AnimatedContainer(
              duration: RodMaeAnimations.fast,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                gradient: RodMaeColors.goldGradient,
                borderRadius: BorderRadius.circular(14),
                boxShadow: RodMaeColors.goldGlow(),
              ),
              child: _savingProfile
                  ? const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.save_rounded, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'SAVE PROFILE',
                          style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarInitials(String initials) {
    return Container(
      color: RodMaeColors.royalBlue,
      child: Center(
        child: Text(
          initials,
          style: GoogleFonts.playfairDisplay(
            color: Colors.white,
            fontSize: 28,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 5),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.inter(
              color: isDark ? RodMaeColors.sky : RodMaeColors.lightTextSoft,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
        ),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.inter(
            fontSize: 14,
            color: isDark ? Colors.white : RodMaeColors.lightText,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, color: iconColor, size: 18),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String title, IconData icon, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: RodMaeColors.gold),
          const SizedBox(width: 7),
          Text(
            title,
            style: GoogleFonts.inter(
              color: RodMaeColors.gold,
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppearanceCard(bool isDark) {
    final current = RodMaeTheme.themeNotifier.value;
    return GlassCard(
      borderColor: RodMaeColors.violet.withValues(alpha: 0.25),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        children: [
          _themeOption(
            label: 'Light Mode',
            subtitle: 'Bright blue & gold — daytime',
            icon: Icons.light_mode_rounded,
            iconColor: RodMaeColors.lemon,
            selected: current == ThemeMode.light,
            isDark: isDark,
            onTap: () {
              RodMaeTheme.themeNotifier.value = ThemeMode.light;
              setState(() {});
              HapticFeedback.selectionClick();
            },
          ),
          _divider(isDark),
          _themeOption(
            label: 'Dark Mode',
            subtitle: 'Deep navy & golden glow — night',
            icon: Icons.dark_mode_rounded,
            iconColor: RodMaeColors.sky,
            selected: current == ThemeMode.dark,
            isDark: isDark,
            onTap: () {
              RodMaeTheme.themeNotifier.value = ThemeMode.dark;
              setState(() {});
              HapticFeedback.selectionClick();
            },
          ),
          _divider(isDark),
          _themeOption(
            label: 'Follow System',
            subtitle: 'Matches your phone automatically',
            icon: Icons.brightness_auto_rounded,
            iconColor: RodMaeColors.mint,
            selected: current == ThemeMode.system,
            isDark: isDark,
            onTap: () {
              RodMaeTheme.themeNotifier.value = ThemeMode.system;
              setState(() {});
              HapticFeedback.selectionClick();
            },
          ),
        ],
      ),
    );
  }

  Widget _themeOption({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: RodMaeAnimations.fast,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? iconColor.withValues(alpha: isDark ? 0.12 : 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.inter(
                    color: isDark ? Colors.white : RodMaeColors.lightText,
                    fontSize: 14, fontWeight: FontWeight.w700,
                  )),
                  Text(subtitle, style: GoogleFonts.inter(
                    color: isDark ? Colors.white38 : RodMaeColors.lightTextMuted,
                    fontSize: 11,
                  )),
                ],
              ),
            ),
            AnimatedContainer(
              duration: RodMaeAnimations.fast,
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? iconColor : Colors.transparent,
                border: selected ? null : Border.all(
                  color: isDark ? Colors.white24 : Colors.black12, width: 1.5,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationsCard(bool isDark) {
    return GlassCard(
      borderColor: RodMaeColors.rose.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        children: [
          _toggleRow(
            label: 'Love Signals',
            subtitle: 'Hearts shower, flying kiss & more',
            icon: Icons.favorite_rounded,
            iconColor: RodMaeColors.rose,
            value: _settings.notifLoveSignals,
            isDark: isDark,
            onChanged: (v) => _saveSetting(update: (s) => s.copyWith(notifLoveSignals: v)),
          ),
          _divider(isDark),
          _toggleRow(
            label: 'Sweet Notes',
            subtitle: 'When your spouse writes you a note',
            icon: Icons.sticky_note_2_rounded,
            iconColor: RodMaeColors.gold,
            value: _settings.notifSweetNotes,
            isDark: isDark,
            onChanged: (v) => _saveSetting(update: (s) => s.copyWith(notifSweetNotes: v)),
          ),
          _divider(isDark),
          _toggleRow(
            label: 'Chat Messages',
            subtitle: 'New messages in your private chat',
            icon: Icons.chat_bubble_outline_rounded,
            iconColor: RodMaeColors.electricBlue,
            value: _settings.notifChatMessages,
            isDark: isDark,
            onChanged: (v) => _saveSetting(update: (s) => s.copyWith(notifChatMessages: v)),
          ),
          _divider(isDark),
          _toggleRow(
            label: 'Milestones & Anniversaries',
            subtitle: 'Countdowns, goals & special days',
            icon: Icons.celebration_outlined,
            iconColor: RodMaeColors.mint,
            value: _settings.notifMilestones,
            isDark: isDark,
            onChanged: (v) => _saveSetting(update: (s) => s.copyWith(notifMilestones: v)),
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleColorCard(bool isDark) {
    final currentHex = _settings.chatBubbleColor ?? '#3B82F6';
    return GlassCard(
      borderColor: RodMaeColors.electricBlue.withValues(alpha: 0.2),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pick your chat bubble color',
            style: GoogleFonts.inter(
              color: isDark ? Colors.white70 : RodMaeColors.lightText,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: _bubbleColors.entries.map((entry) {
              final selected = entry.key == currentHex;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _saveSetting(update: (s) => s.copyWith(chatBubbleColor: entry.key));
                },
                child: AnimatedContainer(
                  duration: RodMaeAnimations.fast,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: entry.value,
                    border: Border.all(
                      color: selected ? RodMaeColors.lemon : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: selected ? RodMaeColors.goldGlow() : null,
                  ),
                  child: selected
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 20)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivacyCard(bool isDark) {
    return GlassCard(
      borderColor: RodMaeColors.mint.withValues(alpha: 0.2),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        children: [
          _toggleRow(
            label: 'Show Online Status',
            subtitle: 'Your spouse can see when you\'re active',
            icon: Icons.radio_button_checked_rounded,
            iconColor: RodMaeColors.mint,
            value: _settings.showOnlineStatus,
            isDark: isDark,
            onChanged: (v) => _saveSetting(update: (s) => s.copyWith(showOnlineStatus: v)),
          ),
          _divider(isDark),
          _toggleRow(
            label: 'Show Last Seen',
            subtitle: 'Display when you were last active',
            icon: Icons.access_time_rounded,
            iconColor: RodMaeColors.sky,
            value: _settings.showLastSeen,
            isDark: isDark,
            onChanged: (v) => _saveSetting(update: (s) => s.copyWith(showLastSeen: v)),
          ),
          _divider(isDark),
          _tapRow(
            label: 'Change Password',
            subtitle: 'Update your account password',
            icon: Icons.lock_outline_rounded,
            iconColor: RodMaeColors.violet,
            isDark: isDark,
            onTap: () => ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Password reset will be sent to your email.')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCoupleCard(bool isDark) {
    return GlassCard(
      borderColor: RodMaeColors.gold.withValues(alpha: 0.25),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: RodMaeColors.rose.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.favorite_rounded, color: RodMaeColors.rose, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Your Couple Name', style: GoogleFonts.inter(
                    color: isDark ? Colors.white : RodMaeColors.lightText,
                    fontSize: 14, fontWeight: FontWeight.w700,
                  )),
                  Text('Give your bond a special name', style: GoogleFonts.inter(
                    color: isDark ? Colors.white38 : RodMaeColors.lightTextMuted,
                    fontSize: 11,
                  )),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nicknameCtrl,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: isDark ? Colors.white : RodMaeColors.lightText,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    hintText: 'e.g. RodMae Forever 💕',
                    prefixIcon: const Icon(Icons.edit_outlined, color: RodMaeColors.gold, size: 18),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _saveNickname,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    gradient: RodMaeColors.goldGradient,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: RodMaeColors.goldGlow(),
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAboutCard(bool isDark) {
    return GlassCard(
      borderColor: isDark
          ? Colors.white.withValues(alpha: 0.07)
          : RodMaeColors.royalBlue.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Column(
        children: [
          _tapRow(
            label: 'App Version',
            subtitle: 'RodMae App v1.0.0',
            icon: Icons.info_outline_rounded,
            iconColor: RodMaeColors.electricBlue,
            isDark: isDark,
            onTap: () {},
            trailing: Text(
              'v1.0.0',
              style: GoogleFonts.robotoMono(
                color: isDark ? Colors.white38 : RodMaeColors.lightTextMuted,
                fontSize: 11,
              ),
            ),
          ),
          _divider(isDark),
          _tapRow(
            label: 'Made with Love',
            subtitle: 'Just for the two of you 💑',
            icon: Icons.favorite_rounded,
            iconColor: RodMaeColors.rose,
            isDark: isDark,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSignOutButton(bool isDark) {
    return GestureDetector(
      onTap: _signOut,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RodMaeColors.coral.withValues(alpha: 0.5)),
          color: RodMaeColors.coral.withValues(alpha: isDark ? 0.1 : 0.06),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.logout_rounded, color: RodMaeColors.coral, size: 20),
            const SizedBox(width: 10),
            Text(
              'Sign Out',
              style: GoogleFonts.inter(
                color: RodMaeColors.coral,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    required bool isDark,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: GoogleFonts.inter(
                color: isDark ? Colors.white : RodMaeColors.lightText,
                fontSize: 14, fontWeight: FontWeight.w700,
              )),
              Text(subtitle, style: GoogleFonts.inter(
                color: isDark ? Colors.white38 : RodMaeColors.lightTextMuted,
                fontSize: 11,
              )),
            ]),
          ),
          Switch.adaptive(
            value: value,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              onChanged(v);
            },
            activeColor: iconColor,
            activeTrackColor: iconColor.withValues(alpha: 0.3),
            inactiveThumbColor: isDark ? Colors.white38 : Colors.black26,
            inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
          ),
        ],
      ),
    );
  }

  Widget _tapRow({
    required String label,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool isDark,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: GoogleFonts.inter(
                  color: isDark ? Colors.white : RodMaeColors.lightText,
                  fontSize: 14, fontWeight: FontWeight.w700,
                )),
                Text(subtitle, style: GoogleFonts.inter(
                  color: isDark ? Colors.white38 : RodMaeColors.lightTextMuted,
                  fontSize: 11,
                )),
              ]),
            ),
            trailing ?? Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: isDark ? Colors.white24 : Colors.black26,
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider(bool isDark) => Divider(
    height: 1, thickness: 0.5, indent: 14, endIndent: 14,
    color: isDark
        ? Colors.white.withValues(alpha: 0.06)
        : RodMaeColors.royalBlue.withValues(alpha: 0.08),
  );
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _SourceButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
