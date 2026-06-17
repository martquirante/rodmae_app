import '../core/utils.dart';

final class CheckinItem {
  final String id;
  final String householdId;
  final DateTime scheduledAt;
  final DateTime? completedAt;
  final String? notes;
  final int? moodScore;

  const CheckinItem({
    required this.id,
    required this.householdId,
    required this.scheduledAt,
    this.completedAt,
    this.notes,
    this.moodScore,
  });

  factory CheckinItem.fromJson(Map<String, dynamic> json) {
    return CheckinItem(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      scheduledAt: Formatters.asDate(json['scheduled_at']),
      completedAt: json['completed_at'] != null ? Formatters.asDate(json['completed_at']) : null,
      notes: json['notes']?.toString(),
      moodScore: json['mood_score'] != null ? int.tryParse(json['mood_score'].toString()) : null,
    );
  }

  factory CheckinItem.fromMap(Map<String, dynamic> map) => CheckinItem.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'scheduled_at': scheduledAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
      if (notes != null) 'notes': notes,
      if (moodScore != null) 'mood_score': moodScore,
    };
  }

  Map<String, dynamic> toMap() => toJson();
}
