import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:any_link_preview/any_link_preview.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/theme.dart';
import '../core/utils.dart';
import '../models/chat_message.dart';
import '../services/auth_service.dart';
import 'advanced_loading_effect.dart';

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

  const ChatBubble({
    required this.message,
    this.isLatestFromMe = false,
    this.partnerAvatarUrl,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final sender = message.sender.toLowerCase();
    final myLabel = PartnerIdentity.active.value.label.toLowerCase();
    final isMe = sender == myLabel;
    final align   = isMe ? Alignment.centerRight : Alignment.centerLeft;
    final isDark  = Theme.of(context).brightness == Brightness.dark;

    final bubbleColor = message.assistant
        ? RodMaeColors.violet
        : isMe
            ? RodMaeColors.sapphire
            : (isDark ? RodMaeColors.charcoal : const Color(0xFFE2E8F0));

    final textColor =
        (!isMe && !isDark && !message.assistant) ? Colors.black87 : Colors.white;
    final timeColor =
        (!isMe && !isDark && !message.assistant) ? Colors.black38 : Colors.white60;

    final maxWidth = MediaQuery.sizeOf(context).width * 0.76;

    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
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
                isMe: isMe,
              ),

              // ── Read receipt (only on latest message from *this* user) ────
              if (isLatestFromMe) ...[
                const SizedBox(height: 3),
                _ReadReceiptIndicator(
                  status: message.status,
                  partnerInitial: PartnerIdentity.active.value == PartnerProfile.rodel ? 'E' : 'R',
                  partnerAvatarUrl: partnerAvatarUrl,
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
    required bool isMe,
  }) {
    switch (message.messageType) {
      case MessageType.image:
        return _ImageBubble(
          message: message,
          bubbleColor: bubbleColor,
          timeColor: timeColor,
          isMe: isMe,
          isDark: isDark,
        );
      case MessageType.location:
        return _LocationBubble(
          message: message,
          isMe: isMe,
          isDark: isDark,
        );
      case MessageType.love:
        return _LoveBubble(
          message: message,
          timeColor: timeColor,
          isMe: isMe,
        );
      case MessageType.text:
        return _TextBubble(
          message: message,
          bubbleColor: bubbleColor,
          textColor: textColor,
          timeColor: timeColor,
          isMe: isMe,
        );
    }
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
  // Also handle inline URLs in longer text
  final urlRegex = RegExp(
    r'https?://[^\s/$.?#].[^\s]*',
    caseSensitive: false,
  );
  return urlRegex.hasMatch(text);
}

String? _extractFirstUrl(String text) {
  // Whole message is a URL
  final trimmed = text.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty) {
    return trimmed;
  }
  // URL embedded in text
  final urlRegex = RegExp(
    r'https?://[^\s/$.?#].[^\s]*',
    caseSensitive: false,
  );
  final match = urlRegex.firstMatch(text);
  return match?.group(0);
}

// ─────────────────────────────────────────────────────────────────────────────
// Text bubble — with automatic URL / link preview
// ─────────────────────────────────────────────────────────────────────────────

class _TextBubble extends StatelessWidget {
  final ChatMessage message;
  final Color bubbleColor;
  final Color textColor;
  final Color timeColor;
  final bool isMe;

