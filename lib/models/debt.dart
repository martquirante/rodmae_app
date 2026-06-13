import '../core/utils.dart';

enum DebtType {
  owe,
  owed;

  String get dbValue => name;

  static DebtType from(dynamic value) {
    final val = '$value'.toLowerCase();
    if (val.contains('owed')) {
      return DebtType.owed;
    }
    return DebtType.owe;
  }
}

final class Debt {
  final String id;
  final String coupleId;
  final String title;
  final double totalAmount;
  final double remainingAmount;
  final DebtType type;
  final String? relatedTransactionId;

  // Convenience getter
  bool get isFullyPaid => remainingAmount <= 0;

  const Debt({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.totalAmount,
    required this.remainingAmount,
    required this.type,
    this.relatedTransactionId,
  });

  factory Debt.fromMap(Map<String, dynamic> row) {
    return Debt(
      id: row['id']?.toString() ?? '',
      coupleId: row['couple_id']?.toString() ?? '',
      title: row['title']?.toString() ?? 'Debt',
      totalAmount: Formatters.asDouble(row['total_amount'] ?? 0.0),
      remainingAmount: Formatters.asDouble(row['remaining_amount'] ?? row['remaining'] ?? 0.0),
      type: DebtType.from(row['type'] ?? 'owe'),
      relatedTransactionId: row['related_transaction_id']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'couple_id': coupleId,
      'title': title,
      'total_amount': totalAmount,
      'remaining_amount': remainingAmount,
      'type': type.dbValue,
      if (relatedTransactionId != null) 'related_transaction_id': relatedTransactionId,
    };
  }

  Debt copyWith({
    String? id,
    String? coupleId,
    String? title,
    double? totalAmount,
    double? remainingAmount,
    DebtType? type,
    String? relatedTransactionId,
  }) {
    return Debt(
      id: id ?? this.id,
      coupleId: coupleId ?? this.coupleId,
      title: title ?? this.title,
      totalAmount: totalAmount ?? this.totalAmount,
      remainingAmount: remainingAmount ?? this.remainingAmount,
      type: type ?? this.type,
      relatedTransactionId: relatedTransactionId ?? this.relatedTransactionId,
    );
  }
}
