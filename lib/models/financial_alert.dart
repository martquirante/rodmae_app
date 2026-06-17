import '../core/utils.dart';

final class FinancialAlert {
  final String id;
  final String householdId;
  final String? userId;
  final String type;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  const FinancialAlert({
    required this.id,
    required this.householdId,
    this.userId,
    required this.type,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory FinancialAlert.fromJson(Map<String, dynamic> json) {
    return FinancialAlert(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      userId: json['user_id']?.toString(),
      type: json['type']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      isRead: json['is_read'] == true,
      createdAt: Formatters.asDate(json['created_at'] ?? DateTime.now()),
    );
  }

  factory FinancialAlert.fromMap(Map<String, dynamic> map) => FinancialAlert.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'user_id': userId,
      'type': type,
      'message': message,
      'is_read': isRead,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() => toJson();
}
