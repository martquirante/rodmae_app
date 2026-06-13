import '../core/utils.dart';

final class Category {
  final String id;
  final String householdId;
  final String name;
  final String color;
  final double monthlyBudget;
  final String? icon;

  // Backward compatibility property
  String get coupleId => householdId;

  const Category({
    required this.id,
    required this.householdId,
    required this.name,
    required this.color,
    required this.monthlyBudget,
    this.icon,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      color: json['color']?.toString() ?? '',
      monthlyBudget: Formatters.asDouble(json['monthly_budget'] ?? 0.0),
      icon: json['icon']?.toString(),
    );
  }

  factory Category.fromMap(Map<String, dynamic> map) => Category.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'name': name,
      'color': color,
      'monthly_budget': monthlyBudget,
      if (icon != null) 'icon': icon,
    };
  }

  Map<String, dynamic> toMap() => toJson();

  Category copyWith({
    String? id,
    String? householdId,
    String? name,
    String? color,
    double? monthlyBudget,
    String? icon,
  }) {
    return Category(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      name: name ?? this.name,
      color: color ?? this.color,
      monthlyBudget: monthlyBudget ?? this.monthlyBudget,
      icon: icon ?? this.icon,
    );
  }
}
