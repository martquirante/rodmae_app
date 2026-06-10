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
      default:
        msgType = MessageType.text;
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
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'sender': sender,
        'message': message,
        'status': status.name,
        'message_type': messageType.name,
        if (imageUrl != null) 'image_url': imageUrl,
        if (locationData != null) 'location_data': locationData,
      };

  ChatMessage copyWith({MessageStatus? status}) => ChatMessage(
        id: id,
        sender: sender,
        message: message,
        createdAt: createdAt,
        assistant: assistant,
        status: status ?? this.status,
        messageType: messageType,
        imageUrl: imageUrl,
        locationData: locationData,
      );
}
