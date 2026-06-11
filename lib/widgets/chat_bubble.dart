import 'dart:io';
import 'dart:ui';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../core/time_utils.dart';
import '../models/chat_message.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'advanced_loading_effect.dart';
import 'glass_card.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:audioplayers/audioplayers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ChatBubble — Messenger-style bubble with read receipts + rich content types
// ─────────────────────────────────────────────────────────────────────────────

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  /// Whether this is the *most recent* message sent by the local user.
  /// Only the latest message shows the receipt indicator (like Messenger).
  final bool isLatestFromMe;

  /// Partner's avatar URL for the 'seen' read receipt mini avatar.
  final String? partnerAvatarUrl;

  /// Current user's avatar URL for showing profile pictures in details.
  final String? myAvatarUrl;

  /// Callback when swiped to reply.
  final void Function(ChatMessage)? onReply;

  /// Callback when error icon is tapped (for retry).
  final VoidCallback? onTapError;

  /// Whether this message failed to send.
  final bool isSendingError;

  /// Callback when user wants to edit their message.
  final void Function(ChatMessage)? onEditRequested;

  const ChatBubble({
    required this.message,
    this.isLatestFromMe = false,
    this.partnerAvatarUrl,
    this.myAvatarUrl,
    this.onReply,
    this.isSendingError = false,
    this.onTapError,
    this.onEditRequested,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final sender = message.sender.toLowerCase();
    final myLabel = PartnerIdentity.active.value.label.toLowerCase();
    final isMe = sender == myLabel;
    final align   = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final isAssistant = message.assistant;

    final Color bubbleColor;
    if (isAssistant) {
      bubbleColor = isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5);
    } else if (isMe) {
      bubbleColor = RodMaeColors.sapphire;
    } else {
      bubbleColor = isDark ? RodMaeColors.charcoal : const Color(0xFFE2E8F0);
    }

    final Color textColor;
    if (isAssistant) {
      textColor = isDark ? const Color(0xFFD1FAE5) : const Color(0xFF065F46);
    } else if (!isMe && !isDark) {
      textColor = Colors.black87;
    } else {
      textColor = Colors.white;
    }

    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!isMe) ...[
                _buildAvatar(context, isDark),
                const SizedBox(width: 8),
              ],
              if (isSendingError && !isMe) ...[
                GestureDetector(
                  onTap: onTapError,
                  child: const Tooltip(
                    message: 'Failed to send. Tap to retry.',
                    child: Icon(Icons.error_outline, color: RodMaeColors.coral, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment:
                      isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    // ── Sender label ─────────────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Text(
                        message.sender,
                        style: GoogleFonts.inter(
                          color: isAssistant
                              ? const Color(0xFF10B981)
                              : (isDark ? Colors.white54 : RodMaeColors.lightTextSoft),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),

                    // ── Reply reference (if this message is a reply) ──────────────
                    if (message.replyToId != null) ...[
                      _buildReplyReference(isMe, isDark),
                      const SizedBox(height: 2),
                    ],

                    // ── Original message reference (if this message is edited) ────
                    if (!message.isDeleted &&
                        message.isEdited &&
                        message.originalMessage != null &&
                        message.originalMessage!.isNotEmpty) ...[
                      _buildOriginalMessagePreview(isMe, isDark),
                      const SizedBox(height: 2),
                    ],

                    // ── Bubble with Swipe & Reactions ─────────────────────────────
                    if (message.isDeleted)
                      _buildDeletedBubble(isMe, isDark)
                    else
                      SwipeToReply(
                        onReply: () => onReply?.call(message),
                        isMe: isMe,
                        child: GestureDetector(
                          onLongPress: () => _showMessageMenu(context),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              _buildBubbleContent(
                                context,
                                isDark: isDark,
                                bubbleColor: bubbleColor,
                                textColor: textColor,
                                isMe: isMe,
                              ),
                              _buildReactionsPill(context, isMe),
                            ],
                          ),
                        ),
                      ),
                    if (isMe)
                      _buildExternalStatusRow(context, isDark)
                    else
                      _buildIncomingExternalStatusRow(context, isDark),
                  ],
                ),
              ),
              if (isSendingError && isMe) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onTapError,
                  child: const Tooltip(
                    message: 'Failed to send. Tap to retry.',
                    child: Icon(Icons.error_outline, color: RodMaeColors.coral, size: 20),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReplyReference(bool isMe, bool isDark) {
    final senderName = message.replyToSender ?? 'Spouse';
    final text = message.replyToText ?? '';
    return Container(
      margin: EdgeInsets.only(
        left: isMe ? 40 : 4,
        right: isMe ? 4 : 40,
        bottom: 2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Replying to $senderName',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionsPill(BuildContext context, bool isMe) {
    if (message.reactions == null || message.reactions!.isEmpty) {
      return const SizedBox.shrink();
    }
    final emojis = message.reactions!.values.toSet().join(' ');
    return Positioned(
      bottom: -6,
      right: isMe ? null : 10,
      left: isMe ? 10 : null,
      child: GestureDetector(
        onTap: () => _showReactionDetails(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.grey[900]!.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24, width: 1),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            emojis,
            style: const TextStyle(fontSize: 10),
          ),
        ),
      ),
    );
  }


  void _showFullEmojiPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final emojis = ['🎉', '🔥', '😮', '💔', '🤔', '🙌', '👀', '✨', '💯', '💩', '🤡', '😭'];
        return GlassCard(
          borderRadius: BorderRadius.circular(24),
          padding: const EdgeInsets.all(16),
          borderColor: Colors.white.withValues(alpha: 0.15),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'More Reactions',
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: emojis.length,
                itemBuilder: (c, idx) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.pop(c);
                      _handleReact(emojis[idx]);
                    },
                    child: Center(
                      child: Text(
                        emojis[idx],
                        style: const TextStyle(fontSize: 26),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _handleReact(String emoji) async {
    final myName = PartnerIdentity.active.value.label;
    final currentReactions = Map<String, String>.from(message.reactions ?? {});
    if (currentReactions[myName] == emoji) {
      currentReactions.remove(myName);
    } else {
      currentReactions[myName] = emoji;
    }
    await SupabaseWeddingRepository.instance.updateMessageReaction(message.id, currentReactions);
  }

  void _showReactionDetails(BuildContext context) {
    final reactions = message.reactions ?? {};
    if (reactions.isEmpty) return;

    final myName = PartnerIdentity.active.value.label;

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Material(
              color: Colors.transparent,
              child: GlassCard(
                borderRadius: BorderRadius.circular(24),
                borderColor: Colors.white.withValues(alpha: 0.15),
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reactions',
                      style: GoogleFonts.playfairDisplay(
                        color: isDark ? Colors.white : RodMaeColors.lightText,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...reactions.entries.map((entry) {
                      final userName = entry.key;
                      final emoji = entry.value;
                      final isCurrentUser = userName == myName;

                      final String? userAvatarUrl;
                      final currentUserProfile = PartnerIdentity.active.value;
                      if (currentUserProfile == PartnerProfile.rodel) {
                        userAvatarUrl = userName.toLowerCase() == 'rodel' 
                            ? myAvatarUrl 
                            : partnerAvatarUrl;
                      } else {
                        userAvatarUrl = userName.toLowerCase() == 'eurine' 
                            ? myAvatarUrl 
                            : partnerAvatarUrl;
                      }

                      final bool hasAvatar = userAvatarUrl != null && userAvatarUrl.isNotEmpty;

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: SizedBox(
                          width: 32,
                          height: 32,
                          child: hasAvatar
                              ? CachedNetworkImage(
                                  imageUrl: userAvatarUrl,
                                  imageBuilder: (context, imageProvider) => CircleAvatar(
                                    radius: 16,
                                    backgroundImage: imageProvider,
                                  ),
                                  placeholder: (context, url) => _buildFallbackSpouseAvatar(),
                                  errorWidget: (context, url, error) => _buildFallbackSpouseAvatar(),
                                )
                              : _buildFallbackSpouseAvatar(),
                        ),
                        title: Text(
                          userName + (isCurrentUser ? ' (You)' : ''),
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white : RodMaeColors.lightText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: isCurrentUser
                            ? Text(
                                'Tap to remove',
                                style: GoogleFonts.inter(
                                  color: RodMaeColors.coral,
                                  fontSize: 10,
                                ),
                              )
                            : null,
                        trailing: Text(
                          emoji,
                          style: const TextStyle(fontSize: 20),
                        ),
                        onTap: isCurrentUser
                            ? () {
                                Navigator.pop(ctx);
                                _handleReact(emoji);
                              }
                            : null,
                      );
                    }).toList(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _showMessageMenu(BuildContext context) {
    final sender = message.sender.toLowerCase();
    final myLabel = PartnerIdentity.active.value.label.toLowerCase();
    final isMe = sender == myLabel;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return GlassCard(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          borderColor: Colors.white.withValues(alpha: 0.15),
          padding: const EdgeInsets.all(24),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Reactions Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildEmojiOptionInSheet(ctx, '❤️'),
                    _buildEmojiOptionInSheet(ctx, '😂'),
                    _buildEmojiOptionInSheet(ctx, '👍'),
                    _buildEmojiOptionInSheet(ctx, '😢'),
                    _buildEmojiOptionInSheet(ctx, '😡'),
                    _buildEmojiOptionInSheet(ctx, '➕', isMore: true),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(color: Colors.white12, height: 1),
                const SizedBox(height: 12),
                
                // 2. Action options list
                if (message.messageType == MessageType.text)
                  ListTile(
                    leading: const Icon(Icons.copy_rounded, color: Colors.white70),
                    title: Text('Copy Text', style: GoogleFonts.inter(color: Colors.white)),
                    onTap: () {
                      Navigator.pop(ctx);
                      Clipboard.setData(ClipboardData(text: message.message));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Message copied to clipboard.')),
                      );
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.reply_rounded, color: Colors.white70),
                  title: Text('Reply', style: GoogleFonts.inter(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(ctx);
                    onReply?.call(message);
                  },
                ),
                if (isMe) ...[
                  if (message.messageType == MessageType.text)
                    ListTile(
                      leading: const Icon(Icons.edit_rounded, color: Colors.white70),
                      title: Text('Edit Message', style: GoogleFonts.inter(color: Colors.white)),
                      onTap: () {
                        Navigator.pop(ctx);
                        onEditRequested?.call(message);
                      },
                    ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    title: Text('Unsend Message', style: GoogleFonts.inter(color: Colors.redAccent, fontWeight: FontWeight.w600)),
                    onTap: () async {
                      Navigator.pop(ctx);
                      try {
                        await SupabaseWeddingRepository.instance.unsendMessage(message.id);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to unsend: $e')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmojiOptionInSheet(BuildContext context, String emoji, {bool isMore = false}) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        if (isMore) {
          _showFullEmojiPicker(context);
        } else {
          _handleReact(emoji);
        }
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Text(
          emoji,
          style: const TextStyle(fontSize: 24),
        ),
      ),
    );
  }

  Widget _buildDeletedBubble(bool isMe, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.black12,
          style: BorderStyle.solid,
          width: 1,
        ),
      ),
      child: Text(
        isMe ? 'You unsent a message' : '${message.sender} unsent a message',
        style: GoogleFonts.inter(
          color: isDark ? Colors.white30 : Colors.black38,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildOriginalMessagePreview(bool isMe, bool isDark) {
    final text = message.originalMessage ?? '';
    return Container(
      margin: EdgeInsets.only(
        left: isMe ? 40 : 4,
        right: isMe ? 4 : 40,
        bottom: 2,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 14,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 4),
              Text(
                'Original Message',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          _buildMessageText(
            text,
            GoogleFonts.inter(
              fontSize: 11,
              fontStyle: FontStyle.italic,
              color: isDark ? Colors.white54 : Colors.black54,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBubbleContent(
    BuildContext context, {
    required bool isDark,
    required Color bubbleColor,
    required Color textColor,
    required bool isMe,
  }) {
    switch (message.messageType) {
      case MessageType.image:
        return _ImageBubble(
          message: message,
          bubbleColor: bubbleColor,
          isMe: isMe,
          isDark: isDark,
        );
      case MessageType.location:
        return _LocationBubble(
          message: message,
          isMe: isMe,
          isDark: isDark,
          senderAvatarUrl: isMe ? myAvatarUrl : partnerAvatarUrl,
        );
      case MessageType.love:
        return _LoveBubble(
          message: message,
          isMe: isMe,
        );
      case MessageType.text:
        return _TextBubble(
          message: message,
          bubbleColor: bubbleColor,
          textColor: textColor,
          isMe: isMe,
        );
      case MessageType.voice:
        return _VoiceBubble(
          message: message,
          bubbleColor: bubbleColor,
          textColor: textColor,
          isMe: isMe,
          isDark: isDark,
        );
    }
  }

  Widget _buildAvatar(BuildContext context, bool isDark) {
    if (message.assistant) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
          border: Border.all(
            color: const Color(0xFF10B981),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.3),
              blurRadius: 6,
              spreadRadius: 1,
            ),
          ],
        ),
        child: const Icon(
          Icons.auto_awesome,
          color: Color(0xFF10B981),
          size: 16,
        ),
      );
    }

    final avatarUrl = partnerAvatarUrl;
    return SizedBox(
      width: 32,
      height: 32,
      child: avatarUrl != null && avatarUrl.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: avatarUrl,
              imageBuilder: (context, imageProvider) => CircleAvatar(
                radius: 16,
                backgroundImage: imageProvider,
              ),
              placeholder: (context, url) => _buildFallbackSpouseAvatar(),
              errorWidget: (context, url, error) => _buildFallbackSpouseAvatar(),
            )
          : _buildFallbackSpouseAvatar(),
    );
  }

  Widget _buildFallbackSpouseAvatar() {
    return Container(
      width: 32,
      height: 32,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [RodMaeColors.rose, RodMaeColors.gold],
        ),
      ),
    );
  }

  Widget _buildExternalStatusRow(BuildContext context, bool isDark) {
    final isOptimistic = message.id.startsWith('-temp_');
    final timeStr = TimeUtils.formatChatTimeFromDateTime(message.createdAt);
    final textStyleColor = isDark ? Colors.white38 : Colors.black45;
    final statusStyleColor = isDark ? Colors.white54 : Colors.black54;

    if (isOptimistic) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, right: 6),
        child: Text(
          '$timeStr • Sending...',
          style: GoogleFonts.inter(
            color: textStyleColor,
            fontSize: 10,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    }

    Widget statusWidget;
    if (message.status == MessageStatus.seen) {
      statusWidget = _buildMiniAvatar(partnerAvatarUrl);
    } else if (message.status == MessageStatus.delivered) {
      statusWidget = Text(
        'Delivered',
        style: GoogleFonts.inter(
          color: statusStyleColor,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      );
    } else { // MessageStatus.sent
      statusWidget = Text(
        'Sent',
        style: GoogleFonts.inter(
          color: textStyleColor,
          fontSize: 10,
          fontWeight: FontWeight.w400,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (message.isEdited) ...[
            Text(
              'Edited • ',
              style: GoogleFonts.inter(
                color: textStyleColor,
                fontSize: 10,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
          Text(
            timeStr,
            style: GoogleFonts.inter(
              color: textStyleColor,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(width: 6),
          statusWidget,
        ],
      ),
    );
  }

  Widget _buildIncomingExternalStatusRow(BuildContext context, bool isDark) {
    final timeStr = TimeUtils.formatChatTimeFromDateTime(message.createdAt);
    final textStyleColor = isDark ? Colors.white38 : Colors.black45;
    final showPfp = message.status == MessageStatus.seen;

    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            timeStr,
            style: GoogleFonts.inter(
              color: textStyleColor,
              fontSize: 10,
              fontWeight: FontWeight.w400,
            ),
          ),
          if (showPfp) ...[
            const SizedBox(width: 6),
            _buildMiniAvatar(myAvatarUrl),
          ],
        ],
      ),
    );
  }

  Widget _buildMiniAvatar(String? url) {
    final hasUrl = url != null && url.isNotEmpty;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: hasUrl
          ? CachedNetworkImage(
              imageUrl: url,
              imageBuilder: (context, imageProvider) => CircleAvatar(
                radius: 7,
                backgroundImage: imageProvider,
              ),
              placeholder: (context, url) => _fallbackMiniAvatar(),
              errorWidget: (context, url, error) => _fallbackMiniAvatar(),
            )
          : _fallbackMiniAvatar(),
    );
  }

  Widget _fallbackMiniAvatar() {
    return Container(
      width: 14,
      height: 14,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [RodMaeColors.rose, RodMaeColors.gold],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// URL detection helper
// ─────────────────────────────────────────────────────────────────────────────

bool _containsUrl(String text) {
  final uri = Uri.tryParse(text.trim());
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
    return true;
  }
  final urlRegex = RegExp(
    r'https?://[^\s/$.?#].[^\s]*',
    caseSensitive: false,
  );
  return urlRegex.hasMatch(text);
}

String? _extractFirstUrl(String text) {
  final trimmed = text.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
    return trimmed;
  }
  final urlRegex = RegExp(
    r'https?://[^\s/$.?#].[^\s]*',
    caseSensitive: false,
  );
  final match = urlRegex.firstMatch(text);
  return match?.group(0);
}

Widget _buildMessageText(
  String text,
  TextStyle baseStyle, {
  int? maxLines,
  TextOverflow? overflow,
}) {
  final regex = RegExp(r'@assistant\b', caseSensitive: false);
  final matches = regex.allMatches(text);
  if (matches.isEmpty) {
    return Text(
      text,
      style: baseStyle,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  final List<InlineSpan> spans = [];
  int lastIndex = 0;
  for (final match in matches) {
    if (match.start > lastIndex) {
      spans.add(TextSpan(
        text: text.substring(lastIndex, match.start),
      ));
    }

    final matchedText = match.group(0)!;
    spans.add(TextSpan(
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
    spans.add(TextSpan(
      text: text.substring(lastIndex),
    ));
  }

  return RichText(
    maxLines: maxLines,
    overflow: overflow ?? TextOverflow.clip,
    text: TextSpan(
      style: baseStyle,
      children: spans,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Text bubble — with automatic URL / link preview
// ─────────────────────────────────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  final ChatMessage message;
  final Color bubbleColor;
  final Color textColor;
  final bool isMe;

  const _TextBubble({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasUrl = _containsUrl(message.message);
    final extractedUrl = hasUrl ? _extractFirstUrl(message.message) : null;
    final isWholeMessageUrl = extractedUrl != null &&
        message.message.trim() == extractedUrl;
    final isAssistant = message.assistant;

    return Container(
      clipBehavior: Clip.antiAlias,
      padding: isWholeMessageUrl
          ? const EdgeInsets.all(1.5)
          : const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
        border: Border.all(
          color: isAssistant
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : Colors.white.withValues(
                  alpha: isDark ? 0.06 : 0.2,
                ),
          width: isAssistant ? 1.5 : 1.0,
        ),
        boxShadow: isAssistant
            ? [
                BoxShadow(
                  color: isDark
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFF10B981).withValues(alpha: 0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isWholeMessageUrl)
            _buildMessageText(
              message.message,
              GoogleFonts.inter(
                color: textColor,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),

          if (extractedUrl != null) ...[
            if (!isWholeMessageUrl) const SizedBox(height: 10),
            _LinkPreviewCard(url: extractedUrl, isDark: isDark),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Link Preview Card — AnyLinkPreview wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _LinkPreviewCard extends StatelessWidget {
  final String url;
  final bool isDark;

  const _LinkPreviewCard({required this.url, required this.isDark});

  Future<void> _launchUrl() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _launchUrl,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AnyLinkPreview(
          link: url,
          displayDirection: UIDirection.uiDirectionVertical,
          showMultimedia: true,
          bodyMaxLines: 2,
          bodyTextOverflow: TextOverflow.ellipsis,
          titleStyle: GoogleFonts.inter(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          bodyStyle: GoogleFonts.inter(
            color: isDark ? Colors.white60 : Colors.black54,
            fontSize: 11,
          ),
          backgroundColor: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.06),
          borderRadius: 12,
          removeElevation: true,
          errorWidget: GestureDetector(
            onTap: _launchUrl,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.link_rounded,
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      url,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        color: RodMaeColors.sky,
                        fontSize: 11,
                        decoration: TextDecoration.underline,
                        decorationColor: RodMaeColors.sky,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    Icons.open_in_new_rounded,
                    size: 13,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ],
              ),
            ),
          ),
          cache: const Duration(hours: 24),
          previewHeight: 160,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image bubble — CachedNetworkImage with shimmer loading
// ─────────────────────────────────────────────────────────────────────────────

class _ImageBubble extends StatelessWidget {
  final ChatMessage message;
  final Color bubbleColor;
  final bool isMe;
  final bool isDark;

  const _ImageBubble({
    required this.message,
    required this.bubbleColor,
    required this.isMe,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final url = message.imageUrl ?? '';
    final isLocalPath = url.startsWith('/');
    final isAssistant = message.assistant;

    Widget mainImage = GestureDetector(
      onTap: () => _openFullscreen(context, url, isLocalPath),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SizedBox(
          width: 220,
          height: 180,
          child: isLocalPath
              ? Image.file(
                  File(url),
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, e, s) => const _ImageErrorWidget(),
                )
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  width: 220,
                  height: 180,
                  placeholder: (context, url) =>
                      const _ImageShimmerWidget(),
                  errorWidget: (context, url, error) =>
                      const _ImageErrorWidget(),
                ),
        ),
      ),
    );

    if (message.message.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          border: Border.all(
            color: isAssistant
                ? const Color(0xFF10B981).withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: isDark ? 0.06 : 0.2),
            width: isAssistant ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isMe ? 20 : 4),
                bottomRight: Radius.circular(isMe ? 4 : 20),
              ),
              child: SizedBox(
                width: 220,
                height: 180,
                child: mainImage,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          border: Border.all(
            color: isAssistant
                ? const Color(0xFF10B981).withValues(alpha: 0.3)
                : Colors.white.withValues(alpha: isDark ? 0.06 : 0.2),
            width: isAssistant ? 1.5 : 1.0,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            mainImage,
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildMessageText(
                    message.message,
                    GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 12,
                      height: 1.4,
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

  void _openFullscreen(BuildContext context, String url, bool isLocal) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenImage(url: url, isLocal: isLocal),
      ),
    );
  }
}

class _ImageShimmerWidget extends StatefulWidget {
  const _ImageShimmerWidget();

  @override
  State<_ImageShimmerWidget> createState() => _ImageShimmerWidgetState();
}

class _ImageShimmerWidgetState extends State<_ImageShimmerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
    _anim = Tween<double>(begin: -1.5, end: 1.5).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Container(
          width: 220,
          height: 180,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(_anim.value - 1, 0),
              end: Alignment(_anim.value + 1, 0),
              colors: const [
                Color(0xFF1A2540),
                Color(0xFF243060),
                Color(0xFF1A2540),
              ],
            ),
          ),
          child: const Center(
            child: Icon(Icons.image_rounded, color: Colors.white24, size: 36),
          ),
        );
      },
    );
  }
}

class _ImageErrorWidget extends StatelessWidget {
  const _ImageErrorWidget();
  @override
  Widget build(BuildContext context) => Container(
        width: 220,
        height: 180,
        color: Colors.black26,
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.broken_image_rounded, color: Colors.white38, size: 40),
            SizedBox(height: 8),
            Text('Image unavailable',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
          ],
        ),
      );
}

class _FullscreenImage extends StatelessWidget {
  final String url;
  final bool isLocal;
  const _FullscreenImage({required this.url, required this.isLocal});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Photo', style: GoogleFonts.inter(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          child: isLocal
              ? Image.file(File(url))
              : CachedNetworkImage(
                  imageUrl: url,
                  placeholder: (ctx, url) => const Center(
                    child: CircularProgressIndicator(color: Colors.white30),
                  ),
                  errorWidget: (ctx, url, err) => const Icon(
                    Icons.broken_image_rounded,
                    color: Colors.white38,
                    size: 48,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pulsing avatar overlay for Live Location indicator
// ─────────────────────────────────────────────────────────────────────────────

class _PulsingAvatarOverlay extends StatefulWidget {
  final String? avatarUrl;
  const _PulsingAvatarOverlay({required this.avatarUrl});

  @override
  State<_PulsingAvatarOverlay> createState() => _PulsingAvatarOverlayState();
}

class _PulsingAvatarOverlayState extends State<_PulsingAvatarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasAvatar = widget.avatarUrl != null && widget.avatarUrl!.isNotEmpty;
    return Center(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final scale = 1.0 + _controller.value * 0.45;
          final opacity = (1.0 - _controller.value).clamp(0.0, 1.0);
          return Stack(
            alignment: Alignment.center,
            children: [
              // Pulsing ring 1
              Container(
                width: 50 * scale,
                height: 50 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RodMaeColors.rose.withValues(alpha: opacity * 0.35),
                ),
              ),
              // Pulsing ring 2
              Container(
                width: 64 * scale,
                height: 64 * scale,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: RodMaeColors.rose.withValues(alpha: opacity * 0.15),
                ),
              ),
              // White border circle
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(2),
                child: hasAvatar
                    ? CachedNetworkImage(
                        imageUrl: widget.avatarUrl!,
                        imageBuilder: (context, imageProvider) => CircleAvatar(
                          backgroundImage: imageProvider,
                        ),
                        placeholder: (context, url) => const CircleAvatar(
                          backgroundColor: RodMaeColors.navy2,
                          child: Icon(Icons.person, color: Colors.white70, size: 20),
                        ),
                        errorWidget: (context, url, error) => const CircleAvatar(
                          backgroundColor: RodMaeColors.navy2,
                          child: Icon(Icons.person, color: Colors.white70, size: 20),
                        ),
                      )
                    : const CircleAvatar(
                        backgroundColor: RodMaeColors.navy2,
                        child: Icon(Icons.person, color: Colors.white70, size: 20),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Location bubble — static map thumbnail + address + navigates to map
// ─────────────────────────────────────────────────────────────────────────────

class _LocationBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isDark;
  final String? senderAvatarUrl;

  const _LocationBubble({
    required this.message,
    required this.isMe,
    required this.isDark,
    this.senderAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    final parts = (message.locationData ?? '').split(',');
    final lat  = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
    final lng  = parts.length > 1 ? double.tryParse(parts[1]) : null;
    final addr = parts.length > 2 ? parts.sublist(2).join(',').trim() : null;
    final hasCoords = lat != null && lng != null;

    final mapUrl = hasCoords
        ? 'https://staticmap.openstreetmap.de/staticmap.php'
          '?center=$lat,$lng&zoom=16&size=320x200&markers=$lat,$lng,none'
        : null;

    return GestureDetector(
      onTap: () {
        if (hasCoords) {
          Navigator.of(context).pushNamed(
            '/map',
            arguments: {
              'autoHeadingHome': false,
              'focusLat': lat,
              'focusLng': lng,
              'focusAddress': addr ?? message.message,
            },
          );
        }
      },
      child: Container(
        width: 280,
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          border: Border.all(
            color: isDark ? Colors.white10 : Colors.black12,
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                if (mapUrl != null)
                  CachedNetworkImage(
                    imageUrl: mapUrl,
                    height: 180,
                    width: 280,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) => _mapPlaceholder(),
                    errorWidget: (ctx, url, err) => _mapPlaceholder(),
                  )
                else
                  _mapPlaceholder(),
                
                if (hasCoords)
                  _PulsingAvatarOverlay(avatarUrl: senderAvatarUrl),

                if (hasCoords)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          color: Colors.black.withValues(alpha: 0.45),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.map_rounded,
                                  size: 12, color: Colors.white),
                              const SizedBox(width: 4),
                              Text(
                                'Open Map',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            Container(
              padding: const EdgeInsets.all(14),
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: RodMaeColors.rose,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          addr ?? message.message,
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white : RodMaeColors.lightText,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'LIVE LOCATION · TAP TO VIEW DETAILS',
                    style: GoogleFonts.inter(
                      color: RodMaeColors.rose,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapPlaceholder() => Container(
        height: 180,
        color: RodMaeColors.navy2,
        child: const Center(
          child: Icon(Icons.map_rounded, color: Colors.white24, size: 44),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Love signal bubble
// ─────────────────────────────────────────────────────────────────────────────

class _LoveBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;

  const _LoveBubble({
    required this.message,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final label = message.message.isNotEmpty ? message.message : '💕 Love Signal';
    final isAssistant = message.assistant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5E8D), Color(0xFFFF8A65)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
        border: isAssistant
            ? Border.all(
                color: const Color(0xFF10B981),
                width: 1.5,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: RodMaeColors.rose.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
          if (isAssistant)
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              blurRadius: 8,
              spreadRadius: 1,
            ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('❤️', style: TextStyle(fontSize: 28)),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.playfairDisplay(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VoiceBubble — Custom inline audio player for voice messages
// ─────────────────────────────────────────────────────────────────────────────

class _VoiceBubble extends StatefulWidget {
  final ChatMessage message;
  final Color bubbleColor;
  final Color textColor;
  final bool isMe;
  final bool isDark;

  const _VoiceBubble({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.isMe,
    required this.isDark,
  });

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  late final AudioPlayer _audioPlayer;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  StreamSubscription? _durationSub;
  StreamSubscription? _positionSub;
  StreamSubscription? _stateSub;
  StreamSubscription? _completeSub;

  @override
  void initState() {
    super.initState();
    _audioPlayer = AudioPlayer();

    final url = widget.message.voiceUrl;
    if (url != null && url.isNotEmpty) {
      final source = url.startsWith('http://') || url.startsWith('https://')
          ? UrlSource(url)
          : DeviceFileSource(url);
      _audioPlayer.setSource(source).catchError((_) {});
    }

    _durationSub = _audioPlayer.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });

    _positionSub = _audioPlayer.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });

    _stateSub = _audioPlayer.onPlayerStateChanged.listen((s) {
      if (mounted) {
        setState(() {
          _isPlaying = s == PlayerState.playing;
        });
      }
    });

    _completeSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _durationSub?.cancel();
    _positionSub?.cancel();
    _stateSub?.cancel();
    _completeSub?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    final url = widget.message.voiceUrl;
    if (url == null || url.isEmpty) return;

    try {
      if (_isPlaying) {
        await _audioPlayer.pause();
      } else {
        final source = url.startsWith('http://') || url.startsWith('https://')
            ? UrlSource(url)
            : DeviceFileSource(url);
        await _audioPlayer.play(source);
      }
    } catch (_) {}
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final activeColor = widget.isMe ? Colors.white : RodMaeColors.electricBlue;
    final inactiveColor = (widget.isMe ? Colors.white : RodMaeColors.electricBlue).withValues(alpha: 0.25);
    final textStyleColor = widget.isMe ? Colors.white70 : Colors.black45;

    final isAssistant = widget.message.assistant;

    return Container(
      width: 240,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: widget.bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(widget.isMe ? 20 : 4),
          bottomRight: Radius.circular(widget.isMe ? 4 : 20),
        ),
        border: Border.all(
          color: isAssistant
              ? const Color(0xFF10B981).withValues(alpha: 0.3)
              : Colors.white.withValues(alpha: widget.isDark ? 0.06 : 0.2),
          width: isAssistant ? 1.5 : 1.0,
        ),
        boxShadow: isAssistant
            ? [
                BoxShadow(
                  color: widget.isDark
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : const Color(0xFF10B981).withValues(alpha: 0.1),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: activeColor,
                    size: 22,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: activeColor,
                        inactiveTrackColor: inactiveColor,
                        thumbColor: activeColor,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                        trackHeight: 3.0,
                        padding: EdgeInsets.zero,
                      ),
                      child: Slider(
                        value: _position.inMilliseconds.toDouble().clamp(
                              0.0,
                              _duration.inMilliseconds > 0
                                  ? _duration.inMilliseconds.toDouble()
                                  : 1.0,
                            ),
                        max: _duration.inMilliseconds > 0
                            ? _duration.inMilliseconds.toDouble()
                            : 1.0,
                        onChanged: (val) {
                          _audioPlayer.seek(Duration(milliseconds: val.toInt()));
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.mic_rounded,
                            size: 10,
                            color: textStyleColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                            style: GoogleFonts.inter(
                              color: textStyleColor,
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatComposer — composer row with Image / Location / Love action buttons
// ─────────────────────────────────────────────────────────────────────────────

class ChatComposer extends StatefulWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final void Function(MessageType type)? onSpecialAction;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool hasKeyboard;
  final ChatMessage? replyToMessage;
  final VoidCallback? onCancelReply;
  final ChatMessage? editingMessage;
  final VoidCallback? onCancelEdit;
  final void Function(String filePath)? onVoiceRecorded;

  const ChatComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.hasKeyboard,
    this.onSpecialAction,
    this.onChanged,
    this.focusNode,
    this.replyToMessage,
    this.onCancelReply,
    this.editingMessage,
    this.onCancelEdit,
    this.onVoiceRecorded,
    super.key,
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> with SingleTickerProviderStateMixin {
  late final AudioRecorder _audioRecorder;
  late final AnimationController _pulseController;
  
  bool _isRecording = false;
  int _recordingDurationSeconds = 0;
  Timer? _recordingTimer;
  String? _tempRecordingPath;
  double _dragPositionX = 0.0;
  bool _cancelTriggered = false;

  @override
  void initState() {
    super.initState();
    _audioRecorder = AudioRecorder();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    
    widget.controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _pulseController.dispose();
    _audioRecorder.dispose();
    _recordingTimer?.cancel();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required to record voice messages.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/voice_msg_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _tempRecordingPath = filePath;

      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: filePath,
      );

      setState(() {
        _isRecording = true;
        _recordingDurationSeconds = 0;
        _dragPositionX = 0.0;
        _cancelTriggered = false;
      });

      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (mounted) {
          setState(() {
            _recordingDurationSeconds++;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
    }
  }

  Future<void> _stopRecording({required bool cancel}) async {
    if (!_isRecording) return;

    try {
      _recordingTimer?.cancel();
      final path = await _audioRecorder.stop();

      final tempPath = _tempRecordingPath;
      _tempRecordingPath = null;

      setState(() {
        _isRecording = false;
      });

      if (cancel) {
        if (tempPath != null) {
          final file = File(tempPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
        return;
      }

      if (_recordingDurationSeconds < 1) {
        if (tempPath != null) {
          final file = File(tempPath);
          if (await file.exists()) {
            await file.delete();
          }
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Message too short.'),
              duration: Duration(seconds: 1),
            ),
          );
        }
        return;
      }

      if (path != null && widget.onVoiceRecorded != null) {
        widget.onVoiceRecorded!(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping recording: $e')),
        );
      }
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = widget.hasKeyboard ? 12.0 : 94.0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final showSend = widget.controller.text.trim().isNotEmpty;

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 8, 18, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.replyToMessage != null && !_isRecording) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.reply_rounded, color: RodMaeColors.sky, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Replying to ${widget.replyToMessage!.sender}',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.replyToMessage!.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: widget.onCancelReply,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 16,
                    ),
                  ],
                ),
              ),
            ],
            if (widget.editingMessage != null && !_isRecording) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.edit_rounded, color: RodMaeColors.gold, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Editing message',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            widget.editingMessage!.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: isDark ? Colors.white.withValues(alpha: 0.87) : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: widget.onCancelEdit,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      splashRadius: 16,
                    ),
                  ],
                ),
              ),
            ],
            if (!_isRecording) ...[
              Row(
                children: [
                  _MiniChatAction(
                    icon: Icons.photo_camera_rounded,
                    label: 'Image',
                    color: RodMaeColors.sky,
                    onTap: () => widget.onSpecialAction?.call(MessageType.image),
                  ),
                  const SizedBox(width: 8),
                  _MiniChatAction(
                    icon: Icons.location_on_outlined,
                    label: 'Location',
                    color: RodMaeColors.mint,
                    onTap: () => widget.onSpecialAction?.call(MessageType.location),
                  ),
                  const SizedBox(width: 8),
                  _MiniChatAction(
                    icon: Icons.favorite_rounded,
                    label: 'Love',
                    color: RodMaeColors.rose,
                    onTap: () => widget.onSpecialAction?.call(MessageType.love),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: _isRecording
                      ? Container(
                          height: 50,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.05)
                                : Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: RodMaeColors.electricBlue.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              AnimatedBuilder(
                                animation: _pulseController,
                                builder: (context, child) {
                                  return Opacity(
                                    opacity: _pulseController.value,
                                    child: Container(
                                      width: 8,
                                      height: 8,
                                      decoration: const BoxDecoration(
                                        color: Colors.redAccent,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _formatDuration(_recordingDurationSeconds),
                                style: GoogleFonts.inter(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Transform.translate(
                                  offset: Offset(_dragPositionX.clamp(-120.0, 0.0), 0.0),
                                  child: Opacity(
                                    opacity: ((100.0 - _dragPositionX.abs()) / 100.0).clamp(0.1, 1.0),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.arrow_back_ios_new_rounded,
                                          size: 11,
                                          color: Colors.grey,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _cancelTriggered ? 'Release to cancel' : 'Slide left to cancel',
                                          style: GoogleFonts.inter(
                                            color: _cancelTriggered ? Colors.redAccent : Colors.grey,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : TextField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          minLines: 1,
                          maxLines: null,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          onChanged: widget.onChanged,
                          decoration: InputDecoration(
                            hintText: 'Direct message to spouse or @assistant...',
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            filled: true,
                            fillColor: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.03),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20),
                              borderSide: const BorderSide(color: RodMaeColors.electricBlue, width: 1.5),
                            ),
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                if (widget.sending || showSend)
                  FloatingActionButton.small(
                    onPressed: widget.sending ? null : widget.onSend,
                    backgroundColor: RodMaeColors.electricBlue,
                    foregroundColor: Colors.white,
                    child: widget.sending
                        ? AdvancedLoadingEffect(
                            isLoading: true,
                            shape: BoxShape.circle,
                            placeholder: Container(
                              width: 16,
                              height: 16,
                              decoration: const BoxDecoration(
                                color: Colors.white38,
                                shape: BoxShape.circle,
                              ),
                            ),
                            child: const SizedBox(width: 16, height: 16),
                          )
                        : const Icon(Icons.send_rounded),
                  )
                else
                  GestureDetector(
                    key: const ValueKey('mic_gesture_detector'),
                    onTap: () {
                      if (_isRecording) {
                        _stopRecording(cancel: false);
                      } else {
                        _startRecording();
                      }
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_isRecording)
                          AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 44 + (_pulseController.value * 8),
                                height: 44 + (_pulseController.value * 8),
                                decoration: BoxDecoration(
                                  color: RodMaeColors.electricBlue.withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                              );
                            },
                          ),
                        Container(
                          width: 44,
                          height: 44,
                          decoration: const BoxDecoration(
                            color: RodMaeColors.electricBlue,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _isRecording ? Icons.send_rounded : Icons.mic_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
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
  final Color color;
  final VoidCallback? onTap;

  const _MiniChatAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 36,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.12 : 0.10),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 15),
              const SizedBox(width: 5),
              Text(
                label,
                style: GoogleFonts.inter(
                  color: color,
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

// ─────────────────────────────────────────────────────────────────────────────
// SwipeToReply — Custom horizontal drag swipe to reply gesture detector
// ─────────────────────────────────────────────────────────────────────────────

class SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  final bool isMe;

  const SwipeToReply({
    required this.child,
    required this.onReply,
    required this.isMe,
    super.key,
  });

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;
  double _dragExtent = 0.0;
  bool _triggered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _offsetAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.08, 0.0), // Pull right to reply
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.decelerate,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (details.primaryDelta! > 0) {
      setState(() {
        _dragExtent += details.primaryDelta!;
        final val = (_dragExtent / 120.0).clamp(0.0, 1.0);
        _controller.value = val;
        
        if (_dragExtent > 70.0 && !_triggered) {
          _triggered = true;
        }
      });
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (_triggered) {
      widget.onReply();
    }
    _controller.animateTo(0.0, curve: Curves.easeOut);
    setState(() {
      _dragExtent = 0.0;
      _triggered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -40,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 100),
              opacity: (_dragExtent / 70.0).clamp(0.0, 1.0),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(
                  color: Colors.white12,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.reply_rounded,
                  color: RodMaeColors.sky,
                  size: 16,
                ),
              ),
            ),
          ),
          SlideTransition(
            position: _offsetAnimation,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
