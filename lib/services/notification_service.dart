import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import 'auth_service.dart';
import 'firebase_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseBackgroundMessageHandler(RemoteMessage message) async {
  await NotificationService.instance.showLocalNotification(message);
}

const _kChannelId = 'rodmae_love_channel';
const _kChannelName = 'RodMae Love Alerts';
const _kChannelDesc =
    'Real-time love signals, chats, and notes from your partner';

/// Fired when an incoming FCM message carries a love signal.
final class LoveSignalPayload {
  final String triggerType;
  final String senderName;

  const LoveSignalPayload({
    required this.triggerType,
    required this.senderName,
  });
}

/// Fired when an incoming FCM message carries a surprise note.
final class SurpriseNotePayload {
  final String content;
  final String senderName;

  const SurpriseNotePayload({
    required this.content,
    required this.senderName,
  });
}


final class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  /// Notifier for incoming love signals received via FCM foreground delivery.
  static final loveSignalNotifier =
      ValueNotifier<LoveSignalPayload?>(null);

  /// Notifier for incoming surprise notes received via FCM foreground delivery.
  /// Subscribe in MainNavigationShell to show the cinematic envelope overlay.
  static final surpriseNoteNotifier =
      ValueNotifier<SurpriseNotePayload?>(null);


  bool _localNotificationsReady = false;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  Future<void> initialize() async {
    await _initializeLocalNotifications();
    unawaited(_initializeFirebaseMessaging());
  }

  Future<void> _initializeLocalNotifications() async {
    if (_localNotificationsReady) {
      return;
    }

    const androidChannel = AndroidNotificationChannel(
      _kChannelId,
      _kChannelName,
      description: _kChannelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFF3B82F6),
    );

    final androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);
    await androidPlugin?.requestNotificationsPermission();

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      ),
    );

    await flutterLocalNotificationsPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        _handleNotificationTap(response.payload);
      },
    );

    _localNotificationsReady = true;
  }

  Future<void> _initializeFirebaseMessaging() async {
    try {
      await _fcm
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
            provisional: false,
          )
          .timeout(const Duration(seconds: 5));

      // iOS: explicitly request foreground presentation of FCM notifications.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundMessageHandler);

      await _foregroundSub?.cancel();
      _foregroundSub = FirebaseMessaging.onMessage.listen((message) async {
        final sender = message.data['sender']?.toString();
        if (_isFromActivePartner(sender)) {
          debugPrint(
            'NotificationService: foreground self-notification suppressed for $sender',
          );
          return;
        }

        final notification = message.notification;
        final title = notification?.title?.trim().isNotEmpty == true
            ? notification!.title!
            : (message.data['title']?.toString() ?? 'RodMae Love Alert');
        final body = notification?.body?.trim().isNotEmpty == true
            ? notification!.body!
            : (message.data['body']?.toString() ?? 'New private update');
        final type = message.data['type']?.toString() ?? 'general';
        final color = _colorForType(type);

        // ── ANDROID FOREGROUND: force system-tray notification ──────────────
        // On Android, FCM suppresses heads-up notifications when the app is in
        // the foreground unless we explicitly call show() via the local plugin.
        final details = NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannelId,
            _kChannelName,
            channelDescription: _kChannelDesc,
            importance: Importance.max,
            priority: Priority.high,
            color: color,
            icon: '@mipmap/ic_launcher',
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            styleInformation: BigTextStyleInformation(body),
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
            enableVibration: true,
            playSound: true,
            ticker: title,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        );

        await flutterLocalNotificationsPlugin.show(
          _notificationId(message),
          title,
          body,
          details,
          payload: jsonEncode(message.data),
        );

        // ── DUAL-TRACK: fire love overlay via FCM foreground message ─────────
        // This guarantees that even if Supabase Realtime is delayed, the
        // receiving partner sees the cinematic overlay immediately.
        if (type == 'signal') {
          final triggerType = message.data['trigger_type']?.toString() ??
              message.data['body']?.toString() ??
              body;
          final senderName = sender ?? 'Your partner';
          _fireLoveSignalOverlay(triggerType: triggerType, senderName: senderName);
        }

        // ── DUAL-TRACK: fire envelope overlay for surprise notes ─────────────
        if (type == 'note') {
          final noteContent = message.data['content']?.toString() ?? body;
          final senderName = sender ?? 'Your partner';
          _fireSurpriseNoteOverlay(content: noteContent, senderName: senderName);
        }

        _triggerInAppBanner(
          title: title,
          body: body,
          type: type,
          payload: message.data,
        );
      });

      await _openedSub?.cancel();
      _openedSub = FirebaseMessaging.onMessageOpenedApp.listen((message) {
        _handleNotificationTap(
          jsonEncode(message.data.isNotEmpty ? message.data : {'type': 'general'}),
        );
      });

      final initialMessage =
          await _fcm.getInitialMessage().timeout(const Duration(seconds: 4));
      if (initialMessage != null) {
        await Future<void>.delayed(const Duration(milliseconds: 650));
        _handleNotificationTap(
          jsonEncode(
            initialMessage.data.isNotEmpty
                ? initialMessage.data
                : {'type': 'general'},
          ),
        );
      }

      await _fcm
          .subscribeToTopic(AppConfig.coupleId)
          .timeout(const Duration(seconds: 5));

      debugPrint(
        'NotificationService: subscribed to FCM topic "${AppConfig.coupleId}"',
      );
    } catch (error) {
      debugPrint('NotificationService: FCM registration failed: $error');
    }
  }

  Future<void> showLocalNotification(RemoteMessage message) async {
    try {
      await _initializeLocalNotifications();

      final sender = message.data['sender']?.toString();
      if (_isFromActivePartner(sender)) {
        debugPrint(
          'NotificationService: local self-notification suppressed for $sender',
        );
        return;
      }

      final notification = message.notification;
      final title = notification?.title?.trim().isNotEmpty == true
          ? notification!.title!
          : (message.data['title']?.toString() ?? 'RodMae Love Alert');
      final body = notification?.body?.trim().isNotEmpty == true
          ? notification!.body!
          : (message.data['body']?.toString() ?? 'New private update');
      final type = message.data['type']?.toString() ?? 'general';

      await flutterLocalNotificationsPlugin.show(
        _notificationId(message),
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _kChannelId,
            _kChannelName,
            channelDescription: _kChannelDesc,
            importance: Importance.max,
            priority: Priority.high,
            color: _colorForType(type),
            icon: '@mipmap/ic_launcher',
            largeIcon:
                const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
            styleInformation: BigTextStyleInformation(body),
            category: AndroidNotificationCategory.message,
            visibility: NotificationVisibility.public,
            enableVibration: true,
            playSound: true,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(message.data),
      );
    } catch (error) {
      debugPrint('NotificationService: local notification failed: $error');
    }
  }

  void _fireLoveSignalOverlay({
    required String triggerType,
    required String senderName,
  }) {
    final payload = LoveSignalPayload(
      triggerType: triggerType,
      senderName: senderName,
    );
    if (loveSignalNotifier.value != null) {
      loveSignalNotifier.value = null;
    }
    Future.delayed(Duration.zero, () {
      loveSignalNotifier.value = payload;
    });
  }

  void _fireSurpriseNoteOverlay({
    required String content,
    required String senderName,
  }) {
    final payload = SurpriseNotePayload(
      content: content,
      senderName: senderName,
    );
    if (surpriseNoteNotifier.value != null) {
      surpriseNoteNotifier.value = null;
    }
    Future.delayed(Duration.zero, () {
      surpriseNoteNotifier.value = payload;
    });
  }

  void _triggerInAppBanner({
    required String title,
    required String body,
    required String type,
    required Map<String, dynamic> payload,
  }) {
    final (icon, color) = _iconAndColorForType(type);
    AppNotificationNavigation.show(
      title: title,
      message: body,
      icon: icon,
      color: color,
      onTap: () => _handleNotificationTap(jsonEncode(payload)),
    );
  }

  void _handleNotificationTap(String? payload) {
    if (payload == null || payload.isEmpty) {
      return;
    }
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type']?.toString() ?? 'general';

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
    } catch (error) {
      debugPrint('NotificationService: invalid notification payload: $error');
    }
  }

  static Future<void> sendPushToSpouse({
    required String title,
    required String body,
    required String type,
    String? sender,
    String? triggerType,
    String topic = AppConfig.coupleId,
  }) async {
    if (!AppRuntime.supabaseReady) {
      return;
    }

    final activeSender = sender ?? PartnerIdentity.active.value.label;
    final record = <String, dynamic>{
      'couple_id': AppConfig.coupleId,
      'sender': activeSender,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      if (type == 'signal') 'trigger_type': triggerType ?? body,
      if (type == 'chat') 'message': body,
      if (type == 'note') 'content': body,
      'topic': topic,
    };

    final table = switch (type) {
      'chat' => 'chat_history',
      'note' => 'surprise_notes',
      'signal' => 'love_triggers',
      _ => 'notifications',
    };

    try {
      await Supabase.instance.client.functions.invoke(
        'send_fcm_notification',
        body: {
          'type': 'INSERT',
          'table': table,
          'record': record,
          'client_fallback': true,
          'notification': {
            'title': title,
            'body': body,
          },
        },
      ).timeout(const Duration(seconds: 7));
    } catch (error) {
      debugPrint('NotificationService: push dispatch fallback failed: $error');
    }
  }

  Future<String?> getToken() async {
    try {
      return await _fcm.getToken().timeout(const Duration(seconds: 5));
    } catch (error) {
      debugPrint('NotificationService: token read failed: $error');
      return null;
    }
  }

  bool _isFromActivePartner(String? sender) {
    if (sender == null || sender.trim().isEmpty) {
      return false;
    }
    return sender.trim().toLowerCase() ==
        PartnerIdentity.active.value.label.toLowerCase();
  }

  int _notificationId(RemoteMessage message) {
    final hash = message.messageId?.hashCode;
    if (hash != null) {
      return hash & 0x7fffffff;
    }
    return DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
  }

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
}
