import '../core/utils.dart';
import 'chat_message.dart';

class LoveTriggerEvent {
  final String id;
  final String coupleId;
  final String sender;
  final String triggerType;
  final MessageStatus status;
  final DateTime createdAt;

  const LoveTriggerEvent({
    required this.id,
    required this.coupleId,
    required this.sender,
    required this.triggerType,
    required this.status,
    required this.createdAt,
  });

  factory LoveTriggerEvent.fromMap(Map<String, dynamic> map) {
    MessageStatus status;
    switch ('${map['status'] ?? 'sent'}') {
      case 'seen':
        status = MessageStatus.seen;
        break;
      case 'delivered':
        status = MessageStatus.delivered;
        break;
      default:
        status = MessageStatus.sent;
    }

    return LoveTriggerEvent(
      id: '${map['id'] ?? ''}',
      coupleId: '${map['couple_id'] ?? ''}',
      sender: '${map['sender'] ?? ''}',
      triggerType: '${map['trigger_type'] ?? ''}',
      status: status,
      createdAt: Formatters.asDate(map['created_at']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'couple_id': coupleId,
      'sender': sender,
      'trigger_type': triggerType,
      'status': status.name,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

