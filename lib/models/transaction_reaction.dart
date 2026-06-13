import '../core/utils.dart';

final class TransactionReaction {
  final String id;
  final String transactionId;
  final String userId;
  final String reactionType; // 'heart', 'thumbs_up', 'shocked', 'sad'
  final DateTime createdAt;

  const TransactionReaction({
    required this.id,
    required this.transactionId,
    required this.userId,
    required this.reactionType,
    required this.createdAt,
  });

  factory TransactionReaction.fromJson(Map<String, dynamic> json) {
    return TransactionReaction(
      id: json['id']?.toString() ?? '',
      transactionId: json['transaction_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      reactionType: json['reaction_type']?.toString() ?? 'thumbs_up',
      createdAt: Formatters.asDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transaction_id': transactionId,
      'user_id': userId,
      'reaction_type': reactionType,
      'created_at': createdAt.toIso8601String(),
    };
  }

  TransactionReaction copyWith({
    String? id,
    String? transactionId,
    String? userId,
    String? reactionType,
    DateTime? createdAt,
  }) {
    return TransactionReaction(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      userId: userId ?? this.userId,
      reactionType: reactionType ?? this.reactionType,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
