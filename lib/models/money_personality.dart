import 'dart:convert';

final class MoneyPersonality {
  final String userId;
  final String personalityType;
  final Map<String, dynamic> quizAnswers;
  final DateTime takenAt;

  const MoneyPersonality({
    required this.userId,
    required this.personalityType,
    required this.quizAnswers,
    required this.takenAt,
  });

  factory MoneyPersonality.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> answers = {};
    if (json['quiz_answers'] != null) {
      if (json['quiz_answers'] is String) {
        try {
          answers = jsonDecode(json['quiz_answers']);
        } catch (_) {}
      } else if (json['quiz_answers'] is Map) {
        answers = Map<String, dynamic>.from(json['quiz_answers']);
      }
    }

    return MoneyPersonality(
      userId: json['user_id']?.toString() ?? '',
      personalityType: json['personality_type']?.toString() ?? 'Saver',
      quizAnswers: answers,
      takenAt: json['taken_at'] != null ? DateTime.parse(json['taken_at']) : DateTime.now(),
    );
  }

  factory MoneyPersonality.fromMap(Map<String, dynamic> map) => MoneyPersonality.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'personality_type': personalityType,
      'quiz_answers': quizAnswers,
      'taken_at': takenAt.toIso8601String(),
    };
  }

  Map<String, dynamic> toMap() => toJson();
}
