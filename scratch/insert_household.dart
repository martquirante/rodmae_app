import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:rodmae_app/core/constants.dart';

Future<String?> getOrCreateUser(SupabaseClient client, String email, String password) async {
  try {
    print('Trying to sign in as $email...');
    final res = await client.auth.signInWithPassword(email: email, password: password);
    return res.user?.id;
  } catch (e) {
    print('Sign in failed for $email, attempting to sign up...');
    try {
      final res = await client.auth.signUp(email: email, password: password);
      return res.user?.id;
    } catch (signUpErr) {
      print('Sign up failed for $email: $signUpErr');
      return null;
    }
  }
}

void main() async {
  // Mock shared preferences to prevent plugin errors in test runner
  SharedPreferences.setMockInitialValues({});

  print('Initializing Supabase with EmptyLocalStorage inside FlutterAuthClientOptions...');
  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.implicit, // use implicit flow to avoid PKCE storage issues
      localStorage: EmptyLocalStorage(),
    ),
  );

  final client = Supabase.instance.client;

  // 1. Get or create Rodel
  final rodelId = await getOrCreateUser(client, 'rodel@rodmae.com', 'rodmae2026');
  print('Rodel UID: $rodelId');

  // 2. Get or create Eurine
  final eurineId = await getOrCreateUser(client, 'marymae@rodmae.com', 'rodmae2026');
  print('Eurine UID: $eurineId');

  if (rodelId == null || eurineId == null) {
    print('Failed to retrieve or create user IDs. Cannot proceed.');
    return;
  }

  // 3. Sign in as Rodel to perform insertions
  print('Signing in back as Rodel to perform insertions...');
  await client.auth.signInWithPassword(
    email: 'rodel@rodmae.com',
    password: 'rodmae2026',
  );

  final householdId = AppConfig.coupleId;

  print('Inserting household...');
  try {
    await client.from('households').insert({
      'id': householdId,
      'name': 'Rodel & Eurine Household',
    });
    print('Household inserted successfully!');
  } catch (e) {
    print('Error inserting household (it may already exist): $e');
  }

  print('Inserting household members...');
  try {
    await client.from('household_members').insert([
      {'household_id': householdId, 'user_id': rodelId},
      {'household_id': householdId, 'user_id': eurineId},
    ]);
    print('Household members linked successfully!');
  } catch (e) {
    print('Error inserting household members (they may already be linked): $e');
  }

  // 4. Create default wallets if they don't exist
  print('Creating default wallets...');
  try {
    await client.from('wallets').insert([
      {
        'id': 'shared-wallet',
        'household_id': householdId,
        'type': 'shared',
        'monthly_limit': 50000.0,
      },
      {
        'id': 'wallet-rodel',
        'household_id': householdId,
        'owner_user_id': rodelId,
        'type': 'personal',
        'monthly_limit': 15000.0,
      },
      {
        'id': 'wallet-eurine',
        'household_id': householdId,
        'owner_user_id': eurineId,
        'type': 'personal',
        'monthly_limit': 15000.0,
      }
    ]);
    print('Wallets created successfully!');
  } catch (e) {
    print('Error inserting wallets (they may already exist): $e');
  }
}
