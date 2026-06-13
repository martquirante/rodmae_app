import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum PartnerProfile {
  rodel,
  maryMae;

  String get label => switch (this) {
        PartnerProfile.rodel   => 'Rodel',
        PartnerProfile.maryMae => 'Eurine',
      };

  String get initials => switch (this) {
        PartnerProfile.rodel => 'R',
        PartnerProfile.maryMae => 'M',
      };

  Alignment get bubbleAlignment => switch (this) {
        PartnerProfile.rodel => Alignment.centerRight,
        PartnerProfile.maryMae => Alignment.centerLeft,
      };

  Color get color => switch (this) {
        PartnerProfile.rodel => const Color(0xFF3B82F6),
        PartnerProfile.maryMae => const Color(0xFFFF5E8D),
      };
}

final class PartnerIdentity {
  PartnerIdentity._();

  static final ValueNotifier<PartnerProfile> active =
      ValueNotifier<PartnerProfile>(PartnerProfile.rodel);

  static void toggle() {
    active.value = active.value == PartnerProfile.rodel
        ? PartnerProfile.maryMae
        : PartnerProfile.rodel;
  }

  static void setFromEmail(String? email) {
    if (email == null) return;
    final lower = email.toLowerCase();
    if (lower.contains('rodel')) {
      active.value = PartnerProfile.rodel;
    } else if (lower.contains('mary') || lower.contains('mae') ||
        lower.contains('eurine')) {
      active.value = PartnerProfile.maryMae;
    }
  }
}

final class AuthService {

  AuthService._();

  static final AuthService instance = AuthService._();

  static String? _cachedEmail;

  SupabaseClient get _client => Supabase.instance.client;

  User? get currentUser => _client.auth.currentUser;

  Session? get currentSession => _client.auth.currentSession;

  bool get isAuthenticated => currentUser != null || _cachedEmail != null;

  static Future<void> loadCachedSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedEmail = prefs.getString('auth_email');
      if (_cachedEmail != null) {
        PartnerIdentity.setFromEmail(_cachedEmail);

        // Perform silent Supabase login if email matches dev bypass
        final email = _cachedEmail!.toLowerCase().trim();
        if (email == 'rodel@rodmae.com' || email == 'marymae@rodmae.com') {
          AuthService.instance.signIn(email: email, password: 'rodmae2026').catchError((err) {
            // ignore: avoid_print
            print('Silent Supabase login failed: $err');
          });
        }
      }
    } catch (_) {}
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final lowerEmail = email.toLowerCase().trim();
    final isDevCreds = (lowerEmail == 'rodel@rodmae.com' || lowerEmail == 'marymae@rodmae.com') &&
        password == 'rodmae2026';

    try {
      // 1. Try real Supabase auth
      final response = await _client.auth.signInWithPassword(
        email: lowerEmail,
        password: password,
      );
      if (response.user != null) {
        final userEmail = response.user!.email ?? lowerEmail;
        PartnerIdentity.setFromEmail(userEmail);
        _cachedEmail = userEmail;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_email', userEmail);
        return;
      }
    } catch (e) {
      // If sign-in fails and it's dev credentials, try to sign up in Supabase
      if (isDevCreds) {
        try {
          final signUpResponse = await _client.auth.signUp(
            email: lowerEmail,
            password: password,
          );
          if (signUpResponse.user != null) {
            final userEmail = signUpResponse.user!.email ?? lowerEmail;
            PartnerIdentity.setFromEmail(userEmail);
            _cachedEmail = userEmail;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('auth_email', userEmail);
            return;
          }
        } catch (signUpError) {
          // ignore: avoid_print
          print('Supabase sign up error: $signUpError');
        }

        // Local bypass fallback if signup fails
        PartnerIdentity.setFromEmail(lowerEmail);
        _cachedEmail = lowerEmail;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_email', lowerEmail);
        return;
      }

      // If not dev credentials, rethrow the signIn error
      rethrow;
    }
  }

  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {}
    _cachedEmail = null;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('auth_email');
    } catch (_) {}
  }

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;
}

final class ProfileNotifier {
  ProfileNotifier._();

  static final ValueNotifier<int> updateNotifier = ValueNotifier<int>(0);

  static void notifyUpdate() {
    updateNotifier.value++;
  }
}

