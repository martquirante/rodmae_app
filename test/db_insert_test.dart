import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rodmae_app/core/constants.dart';

void main() {
  test('Supabase Insert and Query Validation Test', () async {
    final client = SupabaseClient(
      AppConfig.supabaseUrl,
      AppConfig.supabaseAnonKey,
    );

    final testId = 'test-run-${DateTime.now().millisecondsSinceEpoch}';
    print('Starting insert validation test with identifier: $testId');

    // 1. Test Wallets Insert
    try {
      print('Inserting test wallet...');
      final walletRes = await client.from('wallets').insert({
        'id': 'wallet-$testId',
        'household_id': AppConfig.coupleId,
        'type': 'personal',
        'monthly_limit': 10000.0,
        'balance': 500.0,
        'brand_key': 'gcash',
        'name': 'Test GCash Wallet',
      }).select();
      print('Wallet insert response: $walletRes');

      expect(walletRes, isNotEmpty);
      print('Wallet insert SUCCESS!');
    } catch (e) {
      print('Wallet insert FAILED: $e');
    }

    // 2. Test Transactions Insert
    try {
      print('Inserting test transaction...');
      final transRes = await client.from('transactions').insert({
        'id': '00000000-0000-0000-0000-${DateTime.now().millisecondsSinceEpoch.toString().padLeft(12, '0').substring(0, 12)}',
        'wallet_id': 'wallet-$testId',
        'category_id': 'Food',
        'created_by_user_id': 'test-user',
        'amount': 250.0,
        'date': DateTime.now().toIso8601String(),
        'notes': 'Test transaction notes',
      }).select();
      print('Transaction insert response: $transRes');

      expect(transRes, isNotEmpty);
      print('Transaction insert SUCCESS!');
    } catch (e) {
      print('Transaction insert FAILED: $e');
    }

    // 3. Test Budgets Insert
    try {
      print('Inserting test budget...');
      final budgetRes = await client.from('category_budgets').insert({
        'household_id': AppConfig.coupleId,
        'category': 'Food-$testId',
        'budget_limit': 5000.0,
        'period': 'monthly',
      }).select();
      print('Budget insert response: $budgetRes');

      expect(budgetRes, isNotEmpty);
      print('Budget insert SUCCESS!');
    } catch (e) {
      print('Budget insert FAILED: $e');
    }

    // 4. Test Savings Goals Insert
    try {
      print('Inserting test savings goal...');
      final goalRes = await client.from('savings_goals').insert({
        'id': 'goal-$testId',
        'household_id': AppConfig.coupleId,
        'name': 'Test Goal $testId',
        'target_amount': 25000.0,
        'current_amount': 1500.0,
        'category': 'life_event',
      }).select();
      print('Savings goal insert response: $goalRes');

      expect(goalRes, isNotEmpty);
      print('Savings goal insert SUCCESS!');
    } catch (e) {
      print('Savings goal insert FAILED: $e');
    }

    // Cleanup test records
    print('Cleaning up test records...');
    try {
      await client.from('transactions').delete().eq('notes', 'Test transaction notes');
      await client.from('wallets').delete().eq('id', 'wallet-$testId');
      await client.from('category_budgets').delete().eq('category', 'Food-$testId');
      await client.from('savings_goals').delete().eq('id', 'goal-$testId');
      print('Cleanup complete.');
    } catch (cleanupErr) {
      print('Cleanup failed: $cleanupErr');
    }
  });
}

