import '../core/utils.dart';

final class MonthlyReport {
  final String id;
  final String householdId;
  final int month;
  final int year;
  final String overallGrade;
  final double spendingScore;
  final double savingsScore;
  final String aiAdvice;
  final DateTime createdAt;

  const MonthlyReport({
    required this.id,
    required this.householdId,
    required this.month,
    required this.year,
    required this.overallGrade,
    required this.spendingScore,
    required this.savingsScore,
    required this.aiAdvice,
    required this.createdAt,
  });

  factory MonthlyReport.fromJson(Map<String, dynamic> json) {
    return MonthlyReport(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      month: json['month'] is int ? json['month'] : int.tryParse(json['month']?.toString() ?? '') ?? DateTime.now().month,
      year: json['year'] is int ? json['year'] : int.tryParse(json['year']?.toString() ?? '') ?? DateTime.now().year,
      overallGrade: json['overall_grade']?.toString() ?? 'N/A',
      spendingScore: Formatters.asDouble(json['spending_score'] ?? 0.0),
      savingsScore: Formatters.asDouble(json['savings_score'] ?? 0.0),
      aiAdvice: json['ai_advice']?.toString() ?? 'No AI coach advice generated yet.',
      createdAt: Formatters.asDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'month': month,
      'year': year,
      'overall_grade': overallGrade,
      'spending_score': spendingScore,
      'savings_score': savingsScore,
      'ai_advice': aiAdvice,
      'created_at': createdAt.toIso8601String(),
    };
  }

  MonthlyReport copyWith({
    String? id,
    String? householdId,
    int? month,
    int? year,
    String? overallGrade,
    double? spendingScore,
    double? savingsScore,
    String? aiAdvice,
    DateTime? createdAt,
  }) {
    return MonthlyReport(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      month: month ?? this.month,
      year: year ?? this.year,
      overallGrade: overallGrade ?? this.overallGrade,
      spendingScore: spendingScore ?? this.spendingScore,
      savingsScore: savingsScore ?? this.savingsScore,
      aiAdvice: aiAdvice ?? this.aiAdvice,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
