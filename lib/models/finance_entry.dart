import '../core/constants.dart';
import '../core/utils.dart';

enum FinanceType {
  income,
  expense;

  String get dbValue => name;

  static FinanceType from(dynamic value) {
    final text = '$value'.toLowerCase();
    if (text.contains('income') || text.contains('deposit')) {
      return FinanceType.income;
    }
    return FinanceType.expense;
  }
}

final class FinanceEntry {
  final String id;
  final String title;
  final String category;
  final double amount;
  final FinanceType type;
  final DateTime date;
  final String createdBy;

  const FinanceEntry({
    required this.id,
    required this.title,
    required this.category,
    required this.amount,
    required this.type,
    required this.date,
    required this.createdBy,
  });

  factory FinanceEntry.fromMap(Map<String, dynamic> row) {
    final dbTitle = '${row['title'] ?? 'Expense'}';
    String category = 'Shared';
    String title = dbTitle;
    
    // Parse the [Category] - [Title] combination
    if (dbTitle.contains(' - ')) {
      final parts = dbTitle.split(' - ');
      category = parts.first;
      title = parts.sublist(1).join(' - ');
    }
    
    return FinanceEntry(
      id: '${row['id'] ?? row['created_at'] ?? row['title']}',
      title: title,
      category: category,
      amount: Formatters.asDouble(row['amount'] ?? row['total']),
      type: FinanceType.from(row['type']),
      date: Formatters.asDate(row['date'] ?? row['created_at']),
      createdBy: '${row['created_by'] ?? 'RodMae'}',
    );
  }

  Map<String, dynamic> toInsertMap() {
    return {
      'couple_id': AppConfig.coupleId,
      // Store category cleanly inside the title column so we conform to the SQL schema
      'title': '$category - $title',
      'amount': amount,
      // Map to exact SQL enum comments: 'Expense' or 'Income'
      'type': type == FinanceType.income ? 'Income' : 'Expense',
      'date': Formatters.date(date),
      'created_by': createdBy,
    };
  }
}
