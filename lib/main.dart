// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';

import 'firebase_options.dart';
import 'core/theme.dart';
import 'core/constants.dart';
import 'services/firebase_service.dart';
import 'services/auth_service.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'services/presence_controller.dart';
import 'services/connectivity_service.dart';
import 'widgets/network_banner.dart';
import 'models/meal_plan.dart';
import 'models/couple_location.dart';
import 'package:geolocator/geolocator.dart';
import 'widgets/common_widgets.dart';
import 'widgets/love_overlay.dart';
import 'widgets/cinematic_envelope.dart';

// Navigation & Screens
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/home_dashboard.dart';
import 'screens/private_chat.dart';
import 'screens/management_hub.dart';
import 'screens/vault_memories.dart';
import 'screens/account_settings.dart';
import 'screens/map_screen.dart';
import 'screens/loading_screen.dart';
import 'core/animations.dart';
import 'package:latlong2/latlong.dart' hide Path;


Future<void> main() async {
  // ── 1. Binding must be initialized before anything else ────────────────────
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();

  // ── 2. Preserve the native splash until we explicitly remove it ────────────
  //    The OS will keep showing the splash screen drawn by flutter_native_splash
  //    while Flutter engine warms up and our services initialize.
  FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
    ),
  );

  // ── 3. Kick off async service initialization (Firebase, Supabase, etc.) ────
  //    FlutterNativeSplash.remove() is called inside initialize() once done.
  final startupFuture = AppBootstrapper().initialize();
  runApp(RodMaeApp(startupFuture: startupFuture));
}

class RodMaeApp extends StatelessWidget {
  final Future<AppStartupStatus> startupFuture;

  const RodMaeApp({
    required this.startupFuture,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: RodMaeTheme.themeNotifier,
      builder: (context, currentMode, _) {
        return MaterialApp(
          title: 'RodMae App',
          debugShowCheckedModeBanner: false,
          theme: RodMaeTheme.lightTheme,
          darkTheme: RodMaeTheme.darkTheme,
          themeMode: currentMode,
          // ── Global network banner layer wraps every route ──────────────────
          builder: (context, child) => NetworkStatusBannerHost(
            child: child ?? const SizedBox.shrink(),
          ),
          initialRoute: '/',
          onGenerateRoute: (settings) {
            Widget page;
            switch (settings.name) {
              case '/':
                page = SplashScreen(startupFuture: startupFuture);
              case '/login':
                page = const LoginScreen();
              case '/loading':
                page = const ElegantLoadingScreen();
              case '/home':
                final args = (settings.arguments as AppStartupStatus?) ??
                    AppStartupStatus(
                      firebaseReady: AppRuntime.firebaseReady,
                      supabaseReady: AppRuntime.supabaseReady,
                      issue: AppRuntime.startupIssue,
                    );
                page = MainNavigationShell(startup: args);
              case '/map':
                final mapArgs = settings.arguments as Map<String, dynamic>?;
                page = MapScreen(autoHeadingHome: mapArgs?['autoHeadingHome'] == true);
              case '/settings':
                page = const AccountSettingsScreen();
              default:
                page = const LoginScreen();
            }
            return PageRouteBuilder(
              settings: settings,
              pageBuilder: (context, animation, secondaryAnimation) => page,
              transitionDuration: RodMaeAnimations.normal,
              reverseTransitionDuration: RodMaeAnimations.fast,
              transitionsBuilder: RodMaeAnimations.buildSlide3DTransition,
            );
          },
        );
      },
    );
  }
}

class MainNavigationShell extends StatefulWidget {
  final AppStartupStatus startup;

  const MainNavigationShell({
    required this.startup,
    super.key,
  });

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  int _index = 0;
  LoveTrigger? _activeGlobalTrigger;
  late final AnimationController _lottieController;
  
  StreamSubscription? _signalsSub;
  StreamSubscription? _chatSub;
  StreamSubscription? _notesSub;
  StreamSubscription? _locationsSub;

  final Set<String> _processedSignalIds = {};
  late final DateTime _appStartTime;

  // Stream state indicators to prevent startup spam
  bool _chatStreamInitialized = false;
  bool _notesStreamInitialized = false;
  final Set<String> _knownMessageIds = {};
  final Set<String> _knownNoteIds = {};
  String? _lastSpouseStatus;
  StreamSubscription<Position>? _backgroundPositionSub;

