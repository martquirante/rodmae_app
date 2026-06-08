import '../core/utils.dart';

class SurpriseNote {
  final String id;
  final String coupleId;
  final String sender;
  final String content;
  final DateTime createdAt;

  const SurpriseNote({
    required this.id,
    required this.coupleId,
    required this.sender,
    required this.content,
    required this.createdAt,
  });

  factory SurpriseNote.fromMap(Map<String, dynamic> map) {
    return SurpriseNote(
      id: '${map['id'] ?? ''}',
      coupleId: '${map['couple_id'] ?? ''}',
      sender: '${map['sender'] ?? ''}',
      content: '${map['content'] ?? ''}',
      createdAt: Formatters.asDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'couple_id': coupleId,
      'sender': sender,
      'content': content,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
