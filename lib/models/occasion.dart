import '../core/utils.dart';

final class Occasion {
  final String id;
  final String householdId;
  final String name;
  final DateTime date;
  final bool recurring;
  final double budgetAmount;
  final double savedAmount;
  final double monthlyContribution;

  const Occasion({
    required this.id,
    required this.householdId,
    required this.name,
    required this.date,
    required this.recurring,
    required this.budgetAmount,
    required this.savedAmount,
    required this.monthlyContribution,
  });

  factory Occasion.fromJson(Map<String, dynamic> json) {
    return Occasion(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      date: Formatters.asDate(json['date'] ?? json['created_at']),
      recurring: json['recurring'] == true || json['recurring'] == 1 || json['recurring'] == 'true',
      budgetAmount: Formatters.asDouble(json['budget_amount'] ?? json['budget'] ?? 0.0),
      savedAmount: Formatters.asDouble(json['saved_amount'] ?? json['saved'] ?? json['current_balance'] ?? 0.0),
      monthlyContribution: Formatters.asDouble(json['monthly_contribution'] ?? 0.0),
    );
  }

  factory Occasion.fromMap(Map<String, dynamic> map) => Occasion.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      if (id.isNotEmpty) 'id': id,
      'household_id': householdId,
      'name': name,
      'date': date.toIso8601String(),
      'recurring': recurring,
      'budget_amount': budgetAmount,
    };
  }

  Map<String, dynamic> toMap() => toJson();

  Occasion copyWith({
    String? id,
    String? householdId,
    String? name,
    DateTime? date,
    bool? recurring,
    double? budgetAmount,
    double? savedAmount,
    double? monthlyContribution,
  }) {
    return Occasion(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      date: date ?? this.date,
      recurring: recurring ?? this.recurring,
      budgetAmount: budgetAmount ?? this.budgetAmount,
      savedAmount: savedAmount ?? this.savedAmount,
      monthlyContribution: monthlyContribution ?? this.monthlyContribution,
    );
  }
}
