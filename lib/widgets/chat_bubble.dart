import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/chat_message.dart';

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  const ChatBubble({
    required this.message,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final sender = message.sender.toLowerCase();
    final isRodel = sender.contains('rodel');
    final isMary = sender.contains('mary') || sender.contains('mae');
    final align = isRodel ? Alignment.centerRight : Alignment.centerLeft;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final color = message.assistant
        ? RodMaeColors.violet
        : isRodel
            ? RodMaeColors.sapphire
            : (isDark ? RodMaeColors.charcoal : const Color(0xFFE2E8F0));
    final textColor = (isMary && !isDark && !message.assistant) ? Colors.black87 : Colors.white;
    final timeColor = (isMary && !isDark && !message.assistant) ? Colors.black38 : Colors.white60;
    
    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment:
                isRodel ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  message.sender,
                  style: GoogleFonts.inter(
                    color: message.assistant
                        ? RodMaeColors.gold
                        : (isDark ? Colors.white54 : RodMaeColors.lightTextSoft),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(20),
                    topRight: const Radius.circular(20),
                    bottomLeft: Radius.circular(isRodel ? 20 : 4),
                    bottomRight: Radius.circular(isRodel ? 4 : 20),
                  ),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      message.message,
                      style: GoogleFonts.inter(
                        color: textColor,
                        fontSize: 13,
                        height: 1.45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        Formatters.time(message.createdAt),
                        style: GoogleFonts.inter(
                          color: timeColor,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const ChatComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 94),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const _MiniChatAction(icon: Icons.image_outlined, label: 'Image'),
                const SizedBox(width: 8),
                const _MiniChatAction(icon: Icons.location_on_outlined, label: 'Loc'),
                const SizedBox(width: 8),
                const _MiniChatAction(icon: Icons.favorite_border, label: 'Love'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    decoration: const InputDecoration(
                      hintText: 'Direct message to spouse or @assistant...',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FloatingActionButton.small(
                  onPressed: sending ? null : onSend,
                  backgroundColor: RodMaeColors.electricBlue,
                  foregroundColor: Colors.white,
                  child: sending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChatAction extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MiniChatAction({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: isDark ? Colors.white60 : RodMaeColors.lightTextSoft, size: 15),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.inter(
                color: isDark ? Colors.white60 : RodMaeColors.lightTextSoft,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
