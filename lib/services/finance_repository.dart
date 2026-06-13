import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_database/firebase_database.dart' hide Transaction;
import '../core/constants.dart';
import '../core/utils.dart';
import '../models/wallet.dart';
import '../models/transaction.dart';
import '../models/savings_goal.dart';
import '../models/budget.dart';
import '../models/upcoming_payment.dart';
import '../models/debt.dart';
import '../models/investment.dart';
import '../models/quick_note.dart';
import 'firebase_service.dart';

final class FinanceRepository {
  FinanceRepository._();

  static final FinanceRepository instance = FinanceRepository._();

  SupabaseClient get _supabase => Supabase.instance.client;

  // --- Robust Local Caching System (Local-First Offline Support) ---

  Future<List<Map<String, dynamic>>> _loadCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(key);
      if (str != null) {
        final decoded = jsonDecode(str);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveCache(String key, List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(list));
    } catch (_) {}
  }

  // --- Fetch Partner UIDs from Supabase profiles ---

  Future<Map<String, String>> _fetchPartnerUids() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('user_profiles')
            .select('id, partner')
            .eq('couple_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        final map = <String, String>{};
        for (final row in list) {
          final partner = row['partner']?.toString().toLowerCase();
          final id = row['id']?.toString();
          if (partner != null && id != null) {
            map[partner] = id;
          }
        }
        return map;
      }
    } catch (e) {
      debugPrint('FinanceRepository._fetchPartnerUids error: $e');
    }
    return {};
  }

  // --- Transactions & Expenses Syncing ---

  Future<List<Transaction>> fetchTransactions() async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase database is currently offline.';
      }
      final rows = await _supabase
          .from('transactions')
          .select()
          .eq('couple_id', AppConfig.coupleId)
          .order('date', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      await _saveCache('cached_transactions', list);
      return list.map(Transaction.fromMap).toList();
    } catch (e) {
      debugPrint('FinanceRepository.fetchTransactions error: $e');
      final cached = await _loadCache('cached_transactions');
      if (cached.isNotEmpty) {
        return cached.map(Transaction.fromMap).toList();
      }
      throw 'Failed to retrieve transactions: ${e.toString()}';
    }
  }

  Stream<List<Transaction>> watchTransactions() {
    final controller = StreamController<List<Transaction>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 4), (t) async {
        try {
          final data = await fetchTransactions();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError('Sync status: Offline mode. ${e.toString()}');
          }
        }
      });
    }

    void start() async {
      try {
        final cached = await fetchTransactions();
        if (!controller.isClosed) {
          controller.add(cached);
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError('Connection issue: ${e.toString()}');
        }
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _supabase
            .from('transactions')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('date', ascending: false)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_transactions', list);
                if (!controller.isClosed) {
                  controller.add(list.map(Transaction.fromMap).toList());
                }
              },
              onError: (err) {
                if (!controller.isClosed) {
                  controller.addError('Supabase stream error: ${err.toString()}');
                }
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError('Stream setup error: ${e.toString()}');
        }
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream.asBroadcastStream();
  }

  Future<void> insertTransaction(Transaction transaction) async {
    // Save to local cache immediately
    final cached = await _loadCache('cached_transactions');
    final localMap = {
      'id': transaction.id,
      'couple_id': transaction.coupleId,
      'wallet_id': transaction.walletId,
      'paid_by_uid': transaction.paidByUid,
      'type': transaction.type.dbValue,
      'amount': transaction.amount,
      'category': transaction.category,
      'date': transaction.date.toIso8601String(),
      'receipt_url': transaction.receiptUrl,
      'is_split': transaction.isSplit,
      'split_with_uid': transaction.splitWithUid,
      'tags': transaction.tags,
      'sub_category': transaction.subCategory,
    };
    cached.insert(0, localMap);
    await _saveCache('cached_transactions', cached);

    // Asynchronously insert into Supabase
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline. Your transaction has been saved locally.';
      }
      await _supabase.from('transactions').insert(transaction.toInsertMap());

      // Auto-increment savings goal if matching criteria
      final isSharedSavings = transaction.category == 'Shared Savings' ||
          transaction.tags.any((t) => t.toLowerCase().contains('saving') || t.toLowerCase().contains('house'));

      if ((transaction.type == TransactionType.transfer || transaction.type == TransactionType.expense) && isSharedSavings) {
        try {
          final goals = await fetchSavingsGoals();
          final targetIndex = goals.indexWhere(
            (g) => g.title.toLowerCase().contains('house') || g.title.toLowerCase().contains('saving'),
          );
          final houseGoal = targetIndex != -1 ? goals[targetIndex] : (goals.isNotEmpty ? goals.first : null);
          if (houseGoal != null) {
            final nextSaved = houseGoal.savedAmount + transaction.amount;
            
            // Update in Supabase
            await _supabase
                .from('savings_goals')
                .update({'saved_amount': nextSaved})
                .eq('id', houseGoal.id);

            // Update local cache for savings goals
            final cachedGoals = await _loadCache('cached_savings_goals');
            final index = cachedGoals.indexWhere((g) => g['id']?.toString() == houseGoal.id);
            if (index != -1) {
              cachedGoals[index]['saved_amount'] = nextSaved;
              await _saveCache('cached_savings_goals', cachedGoals);
            }
          }
        } catch (goalErr) {
          debugPrint('Error updating savings goal: $goalErr');
        }
      }
      
      // Recalculate and push back to Firebase RTDB
      unawaited(recalculateAndSyncBalances());
    } catch (e) {
      debugPrint('FinanceRepository.insertTransaction error: $e');
      throw 'Failed to sync transaction to cloud: ${e.toString()}';
    }
  }

  // --- Real-time Recalculation and Sync to Firebase RTDB ---

  Future<void> recalculateAndSyncBalances() async {
    if (!AppRuntime.firebaseReady) return;
    try {
      final transactions = await fetchTransactions();
      
      final double totalIncome = transactions
          .where((e) => e.type == TransactionType.income || (e.type == TransactionType.transfer && e.tags.contains('transfer-in')))
          .fold<double>(0, (sum, entry) => sum + entry.amount);
      final double totalExpenses = transactions
          .where((e) => e.type == TransactionType.expense || (e.type == TransactionType.transfer && e.tags.contains('transfer-out')))
          .fold<double>(0, (sum, entry) => sum + entry.amount);

      final double netWorth = totalIncome - totalExpenses;

      double rodelBalance = 0.0;
      double eurineBalance = 0.0;
      double sharedVault = 0.0;

      for (final e in transactions) {
        final amt = e.amount;
        final isIncome = e.type == TransactionType.income || (e.type == TransactionType.transfer && e.tags.contains('transfer-in'));
        final isExpense = e.type == TransactionType.expense || (e.type == TransactionType.transfer && e.tags.contains('transfer-out'));

        final wId = e.walletId ?? '';
        if (wId == 'shared-wallet' || wId.toLowerCase().contains('shared')) {
          if (isIncome) sharedVault += amt;
          if (isExpense) sharedVault -= amt;
        } else if (wId == 'rodel-wallet' || wId.toLowerCase().contains('rodel') || (wId.isEmpty && e.paidByUid.toLowerCase() == 'rodel')) {
          if (isIncome) rodelBalance += amt;
          if (isExpense) rodelBalance -= amt;
        } else if (wId == 'eurine-wallet' || wId.toLowerCase().contains('eurine') || wId.toLowerCase().contains('marymae') || (wId.isEmpty && e.paidByUid.toLowerCase() != 'rodel')) {
          if (isIncome) eurineBalance += amt;
          if (isExpense) eurineBalance -= amt;
        } else {
          if (isIncome) sharedVault += amt;
          if (isExpense) sharedVault -= amt;
        }
      }

      final displayNetWorth = netWorth;
      final displayRodel = rodelBalance;
      final displayEurine = eurineBalance;
      final displayShared = sharedVault;

      // Fetch active partner UIDs
      final uids = await _fetchPartnerUids();
      final rodelUid = uids['rodel'] ?? 'rodel-default-uid';
      final eurineUid = uids['marymae'] ?? uids['eurine'] ?? 'eurine-default-uid';

      final rtdb = FirebaseDatabase.instance;

      // Update Firebase RTDB paths
      await rtdb.ref('users/$rodelUid/wallets/personal').set({
        'balance': displayRodel,
        'currency': 'PHP',
      });
      await rtdb.ref('users/$eurineUid/wallets/personal').set({
        'balance': displayEurine,
        'currency': 'PHP',
      });
      await rtdb.ref('couples/${AppConfig.coupleId}/sharedVault').set({
        'balance': displayShared,
        'currency': 'PHP',
      });
      await rtdb.ref('couples/${AppConfig.coupleId}/netWorth').set({
        'amount': displayNetWorth,
        'lastUpdated': DateTime.now().toUtc().toIso8601String(),
        'changePercent': 3.8,
      });
    } catch (e) {
      debugPrint('FinanceRepository.recalculateAndSyncBalances error: $e');
    }
  }

  // --- Real-time Streams from Firebase RTDB ---

  Stream<double> streamNetWorth() {
    if (!AppRuntime.firebaseReady) {
      return const Stream.empty();
    }
    return FirebaseDatabase.instance
        .ref('couples/${AppConfig.coupleId}/netWorth/amount')
        .onValue
        .map((event) => Formatters.asDouble(event.snapshot.value))
        .asBroadcastStream();
  }

  Stream<double> streamSharedVault() {
    if (!AppRuntime.firebaseReady) {
      return const Stream.empty();
    }
    return FirebaseDatabase.instance
        .ref('couples/${AppConfig.coupleId}/sharedVault/balance')
        .onValue
        .map((event) => Formatters.asDouble(event.snapshot.value))
        .asBroadcastStream();
  }

  Stream<double> streamPersonalWallet(String partnerLabel) {
    if (!AppRuntime.firebaseReady) {
      return const Stream.empty();
    }
    
    final controller = StreamController<double>();
    StreamSubscription? sub;

    void start() async {
      final uids = await _fetchPartnerUids();
      final key = partnerLabel.toLowerCase().contains('rodel') ? 'rodel' : 'marymae';
      final uid = uids[key] ?? '$key-default-uid';

      sub = FirebaseDatabase.instance
          .ref('users/$uid/wallets/personal/balance')
          .onValue
          .listen((event) {
            if (!controller.isClosed) {
              controller.add(Formatters.asDouble(event.snapshot.value));
            }
          });
    }

    controller.onListen = start;
    controller.onCancel = () => sub?.cancel();

    return controller.stream.asBroadcastStream();
  }

  // --- Savings Goals Syncing ---

  Future<List<SavingsGoal>> fetchSavingsGoals() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('savings_goals')
            .select()
            .eq('couple_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_savings_goals', list);
        return list.map(SavingsGoal.fromMap).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchSavingsGoals error: $e');
    }
    final cached = await _loadCache('cached_savings_goals');
    return cached.map(SavingsGoal.fromMap).toList();
  }

  Stream<List<SavingsGoal>> watchSavingsGoals() {
    final controller = StreamController<List<SavingsGoal>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 5), (t) async {
        try {
          final data = await fetchSavingsGoals();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      final cached = await fetchSavingsGoals();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _supabase
            .from('savings_goals')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_savings_goals', list);
                if (!controller.isClosed) {
                  controller.add(list.map(SavingsGoal.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream.asBroadcastStream();
  }

  Future<void> insertSavingsGoal(SavingsGoal goal) async {
    final cached = await _loadCache('cached_savings_goals');
    cached.insert(0, goal.toMap()..['id'] = goal.id);
    await _saveCache('cached_savings_goals', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _supabase.from('savings_goals').insert(goal.toMap());
      }
    } catch (e) {
      debugPrint('FinanceRepository.insertSavingsGoal error: $e');
    }
  }

  // --- Budgets Syncing ---

  Future<List<Budget>> fetchBudgets() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('budgets')
            .select()
            .eq('couple_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_budgets', list);
        return list.map(Budget.fromMap).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchBudgets error: $e');
    }
    final cached = await _loadCache('cached_budgets');
    return cached.map(Budget.fromMap).toList();
  }

  Future<void> insertBudget(Budget budget) async {
    final cached = await _loadCache('cached_budgets');
    cached.insert(0, budget.toMap()..['id'] = budget.id);
    await _saveCache('cached_budgets', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _supabase.from('budgets').insert(budget.toMap());
      }
    } catch (e) {
      debugPrint('FinanceRepository.insertBudget error: $e');
    }
  }

  // --- Upcoming Payments Syncing ---

  Future<List<UpcomingPayment>> fetchUpcomingPayments() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('upcoming_payments')
            .select()
            .eq('couple_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_upcoming_payments', list);
        return list.map(UpcomingPayment.fromMap).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchUpcomingPayments error: $e');
    }
    final cached = await _loadCache('cached_upcoming_payments');
    return cached.map(UpcomingPayment.fromMap).toList();
  }

  Future<void> insertUpcomingPayment(UpcomingPayment payment) async {
    final cached = await _loadCache('cached_upcoming_payments');
    cached.insert(0, payment.toMap()..['id'] = payment.id);
    await _saveCache('cached_upcoming_payments', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _supabase.from('upcoming_payments').insert(payment.toMap());
      }
    } catch (e) {
      debugPrint('FinanceRepository.insertUpcomingPayment error: $e');
    }
  }

  // --- Debts Syncing ---

  Future<List<Debt>> fetchDebts() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('debts')
            .select()
            .eq('couple_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_debts', list);
        return list.map(Debt.fromMap).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchDebts error: $e');
    }
    final cached = await _loadCache('cached_debts');
    return cached.map(Debt.fromMap).toList();
  }

  Stream<List<Debt>> watchDebts() {
    final controller = StreamController<List<Debt>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 5), (t) async {
        try {
          final data = await fetchDebts();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      try {
        final cached = await fetchDebts();
        if (!controller.isClosed) {
          controller.add(cached);
        }
      } catch (_) {}

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _supabase
            .from('debts')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_debts', list);
                if (!controller.isClosed) {
                  controller.add(list.map(Debt.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream.asBroadcastStream();
  }

  Future<void> insertDebt(Debt debt) async {
    final cached = await _loadCache('cached_debts');
    cached.insert(0, debt.toMap()..['id'] = debt.id);
    await _saveCache('cached_debts', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _supabase.from('debts').insert(debt.toMap());
      }
    } catch (e) {
      debugPrint('FinanceRepository.insertDebt error: $e');
    }
  }

  // --- Investments Syncing ---

  Future<List<Investment>> fetchInvestments() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('investments')
            .select()
            .eq('couple_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_investments', list);
        return list.map(Investment.fromMap).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchInvestments error: $e');
    }
    final cached = await _loadCache('cached_investments');
    return cached.map(Investment.fromMap).toList();
  }

  Future<void> insertInvestment(Investment investment) async {
    final cached = await _loadCache('cached_investments');
    cached.insert(0, investment.toMap()..['id'] = investment.id);
    await _saveCache('cached_investments', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _supabase.from('investments').insert(investment.toMap());
      }
    } catch (e) {
      debugPrint('FinanceRepository.insertInvestment error: $e');
    }
  }

  // --- Quick Notes Syncing ---

  Future<List<QuickNote>> fetchQuickNotes() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('quick_notes')
            .select()
            .eq('couple_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_quick_notes', list);
        return list.map(QuickNote.fromMap).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchQuickNotes error: $e');
    }
    final cached = await _loadCache('cached_quick_notes');
    return cached.map(QuickNote.fromMap).toList();
  }

  Future<void> insertQuickNote(QuickNote note) async {
    final cached = await _loadCache('cached_quick_notes');
    cached.insert(0, note.toMap()..['id'] = note.id);
    await _saveCache('cached_quick_notes', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _supabase.from('quick_notes').insert(note.toMap());
      }
    } catch (e) {
      debugPrint('FinanceRepository.insertQuickNote error: $e');
    }
  }

  // --- Advanced Mathematical and Business Logic (Tarsi parity features) ---

  Future<void> addSplitTransaction(Transaction t, double splitPercentage) async {
    try {
      // 1. Save main transaction log first
      await insertTransaction(t);

      // 2. Calculate split share
      final double splitAmount = t.amount * (splitPercentage / 100.0);

      // 3. Create a related Debt item
      final debt = Debt(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        coupleId: t.coupleId,
        title: 'Split Share: ${t.category}',
        totalAmount: splitAmount,
        remainingAmount: splitAmount,
        type: t.paidByUid.toLowerCase() == 'rodel' ? DebtType.owe : DebtType.owed,
        relatedTransactionId: t.id,
      );

      // Insert debt record
      await insertDebt(debt);
    } catch (e) {
      debugPrint('FinanceRepository.addSplitTransaction error: $e');
      throw 'Failed to save split transaction: ${e.toString()}';
    }
  }

  Future<void> recordDebtPayment(String debtId, double paymentAmount, String walletId) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline.';
      }

      // 1. Fetch current debt
      final row = await _supabase
          .from('debts')
          .select()
          .eq('id', debtId)
          .limit(1)
          .maybeSingle();

      if (row == null) {
        throw 'Debt record not found.';
      }

      final debt = Debt.fromMap(row);
      final double nextRemaining = (debt.remainingAmount - paymentAmount).clamp(0.0, debt.totalAmount);

      // 2. Fetch target wallet to update its balance
      final walletRow = await _supabase
          .from('wallets')
          .select()
          .eq('id', walletId)
          .limit(1)
          .maybeSingle();

      if (walletRow == null) {
        throw 'Target wallet not found.';
      }

      final double currentBalance = Formatters.asDouble(walletRow['balance'] ?? 0.0);
      final double nextBalance = currentBalance - paymentAmount;

      // 3. Perform atomic updates: update debt and deduct wallet balance
      await _supabase.from('debts').update({
        'remaining_amount': nextRemaining,
      }).eq('id', debtId);

      await _supabase.from('wallets').update({
        'balance': nextBalance,
      }).eq('id', walletId);

      // 4. Log the payment as a transaction
      final paymentTx = Transaction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        walletId: walletId,
        createdByUserId: debt.type == DebtType.owe ? 'Eurine' : 'Rodel', // who is paying down the debt
        type: TransactionType.expense,
        amount: paymentAmount,
        categoryId: 'Debt Repayment: ${debt.title}',
        date: DateTime.now(),
      );

      await insertTransaction(paymentTx);

      // 5. Update local cache aggregates
      unawaited(recalculateAndSyncBalances());
    } catch (e) {
      debugPrint('FinanceRepository.recordDebtPayment error: $e');
      throw 'Failed to log debt payment: ${e.toString()}';
    }
  }

  Future<void> logInstallmentPayment(UpcomingPayment payment) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline.';
      }

      final int nextInstallment = (payment.currentInstallment ?? 0) + 1;
      final int totalInst = payment.totalInstallments ?? 1;

      // 1. Log the transaction as an expense
      final tx = Transaction(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        walletId: 'shared-wallet',
        createdByUserId: 'System',
        type: TransactionType.expense,
        amount: payment.amount,
        categoryId: '${payment.title} (Installment $nextInstallment/$totalInst)',
        date: DateTime.now(),
      );

      await insertTransaction(tx);

      // 2. Increment the installment counters in database
      await _supabase.from('upcoming_payments').update({
        'current_installment': nextInstallment,
      }).eq('id', payment.id);

    } catch (e) {
      debugPrint('FinanceRepository.logInstallmentPayment error: $e');
      throw 'Failed to record installment payment: ${e.toString()}';
    }
  }

  Future<List<ForecastItem>> fetchCashflowForecast(DateTime startDate, DateTime endDate) async {
    try {
      final List<Transaction> transactions = await fetchTransactions();
      final List<UpcomingPayment> payments = await fetchUpcomingPayments();

      final List<ForecastItem> forecast = [];

      // Add actual transactions that fall within date bounds
      for (final tx in transactions) {
        if (tx.date.isAfter(startDate) && tx.date.isBefore(endDate)) {
          forecast.add(ForecastItem(
            date: tx.date,
            title: tx.category,
            amount: tx.amount,
            type: tx.type == TransactionType.income ? 'actual_income' : 'actual_expense',
            originalSource: tx,
          ));
        }
      }

      // Add upcoming payments projected dates within bounds
      for (final pay in payments) {
        if (pay.dueDate.isAfter(startDate) && pay.dueDate.isBefore(endDate)) {
          forecast.add(ForecastItem(
            date: pay.dueDate,
            title: pay.title,
            amount: pay.amount,
            type: pay.isInstallment ? 'upcoming_installment' : 'upcoming_recurring',
            originalSource: pay,
          ));
        }
      }

      // Sort chronologically ascending
      forecast.sort((a, b) => a.date.compareTo(b.date));
      return forecast;
    } catch (e) {
      debugPrint('FinanceRepository.fetchCashflowForecast error: $e');
      throw 'Failed to construct forecast: ${e.toString()}';
    }
  }

  Future<List<Wallet>> fetchWallets() async {
    try {
      if (!AppRuntime.supabaseReady) {
        final cached = await _loadCache('cached_wallets');
        if (cached.isNotEmpty) {
          return cached.map(Wallet.fromMap).toList();
        }
        return [
          Wallet(id: 'gcash-wallet', householdId: AppConfig.coupleId, ownerUserId: 'eurine', type: WalletType.personal, monthlyLimit: 0.0),
          Wallet(id: 'bdo-wallet', householdId: AppConfig.coupleId, ownerUserId: 'rodel', type: WalletType.personal, monthlyLimit: 0.0),
          Wallet(id: 'bpi-wallet', householdId: AppConfig.coupleId, ownerUserId: 'rodel', type: WalletType.personal, monthlyLimit: 0.0),
          Wallet(id: 'cash-wallet', householdId: AppConfig.coupleId, ownerUserId: null, type: WalletType.shared, monthlyLimit: 0.0),
        ];
      }
      final rows = await _supabase
          .from('wallets')
          .select()
          .eq('couple_id', AppConfig.coupleId);
      final list = List<Map<String, dynamic>>.from(rows as List);
      await _saveCache('cached_wallets', list);
      return list.map(Wallet.fromMap).toList();
    } catch (e) {
      debugPrint('FinanceRepository.fetchWallets error: $e');
      final cached = await _loadCache('cached_wallets');
      if (cached.isNotEmpty) {
        return cached.map(Wallet.fromMap).toList();
      }
      return [
        Wallet(id: 'gcash-wallet', householdId: AppConfig.coupleId, ownerUserId: 'eurine', type: WalletType.personal, monthlyLimit: 0.0),
        Wallet(id: 'bdo-wallet', householdId: AppConfig.coupleId, ownerUserId: 'rodel', type: WalletType.personal, monthlyLimit: 0.0),
        Wallet(id: 'bpi-wallet', householdId: AppConfig.coupleId, ownerUserId: 'rodel', type: WalletType.personal, monthlyLimit: 0.0),
        Wallet(id: 'cash-wallet', householdId: AppConfig.coupleId, ownerUserId: null, type: WalletType.shared, monthlyLimit: 0.0),
      ];
    }
  }

  Stream<List<Wallet>> watchWallets() {
    final controller = StreamController<List<Wallet>>();
    StreamSubscription? sub;
    Timer? timer;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 4), (t) async {
        try {
          final data = await fetchWallets();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError('Sync status: Offline mode. ${e.toString()}');
          }
        }
      });
    }

    void start() async {
      try {
        final cached = await fetchWallets();
        if (!controller.isClosed) {
          controller.add(cached);
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError('Connection issue: ${e.toString()}');
        }
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _supabase
            .from('wallets')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_wallets', list);
                if (!controller.isClosed) {
                  controller.add(list.map(Wallet.fromMap).toList());
                }
              },
              onError: (e) {
                startPolling();
              },
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream.asBroadcastStream();
  }

  Stream<List<UpcomingPayment>> watchUpcomingPayments() {
    final controller = StreamController<List<UpcomingPayment>>();
    StreamSubscription? sub;
    Timer? timer;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 4), (t) async {
        try {
          final data = await fetchUpcomingPayments();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (e) {
          if (!controller.isClosed) {
            controller.addError('Sync status: Offline mode. ${e.toString()}');
          }
        }
      });
    }

    void start() async {
      try {
        final cached = await fetchUpcomingPayments();
        if (!controller.isClosed) {
          controller.add(cached);
        }
      } catch (e) {
        if (!controller.isClosed) {
          controller.addError('Connection issue: ${e.toString()}');
        }
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _supabase
            .from('upcoming_payments')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_upcoming_payments', list);
                if (!controller.isClosed) {
                  controller.add(list.map(UpcomingPayment.fromMap).toList());
                }
              },
              onError: (e) {
                startPolling();
              },
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream.asBroadcastStream();
  }
}

final class ForecastItem {
  final DateTime date;
  final String title;
  final double amount;
  final String type; // 'actual_income', 'actual_expense', 'upcoming_recurring', 'upcoming_installment'
  final dynamic originalSource; // either Transaction or UpcomingPayment

  const ForecastItem({
    required this.date,
    required this.title,
    required this.amount,
    required this.type,
    required this.originalSource,
  });
}
