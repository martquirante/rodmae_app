import '../core/utils.dart';

final class SavingsGoal {
  final String id;
  final String householdId;
  final String name;
  final double targetAmount;
  final double currentAmount;
  final String category; // 'emergency', 'life_event'
  final DateTime? targetDate;
  final DateTime createdAt;

  // Backward compatibility properties
  String get coupleId => householdId;
  String get title => name;
  double get savedAmount => currentAmount;
  DateTime? get deadline => targetDate;

  const SavingsGoal({
    required this.id,
    required this.householdId,
    required this.name,
    required this.targetAmount,
    required this.currentAmount,
    required this.category,
    this.targetDate,
    required this.createdAt,
  });

  factory SavingsGoal.fromJson(Map<String, dynamic> json) {
    return SavingsGoal(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      name: json['name']?.toString() ?? json['title']?.toString() ?? 'Untitled Goal',
      targetAmount: Formatters.asDouble(json['target_amount'] ?? json['target_amount'] ?? 0.0),
      currentAmount: Formatters.asDouble(json['current_amount'] ?? json['saved_amount'] ?? 0.0),
      category: json['category']?.toString() ?? 'life_event',
      targetDate: json['target_date'] != null 
          ? Formatters.asDate(json['target_date']) 
          : (json['deadline'] != null ? Formatters.asDate(json['deadline']) : null),
      createdAt: Formatters.asDate(json['created_at'] ?? DateTime.now()),
    );
  }

  factory SavingsGoal.fromMap(Map<String, dynamic> map) => SavingsGoal.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'name': name,
      'target_amount': targetAmount,
      'current_amount': currentAmount,
      'category': category,
      if (targetDate != null) 'target_date': targetDate!.toIso8601String().split('T').first,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() => toJson();

  SavingsGoal copyWith({
    String? id,
    String? householdId,
    String? name,
    double? targetAmount,
    double? currentAmount,
    String? category,
    DateTime? targetDate,
    DateTime? createdAt,
  }) {
    return SavingsGoal(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      targetAmount: targetAmount ?? this.targetAmount,
      currentAmount: currentAmount ?? this.currentAmount,
      category: category ?? this.category,
      targetDate: targetDate ?? this.targetDate,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
