import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/chat_message.dart';
import 'advanced_loading_effect.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ChatBubble — Messenger-style bubble with read receipts + rich content types
// ─────────────────────────────────────────────────────────────────────────────

class ChatBubble extends StatelessWidget {
  final ChatMessage message;

  /// Whether this is the *most recent* message sent by the local user.
  /// Only the latest message shows the receipt indicator (like Messenger).
  final bool isLatestFromMe;

  const ChatBubble({
    required this.message,
    this.isLatestFromMe = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final sender = message.sender.toLowerCase();
    final isRodel = sender.contains('rodel');
    final isMary  = sender.contains('mary') || sender.contains('mae') ||
                    sender.contains('eurine');
    final align   = isRodel ? Alignment.centerRight : Alignment.centerLeft;
    final isDark  = Theme.of(context).brightness == Brightness.dark;

    final bubbleColor = message.assistant
        ? RodMaeColors.violet
        : isRodel
            ? RodMaeColors.sapphire
            : (isDark ? RodMaeColors.charcoal : const Color(0xFFE2E8F0));

    final textColor =
        (isMary && !isDark && !message.assistant) ? Colors.black87 : Colors.white;
    final timeColor =
        (isMary && !isDark && !message.assistant) ? Colors.black38 : Colors.white60;

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
              // ── Sender label ─────────────────────────────────────────────
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

              // ── Bubble ────────────────────────────────────────────────────
              _buildBubbleContent(
                context,
                isDark: isDark,
                bubbleColor: bubbleColor,
                textColor: textColor,
                timeColor: timeColor,
                isRodel: isRodel,
              ),

              // ── Read receipt (only on latest message from *this* user) ────
              if (isLatestFromMe) ...[
                const SizedBox(height: 3),
                _ReadReceiptIndicator(
                  status: message.status,
                  partnerInitial:
                      isRodel ? 'E' : 'R', // opposite partner initial
                  isDark: isDark,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBubbleContent(
    BuildContext context, {
    required bool isDark,
    required Color bubbleColor,
    required Color textColor,
    required Color timeColor,
    required bool isRodel,
  }) {
    switch (message.messageType) {
      case MessageType.image:
        return _ImageBubble(
          message: message,
          bubbleColor: bubbleColor,
          timeColor: timeColor,
          isRodel: isRodel,
          isDark: isDark,
        );
      case MessageType.location:
        return _LocationBubble(
          message: message,
          isRodel: isRodel,
          isDark: isDark,
        );
      case MessageType.love:
        return _LoveBubble(
          message: message,
          timeColor: timeColor,
          isRodel: isRodel,
        );
      case MessageType.text:
        return _TextBubble(
          message: message,
          bubbleColor: bubbleColor,
          textColor: textColor,
          timeColor: timeColor,
          isRodel: isRodel,
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Text bubble
// ─────────────────────────────────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  final ChatMessage message;
  final Color bubbleColor;
  final Color textColor;
  final Color timeColor;
  final bool isRodel;

  const _TextBubble({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.timeColor,
    required this.isRodel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isRodel ? 20 : 4),
          bottomRight: Radius.circular(isRodel ? 4 : 20),
        ),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0.06 : 0.2,
          ),
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
          const SizedBox(height: 6),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Image bubble
// ─────────────────────────────────────────────────────────────────────────────

class _ImageBubble extends StatelessWidget {
  final ChatMessage message;
  final Color bubbleColor;
  final Color timeColor;
  final bool isRodel;
  final bool isDark;

  const _ImageBubble({
    required this.message,
    required this.bubbleColor,
    required this.timeColor,
    required this.isRodel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final url = message.imageUrl ?? '';
    final isLocalPath = url.startsWith('/');

    return Container(
      decoration: BoxDecoration(
        color: bubbleColor,
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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
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
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return AdvancedLoadingEffect(
                            isLoading: true,
                            placeholder: Container(
                              width: 220,
                              height: 180,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: Container(
                              width: 220,
                              height: 180,
                              color: Colors.transparent,
                            ),
                          );
                        },
                        errorBuilder: (ctx, err, stk) => const _ImageErrorWidget(),
                      ),
              ),
            ),
          ),
          if (message.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: Text(
                message.message,
                style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Align(
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
          ),
        ],
      ),
    );
  }

  void _openFullscreen(BuildContext context, String url, bool isLocal) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _FullscreenImage(url: url, isLocal: isLocal),
      ),
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
              : Image.network(url),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Location bubble — shows a styled map-preview card like Messenger
// ─────────────────────────────────────────────────────────────────────────────

class _LocationBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isRodel;
  final bool isDark;

  const _LocationBubble({
    required this.message,
    required this.isRodel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Parse 'lat,lng,address' payload
    final parts = (message.locationData ?? '').split(',');
    final lat  = parts.isNotEmpty ? double.tryParse(parts[0]) : null;
    final lng  = parts.length > 1 ? double.tryParse(parts[1]) : null;
    final addr = parts.length > 2 ? parts.sublist(2).join(',').trim() : null;
    final hasCoords = lat != null && lng != null;

    // Static map thumbnail via OpenStreetMap tile
    final mapUrl = hasCoords
        ? 'https://staticmap.openstreetmap.de/staticmap.php'
          '?center=$lat,$lng&zoom=15&size=300x160&markers=$lat,$lng,red-pushpin'
        : null;

    return GestureDetector(
      onTap: () {
        if (hasCoords) {
          // hasCoords guarantees lat/lng are non-null via type promotion
          _openInMaps(lat, lng);
        }
      },
      child: Container(
        width: 240,
        decoration: BoxDecoration(
          color: isDark ? RodMaeColors.navy : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isRodel ? 20 : 4),
            bottomRight: Radius.circular(isRodel ? 4 : 20),
          ),
          border: Border.all(
            color: RodMaeColors.mint.withValues(alpha: 0.4),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Map thumbnail
            Stack(
              children: [
                if (mapUrl != null)
                  Image.network(
                    mapUrl,
                    height: 130,
                    width: 240,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, e, s) => _mapPlaceholder(),
                  )
                else
                  _mapPlaceholder(),
                // Location pin overlay
                Positioned.fill(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: RodMaeColors.mint,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: RodMaeColors.mint.withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.location_on_rounded,
                          color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ],
            ),
            // Address row
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.place_rounded,
                          color: RodMaeColors.mint, size: 14),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          addr ?? message.message,
                          style: GoogleFonts.inter(
                            color: isDark ? Colors.white : RodMaeColors.lightText,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        hasCoords ? 'Tap to open in Maps' : 'Live Location',
                        style: GoogleFonts.inter(
                          color: RodMaeColors.mint,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        Formatters.time(message.createdAt),
                        style: GoogleFonts.inter(
                          color: isDark ? Colors.white30 : Colors.black38,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
        height: 130,
        color: RodMaeColors.navy2,
        child: const Center(
          child: Icon(Icons.map_rounded, color: Colors.white24, size: 40),
        ),
      );

  void _openInMaps(double lat, double lng) {
    // Copy coords to clipboard as a fallback (no url_launcher dependency needed)
    Clipboard.setData(ClipboardData(
      text: 'https://maps.google.com/?q=$lat,$lng',
    ));
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// Love signal bubble
// ─────────────────────────────────────────────────────────────────────────────

class _LoveBubble extends StatelessWidget {
  final ChatMessage message;
  final Color timeColor;
  final bool isRodel;

  const _LoveBubble({
    required this.message,
    required this.timeColor,
    required this.isRodel,
  });

  @override
  Widget build(BuildContext context) {
    final label = message.message.isNotEmpty ? message.message : '💕 Love Signal';
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
          bottomLeft: Radius.circular(isRodel ? 20 : 4),
          bottomRight: Radius.circular(isRodel ? 4 : 20),
        ),
        boxShadow: [
          BoxShadow(
            color: RodMaeColors.rose.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
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
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              Formatters.time(message.createdAt),
              style: GoogleFonts.inter(
                color: Colors.white70,
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Read receipt indicator — bottom-right of latest message
// ─────────────────────────────────────────────────────────────────────────────

class _ReadReceiptIndicator extends StatelessWidget {
  final MessageStatus status;
  final String partnerInitial;
  final bool isDark;

  const _ReadReceiptIndicator({
    required this.status,
    required this.partnerInitial,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.seen:
        // Tiny circular avatar (partner's initial) — just like Messenger
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Seen',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 14,
              height: 14,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [RodMaeColors.rose, RodMaeColors.gold],
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  partnerInitial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        );
      case MessageStatus.delivered:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.done_all_rounded,
              size: 14,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            const SizedBox(width: 3),
            Text(
              'Delivered',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white38 : Colors.black38,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      case MessageStatus.sent:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_rounded,
              size: 14,
              color: isDark ? Colors.white30 : Colors.black26,
            ),
            const SizedBox(width: 3),
            Text(
              'Sent',
              style: GoogleFonts.inter(
                color: isDark ? Colors.white30 : Colors.black26,
                fontSize: 9,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatComposer — composer row with Image / Location / Love action buttons
// ─────────────────────────────────────────────────────────────────────────────

class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final void Function(MessageType type)? onSpecialAction;

  const ChatComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
    this.onSpecialAction,
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
                _MiniChatAction(
                  icon: Icons.image_outlined,
                  label: 'Image',
                  color: RodMaeColors.sky,
                  onTap: () => onSpecialAction?.call(MessageType.image),
                ),
                const SizedBox(width: 8),
                _MiniChatAction(
                  icon: Icons.location_on_outlined,
                  label: 'Location',
                  color: RodMaeColors.mint,
                  onTap: () => onSpecialAction?.call(MessageType.location),
                ),
                const SizedBox(width: 8),
                _MiniChatAction(
                  icon: Icons.favorite_rounded,
                  label: 'Love',
                  color: RodMaeColors.rose,
                  onTap: () => onSpecialAction?.call(MessageType.love),
                ),
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
