import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../core/utils.dart';

final class ReceiptExtraction {
  final String storeName;
  final double totalAmount;
  final String category;

  const ReceiptExtraction({
    required this.storeName,
    required this.totalAmount,
    required this.category,
  });

  factory ReceiptExtraction.fromJson(Map<String, dynamic> json) {
    String stringValue(List<String> keys, String fallback) {
      for (final key in keys) {
        final value = json[key];
        if (value != null && '$value'.trim().isNotEmpty) {
          return '$value'.trim();
        }
      }
      return fallback;
    }

    return ReceiptExtraction(
      storeName: stringValue(
        ['store', 'store_name', 'Store Name', 'merchant', 'merchant_name'],
        'Receipt Expense',
      ),
      totalAmount: Formatters.asDouble(
        json['total'] ??
            json['total_amount'] ??
            json['Total Amount'] ??
            json['amount'],
      ),
      category: stringValue(
        ['category', 'Category', 'expense_category'],
        'Receipts',
      ),
    );
  }
}

final class MealPlanDay {
  final String day;
  final String breakfast;
  final String lunch;
  final String dinner;
  final List<String> ingredients;

  const MealPlanDay({
    required this.day,
    required this.breakfast,
    required this.lunch,
    required this.dinner,
    required this.ingredients,
  });

  factory MealPlanDay.fromJson(Map<String, dynamic> json) {
    final rawIngredients = json['ingredients'];
    final ingredients = rawIngredients is List
        ? rawIngredients.map((item) => '$item'.trim()).where((item) {
            return item.isNotEmpty;
          }).toList()
        : <String>[];
    return MealPlanDay(
      day: '${json['day'] ?? 'Day'}',
      breakfast: '${json['breakfast'] ?? 'Oatmeal and fruit'}',
      lunch: '${json['lunch'] ?? 'Chicken adobo with rice'}',
      dinner: '${json['dinner'] ?? 'Vegetable soup'}',
      ingredients: ingredients,
    );
  }
}

final class GroceryChecklistItem {
  final String name;
  bool checked;

  GroceryChecklistItem({
    required this.name,
    this.checked = false,
  });
}

final class GoalItem {
  final String id;
  final String title;
  final String category;
  bool completed;

  GoalItem({
    required this.id,
    required this.title,
    required this.category,
    required this.completed,
  });
}

final class MemoryItem {
  final String imageUrl;
  final String title;
  final String dateLabel;
  final String caption;

  const MemoryItem({
    required this.imageUrl,
    required this.title,
    required this.dateLabel,
    required this.caption,
  });
}

final class MapPerson {
  final String name;
  final String locationLabel;
  final LatLng position;
  final Color color;
  final IconData icon;

  const MapPerson({
    required this.name,
    required this.locationLabel,
    required this.position,
    required this.color,
    required this.icon,
  });
}

final class LoveTrigger {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String animationAsset;
  final String overlayTitle;

  const LoveTrigger({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.animationAsset,
    required this.overlayTitle,
  });
}