  // ── Realtime broadcast channel for sub-100ms love-signal delivery ─────────
  RealtimeChannel? _signalBroadcastChannel;
  bool _envelopeVisible = false;

  static const _loveTriggersMap = <String, LoveTrigger>{
    'Miss You': LoveTrigger(
      title: 'Miss You',
      subtitle: 'Bioluminescent Orbs',
      icon: Icons.blur_circular_rounded,
      color: RodMaeColors.violet,
      animationAsset: 'assets/animations/hearts.json',
      overlayTitle: 'Spouse is thinking of you',
    ),
    'I Love You': LoveTrigger(
      title: 'I Love You',
      subtitle: 'Ruby Glass Hearts',
      icon: Icons.favorite_rounded,
      color: RodMaeColors.rose,
      animationAsset: 'assets/animations/hearts.json',
      overlayTitle: 'Spouse says I Love You',
    ),
    'Heading Home': LoveTrigger(
      title: 'Heading Home',
      subtitle: 'Partner Status',
      icon: Icons.navigation_rounded,
      color: RodMaeColors.mint,
      animationAsset: 'assets/animations/home.json',
      overlayTitle: 'Spouse is heading home! 🏠',
    ),
    'Flying Kiss': LoveTrigger(
      title: 'Flying Kiss',
      subtitle: 'Neon Sonic Rings',
      icon: Icons.radio_button_checked_rounded,
      color: RodMaeColors.rose,
      animationAsset: 'assets/animations/kiss.json',
      overlayTitle: 'Spouse blew a flying kiss',
    ),
    'Warm Embrace': LoveTrigger(
      title: 'Warm Embrace',
      subtitle: 'Golden Stardust Aurora',
      icon: Icons.auto_awesome_rounded,
      color: RodMaeColors.gold,
      animationAsset: 'assets/animations/note.json',
      overlayTitle: 'Spouse sent a warm embrace',
    ),
    'Surprise Note': LoveTrigger(
      title: 'Surprise Note',
      subtitle: 'Push Note',
      icon: Icons.sticky_note_2_rounded,
      color: RodMaeColors.electricBlue,
      animationAsset: 'assets/animations/note.json',
      overlayTitle: 'Spouse sent a sweet note! 📝',
    ),
  };

