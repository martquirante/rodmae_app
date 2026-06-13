import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../core/constants.dart';
import '../models/chat_message.dart';
import '../models/transaction.dart';
import '../services/ai_service.dart';
import '../services/finance_repository.dart';
import '../services/auth_service.dart';

class FinancialAiChatScreen extends StatefulWidget {
  const FinancialAiChatScreen({super.key});

  @override
  State<FinancialAiChatScreen> createState() => _FinancialAiChatScreenState();
}

class _FinancialAiChatScreenState extends State<FinancialAiChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  
  bool _isAiTyping = false;
  bool _simulatingVoice = false;
  String _voiceTranscriptionSample = '';
  late AnimationController _pulsateController;

  final List<String> _voiceSamples = [
    "Love, mag-log nga po ng expense na 450 pesos para sa dinner natin gamit ang GCash.",
    "Log income: 25000 pesos from salary inside Rodel's Account.",
    "Bumili ako ng groceries kanina sa supermarket nagkakahalaga ng 1250 pesos gamit ang Shared Vault.",
    "Paki-log nga yung date night natin 850 pesos gamit ang GCash.",
    "Spent 350 for gas kanina gamit ang Rodel's Cash.",
  ];

  @override
  void initState() {
    super.initState();
    _pulsateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );

    // Initial greeting
    _messages.add(
      ChatMessage(
        id: 'greet-1',
        sender: 'Tarsi',
        message: "Hello love! 💑 Ako ang inyong Personal Finance AI Assistant. \n\nMagtanong tungkol sa inyong shared balance, expenses, o magsabi lang ng like: *\"Log 500 for groceries using Shared Vault\"* at ako na ang kusang maglilista nito para sa inyo! ✨📈",
        createdAt: DateTime.now(),
        assistant: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _pulsateController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _startVoiceSimulation() async {
    if (_simulatingVoice) return;

    final randomSample = _voiceSamples[Random().nextInt(_voiceSamples.length)];
    setState(() {
      _simulatingVoice = true;
      _voiceTranscriptionSample = "Listening...";
    });
    
    _pulsateController.repeat(reverse: true);

    // After 1 second, simulate partial transcription
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;
    setState(() {
      _voiceTranscriptionSample = "... \"$randomSample\" ...";
    });

    // After another 1 second, submit
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    _pulsateController.stop();
    setState(() {
      _simulatingVoice = false;
    });

    _sendMessage(randomSample);
  }

  Future<void> _sendMessage(String text) async {
    if (text.trim().isEmpty) return;

    final userMsg = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: PartnerIdentity.active.value.label,
      message: text,
      createdAt: DateTime.now(),
    );

    setState(() {
      _messages.add(userMsg);
      _isAiTyping = true;
    });

    _controller.clear();
    _scrollToBottom();

    try {
      // 1. Fetch live couple context
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
      final aiResponse = await AiService.generateFinancialResponse(text, contextBuffer.toString());

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

      final aiMsg = ChatMessage(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        sender: 'Tarsi',
        message: displayResponse,
        createdAt: DateTime.now(),
        assistant: true,
      );

      if (mounted) {
        setState(() {
          _messages.add(aiMsg);
          _isAiTyping = false;
        });
        _scrollToBottom();
      }

      // 4. Handle auto-logging
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
            // Default to Shared Vault for family tracking
            walletId = 'shared-wallet';
          }

          final loggedTx = Transaction(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            walletId: walletId,
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
    } catch (error) {
      debugPrint("Tarsi Chat Error: $error");
      if (mounted) {
        setState(() {
          _isAiTyping = false;
          _messages.add(
            ChatMessage(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              sender: 'Tarsi',
              message: "Sorry love, medyo offline ako ngayon. Paki-check ang network or try again later! 🥺💕",
              createdAt: DateTime.now(),
              assistant: true,
            ),
          );
        });
        _scrollToBottom();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: RodMaeColors.getAppBackground(isDark),
            ),
          ),
          
          // Chat View
          SafeArea(
            child: Column(
              children: [
                // Premium Header
                _buildHeader(context, isDark),
                
                // Chat Bubbles List
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    physics: const BouncingScrollPhysics(),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];
                      return _buildChatBubble(message, isDark);
                    },
                  ),
                ),
                
                // Typing Indicator
                if (_isAiTyping) _buildTypingIndicator(isDark),
                
                // Input Bar
                _buildInputBar(isDark),
              ],
            ),
          ),

          // Dictation Wave Overlay
          if (_simulatingVoice) _buildVoiceOverlay(isDark),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.white24,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white12 : Colors.black12,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white : RodMaeColors.navy,
              size: 20,
            ),
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            backgroundColor: RodMaeColors.gold.withValues(alpha: 0.15),
            radius: 20,
            child: const Icon(
              Icons.psychology_rounded,
              color: RodMaeColors.gold,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Talk with Tarsi',
                  style: GoogleFonts.inter(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: isDark ? Colors.white : RodMaeColors.navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Personal Finance AI Assistant',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: RodMaeColors.mint,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatBubble(ChatMessage message, bool isDark) {
    final isMe = !message.assistant && message.sender.toLowerCase() != 'tarsi';
    final accentColor = isMe ? RodMaeColors.electricBlue : RodMaeColors.gold;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe
              ? (isDark ? RodMaeColors.navy.withValues(alpha: 0.8) : Colors.white.withValues(alpha: 0.9))
              : (isDark ? const Color(0xFF0F1B44).withValues(alpha: 0.85) : Colors.amber.shade50.withValues(alpha: 0.9)),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
            bottomRight: isMe ? Radius.zero : const Radius.circular(18),
          ),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.25),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_rounded, color: RodMaeColors.gold, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'TARSI AI',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: RodMaeColors.gold,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            if (!isMe) const SizedBox(height: 6),
            Text(
              message.message,
              style: GoogleFonts.inter(
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.white : RodMaeColors.navy,
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(
                Formatters.time(message.createdAt),
                style: GoogleFonts.inter(
                  fontSize: 9,
                  color: isDark ? Colors.white30 : Colors.black38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, bottom: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Text(
              'Tarsi is typing',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: RodMaeColors.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: RodMaeColors.gold,
                backgroundColor: RodMaeColors.gold.withValues(alpha: 0.2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black38 : Colors.white70,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white10 : Colors.black12,
          ),
        ),
      ),
      child: Row(
        children: [
          // Voice Dictation Button (Gold-glowing microphone)
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: isDark
                  ? RodMaeColors.goldGlow(intensity: 0.3)
                  : [
                      BoxShadow(
                        color: RodMaeColors.gold.withValues(alpha: 0.2),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ],
            ),
            child: CircleAvatar(
              backgroundColor: RodMaeColors.gold,
              child: IconButton(
                onPressed: _startVoiceSimulation,
                icon: const Icon(
                  Icons.mic_rounded,
                  color: RodMaeColors.navy,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Text Input Field
          Expanded(
            child: TextField(
              controller: _controller,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: isDark ? Colors.white : RodMaeColors.navy,
              ),
              decoration: InputDecoration(
                hintText: "Magsabi kay Tarsi...",
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: RodMaeColors.gold, width: 1.5),
                ),
              ),
              onSubmitted: _sendMessage,
            ),
          ),
          const SizedBox(width: 10),
          
          // Send Button
          CircleAvatar(
            backgroundColor: RodMaeColors.electricBlue,
            child: IconButton(
              onPressed: () => _sendMessage(_controller.text),
              icon: const Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoiceOverlay(bool isDark) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Wave pulse animation
            AnimatedBuilder(
              animation: _pulsateController,
              builder: (context, child) {
                final scale = 1.0 + (_pulsateController.value * 0.25);
                final opacity = 0.8 - (_pulsateController.value * 0.5);
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: RodMaeColors.gold.withValues(alpha: opacity.clamp(0.0, 1.0)),
                      ),
                      transform: Matrix4.identity()..scale(scale, scale),
                    ),
                    Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: RodMaeColors.gold,
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: RodMaeColors.navy,
                        size: 44,
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 36),
            Text(
              "Tarsi is listening...",
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                _voiceTranscriptionSample,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                  color: RodMaeColors.gold,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Speak clearly into your phone",
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white30,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
