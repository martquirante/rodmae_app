import '../core/utils.dart';

final class AssetLiability {
  final String id;
  final String householdId;
  final String type; // 'asset' or 'liability'
  final String name;
  final double currentValue;
  final DateTime updatedAt;

  const AssetLiability({
    required this.id,
    required this.householdId,
    required this.type,
    required this.name,
    required this.currentValue,
    required this.updatedAt,
  });

  factory AssetLiability.fromMap(Map<String, dynamic> row) {
    return AssetLiability(
      id: row['id']?.toString() ?? '',
      householdId: row['household_id']?.toString() ?? '',
      type: row['type']?.toString() ?? 'asset',
      name: row['name']?.toString() ?? '',
      currentValue: Formatters.asDouble(row['current_value'] ?? 0.0),
      updatedAt: Formatters.asDate(row['updated_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'household_id': householdId,
      'type': type,
      'name': name,
      'current_value': currentValue,
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  AssetLiability copyWith({
    String? id,
    String? householdId,
    String? type,
    String? name,
    double? currentValue,
    DateTime? updatedAt,
  }) {
    return AssetLiability(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      type: type ?? this.type,
      name: name ?? this.name,
      currentValue: currentValue ?? this.currentValue,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
