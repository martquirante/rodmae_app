import 'dart:async';
import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import 'auth_service.dart';

// ─── Top-level background message handler (required to be top-level) ──────────
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  // flutter_local_notifications will handle showing the notification
  // for data-only messages that arrive in the background.
  await NotificationService.instance._showLocalNotification(message);
}

// ─── Notification Channel IDs ──────────────────────────────────────────────────
const _kChannelId   = 'rodmae_love_channel';
const _kChannelName = 'RodMae Love Alerts';
const _kChannelDesc = 'Real-time love signals, chats, and notes from your partner';

/// Centralised service that:
/// 1. Initialises FlutterLocalNotifications with a high-priority channel.
/// 2. Registers FCM and requests permission on first launch.
/// 3. Shows a local notification for every FCM message (foreground + background).
/// 4. Wires navigation when the user taps a notification.
final class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _flutterLocalNotifications = FlutterLocalNotificationsPlugin();
  final _fcm = FirebaseMessaging.instance;

  /// Call once in main() before runApp.
  Future<void> initialize() async {
    try {
      // ── 1. Android notification channel ────────────────────────────────────────
      const androidChannel = AndroidNotificationChannel(
        _kChannelId,
        _kChannelName,
        description: _kChannelDesc,
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
        enableLights: true,
        ledColor: Color(0xFF3B82F6), // RodMaeColors.electricBlue
      );

      final androidPlugin = _flutterLocalNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(androidChannel);

      // ── 2. Initialise flutter_local_notifications ───────────────────────────────
      const initSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: initSettingsAndroid);

      await _flutterLocalNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (response) {
          // Tapped on a notification → navigate based on payload
          _handleNotificationTap(response.payload);
        },
      );
    } catch (e) {
      debugPrint('NotificationService: Local notifications init failed: $e');
    }

    // Run Firebase/FCM calls in a separate asynchronous task to avoid stalling the main boot process.
    // This is crucial on devices without fully working Google Play Services (e.g., Poco/Xiaomi Chinese ROMs, sandbox)
    unawaited(Future(() async {
      try {
        // ── 3. Request FCM permission ───────────────────────────────────────────────
        await _fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
        ).timeout(const Duration(seconds: 3));

        // ── 4. Background handler (must be top-level function) ────────────────────
        FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);

        // ── 5. Foreground messages → show local notification + in-app banner ───────
        FirebaseMessaging.onMessage.listen((message) {
          _showLocalNotification(message);
          // Also trigger the in-app 3D banner when the app is open
          _triggerInAppBanner(message);
        });

        // ── 6. Notification tapped while app was in background ─────────────────────
        FirebaseMessaging.onMessageOpenedApp.listen((message) {
          _handleNotificationTap(
            jsonEncode(message.data.isNotEmpty ? message.data : {'type': 'general'}),
          );
        });

        // ── 7. Check if app was launched from a terminated notification ─────────────
        final initialMessage = await _fcm.getInitialMessage().timeout(const Duration(seconds: 3));
        if (initialMessage != null) {
          // Small delay to allow the widget tree to mount first
          await Future.delayed(const Duration(milliseconds: 800));
          _handleNotificationTap(
            jsonEncode(initialMessage.data.isNotEmpty ? initialMessage.data : {'type': 'general'}),
          );
        }

        // ── 8. Subscribe to topic for couple-wide broadcasts ───────────────────────
        await _fcm.subscribeToTopic('couple-rodmae-2026').timeout(const Duration(seconds: 4));
      } catch (e) {
        debugPrint('NotificationService: FCM background registration encountered error: $e');
      }
    }));
  }

  /// Displays a native system notification from a RemoteMessage.
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final sender = message.data['sender']?.toString();
      final currentPartner = PartnerIdentity.active.value.label.toLowerCase();
      if (sender != null && sender.toLowerCase() == currentPartner) {
        debugPrint('NotificationService: Suppressing self-notification for $sender');
        return;
      }

      final notification = message.notification;
      final title = notification?.title ?? message.data['title'] ?? 'RodMae 💕';
      final body  = notification?.body  ?? message.data['body']  ?? '';
      final type  = message.data['type'] ?? 'general';

      // Pick accent color based on notification type
      final color = _colorForType(type);

      final androidDetails = AndroidNotificationDetails(
        _kChannelId,
        _kChannelName,
        channelDescription: _kChannelDesc,
        importance: Importance.max,
        priority: Priority.max,
        color: color,
        icon: '@mipmap/ic_launcher',
        largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        styleInformation: BigTextStyleInformation(body),
        enableVibration: true,
        playSound: true,
        ticker: title,
      );

      final details = NotificationDetails(android: androidDetails);
      final id = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      await _flutterLocalNotifications.show(
        id,
        title,
        body,
        details,
        payload: jsonEncode(message.data),
      );
    } catch (e) {
      debugPrint('NotificationService: Failed to display local notification: $e');
    }
  }

  /// Triggers the in-app 3D banner from AppNotificationNavigation
  void _triggerInAppBanner(RemoteMessage message) {
    final sender = message.data['sender']?.toString();
    final currentPartner = PartnerIdentity.active.value.label.toLowerCase();
    if (sender != null && sender.toLowerCase() == currentPartner) {
      debugPrint('NotificationService: Suppressing self-banner for $sender');
      return;
    }

    final type  = message.data['type'] ?? 'general';
    final title = message.notification?.title ?? message.data['title'] ?? 'RodMae 💕';
    final body  = message.notification?.body  ?? message.data['body']  ?? '';

    final (icon, color) = _iconAndColorForType(type);

    AppNotificationNavigation.show(
      title: title,
      message: body,
      icon: icon,
      color: color,
      onTap: () => _handleNotificationTap(jsonEncode(message.data)),
    );
  }

  /// Handles deep-link navigation when a notification is tapped.
  void _handleNotificationTap(String? payload) {
    if (payload == null) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] ?? 'general';

      switch (type) {
        case 'chat':
          AppNotificationNavigation.mainTabNotifier.value = 1;
          AppNotificationNavigation.privateChatTabNotifier.value = 0;
        case 'note':
          AppNotificationNavigation.mainTabNotifier.value = 1;
          AppNotificationNavigation.privateChatTabNotifier.value = 1;
        case 'signal':
          AppNotificationNavigation.mainTabNotifier.value = 1;
          AppNotificationNavigation.privateChatTabNotifier.value = 2;
        case 'location':
          AppNotificationNavigation.mainTabNotifier.value = 0;
        default:
          AppNotificationNavigation.mainTabNotifier.value = 0;
      }
    } catch (_) {}
  }

  /// Returns the accent color for a given notification type.
  Color _colorForType(String type) {
    switch (type) {
      case 'chat':
        return RodMaeColors.electricBlue;
      case 'note':
        return RodMaeColors.gold;
      case 'signal':
        return RodMaeColors.rose;
      case 'location':
        return RodMaeColors.mint;
      default:
        return RodMaeColors.electricBlue;
    }
  }

  /// Returns the (icon, color) pair for in-app banner from a notification type.
  (IconData, Color) _iconAndColorForType(String type) {
    switch (type) {
      case 'chat':
        return (Icons.chat_bubble_rounded, RodMaeColors.electricBlue);
      case 'note':
        return (Icons.sticky_note_2_rounded, RodMaeColors.gold);
      case 'signal':
        return (Icons.favorite_rounded, RodMaeColors.rose);
      case 'location':
        return (Icons.location_on_rounded, RodMaeColors.mint);
      default:
        return (Icons.notifications_rounded, RodMaeColors.electricBlue);
    }
  }

  /// Sends an FCM push notification to the couple topic via the FCM HTTP v1 API.
  /// Call this whenever the current user sends a message, note, or love signal.
  ///
  /// [type] should be one of: 'chat', 'note', 'signal', 'location'
  static Future<void> sendPushToSpouse({
    required String title,
    required String body,
    required String type,
    String topic = 'couple-rodmae-2026',
  }) async {
    // NOTE: For production, this HTTP call should go through a Supabase Edge
    // Function or your own server to keep the FCM server key secret.
    // For now we use the Firebase Admin SDK via a Supabase Edge Function trigger.
    // The push is sent server-side via a Supabase Database Webhook → Edge Function.
    // This method is a stub kept here for documentation purposes.
    //
    // The actual FCM push is triggered automatically by the Supabase Edge Function
    // 'send_fcm_notification' which listens to INSERT events on:
    //   - chat_history
    //   - surprise_notes
    //   - love_triggers
    //
    // See: supabase/functions/send_fcm_notification/index.ts
  }

  /// Get the current device's FCM token (useful for debugging).
  Future<String?> getToken() async {
    try {
      return await _fcm.getToken().timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    }
  }
}
