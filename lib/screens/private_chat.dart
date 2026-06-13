// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../models/transaction.dart';
import '../models/wallet.dart';
import '../services/finance_repository.dart';
import '../core/utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../core/time_utils.dart';
import 'package:ntp/ntp.dart';
import '../models/chat_message.dart';
import '../models/surprise_note.dart';
import '../models/love_trigger_event.dart';
import '../models/meal_plan.dart';
import '../services/auth_service.dart';
import '../services/firebase_service.dart';
import '../services/supabase_service.dart';
import '../services/notification_service.dart';
import '../services/ai_service.dart';
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
  final _chatController = MentionTextEditingController();
  final _noteController = TextEditingController();
  final _scrollController = ScrollController();
  final _chatFocusNode = FocusNode();
  final _optimisticMessages = <ChatMessage>[];
  final _failedMessageIds = <String>{};
  bool _sendingChat = false;
  bool _isAssistantTyping = false;
  bool _isFinancesTyping = false;
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
  String? _rodelAvatarUrl;
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
  ChatMessage? _replyingToMessage;
  ChatMessage? _editingMessage;
  bool _showAssistantSuggestion = false;

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

    _chatStream = SupabaseWeddingRepository.instance.watchChat().asBroadcastStream();
    _switcherChatStream = SupabaseWeddingRepository.instance.watchChat().asBroadcastStream();
    _notesStream = SupabaseWeddingRepository.instance.watchNotes().asBroadcastStream();
    _signalsStream = SupabaseWeddingRepository.instance.watchLoveTriggers().asBroadcastStream();
    _switcherSignalsStream = SupabaseWeddingRepository.instance.watchLoveTriggers().asBroadcastStream();

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

    // Mark signals as seen when the screen opens (chat seen is handled by ViewportIntersectionObserver)
    if (AppNotificationNavigation.mainTabNotifier.value == 1) {
      if (_tab == 2) {
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

  String? _avatarFor(String sender) {
    final lower = sender.toLowerCase();
    if (lower.contains('rodel')) return _rodelAvatarUrl;
    return _eurineAvatarUrl;
  }

  String? get _partnerAvatarUrl {
    return PartnerIdentity.active.value == PartnerProfile.rodel
        ? _eurineAvatarUrl
        : _rodelAvatarUrl;
  }

  String? get _myAvatarUrl {
    return PartnerIdentity.active.value == PartnerProfile.rodel
        ? _rodelAvatarUrl
        : _eurineAvatarUrl;
  }

  void _updateChatActiveStatus() {
    final mainTab = AppNotificationNavigation.mainTabNotifier.value;
    final subTab = AppNotificationNavigation.privateChatTabNotifier.value;

    final isChatOpen = mainTab == 1 && subTab == 0;
    NotificationService.isChatActive = isChatOpen;

    if (mainTab == 1 && mounted) {
      if (subTab == 2) {
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

    // Mention overlay toggle logic
    final showOverlay = text.endsWith('@') || text == '@';
    if (showOverlay != _showAssistantSuggestion) {
      setState(() {
        _showAssistantSuggestion = showOverlay;
      });
    }
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

  bool _isOptimisticMatch(ChatMessage optimistic, ChatMessage server) {
    if (optimistic.sender != server.sender) return false;
    if (optimistic.messageType != server.messageType) return false;
    
    if (optimistic.messageType == MessageType.voice) {
      final diff = optimistic.createdAt.difference(server.createdAt).abs();
      return diff.inSeconds < 45;
    }

    if (optimistic.message != server.message) return false;
    if (optimistic.imageUrl != server.imageUrl) return false;
    if (optimistic.locationData != server.locationData) return false;
    
    final diff = optimistic.createdAt.difference(server.createdAt).abs();
    return diff.inSeconds < 30;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients && mounted) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _retryMessage(ChatMessage failedMsg) async {
    final tempId = failedMsg.id;
    setState(() {
      _failedMessageIds.remove(tempId);
    });

    try {
      if (failedMsg.messageType == MessageType.text) {
        await SupabaseWeddingRepository.instance.sendChatMessage(
          failedMsg.message,
          replyToId: failedMsg.replyToId,
          replyToSender: failedMsg.replyToSender,
          replyToText: failedMsg.replyToText,
        );
      } else if (failedMsg.messageType == MessageType.voice) {
        final filePath = failedMsg.voiceUrl;
        if (filePath != null && filePath.isNotEmpty) {
          final isLocal = !filePath.startsWith('http');
          String finalUrl = filePath;
          if (isLocal) {
            finalUrl = await SupabaseWeddingRepository.instance.uploadVoiceMessage(filePath);
            final file = File(filePath);
            if (await file.exists()) {
              await file.delete();
            }
          }
          await SupabaseWeddingRepository.instance.sendChatMessage(
            '',
            replyToId: failedMsg.replyToId,
            replyToSender: failedMsg.replyToSender,
            replyToText: failedMsg.replyToText,
            voiceUrl: finalUrl,
          );
        }
      } else {
        await SupabaseWeddingRepository.instance.sendRichMessage(failedMsg);
      }
      setState(() {
        _optimisticMessages.removeWhere((x) => x.id == tempId);
      });
    } catch (error) {
      setState(() {
        _failedMessageIds.add(tempId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to resend message.')),
        );
      }
    }
  }

  // ── Message sending ────────────────────────────────────────────────────────

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;

    if (_editingMessage != null) {
      final msgToEdit = _editingMessage!;
      setState(() {
        _editingMessage = null;
        _chatController.clear();
      });
      try {
        await SupabaseWeddingRepository.instance.editMessage(msgToEdit.id, text);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to edit message: $e')),
          );
        }
      }
      return;
    }

    _typingTimer?.cancel();
    if (_isLocalTyping) {
      _isLocalTyping = false;
      _sendTypingStatus(false);
    }

    final replyId = _replyingToMessage?.id;
    final replySender = _replyingToMessage?.sender;
    final replyText = _replyingToMessage?.message;

    final tempId = '-temp_${DateTime.now().microsecondsSinceEpoch}';

    // Clear composer and insert optimistic message IMMEDIATELY to avoid "ghosting"
    setState(() {
      _chatController.clear();
      _replyingToMessage = null;
      _optimisticMessages.add(ChatMessage(
        id: tempId,
        sender: PartnerIdentity.active.value.label,
        message: text,
        createdAt: DateTime.now(), // initial local time fallback
        status: MessageStatus.sent,
        replyToId: replyId,
        replyToSender: replySender,
        replyToText: replyText,
      ));
    });

    _scrollToBottom();

    final isAssistantCommand = text.trim().toLowerCase().startsWith('@assistant');
    final isFinancesCommand = text.trim().toLowerCase().startsWith('@finances');

    // Fetch the true time via NTP.now() with fallback
    DateTime trueTime;
    try {
      trueTime = await NTP.now(timeout: const Duration(seconds: 3));
    } catch (_) {
      trueTime = DateTime.now();
    }
    final trueTimeUtcStr = trueTime.toUtc().toIso8601String();
    final parsedTrueTime = DateTime.parse(trueTimeUtcStr).toLocal();

    // Update optimistic message with the NTP-derived time
    setState(() {
      final index = _optimisticMessages.indexWhere((m) => m.id == tempId);
      if (index != -1) {
        _optimisticMessages[index] = _optimisticMessages[index].copyWith(
          createdAt: parsedTrueTime,
        );
      }
    });

    try {
      await SupabaseWeddingRepository.instance.sendChatMessage(
        text,
        replyToId: replyId,
        replyToSender: replySender,
        replyToText: replyText,
      );
    } catch (error) {
      setState(() {
        _failedMessageIds.add(tempId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send message. Saved locally.')),
        );
      }
    }

    if (isAssistantCommand) {
      _runAssistantQuery(text);
    } else if (isFinancesCommand) {
      _runFinancesQuery(text);
    }
  }

  Future<void> _runAssistantQuery(String userPrompt) async {
    if (!mounted) return;
    setState(() {
      _isAssistantTyping = true;
    });

    try {
      final cleanPrompt = userPrompt.replaceFirst(RegExp(r'^@assistant\s*'), '').trim();
      final response = await AiService.askAssistant(cleanPrompt);
      
      String cleanResponse = response;
      final jsonMatch = RegExp(r'\|\|\|(.*?)\|\|\|', dotAll: true).firstMatch(response);
      if (jsonMatch != null) {
        try {
          final jsonStr = jsonMatch.group(1)?.trim();
          if (jsonStr != null) {
            final decoded = jsonDecode(jsonStr);
            if (decoded['action'] == 'LOG_TRANSACTION') {
              final double amount = (decoded['amount'] as num).toDouble();
              final type = TransactionType.from(decoded['type']);
              final category = decoded['category'] ?? 'Shared';
              
              await FinanceRepository.instance.insertTransaction(
                Transaction(
                  id: DateTime.now().microsecondsSinceEpoch.toString(),
                  walletId: 'shared-wallet',
                  createdByUserId: PartnerIdentity.active.value.label,
                  type: type,
                  amount: amount,
                  categoryId: category,
                  date: DateTime.now(),
                ),
              );
            }
          }
        } catch (e) {
          debugPrint('Error parsing/inserting AI transaction: $e');
        }
        cleanResponse = response.replaceAll(RegExp(r'\|\|\|(.*?)\|\|\|', dotAll: true), '').trim();
      }

      await SupabaseWeddingRepository.instance.sendChatMessage(
        cleanResponse,
        sender: 'assistant',
      );
    } catch (e) {
      debugPrint('AI Assistant query error: $e');
      await SupabaseWeddingRepository.instance.sendChatMessage(
        "I'm sorry, I'm having trouble connecting to my servers right now. Please try again! 💕",
        sender: 'assistant',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isAssistantTyping = false;
        });
      }
    }
  }

  Future<void> _runFinancesQuery(String userPrompt) async {
    if (!mounted) return;
    setState(() {
      _isFinancesTyping = true;
    });

    try {
      final cleanPrompt = userPrompt.replaceFirst(RegExp(r'^@finances\s*', caseSensitive: false), '').trim();

      // 1. Fetch live wallets and transactions context
      final wallets = await FinanceRepository.instance.fetchWallets();
      final txs = await FinanceRepository.instance.fetchTransactions();

      final contextBuffer = StringBuffer();
      contextBuffer.writeln("WALLETS & VAULTS:");
      for (final w in wallets) {
        contextBuffer.writeln("- ${w.name}: PHP ${w.balance.toStringAsFixed(2)}");
      }
      contextBuffer.writeln("\nRECENT TRANSACTIONS:");
      for (final t in txs.take(8)) {
        contextBuffer.writeln("- ${t.paidByUid} logged type [${t.type.name}] amount PHP ${t.amount.toStringAsFixed(2)} category [${t.category}] on ${Formatters.date(t.date)} (wallet_id: ${t.walletId ?? 'none'})");
      }

      // 2. Call the AI service with context injection
      final aiResponse = await AiService.generateFinancialResponse(cleanPrompt, contextBuffer.toString());

      // 3. Extract transaction JSON block if present
      String displayResponse = aiResponse;
      Map<String, dynamic>? parsedJson;

      if (aiResponse.contains('|||')) {
        final parts = aiResponse.split('|||');
        displayResponse = parts.first.trim();
        try {
          final jsonStr = parts[1].trim();
          parsedJson = jsonDecode(jsonStr);
        } catch (e) {
          debugPrint("Failed to parse Tarsi transaction block: $e");
        }
      }

      // 4. Save response to Supabase chat as sender: 'finances'
      await SupabaseWeddingRepository.instance.sendChatMessage(
        displayResponse,
        sender: 'finances',
      );

      // 5. Handle auto-logging
      if (parsedJson != null && parsedJson['action'] == 'LOG_TRANSACTION') {
        final amount = Formatters.asDouble(parsedJson['amount'] ?? 0.0);
        final typeStr = parsedJson['type'] ?? 'expense';
        final category = parsedJson['category'] ?? 'Others';
        final walletName = parsedJson['walletName'] ?? '';

        if (amount > 0) {
          // Attempt to match wallet
          String? walletId;
          final match = walletName.toString().toLowerCase();
          if (match.contains('rodel')) {
            walletId = 'rodel-wallet';
          } else if (match.contains('eurine') || match.contains('gcash')) {
            walletId = 'eurine-wallet';
          } else if (match.contains('shared') || match.contains('vault')) {
            walletId = 'shared-wallet';
          } else {
            walletId = 'shared-wallet';
          }

          final loggedTx = Transaction(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            walletId: walletId ?? 'shared-wallet',
            createdByUserId: PartnerIdentity.active.value.label,
            type: TransactionType.from(typeStr),
            amount: amount,
            categoryId: category,
            date: DateTime.now(),
          );

          await FinanceRepository.instance.insertTransaction(loggedTx);

          if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Tarsi Auto-Logged: ₱${amount.toStringAsFixed(2)} to $category!'),
                backgroundColor: RodMaeColors.mint,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Finances AI query error: $e');
      await SupabaseWeddingRepository.instance.sendChatMessage(
        "I'm sorry, I'm having trouble retrieving your financial context right now. Please try again! 💕",
        sender: 'finances',
      );
    } finally {
      if (mounted) {
        setState(() {
          _isFinancesTyping = false;
        });
      }
    }
  }

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
      case MessageType.voice:
        break;
    }
  }

  Future<void> _sendImageMessage() async {
    if (!mounted) return;

    final source = await _showImageSourceSheet();
    if (source == null) return;

    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1920,
      maxHeight: 1920,
    );
    if (picked == null || !mounted) return;

    final rawBytes = await picked.readAsBytes();
    final originalExt = picked.name.split('.').last.toLowerCase();
    const uploadExt = 'jpg';

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
      compressedBytes = rawBytes;
    }

    if (!mounted) return;
    setState(() => _uploadProgress = 0.4);

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

    final replyId = _replyingToMessage?.id;
    final replySender = _replyingToMessage?.sender;
    final replyText = _replyingToMessage?.message;

    final tempId = '-temp_${DateTime.now().microsecondsSinceEpoch}';
    final msg = ChatMessage(
      id: tempId,
      sender: PartnerIdentity.active.value.label,
      message: '',
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
      messageType: MessageType.image,
      imageUrl: publicUrl,
      replyToId: replyId,
      replyToSender: replySender,
      replyToText: replyText,
    );

    setState(() {
      _replyingToMessage = null;
      _optimisticMessages.add(msg);
      _uploadingImage = false;
      _uploadProgress = 0;
    });

    _scrollToBottom();

    try {
      await SupabaseWeddingRepository.instance.sendRichMessage(msg);
    } catch (_) {
      setState(() {
        _failedMessageIds.add(tempId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send image.')),
        );
      }
    }
  }

  Future<void> _sendVoiceMessage(String filePath) async {
    final replyId = _replyingToMessage?.id;
    final replySender = _replyingToMessage?.sender;
    final replyText = _replyingToMessage?.message;

    final tempId = '-temp_${DateTime.now().microsecondsSinceEpoch}';
    final localMessage = ChatMessage(
      id: tempId,
      sender: PartnerIdentity.active.value.label,
      message: '',
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
      messageType: MessageType.voice,
      voiceUrl: filePath,
      replyToId: replyId,
      replyToSender: replySender,
      replyToText: replyText,
    );

    setState(() {
      _replyingToMessage = null;
      _optimisticMessages.add(localMessage);
    });

    _scrollToBottom();

    try {
      final publicUrl = await SupabaseWeddingRepository.instance.uploadVoiceMessage(filePath);
      
      await SupabaseWeddingRepository.instance.sendChatMessage(
        '',
        replyToId: replyId,
        replyToSender: replySender,
        replyToText: replyText,
        voiceUrl: publicUrl,
      );

      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      setState(() {
        _failedMessageIds.add(tempId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send voice message: $e')),
        );
      }
    }
  }

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
            _SourceTile(
              icon: Icons.camera_alt_rounded,
              label: 'Take a Photo',
              subtitle: 'Open camera',
              color: RodMaeColors.sky,
              isDark: isDark,
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            const SizedBox(height: 12),
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

  Future<void> _sendLocationMessage() async {
    if (!mounted) return;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _LocationConfirmSheet(
        onConfirm: () => Navigator.pop(ctx, true),
        onCancel: () => Navigator.pop(ctx, false),
      ),
    );
    if (confirmed != true || !mounted) return;

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

    String address = 'Sharing current location...';
    try {
      final placemarks = await placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final place = placemarks.first;
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
      address = '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }

    if (!mounted) return;

    final replyId = _replyingToMessage?.id;
    final replySender = _replyingToMessage?.sender;
    final replyText = _replyingToMessage?.message;

    final now = DateTime.now();
    final tempId = '-temp_${now.microsecondsSinceEpoch}';
    final msg = ChatMessage(
      id: tempId,
      sender: PartnerIdentity.active.value.label,
      message: address,
      createdAt: now,
      status: MessageStatus.sent,
      messageType: MessageType.location,
      locationData: '$lat,$lng,$address',
      replyToId: replyId,
      replyToSender: replySender,
      replyToText: replyText,
    );

    setState(() {
      _replyingToMessage = null;
      _optimisticMessages.add(msg);
    });

    _scrollToBottom();

    try {
      await SupabaseWeddingRepository.instance.sendRichMessage(msg);
    } catch (_) {
      setState(() {
        _failedMessageIds.add(tempId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send location.')),
        );
      }
    }
  }

  Future<void> _sendLoveSignalFromChat() async {
    if (!mounted) return;

    // Play tactile haptic feedback
    HapticFeedback.heavyImpact();

    // Trigger active visual overlay state immediately
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

    // Start animation controller immediately
    _lottieController.duration = const Duration(milliseconds: 4200);
    _lottieController
      ..reset()
      ..forward();

    final replyId = _replyingToMessage?.id;
    final replySender = _replyingToMessage?.sender;
    final replyText = _replyingToMessage?.message;

    final tempId = '-temp_${DateTime.now().microsecondsSinceEpoch}';
    final msg = ChatMessage(
      id: tempId,
      sender: PartnerIdentity.active.value.label,
      message: 'Sending love to you 💕',
      createdAt: DateTime.now(),
      status: MessageStatus.sent,
      messageType: MessageType.love,
      replyToId: replyId,
      replyToSender: replySender,
      replyToText: replyText,
    );
    setState(() {
      _replyingToMessage = null;
      _optimisticMessages.add(msg);
    });

    _scrollToBottom();

    try {
      await SupabaseWeddingRepository.instance.sendRichMessage(msg);
    } catch (_) {
      setState(() {
        _failedMessageIds.add(tempId);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to send love signal.')),
        );
      }
    }
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

              // Bulk messages seen marking is removed in favor of ViewportIntersectionObserver.

              final activeOptimistic = _optimisticMessages.where((opt) {
                final isAlreadySaved = base.any((b) => _isOptimisticMatch(opt, b));
                return !isAlreadySaved;
              }).toList();

              final allMessages = [
                ...base,
                ...activeOptimistic,
              ];

              final uniqueMessages = <ChatMessage>[];
              for (final msg in allMessages) {
                if (!uniqueMessages.any((x) => x.id == msg.id)) {
                  uniqueMessages.add(msg);
                }
              }

              uniqueMessages.sort((a, b) => a.createdAt.compareTo(b.createdAt));

              if (uniqueMessages.isEmpty) {
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

              // Find the oldest unread message from the partner
              String? oldestUnreadPartnerMessageId;
              for (final msg in uniqueMessages) {
                if (msg.sender.toLowerCase() != myLabel &&
                    msg.status != MessageStatus.seen) {
                  oldestUnreadPartnerMessageId = msg.id;
                  break;
                }
              }

              final listItems = <dynamic>[];
              DateTime? lastTimestamp;
              bool unreadDividerInserted = false;

              for (final msg in uniqueMessages) {
                // Insert the unread messages divider exactly before the oldest unread message from the partner
                if (!unreadDividerInserted && msg.id == oldestUnreadPartnerMessageId) {
                  listItems.add('UNREAD_SEPARATOR');
                  unreadDividerInserted = true;
                }

                final currentTimestamp = msg.createdAt;
                bool showSeparator = false;
                bool sameDay = false;

                if (lastTimestamp == null) {
                  showSeparator = true;
                } else {
                  final diff = currentTimestamp.difference(lastTimestamp).abs();
                  final isSameDay = currentTimestamp.day == lastTimestamp.day &&
                      currentTimestamp.month == lastTimestamp.month &&
                      currentTimestamp.year == lastTimestamp.year;
                  if (!isSameDay || diff.inMinutes > 20) {
                    showSeparator = true;
                    if (isSameDay) {
                      sameDay = true;
                    }
                  }
                }

                if (showSeparator) {
                  listItems.add(ChatSeparatorData(timestamp: currentTimestamp, showTimeOnly: sameDay));
                }
                listItems.add(msg);
                lastTimestamp = currentTimestamp;
              }

              final renderedItems = listItems.reversed.toList();

              String? latestMineId;
              for (int i = uniqueMessages.length - 1; i >= 0; i--) {
                if (uniqueMessages[i].sender.toLowerCase() == myLabel) {
                  latestMineId = uniqueMessages[i].id;
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
                    reverse: true,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    itemCount: renderedItems.length,
                    itemBuilder: (context, index) {
                      final item = renderedItems[index];
                      if (item is ChatSeparatorData) {
                        return ChatDateSeparator(
                          date: item.timestamp,
                          showTimeOnly: item.showTimeOnly,
                          isDark: isDark,
                        );
                      }
                      if (item == 'UNREAD_SEPARATOR') {
                        return UnreadMessagesDivider(isDark: isDark);
                      }

                      final msg = item as ChatMessage;
                      final isLatestFromMe = msg.id == latestMineId &&
                          msg.sender.toLowerCase() == myLabel;
                      final isSendingError = _failedMessageIds.contains(msg.id);

                      final bubble = ChatBubble(
                        message: msg,
                        isLatestFromMe: isLatestFromMe,
                        partnerAvatarUrl: _partnerAvatarUrl,
                        myAvatarUrl: _myAvatarUrl,
                        isSendingError: isSendingError,
                        onTapError: () => _retryMessage(msg),
                        onReply: (repliedMsg) {
                          setState(() {
                            _replyingToMessage = repliedMsg;
                          });
                          _chatFocusNode.requestFocus();
                        },
                        onEditRequested: (editingMsg) {
                          setState(() {
                            _editingMessage = editingMsg;
                            _chatController.text = editingMsg.message;
                            _replyingToMessage = null; // cancel reply if editing
                          });
                          _chatFocusNode.requestFocus();
                        },
                      );

                      final isSpouse = msg.sender.toLowerCase() != myLabel;
                      final isUnread = isSpouse && msg.status != MessageStatus.seen;

                      if (isUnread) {
                        return ViewportIntersectionObserver(
                          scrollController: _scrollController,
                          onEnteringViewport: () {
                            unawaited(NotificationService.markMessageAsSeen(msg.id, type: 'chat'));
                          },
                          child: bubble,
                        );
                      }
                      return bubble;
                    },
                  ),
                ),
              );
            },
          ),
        ),
        ChatTypingIndicator(
          isTyping: _isPartnerTyping || _isAssistantTyping || _isFinancesTyping,
          isDark: isDark,
          partnerName: _isFinancesTyping
              ? 'Tarsi (Finances)'
              : (_isAssistantTyping
                  ? 'AI Assistant'
                  : (PartnerIdentity.active.value == PartnerProfile.rodel ? 'Eurine' : 'Rodel')),
        ),
        if (_showAssistantSuggestion)
          _buildAssistantSuggestionOverlay(isDark),
        ChatComposer(
          controller: _chatController,
          sending: _sendingChat,
          onSend: _sendMessage,
          onSpecialAction: _onSpecialAction,
          onChanged: _onChatInputChanged,
          focusNode: _chatFocusNode,
          hasKeyboard: hasKeyboard,
          replyToMessage: _replyingToMessage,
          onCancelReply: () {
            setState(() {
              _replyingToMessage = null;
            });
          },
          editingMessage: _editingMessage,
          onCancelEdit: () {
            setState(() {
              _editingMessage = null;
              _chatController.clear();
            });
          },
          onVoiceRecorded: _sendVoiceMessage,
        ),
      ],
    );
  }

  Widget _buildAssistantSuggestionOverlay(bool isDark) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? RodMaeColors.navy : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: RodMaeColors.sky.withValues(alpha: 0.25),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: RodMaeColors.sky.withValues(alpha: 0.15),
              child: const Icon(Icons.psychology_rounded, color: RodMaeColors.sky, size: 16),
            ),
            title: Text(
              '@assistant (AI Assistant)',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : RodMaeColors.lightText,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            onTap: () {
              setState(() {
                _showAssistantSuggestion = false;
                final currentText = _chatController.text;
                if (currentText.endsWith('@')) {
                  _chatController.text = '${currentText.substring(0, currentText.length - 1)}@assistant ';
                } else {
                  _chatController.text = '$currentText@assistant ';
                }
                _chatController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _chatController.text.length),
                );
              });
            },
          ),
          const Divider(height: 1, indent: 40),
          ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: RodMaeColors.gold.withValues(alpha: 0.15),
              child: const Icon(Icons.account_balance_wallet_rounded, color: RodMaeColors.gold, size: 16),
            ),
            title: Text(
              '@finances (Financial Advisor)',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white : RodMaeColors.lightText,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            onTap: () {
              setState(() {
                _showAssistantSuggestion = false;
                final currentText = _chatController.text;
                if (currentText.endsWith('@')) {
                  _chatController.text = '${currentText.substring(0, currentText.length - 1)}@finances ';
                } else {
                  _chatController.text = '$currentText@finances ';
                }
                _chatController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _chatController.text.length),
                );
              });
            },
          ),
        ],
      ),
    );
  }

  // ── Notes tab ──────────────────────────────────────────────────────────────

  Widget _buildNotesTab(bool isDark) {
    return Column(
      children: [
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
                                  Row(
                                    children: [
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
                                  Text(
                                    TimeUtils.formatDateTimeFromDateTime(note.createdAt),
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
                        _SenderAvatar(
                          avatarUrl: senderAvatarUrl,
                          initial: sig.sender.isNotEmpty ? sig.sender[0] : '?',
                          color: color,
                          radius: 18,
                        ),
                        const SizedBox(width: 12),
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
                                TimeUtils.formatDateTimeFromDateTime(sig.createdAt),
                                style: GoogleFonts.robotoMono(
                                  color: isDark ? Colors.white38 : Colors.black38,
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

class ChatSeparatorData {
  final DateTime timestamp;
  final bool showTimeOnly;
  const ChatSeparatorData({required this.timestamp, required this.showTimeOnly});
}

class ChatDateSeparator extends StatelessWidget {
  final DateTime date;
  final bool showTimeOnly;
  final bool isDark;

  const ChatDateSeparator({
    required this.date,
    this.showTimeOnly = false,
    required this.isDark,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final text = showTimeOnly
        ? TimeUtils.formatChatTimeFromDateTime(date)
        : TimeUtils.formatDateSeparatorFromDateTime(date);

    final lineColor = isDark ? Colors.white10 : Colors.black12;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                color: lineColor,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                text,
                style: GoogleFonts.inter(
                  color: isDark ? Colors.white38 : Colors.black45,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                color: lineColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UnreadMessagesDivider extends StatelessWidget {
  final bool isDark;

  const UnreadMessagesDivider({required this.isDark, super.key});

  @override
  Widget build(BuildContext context) {
    final lineColor = isDark 
        ? const Color(0xFFEF4444).withValues(alpha: 0.5) 
        : const Color(0xFFEF4444).withValues(alpha: 0.3);
    final textColor = isDark 
        ? const Color(0xFFFCA5A5) 
        : const Color(0xFFB91C1C);

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [lineColor.withValues(alpha: 0.0), lineColor],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Unread messages',
                style: GoogleFonts.inter(
                  color: textColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Expanded(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [lineColor, lineColor.withValues(alpha: 0.0)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ViewportIntersectionObserver extends StatefulWidget {
  final Widget child;
  final ScrollController scrollController;
  final VoidCallback onEnteringViewport;

  const ViewportIntersectionObserver({
    required this.child,
    required this.scrollController,
    required this.onEnteringViewport,
    super.key,
  });

  @override
  State<ViewportIntersectionObserver> createState() => _ViewportIntersectionObserverState();
}

class _ViewportIntersectionObserverState extends State<ViewportIntersectionObserver> {
  bool _hasTriggered = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_checkVisibility);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkVisibility());
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_checkVisibility);
    super.dispose();
  }

  void _checkVisibility() {
    if (!mounted || _hasTriggered) return;

    final context = this.context;
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final position = renderBox.localToGlobal(Offset.zero);
    final viewportHeight = MediaQuery.sizeOf(context).height;

    final height = renderBox.size.height;
    final top = position.dy;
    final bottom = position.dy + height;

    final isVisible = (top >= 0 && top <= viewportHeight) || 
                      (bottom >= 0 && bottom <= viewportHeight) ||
                      (top < 0 && bottom > viewportHeight);

    if (isVisible) {
      _hasTriggered = true;
      widget.scrollController.removeListener(_checkVisibility);
      widget.onEnteringViewport();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class MentionTextEditingController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    final List<TextSpan> children = [];
    
    final regex = RegExp(r'@assistant\b', caseSensitive: false);
    
    int lastIndex = 0;
    for (final match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        children.add(TextSpan(
          text: text.substring(lastIndex, match.start),
        ));
      }
      
      final matchedText = match.group(0)!;
      children.add(TextSpan(
        text: matchedText,
        style: const TextStyle(
          color: Color(0xFF10B981),
          fontWeight: FontWeight.bold,
          backgroundColor: Color(0x2610B981),
        ),
      ));
      
      lastIndex = match.end;
    }
    
    if (lastIndex < text.length) {
      children.add(TextSpan(
        text: text.substring(lastIndex),
      ));
    }
    
    return TextSpan(children: children, style: style);
  }
}
