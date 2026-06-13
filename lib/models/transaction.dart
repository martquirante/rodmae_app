import '../core/utils.dart';
import 'transaction_reaction.dart';
import 'transaction_comment.dart';

enum TransactionType {
  income,
  expense,
  transfer;

  String get dbValue => name;

  static TransactionType from(dynamic value) {
    final text = '$value'.toLowerCase();
    if (text.contains('income') || text.contains('deposit')) {
      return TransactionType.income;
    }
    if (text.contains('transfer')) {
      return TransactionType.transfer;
    }
    return TransactionType.expense;
  }
}

final class TransactionSplit {
  final String transactionId;
  final String userId;
  final double amountOwed;
  final bool isSettled;

  const TransactionSplit({
    required this.transactionId,
    required this.userId,
    required this.amountOwed,
    required this.isSettled,
  });

  factory TransactionSplit.fromJson(Map<String, dynamic> json) {
    return TransactionSplit(
      transactionId: json['transaction_id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? json['user_uid']?.toString() ?? '',
      amountOwed: Formatters.asDouble(json['amount_owed'] ?? 0.0),
      isSettled: json['is_settled'] == true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'transaction_id': transactionId,
      'user_id': userId,
      'amount_owed': amountOwed,
      'is_settled': isSettled,
    };
  }

  TransactionSplit copyWith({
    String? transactionId,
    String? userId,
    double? amountOwed,
    bool? isSettled,
  }) {
    return TransactionSplit(
      transactionId: transactionId ?? this.transactionId,
      userId: userId ?? this.userId,
      amountOwed: amountOwed ?? this.amountOwed,
      isSettled: isSettled ?? this.isSettled,
    );
  }
}

final class Transaction {
  final String id;
  final String walletId;
  final String? categoryId;
  final String createdByUserId;
  final double amount;
  final DateTime date;
  final String? notes;
  final TransactionType type;
  final List<TransactionSplit> splits;
  final List<TransactionReaction> reactions;
  final List<TransactionComment> comments;

  // Backward compatibility properties for repository and older UI parts
  String get coupleId => walletId;
  String get paidByUid => createdByUserId;
  String get category => categoryId ?? 'General';
  String? get subCategory => null;
  List<String> get tags => const [];
  String? get receiptUrl => null;
  bool get isSplit => splits.isNotEmpty;
  String? get splitWithUid => splits.isNotEmpty ? splits.first.userId : null;

  const Transaction({
    required this.id,
    required this.walletId,
    this.categoryId,
    required this.createdByUserId,
    required this.amount,
    required this.date,
    this.notes,
    this.type = TransactionType.expense,
    this.splits = const [],
    this.reactions = const [],
    this.comments = const [],
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final rawSplits = json['splits'] as List?;
    final parsedSplits = rawSplits != null
        ? rawSplits.map((e) => TransactionSplit.fromJson(Map<String, dynamic>.from(e))).toList()
        : const <TransactionSplit>[];

    final rawReactions = json['reactions'] as List?;
    final parsedReactions = rawReactions != null
        ? rawReactions.map((e) => TransactionReaction.fromJson(Map<String, dynamic>.from(e))).toList()
        : const <TransactionReaction>[];

    final rawComments = json['comments'] as List?;
    final parsedComments = rawComments != null
        ? rawComments.map((e) => TransactionComment.fromJson(Map<String, dynamic>.from(e))).toList()
        : const <TransactionComment>[];

    return Transaction(
      id: json['id']?.toString() ?? '',
      walletId: json['wallet_id']?.toString() ?? '',
      categoryId: json['category_id']?.toString() ?? json['category']?.toString(),
      createdByUserId: json['created_by_user_id']?.toString() ?? json['paid_by_uid']?.toString() ?? json['created_by']?.toString() ?? '',
      amount: Formatters.asDouble(json['amount'] ?? json['total'] ?? 0.0),
      date: Formatters.asDate(json['date'] ?? json['created_at']),
      notes: json['notes']?.toString(),
      type: TransactionType.from(json['type'] ?? 'expense'),
      splits: parsedSplits,
      reactions: parsedReactions,
      comments: parsedComments,
    );
  }

  factory Transaction.fromMap(Map<String, dynamic> map) => Transaction.fromJson(map);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'wallet_id': walletId,
      'category_id': categoryId,
      'created_by_user_id': createdByUserId,
      'amount': amount,
      'date': date.toIso8601String(),
      'type': type.dbValue,
      if (notes != null) 'notes': notes,
      if (splits.isNotEmpty) 'splits': splits.map((e) => e.toJson()).toList(),
      if (reactions.isNotEmpty) 'reactions': reactions.map((e) => e.toJson()).toList(),
      if (comments.isNotEmpty) 'comments': comments.map((e) => e.toJson()).toList(),
    };
  }

  Map<String, dynamic> toMap() => toJson();
  Map<String, dynamic> toInsertMap() => toJson();

  Transaction copyWith({
    String? id,
    String? walletId,
    String? categoryId,
    String? createdByUserId,
    double? amount,
    DateTime? date,
    String? notes,
    TransactionType? type,
    List<TransactionSplit>? splits,
    List<TransactionReaction>? reactions,
    List<TransactionComment>? comments,
  }) {
    return Transaction(
      id: id ?? this.id,
      walletId: walletId ?? this.walletId,
      categoryId: categoryId ?? this.categoryId,
      createdByUserId: createdByUserId ?? this.createdByUserId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      type: type ?? this.type,
      splits: splits ?? this.splits,
      reactions: reactions ?? this.reactions,
      comments: comments ?? this.comments,
    );
  }
}
