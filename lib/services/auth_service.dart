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
      }
    } catch (_) {}
  }

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    final lowerEmail = email.toLowerCase().trim();
    
    // Dev-Mode Bypass Credentials for quick testing
    if ((lowerEmail == 'rodel@rodmae.com' || lowerEmail == 'marymae@rodmae.com') &&
        password == 'rodmae2026') {
      PartnerIdentity.setFromEmail(lowerEmail);
      _cachedEmail = lowerEmail;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_email', lowerEmail);
      return; // Bypassed successfully
    }
    
    // Otherwise fallback to live Supabase Auth
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );
    if (response.user != null) {
      final userEmail = response.user!.email ?? lowerEmail;
      PartnerIdentity.setFromEmail(userEmail);
      _cachedEmail = userEmail;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('auth_email', userEmail);
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

