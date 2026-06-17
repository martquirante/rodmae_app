import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rodmae_app/core/constants.dart';

void main() {
  test('Diagnose debts table columns', () async {
    final client = SupabaseClient(
      AppConfig.supabaseUrl,
      AppConfig.supabaseAnonKey,
    );

    print('--- debts columns diagnose ---');
    final fields = [
      'id',
      'couple_id',
      'household_id',
      'title',
      'name',
      'total_amount',
      'original_balance',
      'remaining_amount',
      'current_balance',
      'type',
      'related_transaction_id',
    ];

    for (final field in fields) {
      try {
        final val = field.contains('id') || field.contains('uid') ? '00000000-0000-0000-0000-000000000000' : 'test';
        await client.from('debts').insert({
          'id': '00000000-0000-0000-0000-000000000001',
          'couple_id': 'test-couple',
          'title': 'Test Debt',
          'total_amount': 100.0,
          'remaining_amount': 100.0,
          'type': 'owe',
          field: field == 'total_amount' || field == 'original_balance' || field == 'remaining_amount' || field == 'current_balance' ? 100.0 : val,
        });
        print('Column "$field" EXISTS (insert did not throw column error)');
      } catch (e) {
        if (e.toString().contains('column') && e.toString().contains('not find')) {
          print('Column "$field" DOES NOT EXIST: $e');
        } else {
          print('Column "$field" may exist but threw other error: $e');
        }
      }
    }
  });
}
