import '../core/utils.dart';

final class SubscriptionItem {
  final String id;
  final String householdId;
  final String? ownerUserId;
  final String name;
  final double amount;
  final String billingCycle; // e.g. monthly, yearly
  final DateTime nextBillingDate;
  final String category;

  const SubscriptionItem({
    required this.id,
    required this.householdId,
    this.ownerUserId,
    required this.name,
    required this.amount,
    required this.billingCycle,
    required this.nextBillingDate,
    required this.category,
  });

  factory SubscriptionItem.fromJson(Map<String, dynamic> json) {
    return SubscriptionItem(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      ownerUserId: json['owner_user_id']?.toString() ?? json['owner_uid']?.toString(),
      name: json['name']?.toString() ?? '',
      amount: Formatters.asDouble(json['amount'] ?? 0.0),
      billingCycle: json['billing_cycle']?.toString() ?? 'monthly',
      nextBillingDate: Formatters.asDate(json['next_billing_date'] ?? json['billing_date'] ?? DateTime.now()),
      category: json['category']?.toString() ?? 'Entertainment',
    );
  }

  factory SubscriptionItem.fromMap(Map<String, dynamic> map) => SubscriptionItem.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'owner_user_id': ownerUserId,
      'name': name,
      'amount': amount,
      'billing_cycle': billingCycle,
      'next_billing_date': nextBillingDate.toIso8601String(),
      'category': category,
    };
  }

  Map<String, dynamic> toMap() => toJson();
}
