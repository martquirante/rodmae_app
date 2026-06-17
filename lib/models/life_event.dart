import '../core/utils.dart';

final class LifeEventCostItem {
  final String id;
  final String eventId;
  final String itemName;
  final double estimatedAmount;
  final bool isRecurring;

  const LifeEventCostItem({
    required this.id,
    required this.eventId,
    required this.itemName,
    required this.estimatedAmount,
    required this.isRecurring,
  });

  factory LifeEventCostItem.fromJson(Map<String, dynamic> json) {
    return LifeEventCostItem(
      id: json['id']?.toString() ?? '',
      eventId: json['event_id']?.toString() ?? '',
      itemName: json['item_name']?.toString() ?? '',
      estimatedAmount: Formatters.asDouble(json['estimated_amount'] ?? 0.0),
      isRecurring: json['is_recurring'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_id': eventId,
      'item_name': itemName,
      'estimated_amount': estimatedAmount,
      'is_recurring': isRecurring,
    };
  }
}

final class LifeEvent {
  final String id;
  final String householdId;
  final String type; // e.g. Baby, New Home, Wedding Anniversary, Car, Education Fund, Abroad Trip
  final String name;
  final DateTime? targetDate;
  final double estimatedCost;
  final double currentSaved;
  final List<LifeEventCostItem> costItems;

  const LifeEvent({
    required this.id,
    required this.householdId,
    required this.type,
    required this.name,
    this.targetDate,
    required this.estimatedCost,
    required this.currentSaved,
    this.costItems = const [],
  });

  factory LifeEvent.fromJson(Map<String, dynamic> json) {
    final rawItems = json['cost_items'] as List?;
    final parsedItems = rawItems != null
        ? rawItems.map((e) => LifeEventCostItem.fromJson(Map<String, dynamic>.from(e))).toList()
        : const <LifeEventCostItem>[];

    return LifeEvent(
      id: json['id']?.toString() ?? '',
      householdId: json['household_id']?.toString() ?? json['couple_id']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      targetDate: json['target_date'] != null ? Formatters.asDate(json['target_date']) : null,
      estimatedCost: Formatters.asDouble(json['estimated_cost'] ?? 0.0),
      currentSaved: Formatters.asDouble(json['current_saved'] ?? 0.0),
      costItems: parsedItems,
    );
  }

  factory LifeEvent.fromMap(Map<String, dynamic> map) => LifeEvent.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'household_id': householdId,
      'type': type,
      'name': name,
      if (targetDate != null) 'target_date': targetDate!.toIso8601String(),
      'estimated_cost': estimatedCost,
      'current_saved': currentSaved,
    };
  }

  Map<String, dynamic> toMap() => toJson();
}
