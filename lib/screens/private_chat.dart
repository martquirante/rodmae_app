import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
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

class _PrivateChatScreenState extends State<PrivateChatScreen> with SingleTickerProviderStateMixin {
  int _tab = 0;
  final _chatController = TextEditingController();
  final _noteController = TextEditingController();
  final _pendingMessages = <ChatMessage>[];
  bool _sendingChat = false;
  bool _sendingNote = false;

  // Custom animations for sender notes
  LoveTrigger? _activeTrigger;
  late final AnimationController _lottieController;



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

    AppNotificationNavigation.privateChatTabNotifier.value = _tab;
    AppNotificationNavigation.privateChatTabNotifier.addListener(_onPrivateChatTabChanged);
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
    AppNotificationNavigation.privateChatTabNotifier.removeListener(_onPrivateChatTabChanged);
    _chatController.dispose();
    _noteController.dispose();
    _lottieController.dispose();
    super.dispose();
  }



  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _sendingChat) {
      return;
    }
    setState(() => _sendingChat = true);
    _chatController.clear();

    final localMessage = ChatMessage(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sender: PartnerIdentity.active.value.label,
      message: text,
      createdAt: DateTime.now(),
    );

    try {
      await SupabaseWeddingRepository.instance.sendChatMessage(text);
      if (!AppRuntime.supabaseReady) {
        setState(() => _pendingMessages.add(localMessage));
      }
    } catch (error) {
      setState(() => _pendingMessages.add(localMessage));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message saved locally (Offline).')),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingChat = false);
      }
    }
  }

  Future<void> _sendNote() async {
    final text = _noteController.text.trim();
    if (text.isEmpty || _sendingNote) {
      return;
    }
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
      if (mounted) {
        setState(() => _sendingNote = false);
      }
    }
  }

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
                    AppNotificationNavigation.privateChatTabNotifier.value = value;
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

  Widget _buildChatTab(bool isDark) {
    return Column(
      children: [
        Expanded(
          child: StreamBuilder<List<ChatMessage>>(
            stream: SupabaseWeddingRepository.instance.watchChat(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
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
                          color: isDark ? Colors.white54 : RodMaeColors.lightTextSoft,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              }

              return ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  return ChatBubble(message: messages[index]);
                },
              );
            },
          ),
        ),
        ChatComposer(
          controller: _chatController,
          sending: _sendingChat,
          onSend: _sendMessage,
        ),
      ],
    );
  }

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
                    const Icon(Icons.sticky_note_2_rounded, color: RodMaeColors.gold, size: 20),
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
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: RodMaeColors.gold),
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
            stream: SupabaseWeddingRepository.instance.watchNotes(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
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

              return ListView.builder(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
                itemCount: notes.length,
                itemBuilder: (context, index) {
                  final note = notes[index];
                  final isMe = note.sender.toLowerCase() == PartnerIdentity.active.value.label.toLowerCase();
                  
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
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: isMe ? RodMaeColors.sky : RodMaeColors.gold,
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
                                      color: isMe ? RodMaeColors.sky : RodMaeColors.gold,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                Formatters.date(note.createdAt),
                                style: GoogleFonts.robotoMono(
                                  color: isDark ? Colors.white30 : Colors.black38,
                                  fontSize: 9,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '"${note.content}"',
                            style: GoogleFonts.playfairDisplay(
                              color: isDark ? Colors.white : RodMaeColors.lightText,
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
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSignalsTab(bool isDark) {
    return StreamBuilder<List<LoveTriggerEvent>>(
      stream: SupabaseWeddingRepository.instance.watchLoveTriggers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
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

        return ListView.builder(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 100),
          itemCount: signals.length,
          itemBuilder: (context, index) {
            final sig = signals[index];
            final isMe = sig.sender.toLowerCase() == PartnerIdentity.active.value.label.toLowerCase();
            
            IconData icon = Icons.favorite_rounded;
            Color color = RodMaeColors.rose;
            String text = '';

            switch (sig.triggerType) {
              case 'Miss You':
                icon = Icons.favorite_rounded;
                color = RodMaeColors.rose;
                text = isMe ? 'You sent a Hearts Shower' : '${sig.sender} sent a Hearts Shower';
                break;
              case 'I Love You':
                icon = Icons.favorite_rounded;
                color = RodMaeColors.rose;
                text = isMe ? 'You declared: "I Love You!" ❤️' : '${sig.sender} declared: "I Love You!" ❤️';
                break;
              case 'Heading Home':
                icon = Icons.navigation_rounded;
                color = RodMaeColors.mint;
                text = isMe ? 'You shared your route home' : '${sig.sender} shared route home';
                break;
              case 'Flying Kiss':
                icon = Icons.favorite_border_rounded;
                color = RodMaeColors.gold;
                text = isMe ? 'You blew a Flying Kiss' : '${sig.sender} blew a Flying Kiss';
                break;
              case 'Surprise Note':
                icon = Icons.sticky_note_2_rounded;
                color = RodMaeColors.electricBlue;
                text = isMe ? 'You sent a Sweet Note' : '${sig.sender} sent a Sweet Note';
                break;
              default:
                icon = Icons.favorite_rounded;
                color = RodMaeColors.rose;
                text = '${sig.sender} triggered love signal: ${sig.triggerType}';
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GlassCard(
                borderColor: color.withValues(alpha: 0.18),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                              color: isDark ? Colors.white : RodMaeColors.lightText,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            Formatters.date(sig.createdAt),
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
        );
      },
    );
  }
}
