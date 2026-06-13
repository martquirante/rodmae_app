import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:rodmae_app/core/constants.dart';

void main() async {
  print('Initializing Supabase client directly...');
  final client = SupabaseClient(
    AppConfig.supabaseUrl,
    AppConfig.supabaseAnonKey,
  );

  print('Fetching households...');
  try {
    final households = await client.from('households').select();
    print('Households: $households');
  } catch (e) {
    print('Error fetching households: $e');
  }

  print('Fetching household_members...');
  try {
    final members = await client.from('household_members').select();
    print('Household Members: $members');
  } catch (e) {
    print('Error fetching household_members: $e');
  }
}
