import '../core/utils.dart';

final class QuickNote {
  final String id;
  final String coupleId;
  final String content;
  final DateTime dateCreated;

  const QuickNote({
    required this.id,
    required this.coupleId,
    required this.content,
    required this.dateCreated,
  });

  factory QuickNote.fromMap(Map<String, dynamic> row) {
    return QuickNote(
      id: row['id']?.toString() ?? '',
      coupleId: row['couple_id']?.toString() ?? '',
      content: row['content']?.toString() ?? '',
      dateCreated: Formatters.asDate(row['date_created'] ?? row['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'couple_id': coupleId,
      'content': content,
      'date_created': dateCreated.toIso8601String(),
    };
  }

  QuickNote copyWith({
    String? id,
    String? coupleId,
    String? content,
    DateTime? dateCreated,
  }) {
    return QuickNote(
      id: id ?? this.id,
      coupleId: coupleId ?? this.coupleId,
      content: content ?? this.content,
      dateCreated: dateCreated ?? this.dateCreated,
    );
  }
}
