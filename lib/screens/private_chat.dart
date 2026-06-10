// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme.dart';
import '../widgets/advanced_loading_effect.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../models/chat_message.dart';
import '../models/surprise_note.dart';
import '../models/love_trigger_event.dart';
import '../models/meal_plan.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/glass_card.dart';
import '../widgets/primary_button.dart';
import '../widgets/common_widgets.dart';
import '../widgets/love_overlay.dart';
import '../widgets/cinematic_envelope.dart';

class PrivateChatScreen extends StatefulWidget {
  const PrivateChatScreen({super.key});

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _tab = 0;
  final _chatController = TextEditingController();
  final _noteController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatFocusNode = FocusNode();
  final _pendingMessages = <ChatMessage>[];
  bool _sendingChat = false;
  bool _sendingNote = false;
  bool _isRefreshingChat = false;
  bool _isRefreshingNotes = false;
  bool _isRefreshingSignals = false;

  // Custom animations for sender notes
  LoveTrigger? _activeTrigger;
  late final AnimationController _lottieController;

  late final Stream<List<ChatMessage>> _chatStream;
  late final Stream<List<ChatMessage>> _switcherChatStream;
  late final Stream<List<SurpriseNote>> _notesStream;
  late final Stream<List<LoveTriggerEvent>> _signalsStream;
  late final Stream<List<LoveTriggerEvent>> _switcherSignalsStream;

  // ── Profile pictures ───────────────────────────────────────────────────────
  /// Avatar URL for Rodel
  String? _rodelAvatarUrl;
  /// Avatar URL for Eurine
  String? _eurineAvatarUrl;

  // ── Image upload state ─────────────────────────────────────────────────────
  bool _uploadingImage = false;
  double _uploadProgress = 0;

  // ── Image picker ───────────────────────────────────────────────────────────
  final _picker = ImagePicker();

  // ── Typing indicator state ──────────────────────────────────────────────────
  Timer? _typingTimer;
  bool _isLocalTyping = false;
  RealtimeChannel? _typingChannel;
  bool _isPartnerTyping = false;
  bool _wasKeyboardOpen = false;
  bool _lastHasKeyboardState = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ProfileNotifier.updateNotifier.addListener(_loadAvatars);