  @override
  void initState() {
    super.initState();
    _appStartTime = DateTime.now().toUtc();
    _lottieController = AnimationController(vsync: this);
    _lottieController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _activeGlobalTrigger = null);
        _lottieController.reset();
      }
    });

    AppNotificationNavigation.mainTabNotifier.value = _index;
    AppNotificationNavigation.mainTabNotifier.addListener(_onMainTabNotifierChanged);

    // Dual-track: also fire overlay when FCM foreground message arrives.
    NotificationService.loveSignalNotifier.addListener(_onFcmLoveSignal);

    // Dual-track for surprise notes: FCM path
    NotificationService.surpriseNoteNotifier.addListener(_onFcmSurpriseNote);

    _listenToSpouseSignals();
    _listenToChat();
    _listenToNotes();
    _listenToLocations();
    _startBackgroundLocationTracking();
    _subscribeSignalBroadcast();
    WidgetsBinding.instance.addObserver(this);

    // Attach global presence tracking for the active partner
    PresenceController.instance.attach(PartnerIdentity.active.value.label);
    PartnerIdentity.active.addListener(_updatePresenceAttachment);
  }

  void _onMainTabNotifierChanged() {
    if (mounted) {
      setState(() {
        _index = AppNotificationNavigation.mainTabNotifier.value;
      });
    }
  }

  void _updatePresenceAttachment() {
    PresenceController.instance.attach(PartnerIdentity.active.value.label);
  }

  /// Called when an FCM foreground message arrives with type='signal'.
  void _onFcmLoveSignal() {
    final payload = NotificationService.loveSignalNotifier.value;
    if (payload == null || !mounted) return;

    final currentPartner = PartnerIdentity.active.value.label.toLowerCase();
    if (payload.senderName.toLowerCase() == currentPartner) return;

    final trigger = _loveTriggersMap[payload.triggerType];
    if (trigger == null) return;

    HapticFeedback.heavyImpact();
    setState(() => _activeGlobalTrigger = trigger);
    _lottieController
      ..reset()
      ..forward();
  }

  /// Called when an FCM foreground message arrives with type='note'.
  void _onFcmSurpriseNote() {
    final payload = NotificationService.surpriseNoteNotifier.value;
    if (payload == null || !mounted) return;

    final currentPartner = PartnerIdentity.active.value.label.toLowerCase();
    if (payload.senderName.toLowerCase() == currentPartner) return;

    // Show the envelope overlay only if it's not already visible
    if (!_envelopeVisible) {
      _envelopeVisible = true;
      showSurpriseNoteReceiveAnimation(
        context,
        content: payload.content,
        senderName: payload.senderName,
      ).then((_) {
        _envelopeVisible = false;
      });
    }
  }

  // ── Realtime Broadcast channel for love signals (sub-100ms) ─────────────

  void _subscribeSignalBroadcast() {
    if (!AppRuntime.supabaseReady) return;
    try {
      _signalBroadcastChannel =
          Supabase.instance.client.channel('signals:${AppConfig.coupleId}');
      _signalBroadcastChannel!
          .onBroadcast(
            event: 'love_signal',
            callback: (payload) {
              if (!mounted) return;
              final sender = payload['sender']?.toString() ?? '';
              final me = PartnerIdentity.active.value.label;
              if (sender.toLowerCase() == me.toLowerCase()) return;

              final triggerType = payload['trigger_type']?.toString() ?? '';
              final trigger = _loveTriggersMap[triggerType];
              if (trigger == null) return;

              // Deduplicate: use the broadcast ID or timestamp
              final broadcastId =
                  payload['id']?.toString() ?? payload['ts']?.toString() ?? '';
              if (broadcastId.isNotEmpty &&
                  _processedSignalIds.contains('bc_$broadcastId')) return;
              if (broadcastId.isNotEmpty) {
                _processedSignalIds.add('bc_$broadcastId');
              }

              HapticFeedback.heavyImpact();
              setState(() => _activeGlobalTrigger = trigger);
              _lottieController
                ..reset()
                ..forward();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void _listenToSpouseSignals() {
    _signalsSub = SupabaseWeddingRepository.instance.watchLoveTriggers().listen((events) {
      if (!mounted || events.isEmpty) return;

      final currentPartner = PartnerIdentity.active.value.label.toLowerCase();
      // Use UTC for both sides to avoid any local-vs-UTC comparison bugs.
      // Allow signals from up to 90 seconds before this session started (grace window).
      final cutoff = _appStartTime.subtract(const Duration(seconds: 90));
      final sortedEvents = [...events]
        ..sort((a, b) => b.createdAt.toUtc().compareTo(a.createdAt.toUtc()));

      for (final latest in sortedEvents) {
        final isSpouse = latest.sender.toLowerCase() != currentPartner;
        // createdAt from Supabase is UTC — compare to UTC cutoff.
        final isRecent = latest.createdAt.toUtc().isAfter(cutoff);
        final isFresh = !_processedSignalIds.contains(latest.id);
        if (!isSpouse || !isRecent || !isFresh) {
          continue;
        }

        _processedSignalIds.add(latest.id);
        final trigger = _loveTriggersMap[latest.triggerType];
        if (trigger != null) {
          HapticFeedback.heavyImpact();
          setState(() => _activeGlobalTrigger = trigger);
          _lottieController
            ..reset()
            ..forward();

          AppNotificationNavigation.show(
            title: '${latest.sender} sent a love signal! 💕',
            message: '${latest.triggerType}: ${trigger.subtitle}',
            icon: trigger.icon,
            color: trigger.color,
            onTap: () {
              AppNotificationNavigation.mainTabNotifier.value = 1;
              AppNotificationNavigation.privateChatTabNotifier.value = 2;
            },
          );
        }
        break;
      }
    });
  }

  void _listenToChat() {
    _chatSub = SupabaseWeddingRepository.instance.watchChat().listen((messages) {
      if (!mounted) return;
      final currentPartner = PartnerIdentity.active.value.label.toLowerCase();

      if (!_chatStreamInitialized) {
        _chatStreamInitialized = true;
        for (final msg in messages) {
          _knownMessageIds.add(msg.id);
        }
        return;
      }

      for (final msg in messages) {
        if (!_knownMessageIds.contains(msg.id)) {
          _knownMessageIds.add(msg.id);
          final isSpouse = msg.sender.toLowerCase() != currentPartner;

          if (isSpouse) {
            final onChatTab = AppNotificationNavigation.mainTabNotifier.value == 1 &&
                              AppNotificationNavigation.privateChatTabNotifier.value == 0;
            if (!onChatTab) {
              AppNotificationNavigation.show(
                title: 'New message from ${msg.sender} 💬',
                message: msg.message,
                icon: Icons.chat_bubble_rounded,
                color: RodMaeColors.electricBlue,
                onTap: () {
                  AppNotificationNavigation.mainTabNotifier.value = 1;
                  AppNotificationNavigation.privateChatTabNotifier.value = 0; // Chat tab
                },
              );
            }
          }
        }
      }
    });
  }

  void _listenToNotes() {
    _notesSub = SupabaseWeddingRepository.instance.watchNotes().listen((notes) {
      if (!mounted) return;
      final currentPartner = PartnerIdentity.active.value.label.toLowerCase();

      if (!_notesStreamInitialized) {
        _notesStreamInitialized = true;
        for (final note in notes) {
          _knownNoteIds.add(note.id);
        }
        return;
      }

      for (final note in notes) {
        if (!_knownNoteIds.contains(note.id)) {
          _knownNoteIds.add(note.id);
          final isSpouse = note.sender.toLowerCase() != currentPartner;

          if (isSpouse) {
            // ── PRIMARY: show cinematic envelope overlay ─────────────────────
            if (!_envelopeVisible) {
              _envelopeVisible = true;
              showSurpriseNoteReceiveAnimation(
                context,
                content: note.content,
                senderName: note.sender,
              ).then((_) {
                _envelopeVisible = false;
              });
            }

            // ── SECONDARY: also show a banner for quick re-access ────────────
            final onNotesTab =
                AppNotificationNavigation.mainTabNotifier.value == 1 &&
                AppNotificationNavigation.privateChatTabNotifier.value == 1;
            if (!onNotesTab) {
              AppNotificationNavigation.show(
                title: 'Sweet note from ${note.sender} 🌸',
                message: note.content,
                icon: Icons.sticky_note_2_rounded,
                color: RodMaeColors.gold,
                onTap: () {
                  AppNotificationNavigation.mainTabNotifier.value = 1;
                  AppNotificationNavigation.privateChatTabNotifier.value = 1;
                },
              );
            }
          }
        }
      }
    });
  }

  void _listenToLocations() {
    _locationsSub = SupabaseWeddingRepository.instance.watchLocations().listen((locations) {
      if (!mounted) return;
      final currentPartner = PartnerIdentity.active.value.label.toLowerCase();
      LatLng? livePos;
      LatLng? homePos;
      LatLng? workPos;

      for (final loc in locations) {
        if (loc.locationType == 'live' && loc.partner.toLowerCase() != currentPartner) {
          livePos = loc.position;
        } else if (loc.locationType == 'home') {
          homePos = loc.position;
        } else if (loc.locationType == 'work' && loc.partner.toLowerCase() != currentPartner) {
          workPos = loc.position;
        }
      }

      if (livePos == null) return;

      double getDist(LatLng p1, LatLng p2) => const Distance().as(LengthUnit.Meter, p1, p2);

      String currentStatus = 'on the move';
      if (homePos != null && getDist(livePos, homePos) < 250) {
        currentStatus = 'at Home';
      } else if (workPos != null && getDist(livePos, workPos) < 250) {
        currentStatus = 'at Work';
      }

      if (_lastSpouseStatus == null) {
        _lastSpouseStatus = currentStatus;
        return;
      }

      if (_lastSpouseStatus != currentStatus) {
        _lastSpouseStatus = currentStatus;
        final spouseName = PartnerIdentity.active.value == PartnerProfile.rodel ? 'Eurine' : 'Rodel';
        
        AppNotificationNavigation.show(
          title: 'Spouse Location Update',
          message: '$spouseName is now $currentStatus',
          icon: Icons.location_on_rounded,
          color: RodMaeColors.mint,
          onTap: () {
            AppNotificationNavigation.mainTabNotifier.value = 0; // Go to Home tab
            Navigator.of(context).pushNamed('/map');
          },
        );
      }
    });
  }

  Future<void> _startBackgroundLocationTracking() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      _updateLiveLocation(pos);

      _backgroundPositionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((p) {
        _updateLiveLocation(p);
      });
    } catch (_) {}
  }

  void _updateLiveLocation(Position pos) {
    if (!mounted) return;
    final me = PartnerIdentity.active.value.label;
    final loc = CoupleLocation(
      id: '',
      coupleId: AppConfig.coupleId,
      partner: me,
      position: LatLng(pos.latitude, pos.longitude),
      locationType: 'live',
      updatedAt: DateTime.now(),
    );
    SupabaseWeddingRepository.instance.upsertLocation(loc).catchError((_) {});
  }

  @override
  void dispose() {
    AppNotificationNavigation.mainTabNotifier.removeListener(_onMainTabNotifierChanged);
    NotificationService.loveSignalNotifier.removeListener(_onFcmLoveSignal);
    NotificationService.surpriseNoteNotifier.removeListener(_onFcmSurpriseNote);
    PartnerIdentity.active.removeListener(_updatePresenceAttachment);
    WidgetsBinding.instance.removeObserver(this);
    PresenceController.instance.detach();
    _signalsSub?.cancel();
    _chatSub?.cancel();
    _notesSub?.cancel();
    _locationsSub?.cancel();
    _backgroundPositionSub?.cancel();
    _lottieController.dispose();
    try {
      _signalBroadcastChannel?.unsubscribe();
    } catch (_) {}
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('MainNavigationShell: App resumed. Reconnecting Supabase Realtime...');
      try {
        Supabase.instance.client.realtime.connect();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeDashboardScreen(startup: widget.startup),
      const PrivateChatScreen(),
      const ManagementHubScreen(),
      const VaultMemoriesScreen(),
    ];
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          IndexedStack(index: _index, children: pages),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            child: _activeGlobalTrigger == null
                ? const SizedBox.shrink()
                : Custom3DLoveOverlay(
                    key: ValueKey(_activeGlobalTrigger!.title),
                    trigger: _activeGlobalTrigger!,
                    controller: _lottieController,
                  ),
          ),
          // Banner pinned explicitly to the top so SlideTransition works correctly
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Sliding3DNotificationBanner(),
          ),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: AppNotificationNavigation.mainTabNotifier,
        builder: (context, activeIndex, _) {
          return RodMaeBottomNavBar(
            selectedIndex: activeIndex,
            onSelected: (value) {
              AppNotificationNavigation.mainTabNotifier.value = value;
            },
          );
        },
      ),
    );
  }
}

