import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
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
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  final _chatController = TextEditingController();
  final _noteController = TextEditingController();
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
  late final Stream<List<SurpriseNote>> _notesStream;
  late final Stream<List<LoveTriggerEvent>> _signalsStream;

  @override
  void initState() {
    super.initState();
    _chatStream = SupabaseWeddingRepository.instance.watchChat();
    _notesStream = SupabaseWeddingRepository.instance.watchNotes();
    _signalsStream = SupabaseWeddingRepository.instance.watchLoveTriggers();

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
  }

  void _onPrivateChatTabChanged() {
    if (mounted) {
      setState(() {
        _tab = AppNotificationNavigation.privateChatTabNotifier.value;
      });
    }
  }

  @override
  void dispose() {
    AppNotificationNavigation.privateChatTabNotifier
        .removeListener(_onPrivateChatTabChanged);
    _chatController.dispose();
    _noteController.dispose();
    _lottieController.dispose();
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

  /// Picks an image and sends it as a chat message.
  Future<void> _sendImageMessage() async {
    // Show a bottom sheet asking the user to paste a URL or pick from gallery
    if (!mounted) return;
    final url = await _showImageUrlDialog();
    if (url == null || url.isEmpty) return;

    final msg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: PartnerIdentity.active.value.label,
      message: '',
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
      messageType: MessageType.image,
      imageUrl: url,
    );
    setState(() => _pendingMessages.add(msg));

    try {
      await SupabaseWeddingRepository.instance.sendRichMessage(msg);
    } catch (_) {}
  }

  Future<String?> _showImageUrlDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: RodMaeColors.navy,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Send Image',
          style: GoogleFonts.playfairDisplay(color: Colors.white, fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Paste an image URL to share with your spouse.',
              style: GoogleFonts.inter(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              style: GoogleFonts.inter(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'https://example.com/photo.jpg',
                hintStyle: GoogleFonts.inter(
                    color: Colors.white30, fontSize: 12),
                prefixIcon: const Icon(Icons.link_rounded,
                    color: RodMaeColors.sky, size: 18),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.inter(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: RodMaeColors.electricBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child:
                Text('Send', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Sends current location as a chat message.
  Future<void> _sendLocationMessage() async {
    if (!mounted) return;
    // Show a confirmation sheet before sending location
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationConfirmSheet(
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    if (confirmed != true) return;

    // We'll use approximate location data via placeholder.
    // In a full implementation, use geolocator package.
    final now = DateTime.now();
    const placeholderAddr = 'Sharing current location...';
    final msg = ChatMessage(
      id: now.microsecondsSinceEpoch.toString(),
      sender: PartnerIdentity.active.value.label,
      message: placeholderAddr,
      createdAt: now,
      status: MessageStatus.sent,
      messageType: MessageType.location,
      locationData: '14.5995,120.9842,$placeholderAddr',
    );
    setState(() => _pendingMessages.add(msg));

    try {
      await SupabaseWeddingRepository.instance.sendRichMessage(msg);
    } catch (_) {}
  }

  /// Sends a love signal from the chat composer (not the home dashboard).
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

    // Trigger the animated love overlay
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

    return Stack(
      children: [
        RodMaePageFrame(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                child: SegmentedSwitcher(
                  labels: const ['Chat', 'Sweet Notes', 'Signals'],
                  icons: const [
                    Icons.chat_bubble_outline_rounded,
                    Icons.sticky_note_2_outlined,
                    Icons.favorite_border_rounded,
                  ],
                  selected: _tab,
                  onSelected: (value) {
                    AppNotificationNavigation.privateChatTabNotifier.value =
                        value;
                  },
                ),
              ),
              Expanded(
                child: IndexedStack(
                  index: _tab,
                  children: [
                    _buildChatTab(isDark),
                    _buildNotesTab(isDark),
                    _buildSignalsTab(isDark),
                  ],
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
      ],
    );
  }

  // ── Chat tab ───────────────────────────────────────────────────────────────

  Widget _buildChatTab(bool isDark) {
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
              final messages = [
                ...base,
                ..._pendingMessages.where(
                  (pending) => !base.any((item) => item.id == pending.id),
                ),
              ];

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

              // Find the index of the latest message sent by the local user
              // for the read receipt indicator
              int latestMineIndex = -1;
              for (int i = messages.length - 1; i >= 0; i--) {
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
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isLatestFromMe = index == latestMineIndex &&
                          msg.sender.toLowerCase() == myLabel;
                      return ChatBubble(
                        message: msg,
                        isLatestFromMe: isLatestFromMe,
                      );
                    },
                  ),
                ),
              );
            },
          ),
        ),
        ChatComposer(
          controller: _chatController,
          sending: _sendingChat,
          onSend: _sendMessage,
          onSpecialAction: _onSpecialAction,
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
                                // Sender
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 10,
                                      backgroundColor: isMe
                                          ? RodMaeColors.sky
                                          : RodMaeColors.gold,
                                      child: Text(
                                        note.sender[0],
                                        style: GoogleFonts.inter(
                                          color: RodMaeColors.navy,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
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
                                // ── Timestamp: date + time ───────────────────
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
                ), // close ListView.builder
                ), // close AdvancedLoadingEffect
              ); // close RefreshIndicator
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
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(width: 14),
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
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          // ── Timestamp: now shows date + time ─────────────
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
          ),  // close ListView.builder
          ),  // close AdvancedLoadingEffect
        );    // close RefreshIndicator
      },
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
            'Your current location will be sent to your spouse in the chat. They can tap it to open in Maps.',
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
