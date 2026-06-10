import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';

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
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  // Ensure Supabase is initialized and PartnerIdentity is correctly set
  // based on the logged-in session before processing.
  await NotificationService.ensureSupabaseAndIdentity();

  if (message.notification == null) {
    await NotificationService.instance.showLocalNotification(message);
  }

  final type = message.data['type']?.toString();
  final messageId = message.data['id']?.toString();

  // Mark all pending messages from spouse as delivered since the device received a notification
  await NotificationService.markAllPendingMessagesAsDelivered();
  
  if ((type == 'chat' || type == 'signal') && messageId != null && messageId.isNotEmpty) {
    await NotificationService.markMessageAsDelivered(messageId, type: type!);
  }
}

const _kChannelId = 'rodmae_high_priority_channel_v2';
const _kChannelName = 'RodMae High Priority Alerts';
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

  /// Global flag to track if the chat screen and message tab are currently active in the foreground.
  static bool isChatActive = false;

  /// Ensures that Supabase is initialized and the correct active PartnerIdentity
  /// is set based on the active user session in this isolate (vital for background isolates).
  static Future<void> ensureSupabaseAndIdentity() async {
    try {
      Supabase.instance.client;
    } catch (_) {
      try {
        await Supabase.initialize(
          url: AppConfig.supabaseUrl,
          anonKey: AppConfig.supabaseAnonKey,
        );
      } catch (e) {
        debugPrint('NotificationService: failed to initialize Supabase in background: $e');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedEmail = prefs.getString('auth_email');
      if (cachedEmail != null) {
        PartnerIdentity.setFromEmail(cachedEmail);
        debugPrint(
          'NotificationService: set PartnerIdentity to ${PartnerIdentity.active.value.label} from cached email $cachedEmail in background',
        );
      } else {
        final user = Supabase.instance.client.auth.currentUser;
        if (user != null && user.email != null) {
          PartnerIdentity.setFromEmail(user.email);
          debugPrint(
            'NotificationService: set PartnerIdentity to ${PartnerIdentity.active.value.label} from email ${user.email} in background',
          );
        } else {
          debugPrint(
            'NotificationService: currentUser and cached email are null in background isolate',
          );
        }
      }
    } catch (e) {
      debugPrint('NotificationService: failed to set PartnerIdentity in background: $e');
    }
  }

  /// Dynamically marks a chat message status as 'delivered' in the database.
  /// If Supabase client is not initialized in the current isolate, it will
  /// be initialized dynamically. Supports exponential backoff retries.
  static Future<void> markMessageAsDelivered(String messageId, {required String type}) async {
    final table = type == 'signal' ? 'love_triggers' : 'chat_history';
    final parsedId = int.tryParse(messageId) ?? messageId;
    int attempts = 3;
    Duration delay = const Duration(seconds: 1);

    for (int i = 0; i < attempts; i++) {
      try {
        await ensureSupabaseAndIdentity();
        final client = Supabase.instance.client;

        await client
            .from(table)
            .update({'status': 'delivered'})
            .eq('id', parsedId)
            .eq('status', 'sent');

        debugPrint('NotificationService: successfully marked $type $messageId as delivered');
        return;
      } catch (error) {
        debugPrint(
          'NotificationService: attempt ${i + 1} to mark $type $messageId as delivered failed: $error',
        );
        if (i < attempts - 1) {
          await Future.delayed(delay);
          delay *= 2;
        } else {
          debugPrint(
            'NotificationService: failed to mark $type $messageId as delivered after $attempts attempts.',
          );
        }
      }
    }
  }

  /// Dynamically marks a chat message status as 'seen' in the database.
  /// If Supabase client is not initialized in the current isolate, it will
  /// be initialized dynamically. Supports exponential backoff retries.
  static Future<void> markMessageAsSeen(String messageId, {required String type}) async {
    final table = type == 'signal' ? 'love_triggers' : 'chat_history';
    final parsedId = int.tryParse(messageId) ?? messageId;
    int attempts = 3;
    Duration delay = const Duration(seconds: 1);

    for (int i = 0; i < attempts; i++) {
      try {
        await ensureSupabaseAndIdentity();
        final client = Supabase.instance.client;

        await client
            .from(table)
            .update({'status': 'seen'})
            .eq('id', parsedId)
            .neq('status', 'seen');

        debugPrint('NotificationService: successfully marked $type $messageId as seen');
        return;
      } catch (error) {
        debugPrint(
          'NotificationService: attempt ${i + 1} to mark $type $messageId as seen failed: $error',
        );
        if (i < attempts - 1) {
          await Future.delayed(delay);
          delay *= 2;
        } else {
          debugPrint(
            'NotificationService: failed to mark $type $messageId as seen after $attempts attempts.',
          );
        }
      }
    }
  }

  /// Automatically marks all pending messages from the partner as 'delivered' in the database.
  /// Used upon app launch, app resume, or receiving push notifications in the background to sync delivery receipts.
  static Future<void> markAllPendingMessagesAsDelivered() async {
    try {
      await ensureSupabaseAndIdentity();
      final client = Supabase.instance.client;
      final myLabel = PartnerIdentity.active.value.label.toLowerCase();
      final spouseLabel = myLabel == 'rodel' ? 'Eurine' : 'Rodel';

      // 1. Update all sent chat messages from partner to delivered
      await client
          .from('chat_history')
          .update({'status': 'delivered'})
          .eq('couple_id', AppConfig.coupleId)
          .eq('sender', spouseLabel)
          .eq('status', 'sent');

      // 2. Update all sent love signals from partner to delivered
      await client
          .from('love_triggers')
          .update({'status': 'delivered'})
          .eq('couple_id', AppConfig.coupleId)
          .eq('sender', spouseLabel)
          .eq('status', 'sent');

      debugPrint('NotificationService: successfully marked all pending messages from $spouseLabel as delivered');
    } catch (error) {
      debugPrint('NotificationService: failed to mark all pending messages as delivered: $error');
    }
  }

  /// Helper to determine if the user is actively viewing a specific context (tab/screen).
  /// Returns true only if the app is currently in the foreground (resumed) and the active tab matches.
  static bool isContextActive(String type) {
    final isResumed = WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (!isResumed) return false;

    final mainTab = AppNotificationNavigation.mainTabNotifier.value;
    final subTab = AppNotificationNavigation.privateChatTabNotifier.value;

    if (mainTab != 1) return false;

    switch (type) {
      case 'chat':
        return subTab == 0;
      case 'note':
        return subTab == 1;
      case 'signal':
        return subTab == 2;
      default:
        return false;
    }
  }

  bool _localNotificationsReady = false;
  StreamSubscription<RemoteMessage>? _foregroundSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  static Future<void> requestPermission() async {
    try {
      // 1. Request FCM permission
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      // 2. Request Android local notification permission
      final androidPlugin = instance.flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      debugPrint('NotificationService: successfully requested notifications permission');
    } catch (e) {
      debugPrint('NotificationService: failed to request notifications permission: $e');
    }
  }

  Future<void> initialize() async {
    await _initializeLocalNotifications();
    unawaited(_initializeFirebaseMessaging());

    PartnerIdentity.active.addListener(() {
      unawaited(syncTopicSubscription());
    });
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

  static Future<void> syncTopicSubscription() async {
    try {
      final myLabel = PartnerIdentity.active.value.label;
      final myTopic = '${AppConfig.coupleId}-$myLabel';
      final otherLabel = PartnerIdentity.active.value == PartnerProfile.rodel ? 'Eurine' : 'Rodel';
      final otherTopic = '${AppConfig.coupleId}-$otherLabel';

      await FirebaseMessaging.instance.unsubscribeFromTopic(AppConfig.coupleId);
      await FirebaseMessaging.instance.unsubscribeFromTopic(otherTopic);
      await FirebaseMessaging.instance.subscribeToTopic(myTopic);
      debugPrint('NotificationService: successfully synced FCM subscription to $myTopic');
    } catch (e) {
      debugPrint('NotificationService: failed to sync FCM subscription: $e');
    }
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

        final type = message.data['type']?.toString() ?? 'general';
        final messageId = message.data['id']?.toString();
        
        // ── DUAL-TRACK RECEIPTS ──────────────────────────────────────────────
        if ((type == 'chat' || type == 'signal') && messageId != null && messageId.isNotEmpty) {
          if (isContextActive(type)) {
            unawaited(NotificationService.markMessageAsSeen(messageId, type: type));
          } else {
            unawaited(NotificationService.markMessageAsDelivered(messageId, type: type));
          }
        }

        // ── CONTEXT-AWARE SYSTEM TRAY NOTIFICATION ───────────────────────────
        // Only trigger heads-up local notification if the user is NOT actively
        // viewing the context for this notification.
        if (isContextActive(type)) {
          debugPrint('NotificationService: local notification suppressed because context $type is active');
        } else {
          await showLocalNotification(message);
        }

        // ── DUAL-TRACK: fire love overlay via FCM foreground message ─────────
        // This guarantees that even if Supabase Realtime is delayed, the
        // receiving partner sees the cinematic overlay immediately.
        if (type == 'signal') {
          final triggerType = message.data['trigger_type']?.toString() ??
              message.data['body']?.toString() ??
              'love signal';
          final senderName = sender ?? 'Your partner';
          _fireLoveSignalOverlay(triggerType: triggerType, senderName: senderName);
        }

        // ── DUAL-TRACK: fire envelope overlay for surprise notes ─────────────
        if (type == 'note') {
          final noteContent = message.data['content']?.toString() ??
              message.data['body']?.toString() ??
              'New note';
          final senderName = sender ?? 'Your partner';
          _fireSurpriseNoteOverlay(content: noteContent, senderName: senderName);
        }
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

      await syncTopicSubscription();
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
            largeIcon: null,
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
    String? id,
    String? topic,
  }) async {
    if (!AppRuntime.supabaseReady) {
      return;
    }

    final activeSender = sender ?? PartnerIdentity.active.value.label;
    final spouseLabel = PartnerIdentity.active.value == PartnerProfile.rodel ? 'Eurine' : 'Rodel';
    final targetTopic = topic ?? '${AppConfig.coupleId}-$spouseLabel';

    final record = <String, dynamic>{
      if (id != null) 'id': id,
      'couple_id': AppConfig.coupleId,
      'sender': activeSender,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      if (type == 'signal') 'trigger_type': triggerType ?? body,
      if (type == 'chat') 'message': body,
      if (type == 'note') 'content': body,
      'topic': targetTopic,
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
}

