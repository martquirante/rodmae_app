import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rodmae_app/core/constants.dart';

void main() {
  test('Supabase schema diagnostics', () async {
    print('Initializing SupabaseClient...');
    final client = SupabaseClient(
      AppConfig.supabaseUrl,
      AppConfig.supabaseAnonKey,
      authOptions: const AuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    );
    print('SupabaseClient initialized.');

    try {
      final email = 'rodel@rodmae.com';
      final password = 'rodmae2026';
      
      User? user;
      try {
        print('Signing in with dev credentials...');
        final response = await client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        user = response.user;
      } catch (signInErr) {
        print('Sign in failed: $signInErr. Trying signup...');
        try {
          final response = await client.auth.signUp(
            email: email,
            password: password,
          );
          user = response.user;
          print('Sign up successful!');
        } catch (signUpErr) {
          print('Sign up also failed: $signUpErr');
        }
      }

      if (user == null) {
        print('FAILED to authenticate user.');
        return;
      }
      print('Authentication successful. User ID: ${user.id}');

      // Fetch household_members
      print('Fetching household_members for user...');
      final memberRows = await client
          .from('household_members')
          .select('household_id')
          .eq('user_id', user.id);
      print('household_members response: $memberRows');

      String? householdId;
      if (memberRows is List && memberRows.isNotEmpty) {
        householdId = memberRows.first['household_id']?.toString();
      }
      print('Household ID from DB: $householdId');

      if (householdId == null) {
        print('Warning: User has no household associated in household_members!');
        householdId = AppConfig.coupleId; // fallback
      }

      // 1. Wallets
      try {
        print('Testing wallets query...');
        final wallets = await client
            .from('wallets')
            .select()
            .eq('household_id', householdId);
        print('Wallets count: ${wallets.length}');
      } catch (e) {
        print('Wallets error: $e');
      }

      // 2. Debts
      try {
        print('Testing debts query...');
        final debts = await client
            .from('debts')
            .select()
            .eq('couple_id', householdId);
        print('Debts count: ${debts.length}');
      } catch (e) {
        print('Debts error: $e');
      }

      // 3. Occasions
      try {
        print('Testing occasions query...');
        final occasions = await client
            .from('occasions')
            .select()
            .eq('household_id', householdId);
        print('Occasions count: ${occasions.length}');
      } catch (e) {
        print('Occasions error: $e');
      }

      // 4. Monthly Reports
      try {
        print('Testing monthly_reports query...');
        final reports = await client
            .from('monthly_reports')
            .select()
            .eq('household_id', householdId);
        print('Monthly reports count: ${reports.length}');
      } catch (e) {
        print('Monthly reports error: $e');
      }

      // 5. Try insert to monthly_reports with overall_grade, etc.
      try {
        print('Testing monthly_reports insert...');
        final now = DateTime.now();
        final insertRes = await client.from('monthly_reports').insert({
          'household_id': householdId,
          'month': now.month,
          'year': now.year,
          'overall_grade': 'A-',
          'spending_score': 88.5,
          'savings_score': 92.0,
          'ai_advice': 'Test advice via diagnostic script',
          'created_at': now.toIso8601String(),
        }).select();
        print('Monthly report insert success: $insertRes');
      } catch (e) {
        print('Monthly report insert FAILED: $e');
      }

    } catch (e) {
      print('Global test error: $e');
    }
  });
}
