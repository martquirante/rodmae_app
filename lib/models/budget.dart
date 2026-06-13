import '../core/utils.dart';

final class Budget {
  final String id;
  final String coupleId;
  final String category;
  final double monthlyLimit;
  final double spent;

  const Budget({
    required this.id,
    required this.coupleId,
    required this.category,
    required this.monthlyLimit,
    required this.spent,
  });

  factory Budget.fromMap(Map<String, dynamic> row) {
    return Budget(
      id: row['id']?.toString() ?? '',
      coupleId: row['couple_id']?.toString() ?? '',
      category: row['category']?.toString() ?? 'General',
      monthlyLimit: Formatters.asDouble(row['monthly_limit'] ?? 0.0),
      spent: Formatters.asDouble(row['spent'] ?? 0.0),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'couple_id': coupleId,
      'category': category,
      'monthly_limit': monthlyLimit,
      'spent': spent,
    };
  }

  Budget copyWith({
    String? id,
    String? coupleId,
    String? category,
    double? monthlyLimit,
    double? spent,
  }) {
    return Budget(
      id: id ?? this.id,
      coupleId: coupleId ?? this.coupleId,
      category: category ?? this.category,
      monthlyLimit: monthlyLimit ?? this.monthlyLimit,
      spent: spent ?? this.spent,
    );
  }
}
