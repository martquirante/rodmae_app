import '../core/utils.dart';

final class UpcomingPayment {
  final String id;
  final String coupleId;
  final String title;
  final double amount;
  final DateTime dueDate;
  final bool isRecurring;

  // New fields for installments and custom intervals
  final bool isInstallment;
  final int? totalInstallments;
  final int? currentInstallment;
  final String? recurrenceInterval; // e.g. 'monthly', 'weekly', 'yearly'

  const UpcomingPayment({
    required this.id,
    required this.coupleId,
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.isRecurring,
    this.isInstallment = false,
    this.totalInstallments,
    this.currentInstallment,
    this.recurrenceInterval = 'monthly',
  });

  factory UpcomingPayment.fromMap(Map<String, dynamic> row) {
    return UpcomingPayment(
      id: row['id']?.toString() ?? '',
      coupleId: row['couple_id']?.toString() ?? '',
      title: row['title']?.toString() ?? 'Upcoming Bill',
      amount: Formatters.asDouble(row['amount'] ?? 0.0),
      dueDate: Formatters.asDate(row['due_date']),
      isRecurring: row['is_recurring'] == true,
      isInstallment: row['is_installment'] == true,
      totalInstallments: row['total_installments'] != null
          ? int.tryParse(row['total_installments'].toString())
          : null,
      currentInstallment: row['current_installment'] != null
          ? int.tryParse(row['current_installment'].toString())
          : null,
      recurrenceInterval: row['recurrence_interval']?.toString() ?? 'monthly',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'couple_id': coupleId,
      'title': title,
      'amount': amount,
      'due_date': dueDate.toIso8601String(),
      'is_recurring': isRecurring,
      'is_installment': isInstallment,
      if (totalInstallments != null) 'total_installments': totalInstallments,
      if (currentInstallment != null) 'current_installment': currentInstallment,
      if (recurrenceInterval != null) 'recurrence_interval': recurrenceInterval,
    };
  }

  UpcomingPayment copyWith({
    String? id,
    String? coupleId,
    String? title,
    double? amount,
    DateTime? dueDate,
    bool? isRecurring,
    bool? isInstallment,
    int? totalInstallments,
    int? currentInstallment,
    String? recurrenceInterval,
  }) {
    return UpcomingPayment(
      id: id ?? this.id,
      coupleId: coupleId ?? this.coupleId,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
      isRecurring: isRecurring ?? this.isRecurring,
      isInstallment: isInstallment ?? this.isInstallment,
      totalInstallments: totalInstallments ?? this.totalInstallments,
      currentInstallment: currentInstallment ?? this.currentInstallment,
      recurrenceInterval: recurrenceInterval ?? this.recurrenceInterval,
    );
  }
}
