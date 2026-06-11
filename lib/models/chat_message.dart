import 'dart:convert';
import '../core/utils.dart';

/// Status lifecycle for a chat message (Messenger-style read receipts).
enum MessageStatus {
  /// Sent to server but not yet confirmed by the partner's device.
  sent,

  /// Message has been delivered to the partner's device.
  delivered,

  /// Partner has opened the chat and seen this message.
  seen,
}

/// Type of content carried by a chat message.
enum MessageType {
  text,
  image,
  location,
  love,
  voice,
}

final class ChatMessage {
  final String id;
  final String sender;
  final String message;
  final DateTime createdAt;
  final bool assistant;

  /// Messenger-style delivery/read status.
  final MessageStatus status;

  /// Content type of the message.
  final MessageType messageType;

  /// URL of an attached image (only meaningful when messageType == image).
  final String? imageUrl;

  /// Encoded location payload — 'lat,lng,address' (only for location type).
  final String? locationData;

  /// Emoji reactions map, e.g. {'Rodel': '❤️', 'Eurine': '👍'}
  final Map<String, String>? reactions;

  /// Parent message reference for swipe-to-reply
  final String? replyToId;
  final String? replyToSender;
  final String? replyToText;

  /// Edit/delete flags
  final bool isDeleted;
  final bool isEdited;

  /// Voice message URL
  final String? voiceUrl;

  /// Original text content before editing
  final String? originalMessage;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.message,
    required this.createdAt,
    this.assistant = false,
    this.status = MessageStatus.sent,
    this.messageType = MessageType.text,
    this.imageUrl,
    this.locationData,
    this.reactions,
    this.replyToId,
    this.replyToSender,
    this.replyToText,
    this.isDeleted = false,
    this.isEdited = false,
    this.voiceUrl,
    this.originalMessage,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> row) {
    final sender = '${row['sender'] ?? row['created_by'] ?? 'RodMae'}';

    MessageStatus status;
    switch ('${row['status'] ?? 'sent'}') {
      case 'seen':
        status = MessageStatus.seen;
        break;
      case 'delivered':
        status = MessageStatus.delivered;
        break;
      default:
        status = MessageStatus.sent;
    }

    MessageType msgType;
    switch ('${row['message_type'] ?? 'text'}') {
      case 'image':
        msgType = MessageType.image;
        break;
      case 'location':
        msgType = MessageType.location;
        break;
      case 'love':
        msgType = MessageType.love;
        break;
      case 'voice':
        msgType = MessageType.voice;
        break;
      default:
        if (row['voice_url'] != null) {
          msgType = MessageType.voice;
        } else {
          msgType = MessageType.text;
        }
    }

    Map<String, String>? reactionsMap;
    if (row['reactions'] != null) {
      try {
        final raw = row['reactions'];
        Map<String, dynamic>? decoded;
        if (raw is String) {
          decoded = jsonDecode(raw) as Map<String, dynamic>?;
        } else if (raw is Map) {
          decoded = Map<String, dynamic>.from(raw);
        }
        if (decoded != null) {
          reactionsMap = decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }

    return ChatMessage(
      id: '${row['id'] ?? row['created_at'] ?? row['message']}',
      sender: sender,
      message: '${row['message'] ?? row['body'] ?? ''}',
      createdAt: Formatters.asDate(row['created_at']),
      assistant: sender.toLowerCase().contains('assistant'),
      status: status,
      messageType: msgType,
      imageUrl: row['image_url'] as String?,
      locationData: row['location_data'] as String?,
      reactions: reactionsMap,
      replyToId: row['reply_to_id']?.toString(),
      replyToSender: row['reply_to_sender'] as String?,
      replyToText: row['reply_to_text'] as String?,
      isDeleted: row['is_deleted'] == true,
      isEdited: row['is_edited'] == true,
      voiceUrl: row['voice_url'] as String?,
      originalMessage: row['original_message'] as String?,
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'sender': sender,
        'message': message,
        'status': status.name,
        'message_type': messageType.name,
        if (imageUrl != null) 'image_url': imageUrl,
        if (locationData != null) 'location_data': locationData,
        if (reactions != null) 'reactions': reactions,
        if (replyToId != null) 'reply_to_id': int.tryParse(replyToId!),
        if (replyToSender != null) 'reply_to_sender': replyToSender,
        if (replyToText != null) 'reply_to_text': replyToText,
        'is_deleted': isDeleted,
        'is_edited': isEdited,
        if (voiceUrl != null) 'voice_url': voiceUrl,
        if (originalMessage != null) 'original_message': originalMessage,
      };

  ChatMessage copyWith({
    DateTime? createdAt,
    MessageStatus? status,
    Map<String, String>? reactions,
    bool? isDeleted,
    bool? isEdited,
    String? originalMessage,
  }) => ChatMessage(
        id: id,
        sender: sender,
        message: message,
        createdAt: createdAt ?? this.createdAt,
        assistant: assistant,
        status: status ?? this.status,
        messageType: messageType,
        imageUrl: imageUrl,
        locationData: locationData,
        reactions: reactions ?? this.reactions,
        replyToId: replyToId,
        replyToSender: replyToSender,
        replyToText: replyToText,
        isDeleted: isDeleted ?? this.isDeleted,
        isEdited: isEdited ?? this.isEdited,
        voiceUrl: voiceUrl,
        originalMessage: originalMessage ?? this.originalMessage,
      );
}