  const _TextBubble({
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.timeColor,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasUrl = _containsUrl(message.message);
    final extractedUrl = hasUrl ? _extractFirstUrl(message.message) : null;
    final isWholeMessageUrl = extractedUrl != null &&
        message.message.trim() == extractedUrl;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMe ? 20 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
        border: Border.all(
          color: Colors.white.withValues(
            alpha: isDark ? 0.06 : 0.2,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show full message text only if it's not purely a URL
          if (!isWholeMessageUrl)
            Text(
              message.message,
              style: GoogleFonts.inter(
                color: textColor,
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),

          // ── Rich Link Preview ─────────────────────────────────────────
          if (extractedUrl != null) ...[
            if (!isWholeMessageUrl) const SizedBox(height: 10),
            _LinkPreviewCard(url: extractedUrl, isDark: isDark),
          ],

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
  final Color timeColor;
  final bool isMe;
  final bool isDark;

  const _ImageBubble({
    required this.message,
    required this.bubbleColor,
    required this.timeColor,
    required this.isMe,
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
          bottomLeft: Radius.circular(isMe ? 20 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 20),
        ),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.2),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
// Location bubble — static map thumbnail + address + navigates to map
// ─────────────────────────────────────────────────────────────────────────────

class _LocationBubble extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final bool isDark;

  const _LocationBubble({
    required this.message,
    required this.isMe,
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
          // Navigate to the Map screen and pass coordinates for auto-zoom
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
        width: 240,
        decoration: BoxDecoration(
          color: isDark ? RodMaeColors.navy : const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: Radius.circular(isMe ? 20 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 20),
          ),
          border: Border.all(
            color: RodMaeColors.mint.withValues(alpha: 0.4),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Static map thumbnail ──────────────────────────────────────
            Stack(
              children: [
                if (mapUrl != null)
                  CachedNetworkImage(
                    imageUrl: mapUrl,
                    height: 130,
                    width: 240,
                    fit: BoxFit.cover,
                    placeholder: (ctx, url) => _mapPlaceholder(),
                    errorWidget: (ctx, url, err) => _mapPlaceholder(),
                  )
                else
                  _mapPlaceholder(),
                // ── Pin overlay ───────────────────────────────────────────
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
                // ── Tap to open hint overlay ──────────────────────────────
                if (hasCoords)
                  Positioned(
                    bottom: 6,
                    right: 8,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          color: Colors.black.withValues(alpha: 0.35),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.map_rounded,
                                  size: 11, color: Colors.white70),
                              const SizedBox(width: 4),
                              Text(
                                'Open in Map',
                                style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
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
            // ── Address row ───────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Love signal bubble
// ─────────────────────────────────────────────────────────────────────────────

class _LoveBubble extends StatelessWidget {
  final ChatMessage message;
  final Color timeColor;
  final bool isMe;

  const _LoveBubble({
    required this.message,
    required this.timeColor,
    required this.isMe,
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
          bottomLeft: Radius.circular(isMe ? 20 : 4),
          bottomRight: Radius.circular(isMe ? 4 : 20),
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
  final String? partnerAvatarUrl;
  final bool isDark;

  const _ReadReceiptIndicator({
    required this.status,
    required this.partnerInitial,
    required this.isDark,
    this.partnerAvatarUrl,
  });

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.seen:
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
            const SizedBox(width: 5),
            // ── Real partner PFP mini avatar ──────────────────────────────
            SizedBox(
              width: 16,
              height: 16,
              child: partnerAvatarUrl != null && partnerAvatarUrl!.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: partnerAvatarUrl!,
                      imageBuilder: (ctx, imageProvider) => CircleAvatar(
                        radius: 8,
                        backgroundImage: imageProvider,
                      ),
                      placeholder: (ctx, url) => _fallbackAvatar(),
                      errorWidget: (ctx, url, err) => _fallbackAvatar(),
                    )
                  : _fallbackAvatar(),
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

  Widget _fallbackAvatar() => Container(
        width: 16,
        height: 16,
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
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ChatComposer — composer row with Image / Location / Love action buttons
// ─────────────────────────────────────────────────────────────────────────────

class ChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final void Function(MessageType type)? onSpecialAction;
  final ValueChanged<String>? onChanged;
  final FocusNode? focusNode;
  final bool hasKeyboard;

  const ChatComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.hasKeyboard,
    this.onSpecialAction,
    this.onChanged,
    this.focusNode,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = hasKeyboard ? 12.0 : 94.0;

    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 8, 18, bottomPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _MiniChatAction(
                  icon: Icons.photo_camera_rounded,
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
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                    onChanged: onChanged,
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
