import '../core/utils.dart';

final class IncomeEntry {
  final String id;
  final String userId;
  final String householdId;
  final String sourceName;
  final double amount;
  final String type;
  final DateTime date;

  const IncomeEntry({
    required this.id,
    required this.userId,
    required this.householdId,
    required this.sourceName,
    required this.amount,
    required this.type,
    required this.date,
  });

  factory IncomeEntry.fromJson(Map<String, dynamic> json) {
    return IncomeEntry(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      sourceName: json['source_name']?.toString() ?? '',
      amount: Formatters.asDouble(json['amount'] ?? 0.0),
      type: json['type']?.toString() ?? 'one-time',
      date: Formatters.asDate(json['date'] ?? json['created_at']),
    );
  }

  factory IncomeEntry.fromMap(Map<String, dynamic> map) => IncomeEntry.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'household_id': householdId,
      'source_name': sourceName,
      'amount': amount,
      'type': type,
      'date': date.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() => toJson();
}
