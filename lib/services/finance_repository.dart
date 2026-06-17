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
import '../models/income_entry.dart';
import '../models/life_event.dart';
import '../models/money_personality.dart';
import '../models/subscription_item.dart';
import '../models/checkin_item.dart';
import '../models/financial_alert.dart';
import '../models/occasion.dart';
import '../models/asset_liability.dart';
import '../models/net_worth_snapshot.dart';
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
          .select('*, reactions:transaction_reactions(*), comments:transaction_comments(*)')
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
            .eq('household_id', AppConfig.coupleId);
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
            .eq('household_id', AppConfig.coupleId)
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
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline. Savings goal saved locally.';
      }
      await _supabase.from('savings_goals').insert(goal.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.insertSavingsGoal error: $e');
      rethrow;
    }
  }

  // --- Budgets Syncing ---

  Future<List<Budget>> fetchBudgets() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('category_budgets')
            .select()
            .eq('household_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_budgets', list);
        return list.map((row) => Budget(
          id: row['id']?.toString() ?? '',
          coupleId: row['household_id']?.toString() ?? '',
          category: row['category']?.toString() ?? 'General',
          monthlyLimit: Formatters.asDouble(row['budget_limit'] ?? 0.0),
          spent: 0.0,
        )).toList();
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
        await _supabase.from('category_budgets').insert({
          'household_id': budget.coupleId,
          'category': budget.category,
          'budget_limit': budget.monthlyLimit,
          'period': 'monthly',
        });
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
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline. Debt saved locally.';
      }
      await _supabase.from('debts').insert(debt.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.insertDebt error: $e');
      rethrow;
    }
  }

  Future<void> deleteDebt(String debtId) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline.';
      }
      await _supabase.from('debts').delete().eq('id', debtId);
      
      // Update local cache
      final cached = await _loadCache('cached_debts');
      cached.removeWhere((d) => d['id']?.toString() == debtId);
      await _saveCache('cached_debts', cached);
    } catch (e) {
      debugPrint('FinanceRepository.deleteDebt error: $e');
      rethrow;
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
        id: UuidUtil.generate(),
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
      // 1. Get the current debt record (try from Supabase if ready, fallback to local cache)
      Map<String, dynamic>? debtMap;
      if (AppRuntime.supabaseReady) {
        try {
          debtMap = await _supabase
              .from('debts')
              .select()
              .eq('id', debtId)
              .limit(1)
              .maybeSingle();
        } catch (_) {}
      }

      if (debtMap == null) {
        // Fallback to local cache
        final cachedDebts = await _loadCache('cached_debts');
        final match = cachedDebts.firstWhere(
          (d) => d['id']?.toString() == debtId,
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          debtMap = match;
        }
      }

      if (debtMap == null) {
        throw 'Debt record not found locally or in cloud.';
      }

      final debt = Debt.fromMap(debtMap);
      final double nextRemaining = (debt.remainingAmount - paymentAmount).clamp(0.0, debt.totalAmount);

      // 2. Get the target wallet (try from Supabase if ready, fallback to local cache)
      Map<String, dynamic>? walletMap;
      if (AppRuntime.supabaseReady) {
        try {
          walletMap = await _supabase
              .from('wallets')
              .select()
              .eq('id', walletId)
              .limit(1)
              .maybeSingle();
        } catch (_) {}
      }

      if (walletMap == null) {
        // Fallback to local cache
        final cachedWallets = await _loadCache('cached_wallets');
        final match = cachedWallets.firstWhere(
          (w) => w['id']?.toString() == walletId,
          orElse: () => <String, dynamic>{},
        );
        if (match.isNotEmpty) {
          walletMap = match;
        }
      }

      if (walletMap == null) {
        throw 'Target wallet not found locally or in cloud.';
      }

      final double currentBalance = Formatters.asDouble(walletMap['balance'] ?? 0.0);
      final double nextBalance = currentBalance - paymentAmount;

      // 3. Update the local caches immediately
      // Update local cache for debts
      final cachedDebts = await _loadCache('cached_debts');
      final debtIndex = cachedDebts.indexWhere((d) => d['id']?.toString() == debtId);
      if (debtIndex != -1) {
        cachedDebts[debtIndex]['remaining_amount'] = nextRemaining;
        await _saveCache('cached_debts', cachedDebts);
      }

      // Update local cache for wallets
      final cachedWallets = await _loadCache('cached_wallets');
      final walletIndex = cachedWallets.indexWhere((w) => w['id']?.toString() == walletId);
      if (walletIndex != -1) {
        cachedWallets[walletIndex]['balance'] = nextBalance;
        await _saveCache('cached_wallets', cachedWallets);
      }

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

      // This will insert locally and try to sync to Supabase
      await insertTransaction(paymentTx);

      // 5. Try updating Supabase in the background
      if (AppRuntime.supabaseReady) {
        try {
          await _supabase.from('debts').update({
            'remaining_amount': nextRemaining,
          }).eq('id', debtId);

          await _supabase.from('wallets').update({
            'balance': nextBalance,
          }).eq('id', walletId);
        } catch (supabaseErr) {
          debugPrint('Supabase recordDebtPayment sync error: $supabaseErr');
        }
      }

      // 6. Recalculate balances
      unawaited(recalculateAndSyncBalances());
    } catch (e) {
      debugPrint('FinanceRepository.recordDebtPayment error: $e');
      throw 'Failed to log debt payment: ${e.toString()}';
    }
  }

  Future<void> logInstallmentPayment(UpcomingPayment payment) async {
    try {
      final int nextInstallment = (payment.currentInstallment ?? 0) + 1;
      final int totalInst = payment.totalInstallments ?? 1;

      // 1. Update local cache immediately
      final cachedUpcoming = await _loadCache('cached_upcoming_payments');
      final index = cachedUpcoming.indexWhere((p) => p['id']?.toString() == payment.id);
      if (index != -1) {
        cachedUpcoming[index]['current_installment'] = nextInstallment;
        await _saveCache('cached_upcoming_payments', cachedUpcoming);
      }

      // 2. Log the transaction as an expense (local-first)
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

      // 3. Try syncing the installment counter update to Supabase
      if (AppRuntime.supabaseReady) {
        try {
          await _supabase.from('upcoming_payments').update({
            'current_installment': nextInstallment,
          }).eq('id', payment.id);
        } catch (supabaseErr) {
          debugPrint('Supabase logInstallmentPayment sync error: $supabaseErr');
        }
      }
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
        if (cached.isNotEmpty) return cached.map(Wallet.fromMap).toList();
        return [];
      }
      final rows = await _supabase
          .from('wallets')
          .select()
          .eq('household_id', AppConfig.coupleId)
          .order('created_at', ascending: true);
      final list = List<Map<String, dynamic>>.from(rows as List);
      await _saveCache('cached_wallets', list);
      return list.map(Wallet.fromMap).toList();
    } catch (e) {
      debugPrint('FinanceRepository.fetchWallets error: $e');
      final cached = await _loadCache('cached_wallets');
      if (cached.isNotEmpty) return cached.map(Wallet.fromMap).toList();
      return [];
    }
  }

  Future<Wallet> addWallet(Wallet wallet) async {
    try {
      final row = await _supabase
          .from('wallets')
          .insert(wallet.toInsertMap())
          .select()
          .single();
      return Wallet.fromMap(row);
    } catch (e) {
      debugPrint('FinanceRepository.addWallet error: $e');
      rethrow;
    }
  }

  Future<void> updateWalletBalance(String walletId, double newBalance) async {
    try {
      await _supabase
          .from('wallets')
          .update({'balance': newBalance, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', walletId);
    } catch (e) {
      debugPrint('FinanceRepository.updateWalletBalance error: $e');
      rethrow;
    }
  }

  Future<void> deleteWallet(String walletId) async {
    try {
      await _supabase.from('wallets').delete().eq('id', walletId);
    } catch (e) {
      debugPrint('FinanceRepository.deleteWallet error: $e');
      rethrow;
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
            .eq('household_id', AppConfig.coupleId)
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

  // --- Income Entries ---
  Future<List<IncomeEntry>> fetchIncomeEntries() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('income_entries')
            .select()
            .eq('household_id', AppConfig.coupleId)
            .order('date', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_income_entries', list);
        return list.map(IncomeEntry.fromJson).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchIncomeEntries error: $e');
    }
    final cached = await _loadCache('cached_income_entries');
    return cached.map(IncomeEntry.fromJson).toList();
  }

  Future<void> insertIncomeEntry(IncomeEntry entry) async {
    final cached = await _loadCache('cached_income_entries');
    cached.insert(0, entry.toMap());
    await _saveCache('cached_income_entries', cached);
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline. Income entry saved locally.';
      }
      await _supabase.from('income_entries').insert(entry.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.insertIncomeEntry error: $e');
      rethrow;
    }
  }

  // --- Life Events ---
  Future<List<LifeEvent>> fetchLifeEvents() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('life_events')
            .select('*, cost_items:event_cost_items(*)')
            .eq('household_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_life_events', list);
        return list.map(LifeEvent.fromJson).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchLifeEvents error: $e');
    }
    final cached = await _loadCache('cached_life_events');
    return cached.map(LifeEvent.fromJson).toList();
  }

  Future<void> insertLifeEvent(LifeEvent event) async {
    final cached = await _loadCache('cached_life_events');
    cached.insert(0, event.toMap());
    await _saveCache('cached_life_events', cached);
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline. Life event saved locally.';
      }
      await _supabase.from('life_events').insert(event.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.insertLifeEvent error: $e');
      rethrow;
    }
  }

  Future<void> insertLifeEventCostItem(LifeEventCostItem item) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline.';
      }
      await _supabase.from('event_cost_items').insert(item.toJson());
    } catch (e) {
      debugPrint('FinanceRepository.insertLifeEventCostItem error: $e');
      rethrow;
    }
  }

  Future<void> deleteLifeEventCostItem(String itemId) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline.';
      }
      await _supabase.from('event_cost_items').delete().eq('id', itemId);
    } catch (e) {
      debugPrint('FinanceRepository.deleteLifeEventCostItem error: $e');
      rethrow;
    }
  }

  Future<void> updateLifeEventSavings(String eventId, double amount) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline.';
      }
      await _supabase
          .from('life_events')
          .update({'current_saved': amount})
          .eq('id', eventId);
      
      final cached = await _loadCache('cached_life_events');
      for (final ev in cached) {
        if (ev['id']?.toString() == eventId) {
          ev['current_saved'] = amount;
        }
      }
      await _saveCache('cached_life_events', cached);
    } catch (e) {
      debugPrint('FinanceRepository.updateLifeEventSavings error: $e');
      rethrow;
    }
  }

  // --- Check-Ins (Finance Dates) ---
  Future<List<CheckinItem>> fetchCheckins() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('checkins')
            .select()
            .eq('household_id', AppConfig.coupleId)
            .order('scheduled_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_checkins', list);
        return list.map(CheckinItem.fromJson).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchCheckins error: $e');
    }
    final cached = await _loadCache('cached_checkins');
    return cached.map(CheckinItem.fromJson).toList();
  }

  Future<void> insertCheckin(CheckinItem checkin) async {
    final cached = await _loadCache('cached_checkins');
    cached.insert(0, checkin.toMap());
    await _saveCache('cached_checkins', cached);
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline. Check-in saved locally.';
      }
      await _supabase.from('checkins').insert(checkin.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.insertCheckin error: $e');
      rethrow;
    }
  }

  // --- Smart Spending Alerts ---
  Future<List<FinancialAlert>> fetchAlerts() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('alerts')
            .select()
            .eq('household_id', AppConfig.coupleId)
            .order('created_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_alerts', list);
        return list.map(FinancialAlert.fromJson).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchAlerts error: $e');
    }
    final cached = await _loadCache('cached_alerts');
    return cached.map(FinancialAlert.fromJson).toList();
  }

  Future<void> insertAlert(FinancialAlert alert) async {
    final cached = await _loadCache('cached_alerts');
    cached.insert(0, alert.toMap());
    await _saveCache('cached_alerts', cached);
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline. Alert saved locally.';
      }
      await _supabase.from('alerts').insert(alert.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.insertAlert error: $e');
      rethrow;
    }
  }

  Future<void> markAlertAsRead(String alertId) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline.';
      }
      await _supabase
          .from('alerts')
          .update({'is_read': true})
          .eq('id', alertId);
    } catch (e) {
      debugPrint('FinanceRepository.markAlertAsRead error: $e');
      rethrow;
    }
  }

  // --- Money Personality ---
  Future<MoneyPersonality?> fetchMoneyPersonality(String userId) async {
    try {
      if (AppRuntime.supabaseReady) {
        final res = await _supabase
            .from('money_personalities')
            .select()
            .eq('user_id', userId)
            .maybeSingle();
        if (res != null) {
          return MoneyPersonality.fromJson(res);
        }
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchMoneyPersonality error: $e');
    }
    return null;
  }

  Future<void> saveMoneyPersonality(MoneyPersonality personality) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline. Quiz result saved locally.';
      }
      await _supabase
          .from('money_personalities')
          .upsert(personality.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.saveMoneyPersonality error: $e');
      rethrow;
    }
  }

  // --- Subscriptions ---
  Future<List<SubscriptionItem>> fetchSubscriptions() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _supabase
            .from('subscriptions')
            .select()
            .eq('household_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_subscriptions', list);
        return list.map(SubscriptionItem.fromJson).toList();
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchSubscriptions error: $e');
    }
    final cached = await _loadCache('cached_subscriptions');
    return cached.map(SubscriptionItem.fromJson).toList();
  }

  Future<void> insertSubscription(SubscriptionItem sub) async {
    final cached = await _loadCache('cached_subscriptions');
    cached.insert(0, sub.toMap());
    await _saveCache('cached_subscriptions', cached);
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline. Subscription saved locally.';
      }
      await _supabase.from('subscriptions').insert(sub.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.insertSubscription error: $e');
      rethrow;
    }
  }

  // --- Retirement Settings ---
  Future<Map<String, dynamic>?> fetchRetirementSettings() async {
    try {
      if (AppRuntime.supabaseReady) {
        final res = await _supabase
            .from('retirement_settings')
            .select()
            .eq('household_id', AppConfig.coupleId)
            .maybeSingle();
        if (res != null) {
          return Map<String, dynamic>.from(res);
        }
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchRetirementSettings error: $e');
    }
    return null;
  }

  Future<void> saveRetirementSettings(int retirementAge, double monthlyContribution, double expectedReturn) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline. Settings saved locally.';
      }
      await _supabase
          .from('retirement_settings')
          .upsert({
            'household_id': AppConfig.coupleId,
            'target_retirement_age': retirementAge,
            'monthly_contribution': monthlyContribution,
            'expected_return_rate': expectedReturn,
          });
    } catch (e) {
      debugPrint('FinanceRepository.saveRetirementSettings error: $e');
      rethrow;
    }
  }

  // --- Emergency Funds ---
  Future<Map<String, dynamic>?> fetchEmergencyFund() async {
    try {
      if (AppRuntime.supabaseReady) {
        final res = await _supabase
            .from('emergency_funds')
            .select()
            .eq('household_id', AppConfig.coupleId)
            .maybeSingle();
        if (res != null) {
          return Map<String, dynamic>.from(res);
        }
      }
    } catch (e) {
      debugPrint('FinanceRepository.fetchEmergencyFund error: $e');
    }
    return null;
  }

  Future<void> saveEmergencyFund(double targetAmount, double currentAmount, int monthsTarget) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is offline. Settings saved locally.';
      }
      await _supabase
          .from('emergency_funds')
          .upsert({
            'household_id': AppConfig.coupleId,
            'target_amount': targetAmount,
            'current_amount': currentAmount,
            'months_target': monthsTarget,
          });
    } catch (e) {
      debugPrint('FinanceRepository.saveEmergencyFund error: $e');
      rethrow;
    }
  }

  // --- Occasions & Sinking Funds ---
  Future<List<Occasion>> fetchOccasions() async {
    try {
      if (!AppRuntime.supabaseReady) {
        final cached = await _loadCache('cached_occasions');
        if (cached.isNotEmpty) return cached.map(Occasion.fromMap).toList();
        return [];
      }
      
      // Fetch occasions
      final rows = await _supabase
          .from('occasions')
          .select()
          .eq('household_id', AppConfig.coupleId);
      final occasionsList = List<Map<String, dynamic>>.from(rows as List);
      
      // Fetch sinking funds
      final fundsRows = await _supabase
          .from('occasion_sinking_funds')
          .select();
      final fundsList = List<Map<String, dynamic>>.from(fundsRows as List);
      
      final List<Map<String, dynamic>> merged = [];
      for (final occ in occasionsList) {
        final occId = occ['id']?.toString() ?? '';
        final fund = fundsList.firstWhere(
          (f) => f['occasion_id']?.toString() == occId,
          orElse: () => <String, dynamic>{},
        );
        
        merged.add({
          ...occ,
          'saved_amount': Formatters.asDouble(fund['current_balance'] ?? 0.0),
          'monthly_contribution': Formatters.asDouble(fund['monthly_contribution'] ?? 0.0),
        });
      }
      
      await _saveCache('cached_occasions', merged);
      return merged.map(Occasion.fromMap).toList();
    } catch (e) {
      debugPrint('FinanceRepository.fetchOccasions error: $e');
      final cached = await _loadCache('cached_occasions');
      if (cached.isNotEmpty) return cached.map(Occasion.fromMap).toList();
      throw 'Failed to retrieve occasions: ${e.toString()}';
    }
  }

  Future<void> insertOccasion(Occasion occasion) async {
    final cached = await _loadCache('cached_occasions');
    // Pre-insert with id to avoid caching issues
    final localMap = {
      ...occasion.toMap(),
      'id': occasion.id,
      'saved_amount': occasion.savedAmount,
      'monthly_contribution': occasion.monthlyContribution,
    };
    cached.insert(0, localMap);
    await _saveCache('cached_occasions', cached);

    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline. Occasion saved locally.';
      }
      
      // 1. Insert into occasions table
      final occRow = await _supabase.from('occasions').insert({
        'id': occasion.id,
        'household_id': occasion.householdId,
        'name': occasion.name,
        'date': occasion.date.toIso8601String(),
        'recurring': occasion.recurring,
        'budget_amount': occasion.budgetAmount,
      }).select().single();
      
      final realOccId = occRow['id']?.toString() ?? occasion.id;

      // 2. Insert into occasion_sinking_funds table
      await _supabase.from('occasion_sinking_funds').insert({
        'occasion_id': realOccId,
        'current_balance': occasion.savedAmount,
        'monthly_contribution': occasion.monthlyContribution,
      });
    } catch (e) {
      debugPrint('FinanceRepository.insertOccasion error: $e');
      rethrow;
    }
  }

  Future<void> deleteOccasion(String occasionId) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline.';
      }
      await _supabase.from('occasions').delete().eq('id', occasionId);
      
      // Update local cache
      final cached = await _loadCache('cached_occasions');
      cached.removeWhere((o) => o['id']?.toString() == occasionId);
      await _saveCache('cached_occasions', cached);
    } catch (e) {
      debugPrint('FinanceRepository.deleteOccasion error: $e');
      rethrow;
    }
  }

  // --- Assets & Liabilities ---
  Future<List<AssetLiability>> fetchAssetsLiabilities() async {
    try {
      if (!AppRuntime.supabaseReady) {
        final cached = await _loadCache('cached_assets_liabilities');
        if (cached.isNotEmpty) return cached.map(AssetLiability.fromMap).toList();
        return [];
      }
      
      final rows = await _supabase
          .from('assets_liabilities')
          .select()
          .eq('household_id', AppConfig.coupleId);
      final list = List<Map<String, dynamic>>.from(rows as List);
      
      await _saveCache('cached_assets_liabilities', list);
      return list.map(AssetLiability.fromMap).toList();
    } catch (e) {
      debugPrint('FinanceRepository.fetchAssetsLiabilities error: $e');
      final cached = await _loadCache('cached_assets_liabilities');
      if (cached.isNotEmpty) return cached.map(AssetLiability.fromMap).toList();
      throw 'Failed to retrieve assets/liabilities: ${e.toString()}';
    }
  }

  Future<void> insertAssetLiability(AssetLiability item) async {
    final cached = await _loadCache('cached_assets_liabilities');
    cached.insert(0, item.toMap());
    await _saveCache('cached_assets_liabilities', cached);

    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline. Item saved locally.';
      }
      
      await _supabase.from('assets_liabilities').insert(item.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.insertAssetLiability error: $e');
      rethrow;
    }
  }

  Future<void> deleteAssetLiability(String id) async {
    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline.';
      }
      await _supabase.from('assets_liabilities').delete().eq('id', id);
      
      final cached = await _loadCache('cached_assets_liabilities');
      cached.removeWhere((item) => item['id']?.toString() == id);
      await _saveCache('cached_assets_liabilities', cached);
    } catch (e) {
      debugPrint('FinanceRepository.deleteAssetLiability error: $e');
      rethrow;
    }
  }

  // --- Net Worth Snapshots ---
  Future<List<NetWorthSnapshot>> fetchNetWorthSnapshots() async {
    try {
      if (!AppRuntime.supabaseReady) {
        final cached = await _loadCache('cached_net_worth_snapshots');
        if (cached.isNotEmpty) return cached.map(NetWorthSnapshot.fromMap).toList();
        return [];
      }
      
      final rows = await _supabase
          .from('net_worth_snapshots')
          .select()
          .eq('household_id', AppConfig.coupleId)
          .order('captured_at', ascending: false);
      final list = List<Map<String, dynamic>>.from(rows as List);
      
      await _saveCache('cached_net_worth_snapshots', list);
      return list.map(NetWorthSnapshot.fromMap).toList();
    } catch (e) {
      debugPrint('FinanceRepository.fetchNetWorthSnapshots error: $e');
      final cached = await _loadCache('cached_net_worth_snapshots');
      if (cached.isNotEmpty) return cached.map(NetWorthSnapshot.fromMap).toList();
      throw 'Failed to retrieve net worth snapshots: ${e.toString()}';
    }
  }

  Future<void> insertNetWorthSnapshot(NetWorthSnapshot snapshot) async {
    final cached = await _loadCache('cached_net_worth_snapshots');
    cached.insert(0, snapshot.toMap());
    await _saveCache('cached_net_worth_snapshots', cached);

    try {
      if (!AppRuntime.supabaseReady) {
        throw 'Supabase is currently offline. Snapshot saved locally.';
      }
      
      await _supabase.from('net_worth_snapshots').insert(snapshot.toMap());
    } catch (e) {
      debugPrint('FinanceRepository.insertNetWorthSnapshot error: $e');
      rethrow;
    }
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
