import '../core/utils.dart';

class LoveTriggerEvent {
  final String id;
  final String coupleId;
  final String sender;
  final String triggerType;
  final DateTime createdAt;

  const LoveTriggerEvent({
    required this.id,
    required this.coupleId,
    required this.sender,
    required this.triggerType,
    required this.createdAt,
  });

  factory LoveTriggerEvent.fromMap(Map<String, dynamic> map) {
    return LoveTriggerEvent(
      id: '${map['id'] ?? ''}',
      coupleId: '${map['couple_id'] ?? ''}',
      sender: '${map['sender'] ?? ''}',
      triggerType: '${map['trigger_type'] ?? ''}',
      createdAt: Formatters.asDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'couple_id': coupleId,
      'sender': sender,
      'trigger_type': triggerType,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