    // Sync initial keyboard state after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final view = View.of(context);
        final currentHasKeyboard = (view.viewInsets.bottom / view.devicePixelRatio) > 0;
        if (currentHasKeyboard != _lastHasKeyboardState) {
          setState(() {
            _lastHasKeyboardState = currentHasKeyboard;
          });
        }
      }
    });

    _chatStream = SupabaseWeddingRepository.instance.watchChat();
    _switcherChatStream = SupabaseWeddingRepository.instance.watchChat();
    _notesStream = SupabaseWeddingRepository.instance.watchNotes();
    _signalsStream = SupabaseWeddingRepository.instance.watchLoveTriggers();
    _switcherSignalsStream = SupabaseWeddingRepository.instance.watchLoveTriggers();

    _lottieController = AnimationController(vsync: this);
    _lottieController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _activeTrigger = null);
        _lottieController.reset();
      }
    });

    AppNotificationNavigation.privateChatTabNotifier.value = _tab;
    AppNotificationNavigation.privateChatTabNotifier
        .addListener(_onPrivateChatTabChanged);
    AppNotificationNavigation.mainTabNotifier
        .addListener(_updateChatActiveStatus);
    _updateChatActiveStatus();

    // Load PFPs in the background — non-blocking
    _loadAvatars();

    // Mark messages/signals as seen when the screen opens
    if (AppNotificationNavigation.mainTabNotifier.value == 1) {
      if (_tab == 0) {
        SupabaseWeddingRepository.instance.markMessagesAsSeen();
      } else if (_tab == 2) {
        SupabaseWeddingRepository.instance.markLoveTriggersAsSeen();
      }
    }

    // Auto-scroll when keyboard opens
    _chatFocusNode.addListener(() {
      if (_chatFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 150), () {
          if (_scrollController.hasClients && mounted) {
            _scrollController.animateTo(
              0.0,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });

    // Subscribe to typing indicators
    _subscribeTypingBroadcast();
  }

  // ── Avatar loading ─────────────────────────────────────────────────────────

  Future<void> _loadAvatars() async {
    try {
      final rodelProfile = await SupabaseWeddingRepository.instance
          .fetchUserProfile(PartnerProfile.rodel.label);
      final eurineProfile = await SupabaseWeddingRepository.instance
          .fetchUserProfile(PartnerProfile.maryMae.label);
      if (mounted) {
        setState(() {
          _rodelAvatarUrl = rodelProfile?.avatarUrl;
          _eurineAvatarUrl = eurineProfile?.avatarUrl;
        });
      }
    } catch (_) {}
  }

  /// Returns the avatar URL for a given sender name.
  String? _avatarFor(String sender) {
    final lower = sender.toLowerCase();
    if (lower.contains('rodel')) return _rodelAvatarUrl;
    return _eurineAvatarUrl;
  }

  /// Returns the partner's avatar URL (the person who READS the message).
  String? get _partnerAvatarUrl {
    return PartnerIdentity.active.value == PartnerProfile.rodel
        ? _eurineAvatarUrl
        : _rodelAvatarUrl;
  }

  void _updateChatActiveStatus() {
    final mainTab = AppNotificationNavigation.mainTabNotifier.value;
    final subTab = AppNotificationNavigation.privateChatTabNotifier.value;

    final isChatOpen = mainTab == 1 && subTab == 0;
    NotificationService.isChatActive = isChatOpen;

    if (mainTab == 1 && mounted) {
      if (subTab == 0) {
        SupabaseWeddingRepository.instance.markMessagesAsSeen();
      } else if (subTab == 2) {
        SupabaseWeddingRepository.instance.markLoveTriggersAsSeen();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _updateChatActiveStatus();
    } else {
      NotificationService.isChatActive = false;
    }
  }

  void _onPrivateChatTabChanged() {
    if (mounted) {
      setState(() {
        _tab = AppNotificationNavigation.privateChatTabNotifier.value;
      });
      _updateChatActiveStatus();
    }
  }

  void _subscribeTypingBroadcast() {
    if (!AppRuntime.supabaseReady) return;
    try {
      final me = PartnerIdentity.active.value.label;
      _typingChannel = Supabase.instance.client.channel('typing:${AppConfig.coupleId}');
      
      _typingChannel!
          .onBroadcast(
            event: 'typing',
            callback: (payload) {
              if (!mounted) return;
              final sender = payload['sender']?.toString() ?? '';
              if (sender.toLowerCase() == me.toLowerCase()) return;
              
              final isTyping = payload['isTyping'] == true;
              setState(() {
                _isPartnerTyping = isTyping;
              });
            },
          )
          .subscribe();
    } catch (_) {}
  }

  void _sendTypingStatus(bool isTyping) {
    if (_typingChannel == null) return;
    try {
      _typingChannel!.sendBroadcastMessage(
        event: 'typing',
        payload: {
          'sender': PartnerIdentity.active.value.label,
          'isTyping': isTyping,
        },
      );
    } catch (_) {}
  }

  void _onChatInputChanged(String text) {
    if (!AppRuntime.supabaseReady || _typingChannel == null) return;

    if (text.isEmpty) {
      _typingTimer?.cancel();
      if (_isLocalTyping) {
        setState(() => _isLocalTyping = false);
        _sendTypingStatus(false);
      }
      return;
    }

    if (!_isLocalTyping) {
      setState(() => _isLocalTyping = true);
      _sendTypingStatus(true);
    }

    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _isLocalTyping) {
        setState(() => _isLocalTyping = false);
        _sendTypingStatus(false);
      }
    });
  }

  @override
  void didChangeMetrics() {
    if (!mounted) return;
    final view = View.of(context);
    final currentHasKeyboard = (view.viewInsets.bottom / view.devicePixelRatio) > 0;
    
    if (currentHasKeyboard != _lastHasKeyboardState) {
      setState(() {
        _lastHasKeyboardState = currentHasKeyboard;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ProfileNotifier.updateNotifier.removeListener(_loadAvatars);
    AppNotificationNavigation.privateChatTabNotifier
        .removeListener(_onPrivateChatTabChanged);
    AppNotificationNavigation.mainTabNotifier
        .removeListener(_updateChatActiveStatus);
    NotificationService.isChatActive = false;
    _chatController.dispose();
    _noteController.dispose();
    _scrollController.dispose();
    _chatFocusNode.dispose();
    _lottieController.dispose();
    _typingTimer?.cancel();
    try {
      _typingChannel?.unsubscribe();
    } catch (_) {}
    super.dispose();
  }

  // ── Pull-to-Refresh handlers ───────────────────────────────────────────────

  Future<void> _refreshChat() async {
    if (_isRefreshingChat) return;
    setState(() => _isRefreshingChat = true);
    try {
      await SupabaseWeddingRepository.instance.fetchChat();
    } catch (_) {}
    if (mounted) {
      setState(() => _isRefreshingChat = false);
    }
  }

  Future<void> _refreshNotes() async {
    if (_isRefreshingNotes) return;
    setState(() => _isRefreshingNotes = true);
    try {
      await SupabaseWeddingRepository.instance.fetchNotes();
    } catch (_) {}
    if (mounted) {
      setState(() => _isRefreshingNotes = false);
    }
  }

  Future<void> _refreshSignals() async {
    if (_isRefreshingSignals) return;
    setState(() => _isRefreshingSignals = true);
    try {
      await SupabaseWeddingRepository.instance.fetchLoveTriggers();
    } catch (_) {}
    if (mounted) {
      setState(() => _isRefreshingSignals = false);
    }
  }

  // ── Message sending ────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _sendingChat) return;
    setState(() => _sendingChat = true);
    _chatController.clear();

    // Reset typing status immediately on message send
    _typingTimer?.cancel();
    if (_isLocalTyping) {
      _isLocalTyping = false;
      _sendTypingStatus(false);
    }

    final localMessage = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: PartnerIdentity.active.value.label,
      message: text,
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
    );

    try {
      await SupabaseWeddingRepository.instance.sendChatMessage(text);
      if (!AppRuntime.supabaseReady) {
        setState(() => _pendingMessages.add(localMessage));
      }
    } catch (error) {
      setState(() => _pendingMessages.add(localMessage));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message saved locally (Offline).')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingChat = false);
    }
  }

  /// Handles Image / Location / Love quick-action buttons.
  Future<void> _onSpecialAction(MessageType type) async {
    switch (type) {
      case MessageType.image:
        await _sendImageMessage();
        break;
      case MessageType.location:
        await _sendLocationMessage();
        break;
      case MessageType.love:
        await _sendLoveSignalFromChat();
        break;
      case MessageType.text:
        break;
    }
  }

  // ── Real image upload: camera / gallery → compress → Supabase ─────────────

  Future<void> _sendImageMessage() async {
    if (!mounted) return;

    // 1. Show camera vs gallery bottom-sheet
    final source = await _showImageSourceSheet();
    if (source == null) return;

    // 2. Pick image
    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 90, // initial device-side quality reduction
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null || !mounted) return;

    // 3. Read bytes + determine extension
    final rawBytes = await picked.readAsBytes();
    final originalExt = picked.name.split('.').last.toLowerCase();
    // We always compress to JPEG for uniform MIME type handling
    const uploadExt = 'jpg';

    // 4. Client-side compression: target 2 MB, keeps us well under the 25 MB
    //    bucket limit while preserving good visible quality.
    setState(() {
      _uploadingImage = true;
      _uploadProgress = 0.1;
    });

    Uint8List compressedBytes;
    try {
      final result = await FlutterImageCompress.compressWithList(
        rawBytes,
        minHeight: 720,
        minWidth: 720,
        quality: 82,
        format: originalExt == 'png'
            ? CompressFormat.png
            : CompressFormat.jpeg,
      );
      compressedBytes = result;
    } catch (_) {
      // Compression failed — use raw bytes (still <= 25 MB for phone photos)
      compressedBytes = rawBytes;
    }

    if (!mounted) return;
    setState(() => _uploadProgress = 0.4);

    // 5. Upload to Supabase
    String? publicUrl;
    try {
      publicUrl = await SupabaseWeddingRepository.instance
          .uploadChatImage(compressedBytes, uploadExt);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingImage = false;
          _uploadProgress = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Upload failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    if (!mounted) return;
    setState(() => _uploadProgress = 0.9);

    // 6. Build & send rich message
    final msg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: PartnerIdentity.active.value.label,
      message: '',
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
      messageType: MessageType.image,
      imageUrl: publicUrl,
    );

    setState(() {
      _pendingMessages.add(msg);
      _uploadingImage = false;
      _uploadProgress = 0;
    });

    try {
      await SupabaseWeddingRepository.instance.sendRichMessage(msg);
    } catch (_) {}
  }

  /// Bottom sheet to choose Camera or Gallery.
  Future<ImageSource?> _showImageSourceSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? RodMaeColors.navy : Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: RodMaeColors.sky.withValues(alpha: 0.25),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ───────────────────────────────────────────────────
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Send a Photo',
              style: GoogleFonts.playfairDisplay(
                color: isDark ? Colors.white : RodMaeColors.lightText,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Images are compressed before sending.',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 24),
            // ── Camera ───────────────────────────────────────────────────
            _SourceTile(
              icon: Icons.camera_alt_rounded,
              label: 'Take a Photo',
              subtitle: 'Open camera',
              color: RodMaeColors.sky,
              isDark: isDark,
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 12),
            // ── Gallery ──────────────────────────────────────────────────
            _SourceTile(
              icon: Icons.photo_library_rounded,
              label: 'Choose from Gallery',
              subtitle: 'Pick existing photo',
              color: RodMaeColors.violet,
              isDark: isDark,
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ── Real location: geolocator + geocoding ──────────────────────────────────

  Future<void> _sendLocationMessage() async {
    if (!mounted) return;

    // 1. Confirmation sheet
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationConfirmSheet(
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    if (confirmed != true || !mounted) return;

    // 2. Check location permission
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permission denied.')),
          );
        }
        return;
      }
    }

    // 3. Fetch current position
    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not get location: $e')),
        );
      }
      return;
    }

    final lat = position.latitude;
    final lng = position.longitude;

    // 4. Reverse-geocode to get a human-readable address
    String address = 'Sharing current location...';
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
        // Build a clean "Street, City, Province" string
        final parts = <String>[
          if ((place.thoroughfare ?? '').isNotEmpty) place.thoroughfare!,
          if ((place.locality ?? '').isNotEmpty) place.locality!,
          if ((place.administrativeArea ?? '').isNotEmpty)
            place.administrativeArea!,
        ];
        if (parts.isNotEmpty) {
          address = parts.join(', ');
        }
      }
    } catch (_) {
      // Geocoding failed — use lat/lng as fallback label
      address =
          '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }

    if (!mounted) return;

    // 5. Build and send the location message
    final now = DateTime.now();
    final msg = ChatMessage(
      id: now.microsecondsSinceEpoch.toString(),
      sender: PartnerIdentity.active.value.label,
      message: address,
      createdAt: now,
      status: MessageStatus.sent,
      messageType: MessageType.location,
      // payload: 'lat,lng,address'
      locationData: '$lat,$lng,$address',
    );

    setState(() => _pendingMessages.add(msg));

    try {
      await SupabaseWeddingRepository.instance.sendRichMessage(msg);
    } catch (_) {}
  }

  /// Sends a love signal from the chat composer.
  Future<void> _sendLoveSignalFromChat() async {
    if (!mounted) return;
    final msg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: PartnerIdentity.active.value.label,
      message: 'Sending love to you 💕',
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
      messageType: MessageType.love,
    );
    setState(() => _pendingMessages.add(msg));
    try {
      await SupabaseWeddingRepository.instance.sendRichMessage(msg);
    } catch (_) {}

    setState(() {
      _activeTrigger = const LoveTrigger(
        title: 'I Love You',
        subtitle: 'Sending love to your spouse!',
        icon: Icons.favorite_rounded,
        color: Color(0xFFFF5E8D),
        animationAsset: 'assets/animations/hearts_shower.json',
        overlayTitle: '❤️ Love Signal',
      );
    });
  }

  // ── Notes ──────────────────────────────────────────────────────────────────

  Future<void> _sendNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty || _sendingNote) return;
    setState(() => _sendingNote = true);
    _noteController.clear();

    final messenger = ScaffoldMessenger.of(context);
    try {
      showSurpriseNoteSendAnimation(context);
      await SupabaseWeddingRepository.instance.insertSurpriseNote(text);
      messenger.showSnackBar(
        const SnackBar(content: Text('Sweet note sent to your spouse!')),
      );
    } catch (error) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Failed to sync note, saved locally.')),
      );
    } finally {
      if (mounted) setState(() => _sendingNote = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasKeyboard = _lastHasKeyboardState;

    if (_wasKeyboardOpen && !hasKeyboard) {
      // Keyboard was open, now closed (e.g. system back button pressed)
      // Unfocus the chat input so tapping it again will request focus normally
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _chatFocusNode.hasFocus) {
          _chatFocusNode.unfocus();
        }
      });
    }
    _wasKeyboardOpen = hasKeyboard;

    return Stack(
      children: [
        RodMaePageFrame(
          hasKeyboard: hasKeyboard,
          child: Column(
            children: [
              if (!hasKeyboard)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                  child: ValueListenableBuilder<PartnerProfile>(
                    valueListenable: PartnerIdentity.active,
                    builder: (context, activeProfile, _) {
                      final myLabel = activeProfile.label.toLowerCase();
                      return StreamBuilder<List<ChatMessage>>(
                        stream: _switcherChatStream,
                        builder: (context, chatSnapshot) {
                          final chatList = chatSnapshot.data ?? [];
                          final chatUnread = chatList.where((m) =>
                              m.sender.toLowerCase() != myLabel &&
                              m.status != MessageStatus.seen).length;

                          return StreamBuilder<List<LoveTriggerEvent>>(
                            stream: _switcherSignalsStream,
                            builder: (context, signalSnapshot) {
                              final signalList = signalSnapshot.data ?? [];
                              final signalUnread = signalList.where((s) =>
                                  s.sender.toLowerCase() != myLabel &&
                                  s.status != MessageStatus.seen).length;

                              return SegmentedSwitcher(
                                labels: const ['Chat', 'Sweet Notes', 'Signals'],
                                icons: const [
                                  Icons.chat_bubble_outline_rounded,
                                  Icons.sticky_note_2_outlined,
                                  Icons.favorite_border_rounded,
                                ],
                                badgeCounts: [chatUnread, 0, signalUnread],
                                selected: _tab,
                                onSelected: (value) {
                                  AppNotificationNavigation.privateChatTabNotifier.value =
                                      value;
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              Expanded(
                child: ValueListenableBuilder<PartnerProfile>(
                  valueListenable: PartnerIdentity.active,
                  builder: (context, activeProfile, _) {
                    return IndexedStack(
                      index: _tab,
                      children: [
                        _buildChatTab(isDark, hasKeyboard),
                        _buildNotesTab(isDark),
                        _buildSignalsTab(isDark),
                      ],
                    );
                  },
                ),
              ),
            ],
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
        // ── Image upload progress overlay ────────────────────────────────
        if (_uploadingImage)
          Positioned(
            left: 18,
            right: 18,
            bottom: 110,
            child: _ImageUploadBanner(progress: _uploadProgress),
          ),
      ],
    );
  }

  // ── Chat tab ───────────────────────────────────────────────────────────────

  Widget _buildChatTab(bool isDark, bool hasKeyboard) {
    final myLabel = PartnerIdentity.active.value.label.toLowerCase();

    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: _chatStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return AdvancedLoadingEffect(
                  isLoading: true,
                  placeholder: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    itemCount: 6,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (_, index) => Container(
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  child: const SizedBox.expand(),
                );
              }

              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Text(
                      'Having trouble connecting to chat. Please check your network connection.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        color: RodMaeColors.coral,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }

              final base = snapshot.data ?? <ChatMessage>[];

              // Mark messages as seen if there are unseen messages from partner and we are actively on the chat screen
              if (AppNotificationNavigation.mainTabNotifier.value == 1 && _tab == 0 && base.isNotEmpty) {
                final hasUnseen = base.any((m) =>
                    m.sender.toLowerCase() != myLabel &&
                    m.status != MessageStatus.seen);
                if (hasUnseen) {
                  Future.microtask(() =>
                      SupabaseWeddingRepository.instance.markMessagesAsSeen());
                }
              }

              // Reverse list so newest are at index 0 (rendered at the bottom)
              final messages = [
                ...base,
                ..._pendingMessages.where(
                  (pending) => !base.any((item) => item.id == pending.id),
                ),
              ].reversed.toList();

              if (messages.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 48,
                        color: isDark ? Colors.white30 : Colors.black26,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'No chat history yet.\nSend a message to start conversing!',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: isDark
                              ? Colors.white54
                              : RodMaeColors.lightTextSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }

              // In reversed list, the latest user message is the first matching index we hit
              int latestMineIndex = -1;
              for (int i = 0; i < messages.length; i++) {
                if (messages[i].sender.toLowerCase() == myLabel) {
                  latestMineIndex = i;
                  break;
                }
              }

              return RefreshIndicator(
                color: Colors.transparent,
                backgroundColor: Colors.transparent,
                displacement: 140.0,
                onRefresh: _refreshChat,
                child: AdvancedLoadingEffect(
                  isLoading: _isRefreshingChat,
                  child: ListView.builder(
                    controller: _scrollController,
                    reverse: true, // Naturally pushes upward when keyboard appears
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isLatestFromMe = index == latestMineIndex &&
                          msg.sender.toLowerCase() == myLabel;
                      return ChatBubble(
                        message: msg,
                        isLatestFromMe: isLatestFromMe,
                        // Pass partner's avatar for the 'seen' receipt indicator
                        partnerAvatarUrl: _partnerAvatarUrl,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        ChatTypingIndicator(
          isTyping: _isPartnerTyping,
          isDark: isDark,
          partnerName: PartnerIdentity.active.value == PartnerProfile.rodel
              ? 'Eurine'
              : 'Rodel',
        ),
        ChatComposer(
          controller: _chatController,
          sending: _sendingChat,
          onSend: _sendMessage,
          onSpecialAction: _onSpecialAction,
          onChanged: _onChatInputChanged,
          focusNode: _chatFocusNode,
          hasKeyboard: hasKeyboard,
        ),
      ],
    );
  }

  // ── Notes tab ──────────────────────────────────────────────────────────────

  Widget _buildNotesTab(bool isDark) {
    return Column(
      children: [
        // Composing Box
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: GlassCard(
            borderColor: RodMaeColors.gold.withValues(alpha: 0.2),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.sticky_note_2_rounded,
                        color: RodMaeColors.gold, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'WRITE A SWEET NOTE',
                      style: GoogleFonts.inter(
                        color: RodMaeColors.gold,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  maxLines: 2,
                  maxLength: 140,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: isDark ? Colors.white : RodMaeColors.lightText,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Write something romantic for your spouse...',
                    hintStyle: GoogleFonts.inter(
                      color: isDark ? Colors.white30 : Colors.black38,
                      fontSize: 12,
                    ),
                    counterStyle: GoogleFonts.inter(
                      color: isDark ? Colors.white30 : Colors.black38,
                      fontSize: 10,
                    ),
                    filled: true,
                    fillColor: Colors.black.withValues(alpha: 0.15),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: RodMaeColors.gold),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PrimaryPillButton(
                      label: 'SEND NOTE',
                      icon: Icons.send_rounded,
                      onPressed: _sendNote,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // History List
        Expanded(
          child: StreamBuilder<List<SurpriseNote>>(
            stream: _notesStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return AdvancedLoadingEffect(
                  isLoading: true,
                  placeholder: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    itemCount: 4,
                    separatorBuilder: (_, index) => const SizedBox(height: 12),
                    itemBuilder: (_, index) => Container(
                      height: 96,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  child: const SizedBox.expand(),
                );
              }

              final notes = snapshot.data ?? <SurpriseNote>[];

              if (notes.isEmpty) {
                return Center(
                  child: Text(
                    'No sweet notes recorded yet.\nWrite the first note above!',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white30 : Colors.black26,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                );
              }

              return RefreshIndicator(
                color: Colors.transparent,
                backgroundColor: Colors.transparent,
                displacement: 140.0,
                onRefresh: _refreshNotes,
                child: AdvancedLoadingEffect(
                  isLoading: _isRefreshingNotes,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
                    itemCount: notes.length,
                    itemBuilder: (context, index) {
                      final note = notes[index];
                      final isMe = note.sender.toLowerCase() ==
                          PartnerIdentity.active.value.label.toLowerCase();
                      final senderAvatarUrl = _avatarFor(note.sender);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          borderColor: isMe
                              ? RodMaeColors.sky.withValues(alpha: 0.18)
                              : RodMaeColors.gold.withValues(alpha: 0.18),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // ── Sender PFP + name ─────────────────
                                  Row(
                                    children: [
                                      // Real profile picture
                                      _SenderAvatar(
                                        avatarUrl: senderAvatarUrl,
                                        initial: note.sender.isNotEmpty
                                            ? note.sender[0]
                                            : '?',
                                        color: isMe
                                            ? RodMaeColors.sky
                                            : RodMaeColors.gold,
                                        radius: 14,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        note.sender,
                                        style: GoogleFonts.inter(
                                          color: isMe
                                              ? RodMaeColors.sky
                                              : RodMaeColors.gold,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                  // ── Timestamp ─────────────────────────
                                  Text(
                                    Formatters.dateTime(note.createdAt),
                                    style: GoogleFonts.robotoMono(
                                      color: isDark
                                          ? Colors.white30
                                          : Colors.black38,
                                      fontSize: 9,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '"${note.content}"',
                                style: GoogleFonts.playfairDisplay(
                                  color: isDark
                                      ? Colors.white
                                      : RodMaeColors.lightText,
                                  fontSize: 14,
                                  fontStyle: FontStyle.italic,
                                  height: 1.32,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ── Signals tab ─────────────────────────────────────────────────────────────

  Widget _buildSignalsTab(bool isDark) {
    return StreamBuilder<List<LoveTriggerEvent>>(
      stream: _signalsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return AdvancedLoadingEffect(
            isLoading: true,
            placeholder: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              itemCount: 5,
              separatorBuilder: (_, index) => const SizedBox(height: 12),
              itemBuilder: (_, index) => Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
            child: const SizedBox.expand(),
          );
        }

        final signals = snapshot.data ?? <LoveTriggerEvent>[];

        // Mark signals as seen if there are unseen signals from partner and we are actively on the signals tab
        if (AppNotificationNavigation.mainTabNotifier.value == 1 && _tab == 2 && signals.isNotEmpty) {
          final myLabel = PartnerIdentity.active.value.label.toLowerCase();
          final hasUnseen = signals.any((s) =>
              s.sender.toLowerCase() != myLabel &&
              s.status != MessageStatus.seen);
          if (hasUnseen) {
            Future.microtask(() =>
                SupabaseWeddingRepository.instance.markLoveTriggersAsSeen());
          }
        }

        if (signals.isEmpty) {
          return Center(
            child: Text(
              'No love signals sent yet.\nTrigger a signal from the Home Dashboard!',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white30 : Colors.black26,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: Colors.transparent,
          backgroundColor: Colors.transparent,
          displacement: 140.0,
          onRefresh: _refreshSignals,
          child: AdvancedLoadingEffect(
            isLoading: _isRefreshingSignals,
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
              itemCount: signals.length,
              itemBuilder: (context, index) {
                final sig = signals[index];
                final isMe = sig.sender.toLowerCase() ==
                    PartnerIdentity.active.value.label.toLowerCase();
                final senderAvatarUrl = _avatarFor(sig.sender);

                IconData icon = Icons.favorite_rounded;
                Color color = RodMaeColors.rose;
                String text = '';

                switch (sig.triggerType) {
                  case 'Miss You':
                    icon = Icons.favorite_rounded;
                    color = RodMaeColors.rose;
                    text = isMe
                        ? 'You sent a Hearts Shower'
                        : '${sig.sender} sent a Hearts Shower';
                    break;
                  case 'I Love You':
                    icon = Icons.favorite_rounded;
                    color = RodMaeColors.rose;
                    text = isMe
                        ? 'You declared: "I Love You!" ❤️'
                        : '${sig.sender} declared: "I Love You!" ❤️';
                    break;
                  case 'Heading Home':
                    icon = Icons.navigation_rounded;
                    color = RodMaeColors.mint;
                    text = isMe
                        ? 'You shared your route home'
                        : '${sig.sender} shared route home';
                    break;
                  case 'Flying Kiss':
                    icon = Icons.favorite_border_rounded;
                    color = RodMaeColors.gold;
                    text = isMe
                        ? 'You blew a Flying Kiss'
                        : '${sig.sender} blew a Flying Kiss';
                    break;
                  case 'Surprise Note':
                    icon = Icons.sticky_note_2_rounded;
                    color = RodMaeColors.electricBlue;
                    text = isMe
                        ? 'You sent a Sweet Note'
                        : '${sig.sender} sent a Sweet Note';
                    break;
                  default:
                    icon = Icons.favorite_rounded;
                    color = RodMaeColors.rose;
                    text =
                        '${sig.sender} triggered love signal: ${sig.triggerType}';
                }

                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GlassCard(
                    borderColor: color.withValues(alpha: 0.18),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        // ── Sender PFP ────────────────────────────────────
                        _SenderAvatar(
                          avatarUrl: senderAvatarUrl,
                          initial: sig.sender.isNotEmpty ? sig.sender[0] : '?',
                          color: color,
                          radius: 18,
                        ),
                        const SizedBox(width: 12),
                        // ── Signal icon ───────────────────────────────────
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(icon, color: color, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                text,
                                style: GoogleFonts.inter(
                                  color: isDark
                                      ? Colors.white
                                      : RodMaeColors.lightText,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                Formatters.dateTime(sig.createdAt),
                                style: GoogleFonts.robotoMono(
                                  color: isDark ? Colors.white30 : Colors.black38,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class ChatTypingIndicator extends StatelessWidget {
  final bool isTyping;
  final bool isDark;
  final String partnerName;

  const ChatTypingIndicator({
    required this.isTyping,
    required this.isDark,
    required this.partnerName,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: isTyping
          ? Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B).withValues(alpha: 0.6)
                        : Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _TypingDotsAnimation(isDark: isDark),
                      const SizedBox(width: 8),
                      Text(
                        '$partnerName is typing...',
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sender Avatar — real PFP via CachedNetworkImage with initial-letter fallback
// ─────────────────────────────────────────────────────────────────────────────

class _SenderAvatar extends StatelessWidget {
  final String? avatarUrl;
  final String initial;
  final Color color;
  final double radius;

  const _SenderAvatar({
    required this.avatarUrl,
    required this.initial,
    required this.color,
    required this.radius,
  });

  @override
  Widget build(BuildContext context) {
    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: avatarUrl!,
        imageBuilder: (ctx, imageProvider) => CircleAvatar(
          radius: radius,
          backgroundImage: imageProvider,
        ),
        placeholder: (ctx, url) => _fallback(),
        errorWidget: (ctx, url, err) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => CircleAvatar(
        radius: radius,
        backgroundColor: color,
        child: Text(
          initial.toUpperCase(),
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.75,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Image upload progress banner
// ─────────────────────────────────────────────────────────────────────────────

class _ImageUploadBanner extends StatelessWidget {
  final double progress;
  const _ImageUploadBanner({required this.progress});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: RodMaeColors.navy,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RodMaeColors.sky.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_upload_rounded,
              color: RodMaeColors.sky, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uploading photo...',
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(RodMaeColors.sky),
                    minHeight: 4,
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

// ─────────────────────────────────────────────────────────────────────────────
// Image source selection tile
// ─────────────────────────────────────────────────────────────────────────────

class _SourceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _SourceTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isDark ? 0.12 : 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white : RodMaeColors.lightText,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                size: 14,
                color: isDark ? Colors.white30 : Colors.black26),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Location confirm bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _LocationConfirmSheet extends StatelessWidget {
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  const _LocationConfirmSheet({
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: RodMaeColors.navy,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: RodMaeColors.mint.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: RodMaeColors.mint.withValues(alpha: 0.15),
              shape: BoxShape.circle,
              border: Border.all(
                color: RodMaeColors.mint.withValues(alpha: 0.4),
              ),
            ),
            child: const Icon(Icons.location_on_rounded,
                color: RodMaeColors.mint, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'Share Your Location?',
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your current address will be reverse-geocoded and sent to your spouse. They can tap the map to open it.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              color: Colors.white60,
              fontSize: 12,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white24),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Cancel',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: onConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: RodMaeColors.mint,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Share',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Typing Dots Animation
// ─────────────────────────────────────────────────────────────────────────────

class _TypingDotsAnimation extends StatefulWidget {
  final bool isDark;
  const _TypingDotsAnimation({required this.isDark});

  @override
  State<_TypingDotsAnimation> createState() => _TypingDotsAnimationState();
}

class _TypingDotsAnimationState extends State<_TypingDotsAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dotColor = widget.isDark ? RodMaeColors.gold : RodMaeColors.sapphire;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.2;
            final double value = (1.0 - ((_controller.value - delay) % 1.0)).clamp(0.2, 1.0);
            return Opacity(
              opacity: value,
              child: Container(
                width: 5,
                height: 5,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            );
          },
        );
      }),
    );
  }
}
