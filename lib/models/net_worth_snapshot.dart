import '../core/utils.dart';

final class NetWorthSnapshot {
  final String id;
  final String householdId;
  final double totalAssets;
  final double totalLiabilities;
  final DateTime capturedAt;

  const NetWorthSnapshot({
    required this.id,
    required this.householdId,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.capturedAt,
  });

  factory NetWorthSnapshot.fromMap(Map<String, dynamic> row) {
    return NetWorthSnapshot(
      id: row['id']?.toString() ?? '',
      householdId: row['household_id']?.toString() ?? '',
      totalAssets: Formatters.asDouble(row['total_assets'] ?? 0.0),
      totalLiabilities: Formatters.asDouble(row['total_liabilities'] ?? 0.0),
      capturedAt: Formatters.asDate(row['captured_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'household_id': householdId,
      'total_assets': totalAssets,
      'total_liabilities': totalLiabilities,
      'captured_at': capturedAt.toIso8601String(),
    };
  }

  NetWorthSnapshot copyWith({
    String? id,
    String? householdId,
    double? totalAssets,
    double? totalLiabilities,
    DateTime? capturedAt,
  }) {
    return NetWorthSnapshot(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      totalAssets: totalAssets ?? this.totalAssets,
      totalLiabilities: totalLiabilities ?? this.totalLiabilities,
      capturedAt: capturedAt ?? this.capturedAt,
    );
  }
}
