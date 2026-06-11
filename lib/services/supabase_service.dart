import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants.dart';
import '../core/utils.dart';
import '../models/couple_settings.dart';
import '../models/finance_entry.dart';
import '../models/chat_message.dart';
import '../models/user_profile.dart';
import '../models/vault_document.dart';
import '../models/meal_plan.dart';
import '../models/surprise_note.dart';
import '../models/love_trigger_event.dart';
import '../models/couple_location.dart';
import 'auth_service.dart';
import 'firebase_service.dart';
import 'notification_service.dart';

final class SupabaseWeddingRepository {
  SupabaseWeddingRepository._();

  static final SupabaseWeddingRepository instance = SupabaseWeddingRepository._();

  SupabaseClient get _client {
    if (!AppRuntime.supabaseReady) {
      throw StateError('Supabase is not initialized.');
    }
    return Supabase.instance.client;
  }

  // --- Highly Robust Local Caching System (Local-First Offline Support) ---

  Future<List<Map<String, dynamic>>> _loadCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(key);
      if (str != null) {
        final decoded = jsonDecode(str);
        if (decoded is List) {
          return decoded.cast<Map<String, dynamic>>();
        }
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveCache(String key, List<Map<String, dynamic>> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(list));
    } catch (_) {}
  }

  // --- Finances & Joint Expense Tracker ---

  Future<List<FinanceEntry>> fetchFinances() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('finances')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('date', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_finances', list);
        return list.map(FinanceEntry.fromMap).toList();
      }
    } catch (e) {
      print('Supabase fetchFinances error: $e');
    }
    // Fallback to local cache so the app remains fully functional offline!
    final cached = await _loadCache('cached_finances');
    return cached.map(FinanceEntry.fromMap).toList();
  }

  Stream<List<FinanceEntry>> watchFinances() {
    final controller = StreamController<List<FinanceEntry>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchFinances();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      // 1. Emit cached immediately for instant UI loading with zero lag
      final cached = await fetchFinances();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('finances')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('date', ascending: false)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_finances', list);
                if (!controller.isClosed) {
                  controller.add(list.map(FinanceEntry.fromMap).toList());
                }
              },
              onError: (err) {
                // Silently fallback to polling if realtime is not active in DB
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> insertFinance(FinanceEntry entry) async {
    final map = entry.toInsertMap();
    
    // Save to local cache immediately for ultra-responsive UI
    final cached = await _loadCache('cached_finances');
    final localMap = {
      'id': entry.id,
      'couple_id': AppConfig.coupleId,
      'title': '${entry.category} - ${entry.title}',
      'amount': entry.amount,
      'type': entry.type == FinanceType.income ? 'Income' : 'Expense',
      'date': Formatters.date(entry.date),
      'created_by': entry.createdBy,
    };
    cached.insert(0, localMap);
    await _saveCache('cached_finances', cached);

    // Asynchronously insert into live Supabase
    try {
      if (AppRuntime.supabaseReady) {
        await _client.from('finances').insert(map);
      }
    } catch (e) {
      print('Supabase insertFinance error: $e');
    }
  }

  Future<void> insertReceiptExpense(ReceiptExtraction receipt) async {
    final entry = FinanceEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: receipt.storeName,
      category: receipt.category,
      amount: receipt.totalAmount,
      type: FinanceType.expense,
      date: DateTime.now(),
      createdBy: PartnerIdentity.active.value.label,
    );
    await insertFinance(entry);
  }

  // --- Spouses chat thread syncing ---

  Future<List<ChatMessage>> fetchChat() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('chat_history')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_chat', list);
        return list.map(ChatMessage.fromMap).toList();
      }
    } catch (e) {
      print('Supabase fetchChat error: $e');
    }
    final cached = await _loadCache('cached_chat');
    return cached.map(ChatMessage.fromMap).toList();
  }

  Stream<List<ChatMessage>> watchChat() {
    final controller = StreamController<List<ChatMessage>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchChat();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      // 1. Emit cached immediately
      final cached = await fetchChat();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('chat_history')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_chat', list);
                if (!controller.isClosed) {
                  controller.add(list.map(ChatMessage.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> sendChatMessage(
    String message, {
    String? sender,
    String? replyToId,
    String? replyToSender,
    String? replyToText,
    String? voiceUrl,
  }) async {
    final activeSender = sender ?? PartnerIdentity.active.value.label;
    final localMap = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'couple_id': AppConfig.coupleId,
      'sender': activeSender,
      'message': message,
      'status': 'sent',
      'message_type': voiceUrl != null ? 'voice' : 'text',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      if (replyToId != null) 'reply_to_id': replyToId,
      if (replyToSender != null) 'reply_to_sender': replyToSender,
      if (replyToText != null) 'reply_to_text': replyToText,
      if (voiceUrl != null) 'voice_url': voiceUrl,
    };
    final cached = await _loadCache('cached_chat');
    cached.add(localMap);
    await _saveCache('cached_chat', cached);

    try {
      if (AppRuntime.supabaseReady) {
        final inserted = await _client.from('chat_history').insert({
          'couple_id': AppConfig.coupleId,
          'sender': activeSender,
          'message': message,
          'status': 'sent',
          'message_type': voiceUrl != null ? 'voice' : 'text',
          // Omit created_at so Supabase uses its server-side now() default!
          if (replyToId != null) 'reply_to_id': int.tryParse(replyToId),
          if (replyToSender != null) 'reply_to_sender': replyToSender,
          if (replyToText != null) 'reply_to_text': replyToText,
          if (voiceUrl != null) 'voice_url': voiceUrl,
        }).select().single();

        final messageId = inserted['id']?.toString() ?? '';
        unawaited(NotificationService.sendPushToSpouse(
          title: '$activeSender 💬',
          body: voiceUrl != null ? '🎤 Sent a voice message' : message,
          type: 'chat',
          sender: activeSender,
          id: messageId,
        ));
      } else {
        throw StateError('Supabase is not ready.');
      }
    } catch (e) {
      print('Supabase sendChatMessage error: $e');
      rethrow;
    }
  }

  /// Sends a rich message (image / location / love signal) to the chat history.
  Future<void> sendRichMessage(ChatMessage msg) async {
    final localMap = {
      'id': msg.id,
      'couple_id': AppConfig.coupleId,
      'sender': msg.sender,
      'message': msg.message,
      'status': msg.status.name,
      'message_type': msg.messageType.name,
      if (msg.imageUrl != null) 'image_url': msg.imageUrl,
      if (msg.locationData != null) 'location_data': msg.locationData,
      'created_at': msg.createdAt.toUtc().toIso8601String(),
      if (msg.replyToId != null) 'reply_to_id': msg.replyToId,
      if (msg.replyToSender != null) 'reply_to_sender': msg.replyToSender,
      if (msg.replyToText != null) 'reply_to_text': msg.replyToText,
      if (msg.reactions != null) 'reactions': msg.reactions,
      'is_deleted': msg.isDeleted,
      'is_edited': msg.isEdited,
      if (msg.voiceUrl != null) 'voice_url': msg.voiceUrl,
    };
    final cached = await _loadCache('cached_chat');
    cached.add(localMap);
    await _saveCache('cached_chat', cached);

    try {
      if (AppRuntime.supabaseReady) {
        final Map<String, dynamic> dbMap = {
          'couple_id': AppConfig.coupleId,
          'sender': msg.sender,
          'message': msg.message,
          'status': msg.status.name,
          'message_type': msg.messageType.name,
          if (msg.imageUrl != null) 'image_url': msg.imageUrl,
          if (msg.locationData != null) 'location_data': msg.locationData,
          // Omit created_at so Supabase uses its server-side now() default!
          if (msg.replyToId != null) 'reply_to_id': int.tryParse(msg.replyToId!),
          if (msg.replyToSender != null) 'reply_to_sender': msg.replyToSender,
          if (msg.replyToText != null) 'reply_to_text': msg.replyToText,
          if (msg.reactions != null) 'reactions': msg.reactions,
          'is_deleted': msg.isDeleted,
          'is_edited': msg.isEdited,
          if (msg.voiceUrl != null) 'voice_url': msg.voiceUrl,
        };

        // If it's a real, non-temporary message ID, include it, otherwise let DB generate it.
        if (msg.id.isNotEmpty && !msg.id.startsWith('-temp_')) {
          final numericId = int.tryParse(msg.id);
          if (numericId != null) {
            dbMap['id'] = numericId;
          }
        }

        await _client.from('chat_history').insert(dbMap);

        String body = msg.message;
        if (msg.messageType == MessageType.image) {
          body = '📷 Sent an image';
        } else if (msg.messageType == MessageType.location) {
          body = '📍 Shared a location';
        } else if (msg.messageType == MessageType.love) {
          body = '💕 Sending love to you';
        }

        final pushType = msg.messageType == MessageType.love ? 'signal' : 'chat';
        final pushTitle = msg.messageType == MessageType.love
            ? '${msg.sender} sent a love signal! 💕'
            : '${msg.sender} 💬';
        final pushBody = msg.messageType == MessageType.love
            ? 'I Love You'
            : body;
        final triggerType = msg.messageType == MessageType.love
            ? 'I Love You'
            : null;

        unawaited(NotificationService.sendPushToSpouse(
          title: pushTitle,
          body: pushBody,
          type: pushType,
          sender: msg.sender,
          triggerType: triggerType,
          id: msg.id,
        ));
      } else {
        throw StateError('Supabase is not ready.');
      }
    } catch (e) {
      print('Supabase sendRichMessage error: $e');
      rethrow;
    }
  }

  /// Updates a message reaction in database and cache.
  Future<void> updateMessageReaction(String messageId, Map<String, String> reactions) async {
    final cached = await _loadCache('cached_chat');
    for (final msg in cached) {
      if (msg['id']?.toString() == messageId) {
        msg['reactions'] = reactions;
        break;
      }
    }
    await _saveCache('cached_chat', cached);

    try {
      if (AppRuntime.supabaseReady) {
        final numericId = int.tryParse(messageId);
        if (numericId != null) {
          await _client
              .from('chat_history')
              .update({'reactions': reactions})
              .eq('id', numericId);
        }
      }
    } catch (e) {
      print('Supabase updateMessageReaction error: $e');
    }
  }

  /// Soft-deletes a message (unsend) by marking it as deleted and clearing content.
  Future<void> unsendMessage(String messageId) async {
    final cached = await _loadCache('cached_chat');
    for (final msg in cached) {
      if (msg['id']?.toString() == messageId) {
        msg['is_deleted'] = true;
        msg['message'] = '';
        break;
      }
    }
    await _saveCache('cached_chat', cached);

    try {
      if (AppRuntime.supabaseReady) {
        final numericId = int.tryParse(messageId);
        if (numericId != null) {
          await _client
              .from('chat_history')
              .update({
                'is_deleted': true,
                'message': '',
              })
              .eq('id', numericId);
        }
      }
    } catch (e) {
      print('Supabase unsendMessage error: $e');
      rethrow;
    }
  }

  /// Edits a message text by setting the new content and updating the is_edited flag.
  Future<void> editMessage(String messageId, String newText) async {
    String? originalText;
    final cached = await _loadCache('cached_chat');
    for (final msg in cached) {
      if (msg['id']?.toString() == messageId) {
        final isAlreadyEdited = msg['is_edited'] == true || msg['original_message'] != null;
        if (!isAlreadyEdited) {
          originalText = msg['message']?.toString();
          msg['original_message'] = originalText;
        } else {
          originalText = msg['original_message']?.toString();
        }
        msg['message'] = newText;
        msg['is_edited'] = true;
        break;
      }
    }
    await _saveCache('cached_chat', cached);

    try {
      if (AppRuntime.supabaseReady) {
        final numericId = int.tryParse(messageId);
        if (numericId != null) {
          if (originalText == null) {
            final existing = await _client
                .from('chat_history')
                .select('message, original_message, is_edited')
                .eq('id', numericId)
                .single();
            final isAlreadyEdited = existing['is_edited'] == true || existing['original_message'] != null;
            if (!isAlreadyEdited) {
              originalText = existing['message']?.toString();
            } else {
              originalText = existing['original_message']?.toString();
            }
          }

          await _client
              .from('chat_history')
              .update({
                'message': newText,
                'is_edited': true,
                if (originalText != null) 'original_message': originalText,
              })
              .eq('id', numericId);
        }
      }
    } catch (e) {
      print('Supabase editMessage error: $e');
      rethrow;
    }
  }

  /// Marks all messages from the *partner* (not the local user) as 'seen'.
  /// Call this when the chat tab becomes active / visible.
  Future<void> markMessagesAsSeen() async {
    final mySender = PartnerIdentity.active.value.label;
    try {
      if (AppRuntime.supabaseReady) {
        await _client
            .from('chat_history')
            .update({'status': 'seen'})
            .eq('couple_id', AppConfig.coupleId)
            .neq('sender', mySender)
            .inFilter('status', ['sent', 'delivered']);
      }
    } catch (e) {
      print('Supabase markMessagesAsSeen error: $e');
    }
  }

  // --- Checklist Methods (Connecting Newlyweds checklist to the Supabase checklist table) ---

  Future<List<GoalItem>> fetchChecklist() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('checklist')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('id', ascending: true);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_checklist', list);
        return list.map((row) => GoalItem(
              id: '${row['id']}',
              title: '${row['title']}',
              category: '${row['category'] ?? 'Newlyweds'}',
              completed: row['is_completed'] == true,
            )).toList();
      }
    } catch (e) {
      print('Supabase fetchChecklist error: $e');
    }
    final cached = await _loadCache('cached_checklist');
    return cached.map((row) => GoalItem(
          id: '${row['id']}',
          title: '${row['title']}',
          category: '${row['category'] ?? 'Newlyweds'}',
          completed: row['is_completed'] == true,
        )).toList();
  }

  Stream<List<GoalItem>> watchChecklist() {
    final controller = StreamController<List<GoalItem>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchChecklist();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      // 1. Emit cached immediately
      final cached = await fetchChecklist();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('checklist')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('id', ascending: true)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_checklist', list);
                if (!controller.isClosed) {
                  controller.add(list.map((row) => GoalItem(
                        id: '${row['id']}',
                        title: '${row['title']}',
                        category: '${row['category'] ?? 'Newlyweds'}',
                        completed: row['is_completed'] == true,
                      )).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> insertChecklistItem(String title, String category) async {
    final localId = DateTime.now().microsecondsSinceEpoch.toString();
    final localMap = {
      'id': localId,
      'couple_id': AppConfig.coupleId,
      'title': title,
      'category': category,
      'is_completed': false,
    };
    final cached = await _loadCache('cached_checklist');
    cached.add(localMap);
    await _saveCache('cached_checklist', cached);

    try {
      if (AppRuntime.supabaseReady) {
        await _client.from('checklist').insert({
          'couple_id': AppConfig.coupleId,
          'title': title,
          'category': category,
          'is_completed': false,
        });
      }
    } catch (e) {
      print('Supabase insertChecklistItem error: $e');
    }
  }

  Future<void> toggleChecklistItem(String id, bool completed) async {
    final cached = await _loadCache('cached_checklist');
    for (final item in cached) {
      if ('${item['id']}' == id) {
        item['is_completed'] = completed;
        break;
      }
    }
    await _saveCache('cached_checklist', cached);

    try {
      if (AppRuntime.supabaseReady) {
        final intId = int.tryParse(id);
        if (intId != null) {
          await _client.from('checklist').update({
            'is_completed': completed,
          }).eq('id', intId);
        }
      }
    } catch (e) {
      print('Supabase toggleChecklistItem error: $e');
    }
  }

  // --- Secret Vault Storage Methods ---

  Future<List<VaultDocument>> fetchVaultDocuments() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('vault_documents')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('uploaded_at', ascending: false);
        final tableDocs = List<Map<String, dynamic>>.from(rows as List)
            .map(VaultDocument.fromMap)
            .toList();
        if (tableDocs.isNotEmpty) {
          return tableDocs;
        }

        final files = await client.storage
            .from(AppConfig.vaultBucket)
            .list(path: AppConfig.coupleId);
        final docs = <VaultDocument>[];
        for (final file in files) {
          final path = '${AppConfig.coupleId}/${file.name}';
          final signedUrl = await client.storage
              .from(AppConfig.vaultBucket)
              .createSignedUrl(path, 60 * 60);
          final size = Formatters.asDouble(file.metadata?['size']);
          docs.add(
            VaultDocument(
              name: file.name,
              sizeLabel: size > 0
                  ? '${(size / (1024 * 1024)).toStringAsFixed(2)} MB'
                  : 'Protected',
              uploadedAt: Formatters.asDate(file.createdAt),
              status: 'storage',
              signedUrl: signedUrl,
            ),
          );
        }
        return docs;
      }
    } catch (e) {
      print('Supabase fetchVaultDocuments error: $e');
    }
    return <VaultDocument>[];
  }

  // --- Surprise Notes System ---

  Future<List<SurpriseNote>> fetchNotes() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('surprise_notes')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_notes', list);
        return list.map(SurpriseNote.fromMap).toList();
      }
    } catch (e) {
      print('Supabase fetchNotes error: $e');
    }
    final cached = await _loadCache('cached_notes');
    return cached.map(SurpriseNote.fromMap).toList();
  }

  Stream<List<SurpriseNote>> watchNotes() {
    final controller = StreamController<List<SurpriseNote>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchNotes();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      final cached = await fetchNotes();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('surprise_notes')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_notes', list);
                if (!controller.isClosed) {
                  controller.add(list.map(SurpriseNote.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> insertSurpriseNote(String content) async {
    final localMap = {
      'id': DateTime.now().microsecondsSinceEpoch.toString(),
      'couple_id': AppConfig.coupleId,
      'sender': PartnerIdentity.active.value.label,
      'content': content,
      'created_at': DateTime.now().toIso8601String(),
    };
    final cached = await _loadCache('cached_notes');
    cached.insert(0, localMap);
    await _saveCache('cached_notes', cached);

    try {
      if (AppRuntime.supabaseReady) {
        final inserted = await _client.from('surprise_notes').insert({
          'couple_id': AppConfig.coupleId,
          'sender': PartnerIdentity.active.value.label,
          'content': content,
          'created_at': DateTime.now().toIso8601String(),
        }).select().single();

        final noteId = inserted['id']?.toString() ?? '';
        unawaited(NotificationService.sendPushToSpouse(
          title: 'Sweet note from ${PartnerIdentity.active.value.label} 🌸',
          body: content,
          type: 'note',
          sender: PartnerIdentity.active.value.label,
          id: noteId,
        ));
      }
    } catch (e) {
      print('Supabase insertSurpriseNote error: $e');
    }
  }

  // --- Love Triggers System ---

  Future<List<LoveTriggerEvent>> fetchLoveTriggers() async {
    try {
      if (AppRuntime.supabaseReady) {
        final client = _client;
        final rows = await client
            .from('love_triggers')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_triggers', list);
        return list.map(LoveTriggerEvent.fromMap).toList();
      }
    } catch (e) {
      print('Supabase fetchLoveTriggers error: $e');
    }
    final cached = await _loadCache('cached_triggers');
    return cached.map(LoveTriggerEvent.fromMap).toList();
  }

  Stream<List<LoveTriggerEvent>> watchLoveTriggers() {
    final controller = StreamController<List<LoveTriggerEvent>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 3), (t) async {
        try {
          final data = await fetchLoveTriggers();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      final cached = await fetchLoveTriggers();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('love_triggers')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .order('created_at', ascending: false)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_triggers', list);
                if (!controller.isClosed) {
                  controller.add(list.map(LoveTriggerEvent.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  Future<void> insertLoveTrigger(String triggerType) async {
    final localId = DateTime.now().microsecondsSinceEpoch.toString();
    final localMap = {
      'id': localId,
      'couple_id': AppConfig.coupleId,
      'sender': PartnerIdentity.active.value.label,
      'trigger_type': triggerType,
      'status': 'sent',
      'created_at': DateTime.now().toIso8601String(),
    };
    final cached = await _loadCache('cached_triggers');
    cached.insert(0, localMap);
    await _saveCache('cached_triggers', cached);

    try {
      if (AppRuntime.supabaseReady) {
        final inserted = await _client.from('love_triggers').insert({
          'couple_id': AppConfig.coupleId,
          'sender': PartnerIdentity.active.value.label,
          'trigger_type': triggerType,
          'status': 'sent',
          'created_at': DateTime.now().toIso8601String(),
        }).select().single();

        final triggerId = inserted['id']?.toString() ?? localId;
        final senderName = PartnerIdentity.active.value.label;
        unawaited(NotificationService.sendPushToSpouse(
          title: '$senderName sent a love signal! 💕',
          body: triggerType,
          type: 'signal',
          sender: senderName,
          triggerType: triggerType,
          id: triggerId,
        ));
      }
    } catch (e) {
      print('Supabase insertLoveTrigger error: $e');
      rethrow;
    }
  }

  /// Marks all love triggers from the partner as 'seen' in the database.
  Future<void> markLoveTriggersAsSeen() async {
    final mySender = PartnerIdentity.active.value.label;
    try {
      if (AppRuntime.supabaseReady) {
        await _client
            .from('love_triggers')
            .update({'status': 'seen'})
            .eq('couple_id', AppConfig.coupleId)
            .neq('sender', mySender)
            .inFilter('status', ['sent', 'delivered']);
      }
    } catch (e) {
      print('Supabase markLoveTriggersAsSeen error: $e');
    }
  }


  // ─── User Profiles (PFP + Display Name + Bio) ─────────────────────────────

  Future<UserProfile?> fetchUserProfile(String partner) async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _client
            .from('user_profiles')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .eq('partner', partner)
            .limit(1);
        final list = List<Map<String, dynamic>>.from(rows as List);
        if (list.isNotEmpty) {
          final profile = UserProfile.fromMap(list.first);
          // Cache locally
          final prefs = await SharedPreferences.getInstance();
          if (profile.avatarUrl != null) {
            await prefs.setString('avatar_url_$partner', profile.avatarUrl!);
          }
          return profile;
        }
      }
    } catch (e) {
      print('fetchUserProfile error: $e');
    }
    // Fallback to local cache
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString('avatar_url_$partner');
      if (cachedUrl != null) {
        return UserProfile(
          id: '',
          coupleId: AppConfig.coupleId,
          partner: partner,
          avatarUrl: cachedUrl,
          updatedAt: DateTime.now(),
        );
      }
    } catch (_) {}
    return null;
  }

  Future<void> upsertUserProfile({
    required String partner,
    String? displayName,
    String? bio,
    String? avatarUrl,
  }) async {
    if (!AppRuntime.supabaseReady) return;

    try {
      final existing = await _client
          .from('user_profiles')
          .select('id')
          .eq('couple_id', AppConfig.coupleId)
          .eq('partner', partner)
          .maybeSingle();

      final data = {
        'couple_id': AppConfig.coupleId,
        'partner': partner,
        if (displayName != null) 'display_name': displayName,
        if (bio != null) 'bio': bio,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (existing != null) {
        await _client
            .from('user_profiles')
            .update(data)
            .eq('id', existing['id']);
      } else {
        await _client
            .from('user_profiles')
            .insert(data);
      }
      ProfileNotifier.notifyUpdate();
    } catch (e) {
      print('upsertUserProfile error: $e');
      rethrow;
    }
  }

  /// Upload avatar bytes to Supabase Storage and return the public URL.
  Future<String?> uploadAvatar(Uint8List bytes, String partner) async {
    if (!AppRuntime.supabaseReady) return null;
    try {
      final filename = '${partner.toLowerCase().replaceAll(' ', '_')}.jpg';
      final path = filename;
      await _client.storage
          .from('avatars')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
              upsert: true,
            ),
          );
      final url = _client.storage.from('avatars').getPublicUrl(path);
      return url;
    } catch (e) {
      print('uploadAvatar error: $e');
      rethrow;
    }
  }

  /// Upload compressed image bytes to the chat-media bucket and return public URL.
  ///
  /// [bytes]     — already-compressed JPEG bytes (caller must compress first)
  /// [extension] — file extension WITHOUT the dot, e.g. 'jpg', 'png', 'webp'
  ///
  /// Stores files at: `{coupleId}/{timestamp}.{extension}`
  /// Bucket is public so no signed URL is needed.
  Future<String> uploadChatImage(Uint8List bytes, String extension) async {
    if (!AppRuntime.supabaseReady) {
      throw StateError('Supabase is not initialized. Cannot upload image.');
    }

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final filename = '$timestamp.$extension';
    final storagePath = '${AppConfig.coupleId}/$filename';

    // Map extension to a valid MIME type accepted by the bucket policy
    final contentType = switch (extension.toLowerCase()) {
      'png'  => 'image/png',
      'webp' => 'image/webp',
      'gif'  => 'image/gif',
      _      => 'image/jpeg', // jpeg / jpg fallback
    };

    await _client.storage
        .from(AppConfig.chatMediaBucket)
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            upsert: false, // never silently overwrite
          ),
        );

    // getPublicUrl is synchronous — bucket must be public (which it is)
    return _client.storage
        .from(AppConfig.chatMediaBucket)
        .getPublicUrl(storagePath);
  }


  // ─── Couple Settings ────────────────────────────────────────────────────────

  Future<CoupleSettings> fetchCoupleSettings() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _client
            .from('couple_settings')
            .select()
            .eq('couple_id', AppConfig.coupleId)
            .limit(1);
        final list = List<Map<String, dynamic>>.from(rows as List);
        if (list.isNotEmpty) {
          return CoupleSettings.fromMap(list.first);
        }
      }
    } catch (e) {
      print('fetchCoupleSettings error: $e');
    }
    return CoupleSettings.defaults();
  }

  Future<void> upsertCoupleSettings(CoupleSettings settings) async {
    if (!AppRuntime.supabaseReady) return;
    try {
      await _client.from('couple_settings').upsert(
        {...settings.toMap(), 'updated_at': DateTime.now().toIso8601String()},
        onConflict: 'couple_id',
      );
    } catch (e) {
      print('upsertCoupleSettings error: $e');
    }
  }

  // ─── Couple Locations ──────────────────────────────────────────────────────

  Future<List<CoupleLocation>> fetchLocations() async {
    try {
      if (AppRuntime.supabaseReady) {
        final rows = await _client
            .from('couple_locations')
            .select()
            .eq('couple_id', AppConfig.coupleId);
        final list = List<Map<String, dynamic>>.from(rows as List);
        await _saveCache('cached_locations', list);
        return list.map(CoupleLocation.fromMap).toList();
      }
    } catch (e) {
      print('fetchLocations error: $e');
    }
    final cached = await _loadCache('cached_locations');
    return cached.map(CoupleLocation.fromMap).toList();
  }

  Future<void> upsertLocation(CoupleLocation location) async {
    try {
      if (AppRuntime.supabaseReady) {
        final payload = {
          ...location.toMap(),
          'updated_at': DateTime.now().toIso8601String(),
        };
        // Resolve conflict on the composite unique constraint (couple_id, partner, location_type)
        await _client.from('couple_locations').upsert(
          payload,
          onConflict: 'couple_id,partner,location_type',
        );
      }
      // Update local cache
      final currentCache = await _loadCache('cached_locations');
      final updatedList = currentCache.where((m) =>
        !(m['partner'] == location.partner && m['location_type'] == location.locationType)
      ).toList();
      updatedList.add({
        ...location.toMap(),
        'id': location.id,
        'updated_at': DateTime.now().toIso8601String(),
      });
      await _saveCache('cached_locations', updatedList);
    } catch (e) {
      print('upsertLocation error: $e');
      rethrow; // propagate so callers can show error UI
    }
  }

  Stream<List<CoupleLocation>> watchLocations() {
    final controller = StreamController<List<CoupleLocation>>();
    StreamSubscription? sub;
    Timer? timer;
    bool failed = false;

    void startPolling() {
      sub?.cancel();
      sub = null;
      timer = Timer.periodic(const Duration(seconds: 4), (t) async {
        try {
          final data = await fetchLocations();
          if (!controller.isClosed) {
            controller.add(data);
          }
        } catch (_) {}
      });
    }

    void start() async {
      // Emit cached immediately
      final cached = await fetchLocations();
      if (!controller.isClosed) {
        controller.add(cached);
      }

      if (!AppRuntime.supabaseReady) {
        startPolling();
        return;
      }

      try {
        sub = _client
            .from('couple_locations')
            .stream(primaryKey: ['id'])
            .eq('couple_id', AppConfig.coupleId)
            .listen(
              (rows) async {
                final list = List<Map<String, dynamic>>.from(rows);
                await _saveCache('cached_locations', list);
                if (!controller.isClosed) {
                  controller.add(list.map(CoupleLocation.fromMap).toList());
                }
              },
              onError: (err) {
                if (!failed) {
                  failed = true;
                  startPolling();
                }
              },
              cancelOnError: true,
            );
      } catch (_) {
        startPolling();
      }
    }

    controller.onListen = start;
    controller.onCancel = () {
      sub?.cancel();
      timer?.cancel();
    };

    return controller.stream;
  }

  // ── Presence heartbeat ────────────────────────────────────────────────────
  /// Touch `updated_at` on the live-location row so the partner can show
  /// "last seen X seconds ago" even when the device hasn't moved.
  Future<void> updatePresenceHeartbeat(String partner) async {
    try {
      if (!AppRuntime.supabaseReady) return;
      await _client
          .from('couple_locations')
          .update({'updated_at': DateTime.now().toUtc().toIso8601String()})
          .eq('couple_id', AppConfig.coupleId)
          .eq('partner', partner)
          .eq('location_type', 'live');
    } catch (e) {
      // ignore: avoid_print
      print('Presence heartbeat error: $e');
    }
  }

  /// Upload a voice message audio file to the 'voice_messages' Supabase bucket and return public URL.
  Future<String> uploadVoiceMessage(String filePath) async {
    if (!AppRuntime.supabaseReady) {
      throw StateError('Supabase is not initialized. Cannot upload voice message.');
    }

    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('Voice file does not exist', filePath);
    }

    final bytes = await file.readAsBytes();
    final filename = '${DateTime.now().microsecondsSinceEpoch}.m4a';
    final storagePath = '${AppConfig.coupleId}/$filename';

    await _client.storage
        .from('voice_messages')
        .uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'audio/m4a',
            upsert: false,
          ),
        );

    return _client.storage.from('voice_messages').getPublicUrl(storagePath);
  }
}
