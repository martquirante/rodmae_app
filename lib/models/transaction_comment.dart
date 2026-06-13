import '../core/utils.dart';

final class TransactionComment {
  final String id;
  final String transactionId;
  final String userId;
  final String commentText;
  final DateTime createdAt;

  const TransactionComment({
    required this.id,
    required this.transactionId,
    required this.userId,
    required this.commentText,
    required this.createdAt,
  });

  factory TransactionComment.fromJson(Map<String, dynamic> json) {
    return TransactionComment(
      id: json['id']?.toString() ?? '',
      transactionId: json['transaction_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      commentText: json['comment_text']?.toString() ?? '',
      createdAt: Formatters.asDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'transaction_id': transactionId,
      'user_id': userId,
      'comment_text': commentText,
      'created_at': createdAt.toIso8601String(),
    };
  }

  TransactionComment copyWith({
    String? id,
    String? transactionId,
    String? userId,
    String? commentText,
    DateTime? createdAt,
  }) {
    return TransactionComment(
      id: id ?? this.id,
      transactionId: transactionId ?? this.transactionId,
      userId: userId ?? this.userId,
      commentText: commentText ?? this.commentText,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
