import '../core/utils.dart';

final class PurchaseRequest {
  final String id;
  final String householdId;
  final String requesterId;
  final String itemName;
  final double amount;
  final String status; // 'pending', 'approved', 'declined'
  final DateTime createdAt;

  const PurchaseRequest({
    required this.id,
    required this.householdId,
    required this.requesterId,
    required this.itemName,
    required this.amount,
    required this.status,
    required this.createdAt,
  });

  factory PurchaseRequest.fromJson(Map<String, dynamic> json) {
    return PurchaseRequest(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      requesterId: json['requester_id']?.toString() ?? json['requester_uid']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? 'Unnamed Item',
      amount: Formatters.asDouble(json['amount'] ?? 0.0),
      status: json['status']?.toString() ?? 'pending',
      createdAt: Formatters.asDate(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'requester_id': requesterId,
      'item_name': itemName,
      'amount': amount,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }

  PurchaseRequest copyWith({
    String? id,
    String? householdId,
    String? requesterId,
    String? itemName,
    double? amount,
    String? status,
    DateTime? createdAt,
  }) {
    return PurchaseRequest(
      id: id ?? this.id,
      householdId: householdId ?? this.householdId,
      requesterId: requesterId ?? this.requesterId,
      itemName: itemName ?? this.itemName,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
