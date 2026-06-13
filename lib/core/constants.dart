import 'package:flutter/material.dart';

final class AppConfig {
  AppConfig._();

  static const String coupleId = 'couple-rodel-marymae-2026';
  static const String vaultBucket    = 'rodmae-vault';
  static const String chatMediaBucket = 'rodmae-chat-media';

  static const String geminiApiKey = 'YOUR_GEMINI_API_KEY';
  static const String supabaseUrl = 'https://axqbpjafmlwvqnhodtph.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_gxjk9pVdgbZdDv-aeMJMbQ__N4BGZj6';
  static final DateTime weddingDate = DateTime(2026, 6, 3, 15);
}

class AppNotification {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const AppNotification({
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    this.onTap,
  });
}

final class AppNotificationNavigation {
  AppNotificationNavigation._();

  static final mainTabNotifier = ValueNotifier<int>(0);
  static final privateChatTabNotifier = ValueNotifier<int>(0);
  static final activeNotificationNotifier = ValueNotifier<AppNotification?>(null);

  static void show({
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
  }) {
    // Always create a fresh notification object. If a notification is currently
    // showing, force the notifier to fire again by momentarily clearing it first.
    final notification = AppNotification(
      title: title,
      message: message,
      icon: icon,
      color: color,
      onTap: onTap,
    );
    if (activeNotificationNotifier.value != null) {
      // Null out first, then re-set so the listener fires even for back-to-back notifications
      activeNotificationNotifier.value = null;
    }
    // Use a tiny delay so ValueNotifier has time to flush the null before setting the new value
    Future.delayed(Duration.zero, () {
      activeNotificationNotifier.value = notification;
    });
  }

  static void clear() {
    activeNotificationNotifier.value = null;
  }
}