final class AppBootstrapper {
  Future<AppStartupStatus> initialize() async {
    var firebaseReady = false;
    var supabaseReady = false;
    final issues = <String>[];

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }
      firebaseReady = true;
      // ── Initialise push notifications after Firebase is ready ──────────────
      await NotificationService.instance.initialize();
    } catch (error) {
      issues.add('Firebase: $error');
    }

    try {
      await Supabase.initialize(
        url: AppConfig.supabaseUrl,
        anonKey: AppConfig.supabaseAnonKey,
      );
      supabaseReady = true;
    } catch (error) {
      issues.add('Supabase: $error');
    }

    // Load cached session for bypass credentials
    await AuthService.loadCachedSession();

    // ── Start background connectivity supervisor ────────────────────────────
    await ConnectivityService.instance.initialize();

    AppRuntime.firebaseReady = firebaseReady;
    AppRuntime.supabaseReady = supabaseReady;
    AppRuntime.startupIssue = issues.isEmpty ? null : issues.join('\n');

    // ── 4. All services are ready — dismiss the native splash screen ──────────
    //    Flutter will now paint its first frame (your SplashScreen widget)
    //    and the native splash will cross-fade out seamlessly.
    FlutterNativeSplash.remove();

    return AppStartupStatus(
      firebaseReady: firebaseReady,
      supabaseReady: supabaseReady,
      issue: AppRuntime.startupIssue,
    );
  }
}
