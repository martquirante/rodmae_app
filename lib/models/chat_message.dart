import '../core/utils.dart';

final class ChatMessage {
  final String id;
  final String sender;
  final String message;
  final DateTime createdAt;
  final bool assistant;

  const ChatMessage({
    required this.id,
    required this.sender,
    required this.message,
    required this.createdAt,
    this.assistant = false,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> row) {
    final sender = '${row['sender'] ?? row['created_by'] ?? 'RodMae'}';
    return ChatMessage(
      id: '${row['id'] ?? row['created_at'] ?? row['message']}',
      sender: sender,
      message: '${row['message'] ?? row['body'] ?? ''}',
      createdAt: Formatters.asDate(row['created_at']),
      assistant: sender.toLowerCase().contains('assistant'),
    );
  }
}
