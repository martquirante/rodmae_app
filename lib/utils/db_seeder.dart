import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Executable utility class to seed test database records for the RodMae App.
class DbSeeder {
  DbSeeder._();

  /// Seeds initial wallet records, mixed transaction history, and active savings goals.
  static Future<void> seedInitialCoupleData({
    required String coupleId,
    required String partner1Id,
    required String partner2Id,
  }) async {
    final supabase = Supabase.instance.client;

    debugPrint('DBSeeder: Seeding wallets...');
    
    // 1. Seed 3 Wallets (Rodel, Eurine, Shared Vault)
    final walletData = [
      {
        'couple_id': coupleId,
        'owner_uid': partner1Id,
        'wallet_type': 'personal',
        'name': "Rodel's Account",
        'balance': 38450.00,
      },
      {
        'couple_id': coupleId,
        'owner_uid': partner2Id,
        'wallet_type': 'personal',
        'name': "Eurine's Account",
        'balance': 42320.00,
      },
      {
        'couple_id': coupleId,
        'owner_uid': null,
        'wallet_type': 'shared',
        'name': 'Shared Vault',
        'balance': 18000.00,
      }
    ];

    final insertedWallets = await supabase
        .from('wallets')
        .insert(walletData)
        .select('id, name');

    debugPrint('DBSeeder: Wallets seeded successfully: $insertedWallets');

    String? rodelWalletId;
    String? eurineWalletId;
    String? sharedWalletId;

    for (final w in insertedWallets) {
      final name = w['name']?.toString();
      final id = w['id']?.toString();
      if (name != null && id != null) {
        if (name.contains("Rodel")) {
          rodelWalletId = id;
        } else if (name.contains("Eurine")) {
          eurineWalletId = id;
        } else if (name.contains("Shared")) {
          sharedWalletId = id;
        }
      }
    }

    // 2. Seed 5 Mixed Transactions (Salary income, Grocery expense, Transfer to vault)
    final transactionData = [
      {
        'couple_id': coupleId,
        'wallet_id': rodelWalletId,
        'paid_by_uid': 'Rodel',
        'type': 'income',
        'amount': 95000.00,
        'category': 'Salary',
        'date': DateTime.now().subtract(const Duration(days: 5)).toUtc().toIso8601String(),
      },
      {
        'couple_id': coupleId,
        'wallet_id': eurineWalletId,
        'paid_by_uid': 'Eurine',
        'type': 'income',
        'amount': 88000.00,
        'category': 'Salary',
        'date': DateTime.now().subtract(const Duration(days: 4)).toUtc().toIso8601String(),
      },
      {
        'couple_id': coupleId,
        'wallet_id': sharedWalletId,
        'paid_by_uid': 'Rodel',
        'type': 'expense',
        'amount': 4500.00,
        'category': 'Groceries',
        'date': DateTime.now().subtract(const Duration(days: 2)).toUtc().toIso8601String(),
      },
      {
        'couple_id': coupleId,
        'wallet_id': rodelWalletId,
        'paid_by_uid': 'Rodel',
        'type': 'transfer',
        'amount': 15000.00,
        'category': 'Vault Transfer',
        'date': DateTime.now().subtract(const Duration(days: 1)).toUtc().toIso8601String(),
      },
      {
        'couple_id': coupleId,
        'wallet_id': eurineWalletId,
        'paid_by_uid': 'Eurine',
        'type': 'expense',
        'amount': 1200.00,
        'category': 'Dining Out',
        'date': DateTime.now().toUtc().toIso8601String(),
      }
    ];

    debugPrint('DBSeeder: Seeding transactions...');
    await supabase.from('transactions').insert(transactionData);
    debugPrint('DBSeeder: Transactions seeded successfully.');

    // 3. Seed 1 active Savings Goal ("House Savings")
    final savingsGoalData = {
      'couple_id': coupleId,
      'title': 'House Savings',
      'target_amount': 120000.00,
      'saved_amount': 55000.00,
      'deadline': DateTime.now().add(const Duration(days: 180)).toUtc().toIso8601String(),
    };

    debugPrint('DBSeeder: Seeding savings goal...');
    await supabase.from('savings_goals').insert(savingsGoalData);
    debugPrint('DBSeeder: Savings goal seeded successfully.');
  }
}
